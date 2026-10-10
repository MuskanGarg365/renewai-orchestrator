@IsTest
private class RenewAIAgentActionsTest {

    static final Datetime AS_OF = Datetime.newInstanceGmt(2026, 10, 8, 12, 0, 0);
    static final String AS_OF_TEXT = '2026-10-08T12:00:00Z';

    @TestSetup
    static void setupData() {
        List<RenewAI_Energy_Asset__c> assets = new List<RenewAI_Energy_Asset__c>{
            asset('SOLAR_MH_01', 'Solar Asset', 'Solar', 50),
            asset('WIND_MH_01', 'Wind Asset', 'Wind', 75),
            asset('BATTERY_MH_01', 'Battery Asset', 'Battery', 20),
            asset('IND_DEMAND_01', 'Industrial Demand', 'Industrial Demand', 150),
            asset('GRID_INDIA_01', 'Grid', 'Grid', 150)
        };
        insert assets;

        Map<String, Id> ids = new Map<String, Id>();
        for (RenewAI_Energy_Asset__c a : assets) {
            ids.put(a.Asset_Code__c, a.Id);
        }

        insert new List<Operating_Snapshot__c>{
            snapshot(ids.get('SOLAR_MH_01'), 'SOLAR-1200', 40, 0),
            snapshot(ids.get('WIND_MH_01'), 'WIND-1200', 60, 0),
            snapshot(ids.get('IND_DEMAND_01'), 'DEMAND-1200', 0, 130)
        };

        insert new Battery_State__c(
            Name = 'BATTERY-1200',
            Energy_Asset__c = ids.get('BATTERY_MH_01'),
            Battery_State_Key__c = 'BATTERY-1200',
            Timestamp__c = AS_OF,
            State_Of_Charge__c = 70,
            Charge_MW__c = 0,
            Discharge_MW__c = 0,
            Available_Capacity__c = 28
        );

        insert new Market_Signal__c(
            Name = 'MKT-1200',
            Market_Signal_Key__c = 'MKT-1200',
            Timestamp__c = AS_OF,
            Energy_Price_MWh__c = 4200
        );
    }

    // ------------------------------------------------- Get Portfolio State

    @IsTest
    static void portfolioStateReturnsNumbersAndCorrelationId() {
        RenewAIAgentGetPortfolioState.Request request =
            new RenewAIAgentGetPortfolioState.Request();
        request.asOf = AS_OF_TEXT;

        RenewAIAgentGetPortfolioState.Response r =
            RenewAIAgentGetPortfolioState.run(
                new List<RenewAIAgentGetPortfolioState.Request>{ request })[0];

        System.assertEquals(true, r.success);
        System.assert(r.correlationId.startsWith('RENEWAI-'));
        assertClose(100, r.renewableMW, 0.01, 'renewable');
        assertClose(130, r.demandMW, 0.01, 'demand');
        assertClose(30, r.demandGapMW, 0.01, 'gap');
        assertClose(4200, r.energyPriceMWh, 0.01, 'price');
        assertClose(80, r.confidencePct, 0.01, 'confidence');
        System.assert(r.batteryStatus.contains('BATTERY_MH_01'));
        System.assert(r.summary.contains('UTC'));
    }

    @IsTest
    static void portfolioStateReportsAMisalignedTimeAsAStructuredError() {
        RenewAIAgentGetPortfolioState.Request request =
            new RenewAIAgentGetPortfolioState.Request();
        request.asOf = '2026-10-08T12:07:00Z';

        RenewAIAgentGetPortfolioState.Response r =
            RenewAIAgentGetPortfolioState.run(
                new List<RenewAIAgentGetPortfolioState.Request>{ request })[0];

        System.assertEquals(false, r.success);
        System.assertEquals('INTERVAL_MISALIGNED', r.errorCode);
        System.assertNotEquals(null, r.correlationId);
    }

    // ---------------------------------------------------------- Run Decision

    @IsTest
    static void runDecisionSavesAndReturnsSetpoints() {
        RenewAIAgentRunDecision.Request request =
            new RenewAIAgentRunDecision.Request();
        request.objectiveMode = 'Cost First';
        request.asOf = AS_OF_TEXT;

        RenewAIAgentRunDecision.Response r = RenewAIAgentRunDecision.run(
            new List<RenewAIAgentRunDecision.Request>{ request })[0];

        System.assertEquals(true, r.success);
        System.assertEquals('Cost First', r.objectiveMode);
        System.assertNotEquals(null, r.selectedLabel);
        System.assertNotEquals(null, r.setpoints);
        System.assert(
            r.approvalStatus == 'Pending' || r.approvalStatus == 'Not Required');
        System.assertNotEquals(null, r.scoreBreakdown);
        System.assertNotEquals(null, r.explanation);
        System.assertEquals(1, [SELECT COUNT() FROM Decision__c
            WHERE Correlation_Id__c = :r.correlationId]);
    }

