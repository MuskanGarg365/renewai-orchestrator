/**
 * Runs the two-hour simulation: loads eight intervals, simulates the chosen
 * objective (and optionally the other three for comparison), saves one
 * Decision__c per step and a Scenario__c that tracks the status.
 */
public with sharing class RenewAISimulationService {

    // Lets a unit test prove that a mid-run failure rolls everything back.
    @TestVisible
    private static Boolean forceFailure = false;

    public static final List<String> MODES = new List<String>{
        'Balanced', 'Cost First', 'Clean Energy First', 'Reliability First'
    };

    public static RenewAIDTO.SimulationResponse run(
        RenewAIDTO.SimulationRequest request,
        String correlationId
    ) {
        if (request == null) {
            throw validation(
                'request', 'REQUIRED', 'A simulation request is required.');
        }
        if (request.asOf == null) {
            throw validation('asOf', 'REQUIRED', 'asOf is required.');
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
        if (!MODES.contains(mode)) {
            throw validation(
                'objectiveMode',
                'INVALID_MODE',
                'Use Balanced, Cost First, Clean Energy First or Reliability First.'
            );
        }
        Boolean compare = request.compareModes == null
            ? true
            : request.compareModes;

        // Eight intervals, each validated and read by the normal portfolio
        // service. A bad time or missing data gives a structured 400 here.
        List<RenewAIDecisionEngine.Context> baseContexts =
            new List<RenewAIDecisionEngine.Context>();
        for (Integer i = 0; i < RenewAISimulationEngine.STEPS; i++) {
            baseContexts.add(RenewAIDecisionService.loadContext(
                request.asOf.addMinutes(
                    i * RenewAIInputValidator.INTERVAL_MINUTES),
                correlationId));
        }

        List<Decimal> profile =
            RenewAISimulationEngine.profileFor(request.scenarioType);
        String scenarioName = ('Simulation: ' + request.scenarioType + ' ' +
            request.asOf.formatGmt('yyyy-MM-dd HH:mm')).left(80);

        Savepoint savepoint = Database.setSavepoint();
        try {
            Scenario__c scenario = new Scenario__c(
                Name = scenarioName,
                Scenario_Key__c = correlationId,
                Scenario_Type__c = request.scenarioType,
                Status__c = 'Running',
                Objective_Mode__c = mode,
                As_Of__c = request.asOf,
                Correlation_Id__c = correlationId,
                Time_Horizon_Hours__c = 2,
                Parameters__c = JSON.serialize(profile)
            );
            insert as user scenario;

            RenewAISimulationEngine.Outcome primary =
                RenewAISimulationEngine.simulate(
                    baseContexts, request.scenarioType, mode);

            // Save one decision per step, linked to the scenario.
            for (Integer i = 0; i < RenewAISimulationEngine.STEPS; i++) {
                RenewAIDTO.DecisionResponse saved =
                    RenewAIDecisionService.saveDecision(
                        primary.contexts[i], mode, correlationId,
                        correlationId + '-S' + i, scenario.Id,
                        'Simulation', i, primary.results[i]);
                primary.run.steps[i].decisionId =
                    String.valueOf(saved.decisionId);
            }

            if (forceFailure) {
                throw new IllegalArgumentException(
                    'Simulated failure after saving the decisions');
            }

            RenewAIDTO.SimulationResponse response =
                new RenewAIDTO.SimulationResponse();
            response.correlationId = correlationId;
            response.scenarioId = scenario.Id;
            response.scenarioType = request.scenarioType;
            response.description =
                RenewAIScenarioCatalog.descriptionFor(request.scenarioType);
            response.status = 'Completed';
            response.asOf = request.asOf;
            response.intervalMinutes = RenewAIInputValidator.INTERVAL_MINUTES;
            response.objectiveMode = mode;
            response.intensityProfile = profile;
            response.primary = primary.run;

            // Comparison runs use the same inputs but are not saved.
            if (compare) {
                for (String other : MODES) {
                    response.comparison.add(
                        other == mode
                            ? primary.run
                            : RenewAISimulationEngine.simulate(
                                baseContexts, request.scenarioType, other).run
                    );
                }
            }

            Map<String, Object> results = new Map<String, Object>();
            for (RenewAIDTO.SimRun r : response.comparison) {
                results.put(r.objectiveMode, r.totals);
            }
            results.put('primary', primary.run.totals);

            scenario.Status__c = 'Completed';
            scenario.Results__c = JSON.serialize(results);
            update as user scenario;

            return response;
        } catch (Exception exceptionRecord) {
            Database.rollback(savepoint);
            recordFailure(
                scenarioName, request, mode, correlationId, exceptionRecord);
            throw exceptionRecord;
        }
    }

    // After a rollback, keep a small audit row so the failure is visible.
    private static void recordFailure(
        String scenarioName,
        RenewAIDTO.SimulationRequest request,
        String mode,
        String correlationId,
        Exception exceptionRecord
    ) {
        try {
            insert as user new Scenario__c(
                Name = scenarioName,
                Scenario_Key__c = correlationId,
                Scenario_Type__c = request.scenarioType,
                Status__c = 'Failed',
                Objective_Mode__c = mode,
                As_Of__c = request.asOf,
                Correlation_Id__c = correlationId,
                Time_Horizon_Hours__c = 2,
                Notes__c = (exceptionRecord.getTypeName() + ': ' +
                    exceptionRecord.getMessage()).left(2000)
            );
        } catch (Exception ignored) {
            System.debug(
                LoggingLevel.ERROR,
                'RenewAI could not record the failed simulation: ' +
                ignored.getMessage()
            );
        }
    }

    // ------------------------------------------------------------- cancel

    /**
     * Marks a saved simulation as Cancelled. A synchronous Apex call cannot
     * be interrupted while it runs, so this is the way to discard a run
     * that has already been saved.
     */
    public static RenewAIDTO.SimulationCancelResponse cancel(
        RenewAIDTO.SimulationCancelRequest request,
        String correlationId
    ) {
        if (request == null || String.isBlank(request.scenarioId)) {
            throw validation(
                'scenarioId', 'REQUIRED', 'A scenario ID is required.');
        }

        Id scenarioId;
        try {
            scenarioId = Id.valueOf(request.scenarioId.trim());
        } catch (Exception exceptionRecord) {
            throw validation(
                'scenarioId', 'INVALID_ID', 'That is not a valid scenario ID.');
        }

        List<Scenario__c> rows = [
            SELECT Id, Status__c
            FROM Scenario__c
            WHERE Id = :scenarioId
            WITH USER_MODE
            LIMIT 1
        ];
        if (rows.isEmpty()) {
            throw validation(
                'scenarioId', 'SCENARIO_NOT_FOUND', 'No scenario has that ID.');
        }

        Scenario__c scenario = rows[0];
        if (scenario.Status__c != 'Cancelled') {
            scenario.Status__c = 'Cancelled';
            update as user scenario;
        }

        RenewAIDTO.SimulationCancelResponse response =
            new RenewAIDTO.SimulationCancelResponse();
        response.correlationId = correlationId;
        response.scenarioId = String.valueOf(scenario.Id);
        response.status = 'Cancelled';
        return response;
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
