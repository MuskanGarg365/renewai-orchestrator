@IsTest
private class RenewAIDecisionServiceTest {

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

    @IsTest
    static void runPersistsDecisionAndActions() {
        RenewAIDTO.DecisionRequest request = new RenewAIDTO.DecisionRequest();
        request.asOf = AS_OF;
        request.objectiveMode = 'Balanced';

        RenewAIDTO.DecisionResponse response =
            RenewAIDecisionService.run(request, 'TEST-DEC-1');

        System.assertEquals(true, response.success);
        System.assertNotEquals(null, response.decisionId);
        System.assertNotEquals(null, response.selected);
        assertClose(0.8, response.confidence, 0.001, 'confidence');
        assertClose(30, response.inputs.demandGapMW, 0.01, 'demand gap');

        List<Decision__c> decisions = [
            SELECT Id, Correlation_Id__c, Objective_Mode__c, Approval_Status__c,
                   Score__c, Confidence__c, Reasoning__c, Score_Breakdown__c
            FROM Decision__c
        ];
        System.assertEquals(1, decisions.size());
        System.assertEquals('TEST-DEC-1', decisions[0].Correlation_Id__c);
        System.assertEquals('Balanced', decisions[0].Objective_Mode__c);
        assertClose(80, decisions[0].Confidence__c, 0.01, 'stored confidence');
        System.assertNotEquals(null, decisions[0].Reasoning__c);
        System.assertNotEquals(null, decisions[0].Score_Breakdown__c);

        List<Action__c> actions = [
            SELECT Action_Type__c, Quantity_MW__c, Status__c, Decision__c
            FROM Action__c
        ];
        System.assertEquals(response.selected.actions.size(), actions.size());
        for (Action__c a : actions) {
            System.assertEquals('Planned', a.Status__c);
            System.assertEquals(decisions[0].Id, a.Decision__c);
            System.assert(a.Quantity_MW__c > 0);
        }
    }

    @IsTest
    static void batteryRateLimitRejectsCoveringTheWholeGap() {
        RenewAIDTO.DecisionRequest request = new RenewAIDTO.DecisionRequest();
        request.asOf = AS_OF;

        RenewAIDTO.DecisionResponse response =
            RenewAIDecisionService.run(request, 'TEST-DEC-2');

        // Gap is 30 MW but the single battery is rated 20 MW.
        Boolean rejected = false;
        for (RenewAIDTO.CandidateResult r : response.rejected) {
            if (r.candidateId == 'DISCHARGE_TO_GAP') {
                rejected = r.rejectionReasons.contains('BATTERY_RATE_LIMIT');
            }
        }
        System.assertEquals(true, rejected);
        System.assertEquals('Balanced', response.objectiveMode);
    }

    @IsTest
    static void misalignedTimeIsRejected() {
        RenewAIDTO.DecisionRequest request = new RenewAIDTO.DecisionRequest();
        request.asOf = AS_OF.addMinutes(7);

        try {
            RenewAIDecisionService.run(request, 'TEST-DEC-3');
            System.assert(false, 'Expected a validation exception');
        } catch (RenewAIValidationException e) {
            System.assertEquals('INTERVAL_MISALIGNED', e.validationErrors[0].code);
        }
    }

    @IsTest
    static void invalidModeIsRejectedAndNothingIsSaved() {
        RenewAIDTO.DecisionRequest request = new RenewAIDTO.DecisionRequest();
        request.asOf = AS_OF;
        request.objectiveMode = 'Fastest';

        try {
            RenewAIDecisionService.run(request, 'TEST-DEC-4');
            System.assert(false, 'Expected a validation exception');
        } catch (RenewAIValidationException e) {
            System.assertEquals('INVALID_MODE', e.validationErrors[0].code);
        }
        System.assertEquals(0, [SELECT COUNT() FROM Decision__c]);
    }

    @IsTest
    static void restPostReturnsDecision() {
        RestRequest req = new RestRequest();
        req.requestUri = '/services/apexrest/renewai/v1/decision';
        req.httpMethod = 'POST';
        req.requestBody = Blob.valueOf(
            '{"asOf":"2026-10-08T12:00:00Z","objectiveMode":"Cost First"}');
        RestContext.request = req;
        RestContext.response = new RestResponse();

        Test.startTest();
        RenewAIRestResource.doPost();
        Test.stopTest();

        System.assertEquals(200, RestContext.response.statusCode);
        Map<String, Object> body = (Map<String, Object>) JSON.deserializeUntyped(
            RestContext.response.responseBody.toString());
        System.assertEquals(true, body.get('success'));
        System.assertEquals('Cost First', body.get('objectiveMode'));
        System.assertNotEquals(null, body.get('decisionId'));
    }

    @IsTest
    static void restPostRejectsBadJson() {
        RestRequest req = new RestRequest();
        req.requestUri = '/services/apexrest/renewai/v1/decision';
        req.httpMethod = 'POST';
        req.requestBody = Blob.valueOf('{not json');
        RestContext.request = req;
        RestContext.response = new RestResponse();

        RenewAIRestResource.doPost();

        System.assertEquals(400, RestContext.response.statusCode);
        Map<String, Object> body = (Map<String, Object>) JSON.deserializeUntyped(
            RestContext.response.responseBody.toString());
        System.assertEquals('INVALID_JSON', body.get('errorCode'));
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

    private static void assertClose(
        Decimal expected,
        Decimal actual,
        Decimal tolerance,
        String message
    ) {
        System.assert(
            actual != null && Math.abs(expected - actual) <= tolerance,
            message + ': expected ' + expected + ' but got ' + actual
        );
    }
}