    @IsTest
    static void runDecisionDefaultsToBalanced() {
        RenewAIAgentRunDecision.Request request =
            new RenewAIAgentRunDecision.Request();
        request.asOf = AS_OF_TEXT;

        RenewAIAgentRunDecision.Response r = RenewAIAgentRunDecision.run(
            new List<RenewAIAgentRunDecision.Request>{ request })[0];

        System.assertEquals(true, r.success);
        System.assertEquals('Balanced', r.objectiveMode);
    }

    // The "simulated tool failure": an invalid objective must come back as a
    // structured error the agent can explain, never an unhandled fault.
    @IsTest
    static void runDecisionToolFailureIsStructuredAndSavesNothing() {
        RenewAIAgentRunDecision.Request request =
            new RenewAIAgentRunDecision.Request();
        request.objectiveMode = 'Fastest';
        request.asOf = AS_OF_TEXT;

        RenewAIAgentRunDecision.Response r = RenewAIAgentRunDecision.run(
            new List<RenewAIAgentRunDecision.Request>{ request })[0];

        System.assertEquals(false, r.success);
        System.assertEquals('INVALID_MODE', r.errorCode);
        System.assertNotEquals(null, r.errorMessage);
        System.assertNotEquals(null, r.correlationId);
        System.assertEquals(null, r.selectedLabel);
        System.assertEquals(0, [SELECT COUNT() FROM Decision__c]);
    }

    @IsTest
    static void runDecisionRejectsAnUnreadableTime() {
        RenewAIAgentRunDecision.Request request =
            new RenewAIAgentRunDecision.Request();
        request.asOf = 'tomorrow morning';

        RenewAIAgentRunDecision.Response r = RenewAIAgentRunDecision.run(
            new List<RenewAIAgentRunDecision.Request>{ request })[0];

        System.assertEquals(false, r.success);
        System.assertEquals('INVALID_DATETIME', r.errorCode);
    }

    // ---------------------------------------------------------- Run Scenario

    @IsTest
    static void runScenarioReturnsBeforeAndAfter() {
        RenewAIAgentRunScenario.Request request =
            new RenewAIAgentRunScenario.Request();
        request.scenarioType = 'Cloud Front';
        request.asOf = AS_OF_TEXT;

        RenewAIAgentRunScenario.Response r = RenewAIAgentRunScenario.run(
            new List<RenewAIAgentRunScenario.Request>{ request })[0];

        System.assertEquals(true, r.success);
        System.assertEquals('Cloud Front', r.scenarioType);
        System.assert(r.appliedChanges.contains('Solar output'));
        System.assertNotEquals(null, r.baselineSetpoints);
        System.assertNotEquals(null, r.disturbedSetpoints);
        System.assertNotEquals(null, r.decisionChanged);
        System.assertNotEquals(null, r.keyChanges);
        System.assertEquals(1, [SELECT COUNT() FROM Scenario__c]);
        System.assertEquals(2, [SELECT COUNT() FROM Decision__c
            WHERE Correlation_Id__c = :r.correlationId]);
    }

    @IsTest
    static void runScenarioRejectsAnUnknownScenario() {
        RenewAIAgentRunScenario.Request request =
            new RenewAIAgentRunScenario.Request();
        request.scenarioType = 'Meteor';
        request.asOf = AS_OF_TEXT;

        RenewAIAgentRunScenario.Response r = RenewAIAgentRunScenario.run(
            new List<RenewAIAgentRunScenario.Request>{ request })[0];

        System.assertEquals(false, r.success);
        System.assertEquals('INVALID_SCENARIO', r.errorCode);
        System.assertEquals(0, [SELECT COUNT() FROM Scenario__c]);
    }

    // ------------------------------------------------ Get Decision Explanation

