/**
 * Pure two-hour simulation: eight 15-minute steps. No SOQL, no DML.
 *
 * For each step it applies the scenario at that step's intensity, runs the
 * deterministic decision engine, books the KPIs and carries the battery
 * charge level into the next step. Same inputs always give the same result.
 */
public with sharing class RenewAISimulationEngine {

    public static final Integer STEPS = 8;

    // A step counts as a reliability event when the selected plan leaves at
    // least 30% of the reserve target unmet (reliability term >= 0.30).
    public static final Decimal RELIABILITY_EVENT_THRESHOLD = 0.30;

    public class Outcome {
        public RenewAIDTO.SimRun run = new RenewAIDTO.SimRun();
        public List<RenewAIDecisionEngine.Context> contexts =
            new List<RenewAIDecisionEngine.Context>();
        public List<RenewAIDecisionEngine.EngineResult> results =
            new List<RenewAIDecisionEngine.EngineResult>();
    }

    // How strongly the disturbance acts in each of the eight steps.
    public static List<Decimal> profileFor(String scenarioType) {
        switch on scenarioType {
            when 'Cloud Front' {
                return new List<Decimal>{ 0, 0, 0.5, 1, 1, 1, 0.5, 0 };
            }
            when 'Price Spike' {
                return new List<Decimal>{ 0, 0, 1, 1, 1, 0, 0, 0 };
            }
            when 'Demand Surge' {
                return new List<Decimal>{ 0, 0, 0.5, 1, 1, 1, 1, 0.5 };
            }
            when 'Battery Outage' {
                return new List<Decimal>{ 0, 0, 0, 1, 1, 1, 1, 1 };
            }
            when else {
                return new List<Decimal>{ 0, 0, 0, 0, 0, 0, 0, 0 };
            }
        }
    }

    public static Outcome simulate(
        List<RenewAIDecisionEngine.Context> baseContexts,
        String scenarioType,
        String mode
    ) {
        if (baseContexts == null || baseContexts.size() != STEPS) {
            throw new RenewAIValidationException(
                new List<RenewAIDTO.ErrorDetail>{
                    new RenewAIDTO.ErrorDetail(
                        'steps',
                        'INVALID_STEPS',
                        'A simulation needs exactly ' + STEPS + ' intervals.'
                    )
                }
            );
        }

        List<Decimal> profile = profileFor(scenarioType);
        Outcome outcome = new Outcome();
        outcome.run.objectiveMode = mode;

        RenewAIDTO.SimTotals totals = new RenewAIDTO.SimTotals();
        totals.energyCostINR = 0;
        totals.revenueINR = 0;
        totals.carbonT = 0;
        totals.curtailedMWh = 0;
        totals.reliabilityEvents = 0;
        totals.pendingApprovals = 0;
        totals.clusterChanges = 0;

        Map<String, Decimal> socByCode = new Map<String, Decimal>();
        String previousCluster = null;
        List<String> signature = new List<String>();

        for (Integer i = 0; i < STEPS; i++) {
            RenewAIDecisionEngine.Context base =
                RenewAIScenarioCatalog.copyOf(baseContexts[i]);

            // From step 1 on, the batteries start where the last step left them.
            for (RenewAIDecisionEngine.Battery b : base.batteries) {
                if (socByCode.containsKey(b.assetCode)) {
                    b.socPercent = socByCode.get(b.assetCode);
                }
            }

            RenewAIDecisionEngine.Context ctx =
                RenewAIScenarioCatalog.apply(
                    base, scenarioType, profile[i]).context;

            RenewAIDecisionEngine.EngineResult result =
                RenewAIDecisionEngine.decide(ctx, mode);
            List<RenewAIDTO.ActionLine> actions = result.selected.actions;

            Decimal buy = sumOf(actions, 'Buy', null);
            Decimal sell = sumOf(actions, 'Sell', null);
            Decimal curtail = sumOf(actions, 'Curtail', null);
            Decimal discharge = sumOf(actions, 'Discharge', null);
            Decimal charge = sumOf(actions, 'Charge', null);

            Decimal energyCost = buy * ctx.priceMWh *
                RenewAIDecisionEngine.BUY_PRICE_FACTOR *
                RenewAIDecisionEngine.INTERVAL_HOURS;
            Decimal revenue = sell * ctx.priceMWh *
                RenewAIDecisionEngine.SELL_PRICE_FACTOR *
                RenewAIDecisionEngine.INTERVAL_HOURS;
            Decimal carbon = buy * RenewAIDecisionEngine.INTERVAL_HOURS *
                RenewAIDecisionEngine.CARBON_T_PER_MWH;
            Decimal curtailed = curtail * RenewAIDecisionEngine.INTERVAL_HOURS;
            Boolean reliabilityEvent = reliabilityOf(result) >=
                RELIABILITY_EVENT_THRESHOLD;

            totals.energyCostINR += energyCost;
            totals.revenueINR += revenue;
            totals.carbonT += carbon;
            totals.curtailedMWh += curtailed;
            if (reliabilityEvent) {
                totals.reliabilityEvents++;
            }
            if (result.approvalStatus == 'Pending') {
                totals.pendingApprovals++;
            }
            if (previousCluster != null &&
                previousCluster != result.selected.candidateId) {
                totals.clusterChanges++;
            }
            previousCluster = result.selected.candidateId;

            RenewAIDTO.SimStep step = new RenewAIDTO.SimStep();
            step.stepIndex = i;
            step.timestamp = ctx.asOf;
            step.intensity = profile[i];
            step.renewableMW = round2(ctx.renewableMW);
            step.demandMW = round2(ctx.demandMW);
            step.priceMWh = round2(ctx.priceMWh);
            step.confidencePct = round2(ctx.confidence * 100);
            step.reserveMW = round2(result.reserveMW);
            step.clusterId = result.selected.candidateId;
            step.clusterLabel = result.selected.label;
            step.setpoints = RenewAIAgentSupport.describeActions(actions);
            step.approvalStatus = result.approvalStatus;
            step.reliabilityEvent = reliabilityEvent;
            step.dischargeMW = round2(discharge);
            step.chargeMW = round2(charge);
            step.buyMW = round2(buy);
            step.sellMW = round2(sell);
            step.curtailMW = round2(curtail);
            step.energyCostINR = round2(energyCost);
            step.revenueINR = round2(revenue);
            step.carbonT = round2(carbon);
            step.curtailedMWh = round2(curtailed);
            step.cumEnergyCostINR = round2(totals.energyCostINR);
            step.cumRevenueINR = round2(totals.revenueINR);
            step.cumCarbonT = round2(totals.carbonT);
            step.cumCurtailedMWh = round2(totals.curtailedMWh);
            step.cumReliabilityEvents = totals.reliabilityEvents;

            // Carry battery charge forward.
            for (RenewAIDecisionEngine.Battery b : ctx.batteries) {
                Decimal out = sumOf(actions, 'Discharge', b.assetCode);
                Decimal inn = sumOf(actions, 'Charge', b.assetCode);
                Decimal energyMWh = b.ratedMW *
                    RenewAIDecisionEngine.BATTERY_ENERGY_HOURS;
                Decimal change = energyMWh > 0
                    ? (inn - out) * RenewAIDecisionEngine.INTERVAL_HOURS /
                        energyMWh * 100
                    : 0.0;
                Decimal next = Math.min(Math.max(b.socPercent + change, 0), 100);
                socByCode.put(b.assetCode, next);
                step.batteries.add(new RenewAIDTO.BatteryPoint(
                    b.assetCode, round2(next), b.available));
            }

            signature.add(
                result.selected.candidateId + ':' + step.setpoints);

            outcome.run.steps.add(step);
            outcome.contexts.add(ctx);
            outcome.results.add(result);
        }

        totals.netCostINR = round2(totals.energyCostINR - totals.revenueINR);
        totals.energyCostINR = round2(totals.energyCostINR);
        totals.revenueINR = round2(totals.revenueINR);
        totals.carbonT = round2(totals.carbonT);
        totals.curtailedMWh = round2(totals.curtailedMWh);

        outcome.run.totals = totals;
        outcome.run.checksum = EncodingUtil.convertToHex(
            Crypto.generateDigest(
                'MD5', Blob.valueOf(String.join(signature, '|')))
        ).substring(0, 12).toUpperCase();

        return outcome;
    }

    // ------------------------------------------------------------- helpers

    // assetCode = null sums every asset.
    private static Decimal sumOf(
        List<RenewAIDTO.ActionLine> actions,
        String actionType,
        String assetCode
    ) {
        Decimal total = 0;
        for (RenewAIDTO.ActionLine line : actions) {
            if (line.actionType == actionType &&
                (assetCode == null || line.assetCode == assetCode)) {
                total += line.quantityMW;
            }
        }
        return total;
    }

    private static Decimal reliabilityOf(
        RenewAIDecisionEngine.EngineResult result
    ) {
        for (RenewAIDTO.TermScore t : result.selected.breakdown) {
            if (t.term == 'reliability') {
                return t.rawValue == null ? 0 : t.rawValue;
            }
        }
        return 0;
    }

    private static Decimal round2(Decimal value) {
        return value.setScale(2, System.RoundingMode.HALF_UP);
    }
}
