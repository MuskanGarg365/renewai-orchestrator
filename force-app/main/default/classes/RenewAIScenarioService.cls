/**
 * Runs one scripted scenario: a baseline decision, then the same decision
 * after the disturbance. Both are saved and linked to a Scenario__c record.
 */
public with sharing class RenewAIScenarioService {

    public static RenewAIDTO.ScenarioResponse run(
        RenewAIDTO.ScenarioRequest request,
        String correlationId
    ) {
        if (request == null) {
            throw validation(
                'request', 'REQUIRED', 'A scenario request is required.');
        }
        if (!RenewAIScenarioCatalog.isSupported(request.scenarioType)) {
            throw validation(
                'scenarioType',
                'INVALID_SCENARIO',
                'Use Cloud Front, Price Spike, Demand Surge or Battery Outage.'
            );
        }

        String mode = String.isBlank(request.objectiveMode)
            ? RenewAIScenarioCatalog.defaultModeFor(request.scenarioType)
            : request.objectiveMode;

        // Throws a structured 400 for a bad asOf or a stale portfolio.
        RenewAIDecisionEngine.Context base =
            RenewAIDecisionService.loadContext(request.asOf, correlationId);

        RenewAIScenarioCatalog.Disturbed disturbed =
            RenewAIScenarioCatalog.apply(
                base, request.scenarioType, 1);

        // All-or-nothing: if anything fails, no half-saved scenario remains.
        Savepoint savepoint = Database.setSavepoint();
        try {
            Scenario__c scenario = new Scenario__c(
                Name = (request.scenarioType + ' ' +
                    request.asOf.formatGmt('yyyy-MM-dd HH:mm')).left(80),
                Scenario_Key__c = correlationId,
                Scenario_Type__c = request.scenarioType,
                Status__c = 'Running',
                Objective_Mode__c = mode,
                As_Of__c = request.asOf,
                Correlation_Id__c = correlationId,
                Parameters__c = JSON.serialize(disturbed.changes)
            );
            insert as user scenario;

            RenewAIDTO.DecisionResponse baselineResult =
                RenewAIDecisionService.decideAndPersist(
                    base, mode, correlationId, correlationId + '-BASE',
                    scenario.Id, 'Baseline', null);

            RenewAIDTO.DecisionResponse disturbedResult =
                RenewAIDecisionService.decideAndPersist(
                    disturbed.context, mode, correlationId,
                    correlationId + '-EVENT',
                    scenario.Id, 'Disturbed', null);

            scenario.Status__c = 'Completed';
            update as user scenario;

            RenewAIDTO.ScenarioResponse response =
                new RenewAIDTO.ScenarioResponse();
            response.correlationId = correlationId;
            response.scenarioId = scenario.Id;
            response.scenarioType = request.scenarioType;
            response.description =
                RenewAIScenarioCatalog.descriptionFor(request.scenarioType);
            response.objectiveMode = mode;
            response.asOf = request.asOf;
            response.status = 'Completed';
            response.parameters = disturbed.changes;
            response.baseline = baselineResult;
            response.disturbed = disturbedResult;
            response.comparison = compare(baselineResult, disturbedResult);
            return response;
        } catch (Exception exceptionRecord) {
            Database.rollback(savepoint);
            throw exceptionRecord;
        }
    }

    // ---------------------------------------------------------- comparison

    public static RenewAIDTO.ScenarioComparison compare(
        RenewAIDTO.DecisionResponse baseline,
        RenewAIDTO.DecisionResponse disturbed
    ) {
        RenewAIDTO.ScenarioComparison comparison =
            new RenewAIDTO.ScenarioComparison();
        comparison.baselineLabel = baseline.selected.label;
        comparison.disturbedLabel = disturbed.selected.label;
        comparison.decisionChanged =
            baseline.selected.candidateId != disturbed.selected.candidateId;

        comparison.deltas.add(delta('renewableMW', 'Renewable output', 'MW',
            baseline.inputs.renewableMW, disturbed.inputs.renewableMW));
        comparison.deltas.add(delta('demandMW', 'Demand', 'MW',
            baseline.inputs.demandMW, disturbed.inputs.demandMW));
        comparison.deltas.add(delta('priceMWh', 'Energy price', 'INR/MWh',
            baseline.inputs.energyPriceMWh, disturbed.inputs.energyPriceMWh));
        comparison.deltas.add(delta('confidencePct', 'Forecast confidence', '%',
            baseline.confidence * 100, disturbed.confidence * 100));
        comparison.deltas.add(delta('reserveMW', 'Reserve target', 'MW',
            baseline.reserveMW, disturbed.reserveMW));
        comparison.deltas.add(delta('dischargeMW', 'Battery discharge', 'MW',
            total(baseline, 'Discharge'), total(disturbed, 'Discharge')));
        comparison.deltas.add(delta('chargeMW', 'Battery charge', 'MW',
            total(baseline, 'Charge'), total(disturbed, 'Charge')));
        comparison.deltas.add(delta('buyMW', 'Grid purchase', 'MW',
            total(baseline, 'Buy'), total(disturbed, 'Buy')));
        comparison.deltas.add(delta('sellMW', 'Grid sale', 'MW',
            total(baseline, 'Sell'), total(disturbed, 'Sell')));
        comparison.deltas.add(delta('netValueINR', 'Net trading value', 'INR',
            netValue(baseline), netValue(disturbed)));

        return comparison;
    }

    public static Decimal total(
        RenewAIDTO.DecisionResponse decision,
        String actionType
    ) {
        Decimal sum = 0;
        for (RenewAIDTO.ActionLine line : decision.selected.actions) {
            if (line.actionType == actionType) {
                sum += line.quantityMW;
            }
        }
        return sum;
    }

    // Revenue from sales minus cost of purchases over one 15-minute interval.
    public static Decimal netValue(RenewAIDTO.DecisionResponse decision) {
        Decimal price = decision.inputs.energyPriceMWh;
        Decimal revenue = total(decision, 'Sell') * price *
            RenewAIDecisionEngine.SELL_PRICE_FACTOR;
        Decimal cost = total(decision, 'Buy') * price *
            RenewAIDecisionEngine.BUY_PRICE_FACTOR;
        return ((revenue - cost) * RenewAIDecisionEngine.INTERVAL_HOURS)
            .setScale(2, System.RoundingMode.HALF_UP);
    }

    private static RenewAIDTO.MetricDelta delta(
        String metric,
        String label,
        String unit,
        Decimal baselineValue,
        Decimal disturbedValue
    ) {
        RenewAIDTO.MetricDelta d = new RenewAIDTO.MetricDelta();
        d.metric = metric;
        d.label = label;
        d.unit = unit;
        d.baseline = baselineValue.setScale(2, System.RoundingMode.HALF_UP);
        d.disturbed = disturbedValue.setScale(2, System.RoundingMode.HALF_UP);
        d.change = (disturbedValue - baselineValue)
            .setScale(2, System.RoundingMode.HALF_UP);
        return d;
    }

    private static RenewAIValidationException validation(
        String field,
        String code,
        String message
    ) {
        return new RenewAIValidationException(
            new List<RenewAIDTO.ErrorDetail>{
                new RenewAIDTO.ErrorDetail(field, code, message)
            }
        );
    }
}