    @IsTest
    static void explanationFoundByDecisionIdAndByCorrelationId() {
        RenewAIAgentRunDecision.Request run =
            new RenewAIAgentRunDecision.Request();
        run.asOf = AS_OF_TEXT;
        RenewAIAgentRunDecision.Response saved = RenewAIAgentRunDecision.run(
            new List<RenewAIAgentRunDecision.Request>{ run })[0];

        RenewAIAgentGetExplanation.Request byId =
            new RenewAIAgentGetExplanation.Request();
        byId.decisionId = saved.decisionId;
        RenewAIAgentGetExplanation.Response a = RenewAIAgentGetExplanation.run(
            new List<RenewAIAgentGetExplanation.Request>{ byId })[0];

        System.assertEquals(true, a.success);
        System.assertEquals(saved.correlationId, a.correlationId);
        System.assertEquals(saved.explanation, a.explanation);
        System.assertEquals('Balanced', a.objectiveMode);

        RenewAIAgentGetExplanation.Request byCorrelation =
            new RenewAIAgentGetExplanation.Request();
        byCorrelation.correlationId = saved.correlationId;
        RenewAIAgentGetExplanation.Response b = RenewAIAgentGetExplanation.run(
            new List<RenewAIAgentGetExplanation.Request>{ byCorrelation })[0];

        System.assertEquals(true, b.success);
        System.assertEquals(saved.decisionId, b.decisionId);
    }

    @IsTest
    static void explanationForAScenarioReturnsTheDisturbedDecision() {
        RenewAIAgentRunScenario.Request scenario =
            new RenewAIAgentRunScenario.Request();
        scenario.scenarioType = 'Demand Surge';
        scenario.asOf = AS_OF_TEXT;
        RenewAIAgentRunScenario.Response saved = RenewAIAgentRunScenario.run(
            new List<RenewAIAgentRunScenario.Request>{ scenario })[0];

        RenewAIAgentGetExplanation.Request request =
            new RenewAIAgentGetExplanation.Request();
        request.correlationId = saved.correlationId;
        RenewAIAgentGetExplanation.Response r = RenewAIAgentGetExplanation.run(
            new List<RenewAIAgentGetExplanation.Request>{ request })[0];

        System.assertEquals(true, r.success);
        System.assertEquals('Disturbed', r.scenarioPhase);
    }

    @IsTest
    static void explanationErrorsAreStructured() {
        RenewAIAgentGetExplanation.Request missing =
            new RenewAIAgentGetExplanation.Request();
        RenewAIAgentGetExplanation.Response a = RenewAIAgentGetExplanation.run(
            new List<RenewAIAgentGetExplanation.Request>{ missing })[0];
        System.assertEquals(false, a.success);
        System.assertEquals('REQUIRED', a.errorCode);

        RenewAIAgentGetExplanation.Request badId =
            new RenewAIAgentGetExplanation.Request();
        badId.decisionId = 'not-an-id';
        RenewAIAgentGetExplanation.Response b = RenewAIAgentGetExplanation.run(
            new List<RenewAIAgentGetExplanation.Request>{ badId })[0];
        System.assertEquals('INVALID_ID', b.errorCode);

        RenewAIAgentGetExplanation.Request unknown =
            new RenewAIAgentGetExplanation.Request();
        unknown.correlationId = 'RENEWAI-DOESNOTEXIST';
        RenewAIAgentGetExplanation.Response c = RenewAIAgentGetExplanation.run(
            new List<RenewAIAgentGetExplanation.Request>{ unknown })[0];
        System.assertEquals(false, c.success);
        System.assertEquals('DECISION_NOT_FOUND', c.errorCode);
    }

    // ------------------------------------------------------------- helpers

    private static RenewAI_Energy_Asset__c asset(
        String code, String name, String type, Decimal capacity
    ) {
        return new RenewAI_Energy_Asset__c(
            Name = name,
            Asset_Code__c = code,
            Asset_Type__c = type,
            Capacity_MW__c = capacity,
            Status__c = 'Active'
        );
    }

    private static Operating_Snapshot__c snapshot(
        Id assetId, String key, Decimal generation, Decimal demand
    ) {
        return new Operating_Snapshot__c(
            Energy_Asset__c = assetId,
            Snapshot_Key__c = key,
            Timestamp__c = AS_OF,
            Generation_MW__c = generation,
            Demand_MW__c = demand,
            Grid_Frequency_Hz__c = 50,
            Weather_Score__c = 80
        );
    }

    private static void assertClose(
        Decimal expected, Decimal actual, Decimal tolerance, String message
    ) {
        System.assert(
            actual != null && Math.abs(expected - actual) <= tolerance,
            message + ': expected ' + expected + ' but got ' + actual
        );
    }
}
