@IsTest
private class RenewAIScenarioServiceTest {

    static final Datetime AS_OF = Datetime.newInstanceGmt(2026, 10, 8, 12, 0, 0);

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

    private static RenewAIDTO.ScenarioResponse runScenario(
        String scenarioType, String correlationId
    ) {
        RenewAIDTO.ScenarioRequest request = new RenewAIDTO.ScenarioRequest();
        request.asOf = AS_OF;
        request.scenarioType = scenarioType;
        return RenewAIScenarioService.run(request, correlationId);
    }

    @IsTest
    static void everyScenarioSavesLinkedBeforeAndAfterDecisions() {
        Integer n = 0;
        for (String scenarioType : RenewAIScenarioCatalog.types()) {
            n++;
            RenewAIDTO.ScenarioResponse r =
                runScenario(scenarioType, 'TEST-SCN-' + n);

            System.assertEquals('Completed', r.status, scenarioType);
            System.assertNotEquals(null, r.baseline.decisionId, scenarioType);
            System.assertNotEquals(null, r.disturbed.decisionId, scenarioType);
            System.assertNotEquals(r.baseline.decisionId, r.disturbed.decisionId);
            System.assert(r.parameters.size() > 0, scenarioType);
            System.assert(r.comparison.deltas.size() >= 8, scenarioType);

            Scenario__c saved = [
                SELECT Status__c, Scenario_Type__c, Correlation_Id__c,
                       Objective_Mode__c, Parameters__c
                FROM Scenario__c
                WHERE Id = :r.scenarioId
            ];
            System.assertEquals('Completed', saved.Status__c);
            System.assertEquals(scenarioType, saved.Scenario_Type__c);
            System.assertEquals('TEST-SCN-' + n, saved.Correlation_Id__c);
            System.assertNotEquals(null, saved.Parameters__c);

            List<Decision__c> decisions = [
                SELECT Scenario_Phase__c
                FROM Decision__c
                WHERE Scenario__c = :r.scenarioId
                ORDER BY Scenario_Phase__c
            ];
            System.assertEquals(2, decisions.size(), scenarioType);
            System.assertEquals('Baseline', decisions[0].Scenario_Phase__c);
            System.assertEquals('Disturbed', decisions[1].Scenario_Phase__c);
        }
    }

    @IsTest
    static void cloudFrontChangesTheInputs() {
        RenewAIDTO.ScenarioResponse r = runScenario('Cloud Front', 'TEST-SCN-9');

        System.assert(
            r.disturbed.inputs.renewableMW < r.baseline.inputs.renewableMW,
            'renewable output should fall');
        System.assert(
            r.disturbed.confidence < r.baseline.confidence,
            'confidence should fall');
        System.assertEquals('Balanced', r.objectiveMode);
    }

    @IsTest
    static void batteryOutageRemovesTheOnlyBatteryFromDispatch() {
        RenewAIDTO.ScenarioResponse r =
            runScenario('Battery Outage', 'TEST-SCN-10');

        for (RenewAIDTO.ActionLine line : r.disturbed.selected.actions) {
            System.assertNotEquals('BATTERY_MH_01', line.assetCode);
        }
        System.assertEquals('Cost First', r.objectiveMode);
    }

    @IsTest
    static void unknownScenarioIsRejectedAndNothingIsSaved() {
        try {
            runScenario('Meteor', 'TEST-SCN-11');
            System.assert(false, 'Expected a validation exception');
        } catch (RenewAIValidationException e) {
            System.assertEquals('INVALID_SCENARIO', e.validationErrors[0].code);
        }
        System.assertEquals(0, [SELECT COUNT() FROM Scenario__c]);
        System.assertEquals(0, [SELECT COUNT() FROM Decision__c]);
    }

    @IsTest
    static void restPostRunsAScenario() {
        RestRequest req = new RestRequest();
        req.requestUri = '/services/apexrest/renewai/v1/scenario';
        req.httpMethod = 'POST';
        req.requestBody = Blob.valueOf(
            '{"asOf":"2026-10-08T12:00:00Z","scenarioType":"Demand Surge"}');
        RestContext.request = req;
        RestContext.response = new RestResponse();

        Test.startTest();
        RenewAIRestResource.doPost();
        Test.stopTest();

        System.assertEquals(200, RestContext.response.statusCode);
        Map<String, Object> body = (Map<String, Object>) JSON.deserializeUntyped(
            RestContext.response.responseBody.toString());
        System.assertEquals('Demand Surge', body.get('scenarioType'));
        System.assertEquals('Completed', body.get('status'));
        System.assertNotEquals(null, body.get('comparison'));
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
}
