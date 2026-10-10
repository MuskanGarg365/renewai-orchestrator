@IsTest
private class RenewAISimulationServiceTest {

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

        List<Operating_Snapshot__c> snapshots = new List<Operating_Snapshot__c>();
        List<Battery_State__c> states = new List<Battery_State__c>();
        List<Market_Signal__c> signals = new List<Market_Signal__c>();

        // Eight 15-minute intervals starting at AS_OF.
        for (Integer i = 0; i < 8; i++) {
            Datetime ts = AS_OF.addMinutes(15 * i);
            String key = String.valueOf(i);

            snapshots.add(snapshot(ids.get('SOLAR_MH_01'), 'SOLAR-' + key, ts, 40, 0));
            snapshots.add(snapshot(ids.get('WIND_MH_01'), 'WIND-' + key, ts, 60, 0));
            snapshots.add(snapshot(ids.get('IND_DEMAND_01'), 'DEMAND-' + key, ts, 0, 130 + i));

            states.add(new Battery_State__c(
                Name = 'BATTERY-' + key,
                Energy_Asset__c = ids.get('BATTERY_MH_01'),
                Battery_State_Key__c = 'BATTERY-' + key,
                Timestamp__c = ts,
                State_Of_Charge__c = 70,
                Charge_MW__c = 0,
                Discharge_MW__c = 0,
                Available_Capacity__c = 28
            ));

            signals.add(new Market_Signal__c(
                Name = 'MKT-' + key,
                Market_Signal_Key__c = 'MKT-' + key,
                Timestamp__c = ts,
                Energy_Price_MWh__c = 4200 + 20 * i
            ));
        }
        insert snapshots;
        insert states;
        insert signals;
    }

    private static RenewAIDTO.SimulationResponse simulate(
        String scenarioType, String correlationId
    ) {
        RenewAIDTO.SimulationRequest request = new RenewAIDTO.SimulationRequest();
        request.asOf = AS_OF;
        request.scenarioType = scenarioType;
        return RenewAISimulationService.run(request, correlationId);
    }

    @IsTest
    static void simulationSavesLinkedDecisionsAndCompletesTheScenario() {
        RenewAIDTO.SimulationResponse r = simulate('Cloud Front', 'TEST-SIM-1');

        System.assertEquals('Completed', r.status);
        System.assertEquals('Balanced', r.objectiveMode);
        System.assertEquals(8, r.primary.steps.size());
        System.assertEquals(8, r.intensityProfile.size());
        System.assertEquals(4, r.comparison.size());
        System.assertNotEquals(null, r.primary.checksum);

        Scenario__c saved = [
            SELECT Status__c, Scenario_Type__c, Time_Horizon_Hours__c,
                   Results__c, Parameters__c, Correlation_Id__c
            FROM Scenario__c
            WHERE Id = :r.scenarioId
        ];
        System.assertEquals('Completed', saved.Status__c);
        System.assertEquals('Cloud Front', saved.Scenario_Type__c);
        System.assertEquals(2, saved.Time_Horizon_Hours__c);
        System.assertNotEquals(null, saved.Results__c);
        System.assertEquals('TEST-SIM-1', saved.Correlation_Id__c);

        List<Decision__c> decisions = [
            SELECT Step_Index__c, Scenario_Phase__c, Objective_Mode__c
            FROM Decision__c
            WHERE Scenario__c = :r.scenarioId
            ORDER BY Step_Index__c
        ];
        System.assertEquals(8, decisions.size());
        for (Integer i = 0; i < 8; i++) {
            System.assertEquals(i, decisions[i].Step_Index__c);
            System.assertEquals('Simulation', decisions[i].Scenario_Phase__c);
            System.assertEquals('Balanced', decisions[i].Objective_Mode__c);
            System.assertEquals(
                String.valueOf(decisions[i].Id), r.primary.steps[i].decisionId);
        }
    }

    // One test per scenario: each run uses about 50 SOQL queries (eight
    // intervals), so they must not share a transaction.
    private static void assertCompletes(String scenarioType) {
        RenewAIDTO.SimulationResponse r = simulate(scenarioType, 'TEST-SIM-X');
        System.assertEquals('Completed', r.status, scenarioType);
        System.assertEquals(8, r.primary.steps.size(), scenarioType);
        System.assertEquals(
            8, [SELECT COUNT() FROM Decision__c WHERE Scenario__c = :r.scenarioId]);
    }

    @IsTest
    static void cloudFrontCompletes() {
        assertCompletes('Cloud Front');
    }

    @IsTest
    static void priceSpikeCompletes() {
        assertCompletes('Price Spike');
    }

    @IsTest
    static void demandSurgeCompletes() {
        assertCompletes('Demand Surge');
    }

    @IsTest
    static void batteryOutageCompletes() {
        assertCompletes('Battery Outage');
    }

    // Test.startTest() gives the second run a fresh set of governor limits.
    @IsTest
    static void twoRunsAreRepeatable() {
        RenewAIDTO.SimulationResponse a = simulate('Demand Surge', 'TEST-SIM-2');

        Test.startTest();
        RenewAIDTO.SimulationResponse b = simulate('Demand Surge', 'TEST-SIM-3');
        Test.stopTest();

        System.assertEquals(a.primary.checksum, b.primary.checksum);
        System.assertEquals(
            a.primary.totals.energyCostINR, b.primary.totals.energyCostINR);
    }

    @IsTest
    static void comparisonCanBeSwitchedOff() {
        RenewAIDTO.SimulationRequest request = new RenewAIDTO.SimulationRequest();
        request.asOf = AS_OF;
        request.scenarioType = 'Price Spike';
        request.compareModes = false;

        RenewAIDTO.SimulationResponse r =
            RenewAISimulationService.run(request, 'TEST-SIM-4');

        System.assertEquals(0, r.comparison.size());
        System.assertEquals('Cost First', r.objectiveMode);
    }

    @IsTest
    static void cancelMarksTheScenarioCancelled() {
        RenewAIDTO.SimulationResponse r = simulate('Cloud Front', 'TEST-SIM-5');

        RenewAIDTO.SimulationCancelRequest cancel =
            new RenewAIDTO.SimulationCancelRequest();
        cancel.scenarioId = String.valueOf(r.scenarioId);

        RenewAIDTO.SimulationCancelResponse c =
            RenewAISimulationService.cancel(cancel, 'TEST-CANCEL-1');
        System.assertEquals('Cancelled', c.status);
        System.assertEquals('Cancelled',
            [SELECT Status__c FROM Scenario__c WHERE Id = :r.scenarioId].Status__c);

        // Cancelling twice is harmless.
        System.assertEquals('Cancelled',
            RenewAISimulationService.cancel(cancel, 'TEST-CANCEL-2').status);
    }

    @IsTest
    static void cancelRejectsBadInput() {
        RenewAIDTO.SimulationCancelRequest missing =
            new RenewAIDTO.SimulationCancelRequest();
        try {
            RenewAISimulationService.cancel(missing, 'TEST-CANCEL-3');
            System.assert(false, 'Expected a validation exception');
        } catch (RenewAIValidationException e) {
            System.assertEquals('REQUIRED', e.validationErrors[0].code);
        }

        RenewAIDTO.SimulationCancelRequest bad =
            new RenewAIDTO.SimulationCancelRequest();
        bad.scenarioId = 'nope';
        try {
            RenewAISimulationService.cancel(bad, 'TEST-CANCEL-4');
            System.assert(false, 'Expected a validation exception');
        } catch (RenewAIValidationException e) {
            System.assertEquals('INVALID_ID', e.validationErrors[0].code);
        }

        RenewAIDTO.SimulationCancelRequest unknown =
            new RenewAIDTO.SimulationCancelRequest();
        unknown.scenarioId =
            Scenario__c.SObjectType.getDescribe().getKeyPrefix() + '000000000000';
        try {
            RenewAISimulationService.cancel(unknown, 'TEST-CANCEL-5');
            System.assert(false, 'Expected a validation exception');
        } catch (RenewAIValidationException e) {
            System.assertEquals('SCENARIO_NOT_FOUND', e.validationErrors[0].code);
        }
    }

    @IsTest
    static void aMidRunFailureRollsBackAndLeavesAFailedAuditRow() {
        RenewAISimulationService.forceFailure = true;
        try {
            simulate('Cloud Front', 'TEST-SIM-6');
            System.assert(false, 'Expected the simulated failure');
        } catch (IllegalArgumentException e) {
            System.assert(e.getMessage().contains('Simulated failure'));
        }

        System.assertEquals(0, [SELECT COUNT() FROM Decision__c]);
        System.assertEquals(0, [SELECT COUNT() FROM Action__c]);

        List<Scenario__c> rows = [
            SELECT Status__c, Notes__c FROM Scenario__c
        ];
        System.assertEquals(1, rows.size());
        System.assertEquals('Failed', rows[0].Status__c);
        System.assert(rows[0].Notes__c.contains('Simulated failure'));
    }

    @IsTest
    static void invalidInputIsRejectedBeforeAnythingIsSaved() {
        RenewAIDTO.SimulationRequest request = new RenewAIDTO.SimulationRequest();
        request.asOf = AS_OF;
        request.scenarioType = 'Meteor';
        try {
            RenewAISimulationService.run(request, 'TEST-SIM-7');
            System.assert(false, 'Expected a validation exception');
        } catch (RenewAIValidationException e) {
            System.assertEquals('INVALID_SCENARIO', e.validationErrors[0].code);
        }

        request.scenarioType = 'Cloud Front';
        request.objectiveMode = 'Fastest';
        try {
            RenewAISimulationService.run(request, 'TEST-SIM-8');
            System.assert(false, 'Expected a validation exception');
        } catch (RenewAIValidationException e) {
            System.assertEquals('INVALID_MODE', e.validationErrors[0].code);
        }
        System.assertEquals(0, [SELECT COUNT() FROM Scenario__c]);
    }

    @IsTest
    static void restPostRunsAndCancelsASimulation() {
        RestRequest req = new RestRequest();
        req.requestUri = '/services/apexrest/renewai/v1/simulation';
        req.httpMethod = 'POST';
        req.requestBody = Blob.valueOf(
            '{"asOf":"' + AS_OF_TEXT + '","scenarioType":"Battery Outage","compareModes":false}');
        RestContext.request = req;
        RestContext.response = new RestResponse();

        Test.startTest();
        RenewAIRestResource.doPost();
        Test.stopTest();

        System.assertEquals(200, RestContext.response.statusCode);
        Map<String, Object> body = (Map<String, Object>) JSON.deserializeUntyped(
            RestContext.response.responseBody.toString());
        System.assertEquals('Completed', body.get('status'));
        String scenarioId = (String) body.get('scenarioId');
        System.assertNotEquals(null, scenarioId);

        RestRequest cancelReq = new RestRequest();
        cancelReq.requestUri = '/services/apexrest/renewai/v1/simulation/cancel';
        cancelReq.httpMethod = 'POST';
        cancelReq.requestBody = Blob.valueOf('{"scenarioId":"' + scenarioId + '"}');
        RestContext.request = cancelReq;
        RestContext.response = new RestResponse();

        RenewAIRestResource.doPost();

        System.assertEquals(200, RestContext.response.statusCode);
        Map<String, Object> cancelBody = (Map<String, Object>) JSON.deserializeUntyped(
            RestContext.response.responseBody.toString());
        System.assertEquals('Cancelled', cancelBody.get('status'));
    }

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
        Id assetId, String key, Datetime ts, Decimal generation, Decimal demand
    ) {
        return new Operating_Snapshot__c(
            Energy_Asset__c = assetId,
            Snapshot_Key__c = key,
            Timestamp__c = ts,
            Generation_MW__c = generation,
            Demand_MW__c = demand,
            Grid_Frequency_Hz__c = 50,
            Weather_Score__c = 80
        );
    }
}
