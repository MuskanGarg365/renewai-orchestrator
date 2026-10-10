/**
 * Deterministic decision engine. Pure logic: no SOQL and no DML, so it can be
 * unit tested with hand-built contexts.
 *
 * Model (one 15-minute interval, all quantities are average MW):
 *   renewable - curtail + discharge + buy - charge - sell = demand
 *
 * 1. Build a small, fixed set of candidate action clusters.
 * 2. Reject any candidate that violates a hard constraint (with reason codes).
 * 3. Normalise six cost terms across the feasible candidates (0 = best).
 * 4. Weight the terms with the objective profile and pick the lowest score.
 *    Ties are broken by candidate order, so a given input always gives the
 *    same answer.
 */
public with sharing class RenewAIDecisionEngine {

    public static final Decimal INTERVAL_HOURS = 0.25;
    public static final Decimal INTERVALS_PER_HOUR = 4;
    public static final Decimal MIN_SOC = 10;
    public static final Decimal MAX_SOC = 95;
    public static final Decimal BATTERY_ENERGY_HOURS = 2;
    public static final Decimal TOLERANCE_MW = 0.5;
    public static final Decimal BUY_PRICE_FACTOR = 1.05;
    public static final Decimal SELL_PRICE_FACTOR = 0.95;
    public static final Decimal CARBON_T_PER_MWH = 0.82;
    public static final Decimal BASE_RESERVE_MW = 5;
    public static final Decimal EXTRA_RESERVE_MW = 15;
    public static final Decimal LOW_CONFIDENCE = 0.6;
    public static final Decimal APPROVAL_RELIABILITY_RISK = 0.7;

    public static final List<String> TERMS = new List<String>{
        'cost', 'carbon', 'curtailment',
        'degradation', 'reliability', 'profit'
    };

    // ---------------------------------------------------------------- inputs

    public class Battery {
        public String assetCode;
        public Decimal ratedMW;
        public Decimal socPercent;
        public Boolean available;

        public Battery(
            String assetCode,
            Decimal ratedMW,
            Decimal socPercent,
            Boolean available
        ) {
            this.assetCode = assetCode;
            this.ratedMW = ratedMW;
            this.socPercent = socPercent;
            this.available = available;
        }
    }

    public class Context {
        public Datetime asOf;
        public Decimal renewableMW;
        public Decimal demandMW;
        public Decimal priceMWh;
        public Decimal gridLimitMW;
        public Decimal confidence;
        public String gridAssetCode;
        public List<Battery> batteries = new List<Battery>();
    }

    // --------------------------------------------------------------- outputs

    public class EngineResult {
        public RenewAIDTO.CandidateResult selected;
        public List<RenewAIDTO.CandidateResult> alternatives =
            new List<RenewAIDTO.CandidateResult>();
        public List<RenewAIDTO.CandidateResult> rejected =
            new List<RenewAIDTO.CandidateResult>();
        public Decimal confidence;
        public Decimal reserveMW;
        public String approvalStatus;
        public String decisionType;
        public String recommendedAction;
        public String explanation;
    }

    // ------------------------------------------------------------- internals

    private class Caps {
        Decimal dischargeMW = 0;
        Decimal chargeMW = 0;
        Decimal availableRatedMW = 0;
        Decimal ratedMW = 0;
        List<Decimal> batteryDischarge = new List<Decimal>();
        List<Decimal> batteryCharge = new List<Decimal>();
    }

    private class Plan {
        String id;
        String label;
        Decimal discharge = 0;
        Decimal charge = 0;
        Decimal curtail = 0;
        Decimal buy = 0;
        Decimal sell = 0;
        Decimal reserve = 0;
    }

    private class Evaluated {
        Plan plan;
        RenewAIDTO.CandidateResult result;
        Map<String, Decimal> raw = new Map<String, Decimal>();
        Integer sequence;
    }

    // ------------------------------------------------------------ public API

    public static Map<String, Decimal> weightsFor(String mode) {
        Map<String, Decimal> w = new Map<String, Decimal>();

        switch on mode {
            when 'Balanced' {
                w.put('cost', 0.25);
                w.put('carbon', 0.15);
                w.put('curtailment', 0.15);
                w.put('degradation', 0.10);
                w.put('reliability', 0.20);
                w.put('profit', 0.15);
            }
            when 'Cost First' {
                w.put('cost', 0.40);
                w.put('carbon', 0.05);
                w.put('curtailment', 0.05);
                w.put('degradation', 0.05);
                w.put('reliability', 0.10);
                w.put('profit', 0.35);
            }
            when 'Clean Energy First' {
                w.put('cost', 0.10);
                w.put('carbon', 0.30);
                w.put('curtailment', 0.30);
                w.put('degradation', 0.05);
                w.put('reliability', 0.15);
                w.put('profit', 0.10);
            }
            when 'Reliability First' {
                w.put('cost', 0.10);
                w.put('carbon', 0.05);
                w.put('curtailment', 0.05);
                w.put('degradation', 0.05);
                w.put('reliability', 0.65);
                w.put('profit', 0.10);
            }
            when else {
                throw new RenewAIValidationException(
                    new List<RenewAIDTO.ErrorDetail>{
                        new RenewAIDTO.ErrorDetail(
                            'objectiveMode',
                            'INVALID_MODE',
                            'Use Balanced, Cost First, Clean Energy First or Reliability First.'
                        )
                    }
                );
            }
        }

        return w;
    }

    public static EngineResult decide(Context ctx, String mode) {
        Map<String, Decimal> weights = weightsFor(mode);
        validateContext(ctx);

        Caps caps = computeCaps(ctx);
        Decimal reserveMW = BASE_RESERVE_MW +
            EXTRA_RESERVE_MW * (1 - ctx.confidence);

        List<Plan> plans = buildPlans(ctx, caps, reserveMW);

        List<Evaluated> feasible = new List<Evaluated>();
        List<Evaluated> infeasible = new List<Evaluated>();
        Integer sequence = 0;

        for (Plan plan : plans) {
            Evaluated evaluated = evaluate(ctx, caps, plan, reserveMW);
            evaluated.sequence = sequence;
            sequence++;

            if (evaluated.result.rejectionReasons.isEmpty()) {
                feasible.add(evaluated);
            } else {
                infeasible.add(evaluated);
            }
        }

        if (feasible.isEmpty()) {
            throw new RenewAIValidationException(
                new List<RenewAIDTO.ErrorDetail>{
                    new RenewAIDTO.ErrorDetail(
                        'decision',
                        'NO_FEASIBLE_CANDIDATE',
                        'Every candidate action cluster violated a hard constraint.'
                    )
                }
            );
        }

        scoreCandidates(feasible, weights);
        sortByScore(feasible);

        EngineResult result = new EngineResult();
        result.confidence = ctx.confidence;
        result.reserveMW = reserveMW.setScale(2, System.RoundingMode.HALF_UP);

        Integer rank = 1;
        for (Evaluated e : feasible) {
            e.result.feasible = true;
            e.result.rank = rank;
            rank++;
            e.result.actions = buildActions(ctx, caps, e.plan);
        }
        for (Evaluated e : infeasible) {
            e.result.feasible = false;
            e.result.actions = buildActions(ctx, caps, e.plan);
            result.rejected.add(e.result);
        }

        Evaluated winner = feasible[0];
        result.selected = winner.result;
        for (Integer i = 1; i < feasible.size(); i++) {
            result.alternatives.add(feasible[i].result);
        }

        Decimal reliabilityRisk = winner.raw.get('reliability');
        result.approvalStatus =
            (ctx.confidence < LOW_CONFIDENCE ||
             reliabilityRisk >= APPROVAL_RELIABILITY_RISK)
                ? 'Pending'
                : 'Not Required';

        result.decisionType = decisionType(winner.plan);
        result.recommendedAction = summarize(winner.result.actions);
        result.explanation = explain(ctx, result, mode, feasible, infeasible.size());

        return result;
    }

    // ------------------------------------------------------------ validation

    private static void validateContext(Context ctx) {
        List<RenewAIDTO.ErrorDetail> errors =
            new List<RenewAIDTO.ErrorDetail>();

        if (ctx == null) {
            errors.add(new RenewAIDTO.ErrorDetail(
                'context', 'REQUIRED', 'Decision context is required.'));
        } else {
            if (ctx.renewableMW == null || ctx.renewableMW < 0) {
                errors.add(new RenewAIDTO.ErrorDetail(
                    'renewableMW', 'OUT_OF_RANGE',
                    'Renewable generation must be zero or more.'));
            }
            if (ctx.demandMW == null || ctx.demandMW < 0) {
                errors.add(new RenewAIDTO.ErrorDetail(
                    'demandMW', 'OUT_OF_RANGE',
                    'Demand must be zero or more.'));
            }
            if (ctx.priceMWh == null || ctx.priceMWh < 0) {
                errors.add(new RenewAIDTO.ErrorDetail(
                    'priceMWh', 'MISSING_PRICE',
                    'A current energy price is required.'));
            }
            if (ctx.gridLimitMW == null || ctx.gridLimitMW <= 0) {
                errors.add(new RenewAIDTO.ErrorDetail(
                    'gridLimitMW', 'MISSING_GRID',
                    'A grid connection limit is required.'));
            }
            if (ctx.confidence == null ||
                ctx.confidence < 0 || ctx.confidence > 1) {
                errors.add(new RenewAIDTO.ErrorDetail(
                    'confidence', 'OUT_OF_RANGE',
                    'Confidence must be between 0 and 1.'));
            }
        }

        if (!errors.isEmpty()) {
            throw new RenewAIValidationException(errors);
        }
    }

    // ---------------------------------------------------------- battery caps

    private static Caps computeCaps(Context ctx) {
        Caps caps = new Caps();

        for (Battery b : ctx.batteries) {
            caps.ratedMW += b.ratedMW;

            Decimal dischargeMW = 0;
            Decimal chargeMW = 0;

            if (b.available == true && b.socPercent != null) {
                caps.availableRatedMW += b.ratedMW;

                // MW that the stored energy can sustain for one interval.
                Decimal energyMWh = b.ratedMW * BATTERY_ENERGY_HOURS;
                Decimal usableDown = Math.max(b.socPercent - MIN_SOC, 0) *
                    0.01 * energyMWh * INTERVALS_PER_HOUR;
                Decimal usableUp = Math.max(MAX_SOC - b.socPercent, 0) *
                    0.01 * energyMWh * INTERVALS_PER_HOUR;

                dischargeMW = Math.min(b.ratedMW, usableDown);
                chargeMW = Math.min(b.ratedMW, usableUp);
            }

            caps.batteryDischarge.add(dischargeMW);
            caps.batteryCharge.add(chargeMW);
            caps.dischargeMW += dischargeMW;
            caps.chargeMW += chargeMW;
        }

        return caps;
    }

    // ------------------------------------------------------------ candidates

    private static List<Plan> buildPlans(
        Context ctx,
        Caps caps,
        Decimal reserveMW
    ) {
        Decimal gap = ctx.demandMW - ctx.renewableMW;
        Decimal surplus = gap < 0 ? -gap : 0;
        Decimal deficit = gap > 0 ? gap : 0;

        List<Plan> candidates = new List<Plan>();

        candidates.add(makePlan(gap, 'GRID_BALANCE',
            'Balance with the grid; keep batteries idle',
            0, 0, 0, 0));

        candidates.add(makePlan(gap, 'DISCHARGE_TO_GAP',
            'Discharge batteries to cover the demand gap',
            deficit, 0, 0, 0));

        candidates.add(makePlan(gap, 'CHARGE_SURPLUS',
            'Charge batteries from renewable surplus',
            0, surplus, 0, 0));

        candidates.add(makePlan(gap, 'CURTAIL_SURPLUS',
            'Curtail the renewable surplus',
            0, 0, surplus, 0));

        candidates.add(makePlan(gap, 'DISCHARGE_AND_SELL',
            'Discharge at full rating and sell to the grid',
            caps.ratedMW, 0, 0, 0));

        candidates.add(makePlan(gap, 'CHARGE_FROM_GRID',
            'Charge batteries from the grid',
            0, caps.ratedMW * 0.5, 0, 0));

        candidates.add(makePlan(gap, 'RESERVE_DISCHARGE',
            'Cover the gap and hold a discharge reserve',
            deficit, 0, 0,
            Math.min(reserveMW, Math.max(caps.dischargeMW - deficit, 0))));

        candidates.add(makePlan(gap, 'HOLD_AND_RESERVE',
            'Balance with the grid and hold a discharge reserve',
            0, 0, 0,
            Math.min(reserveMW, caps.dischargeMW)));

        if (surplus > TOLERANCE_MW) {
            candidates.add(makePlan(gap, 'CHARGE_AND_RESERVE',
                'Charge from surplus and hold a discharge reserve',
                0, surplus, 0,
                Math.min(reserveMW, caps.dischargeMW)));
        }

        // Drop candidates whose quantities are identical to an earlier one.
        List<Plan> deduped = new List<Plan>();
        Set<String> seen = new Set<String>();
        for (Plan p : candidates) {
            String signature = q(p.discharge) + '|' + q(p.charge) + '|' +
                q(p.curtail) + '|' + q(p.buy) + '|' + q(p.sell) + '|' +
                q(p.reserve);
            if (seen.add(signature)) {
                deduped.add(p);
            }
        }
        return deduped;
    }

    private static Plan makePlan(
        Decimal gap,
        String id,
        String label,
        Decimal discharge,
        Decimal charge,
        Decimal curtail,
        Decimal reserve
    ) {
        Plan p = new Plan();
        p.id = id;
        p.label = label;
        p.discharge = discharge;
        p.charge = charge;
        p.curtail = curtail;
        p.reserve = reserve;

        // The grid settles whatever the other actions leave over.
        Decimal net = -gap + discharge - charge - curtail;
        if (net > 0) {
            p.sell = net;
        } else {
            p.buy = -net;
        }
        return p;
    }

    private static String q(Decimal value) {
        return value.setScale(2, System.RoundingMode.HALF_UP).toPlainString();
    }

    // --------------------------------------------------------- hard checks

    private static Evaluated evaluate(
        Context ctx,
        Caps caps,
        Plan p,
        Decimal reserveMW
    ) {
        Evaluated e = new Evaluated();
        e.plan = p;
        e.result = new RenewAIDTO.CandidateResult();
        e.result.candidateId = p.id;
        e.result.label = p.label;

        List<String> reasons = e.result.rejectionReasons;

        Decimal balance = ctx.renewableMW - p.curtail + p.discharge +
            p.buy - p.charge - p.sell - ctx.demandMW;
        if (Math.abs(balance) > TOLERANCE_MW) {
            reasons.add('POWER_BALANCE');
        }

        if (p.discharge > caps.dischargeMW + TOLERANCE_MW) {
            if (caps.availableRatedMW == 0) {
                reasons.add('BATTERY_UNAVAILABLE');
            } else if (p.discharge > caps.availableRatedMW + TOLERANCE_MW) {
                reasons.add('BATTERY_RATE_LIMIT');
            } else {
                reasons.add('SOC_MIN_VIOLATION');
            }
        }

        if (p.charge > caps.chargeMW + TOLERANCE_MW) {
            if (caps.availableRatedMW == 0) {
                reasons.add('BATTERY_UNAVAILABLE');
            } else if (p.charge > caps.availableRatedMW + TOLERANCE_MW) {
                reasons.add('BATTERY_RATE_LIMIT');
            } else {
                reasons.add('SOC_MAX_VIOLATION');
            }
        }

        if (p.buy > ctx.gridLimitMW + TOLERANCE_MW ||
            p.sell > ctx.gridLimitMW + TOLERANCE_MW) {
            reasons.add('GRID_LIMIT');
        }

        if (p.curtail > ctx.renewableMW + TOLERANCE_MW) {
            reasons.add('CURTAIL_LIMIT');
        }

        // Raw (lower is better) term values.
        Decimal headroom = Math.max(caps.dischargeMW - p.discharge, 0);
        Decimal shortfall = 0;
        Decimal held = 1;
        if (reserveMW > 0) {
            shortfall = Math.max(reserveMW - headroom, 0)
                .divide(reserveMW, 6, System.RoundingMode.HALF_UP);
            held = Math.min(p.reserve, reserveMW)
                .divide(reserveMW, 6, System.RoundingMode.HALF_UP);
        }

        e.raw.put('cost',
            p.buy * ctx.priceMWh * BUY_PRICE_FACTOR * INTERVAL_HOURS);
        e.raw.put('carbon', p.buy * INTERVAL_HOURS * CARBON_T_PER_MWH);
        e.raw.put('curtailment', p.curtail * INTERVAL_HOURS);
        e.raw.put('degradation', (p.charge + p.discharge) * INTERVAL_HOURS);
        e.raw.put('reliability', 0.7 * shortfall + 0.3 * (1 - held));
        e.raw.put('profit',
            -(p.sell * ctx.priceMWh * SELL_PRICE_FACTOR * INTERVAL_HOURS));

        return e;
    }

    // --------------------------------------------------------------- scoring

    private static void scoreCandidates(
        List<Evaluated> feasible,
        Map<String, Decimal> weights
    ) {
        Map<String, Decimal> lows = new Map<String, Decimal>();
        Map<String, Decimal> highs = new Map<String, Decimal>();

        for (String term : TERMS) {
            Decimal low = null;
            Decimal high = null;
            for (Evaluated e : feasible) {
                Decimal v = e.raw.get(term);
                if (low == null || v < low) { low = v; }
                if (high == null || v > high) { high = v; }
            }
            lows.put(term, low);
            highs.put(term, high);
        }

        for (Evaluated e : feasible) {
            Decimal total = 0;

            for (String term : TERMS) {
                Decimal range = highs.get(term) - lows.get(term);
                Decimal normalized = range == 0
                    ? 0
                    : (e.raw.get(term) - lows.get(term))
                        .divide(range, 6, System.RoundingMode.HALF_UP);
                Decimal weight = weights.get(term);
                Decimal contribution = weight * normalized;
                total += contribution;

                RenewAIDTO.TermScore t = new RenewAIDTO.TermScore();
                t.term = term;
                t.rawValue = e.raw.get(term)
                    .setScale(2, System.RoundingMode.HALF_UP);
                t.normalized = normalized
                    .setScale(4, System.RoundingMode.HALF_UP);
                t.weight = weight;
                t.contribution = contribution
                    .setScale(4, System.RoundingMode.HALF_UP);
                e.result.breakdown.add(t);
            }

            e.result.score = total.setScale(4, System.RoundingMode.HALF_UP);
        }
    }

    // Insertion sort by score, then by original order (stable and tiny).
    private static void sortByScore(List<Evaluated> items) {
        for (Integer i = 1; i < items.size(); i++) {
            Evaluated current = items[i];
            Integer j = i - 1;
            while (j >= 0 && isBetter(current, items[j])) {
                items[j + 1] = items[j];
                j--;
            }
            items[j + 1] = current;
        }
    }

    private static Boolean isBetter(Evaluated a, Evaluated b) {
        if (a.result.score != b.result.score) {
            return a.result.score < b.result.score;
        }
        return a.sequence < b.sequence;
    }

    // --------------------------------------------------------------- actions

    private static List<RenewAIDTO.ActionLine> buildActions(
        Context ctx,
        Caps caps,
        Plan p
    ) {
        List<RenewAIDTO.ActionLine> lines =
            new List<RenewAIDTO.ActionLine>();

        lines.addAll(allocate('Discharge', p.discharge,
            ctx.batteries, caps.batteryDischarge, caps.dischargeMW));
        lines.addAll(allocate('Charge', p.charge,
            ctx.batteries, caps.batteryCharge, caps.chargeMW));
        lines.addAll(allocate('Reserve', p.reserve,
            ctx.batteries, caps.batteryDischarge, caps.dischargeMW));

        if (p.buy >= 0.005) {
            lines.add(new RenewAIDTO.ActionLine('Buy',
                ctx.gridAssetCode, round2(p.buy)));
        }
        if (p.sell >= 0.005) {
            lines.add(new RenewAIDTO.ActionLine('Sell',
                ctx.gridAssetCode, round2(p.sell)));
        }
        if (p.curtail >= 0.005) {
            lines.add(new RenewAIDTO.ActionLine('Curtail',
                'PORTFOLIO', round2(p.curtail)));
        }

        return lines;
    }

    private static List<RenewAIDTO.ActionLine> allocate(
        String actionType,
        Decimal quantity,
        List<Battery> batteries,
        List<Decimal> batteryCaps,
        Decimal totalCap
    ) {
        List<RenewAIDTO.ActionLine> lines =
            new List<RenewAIDTO.ActionLine>();

        if (quantity < 0.005) {
            return lines;
        }

        if (totalCap <= 0) {
            lines.add(new RenewAIDTO.ActionLine(
                actionType, 'BATTERY_FLEET', round2(quantity)));
            return lines;
        }

        Integer lastIndex = -1;
        for (Integer i = 0; i < batteries.size(); i++) {
            if (batteryCaps[i] > 0) { lastIndex = i; }
        }

        Decimal allocated = 0;
        for (Integer i = 0; i < batteries.size(); i++) {
            if (batteryCaps[i] <= 0) { continue; }

            Decimal share = (i == lastIndex)
                ? quantity - allocated
                : round2((quantity * batteryCaps[i])
                    .divide(totalCap, 6, System.RoundingMode.HALF_UP));
            allocated += share;

            if (share >= 0.005) {
                lines.add(new RenewAIDTO.ActionLine(
                    actionType, batteries[i].assetCode, round2(share)));
            }
        }
        return lines;
    }

    private static Decimal round2(Decimal value) {
        return value.setScale(2, System.RoundingMode.HALF_UP);
    }

    // ------------------------------------------------------------ narrative

    private static String decisionType(Plan p) {
        String kind = 'Hold';
        Decimal best = TOLERANCE_MW;

        if (p.discharge > best) { kind = 'Discharge'; best = p.discharge; }
        if (p.charge > best) { kind = 'Charge'; best = p.charge; }
        if (p.curtail > best) { kind = 'Curtail'; best = p.curtail; }
        if (p.buy > best) { kind = 'Buy Power'; best = p.buy; }
        if (p.sell > best) { kind = 'Sell Power'; best = p.sell; }

        return kind;
    }

    // One line per action type, e.g. "Discharge 0.97 MW; Reserve 7.25 MW".
    private static String summarize(List<RenewAIDTO.ActionLine> actions) {
        if (actions.isEmpty()) {
            return 'Hold: no action required';
        }

        List<String> typeOrder = new List<String>{
            'Discharge', 'Charge', 'Reserve', 'Buy', 'Sell', 'Curtail'
        };
        List<String> parts = new List<String>();

        for (String actionType : typeOrder) {
            Decimal total = 0;
            for (RenewAIDTO.ActionLine line : actions) {
                if (line.actionType == actionType) {
                    total += line.quantityMW;
                }
            }
            if (total > 0) {
                parts.add(actionType + ' ' + round2(total).toPlainString() + ' MW');
            }
        }

        String text = String.join(parts, '; ');
        return text.length() > 255 ? text.substring(0, 255) : text;
    }

    private static String explain(
        Context ctx,
        EngineResult result,
        String mode,
        List<Evaluated> feasible,
        Integer rejectedCount
    ) {
        Decimal gap = ctx.demandMW - ctx.renewableMW;
        RenewAIDTO.CandidateResult sel = result.selected;

        String text =
            'At ' + ctx.asOf.formatGmt('yyyy-MM-dd HH:mm') + ' UTC, renewables ' +
            'produce ' + q(ctx.renewableMW) + ' MW against demand of ' +
            q(ctx.demandMW) + ' MW (gap ' + q(gap) + ' MW) at a price of ' +
            q(ctx.priceMWh) + ' per MWh. Under the ' + mode +
            ' objective the engine selected "' + sel.label + '" (score ' +
            sel.score.toPlainString() + '): ' + result.recommendedAction + '.';

        if (feasible.size() > 1) {
            RenewAIDTO.CandidateResult runnerUp = feasible[1].result;
            text += ' Runner-up: "' + runnerUp.label + '" (score ' +
                runnerUp.score.toPlainString() + ').';
        }

        text += ' ' + rejectedCount + ' candidate(s) were rejected by hard ' +
            'constraints. Forecast confidence is ' +
            q(ctx.confidence * 100) + '% and the reserve target is ' +
            result.reserveMW.toPlainString() + ' MW.';

        if (result.approvalStatus == 'Pending') {
            text += ' Operator approval is required before execution ' +
                '(low confidence or high reliability risk).';
        }

        return text;
    }
}
