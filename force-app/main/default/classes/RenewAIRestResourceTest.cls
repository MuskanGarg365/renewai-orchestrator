@IsTest
private class RenewAIRestResourceTest {

    static final Datetime AS_OF =
        Datetime.newInstanceGmt(2026, 10, 8, 12, 0, 0);

    @TestSetup
    static void setupData() {
        List<RenewAI_Energy_Asset__c> assets =
            new List<RenewAI_Energy_Asset__c>{
                asset('SOLAR_MH_01', 'Solar Asset', 'Solar', 50),
                asset('WIND_MH_01', 'Wind Asset', 'Wind', 75),
                asset('IND_DEMAND_01', 'Industrial Demand', 'Industrial Demand', 150),
                asset('GRID_INDIA_01', 'Grid', 'Grid', 500)
            };

        insert assets;

        Map<String, Id> ids = new Map<String, Id>();
        for (RenewAI_Energy_Asset__c a : assets)
            ids.put(a.Asset_Code__c, a.Id);

        insert new List<Operating_Snapshot__c>{
            snapshot(ids.get('SOLAR_MH_01'), 'SOLAR-1200', 40, 0),
            snapshot(ids.get('WIND_MH_01'), 'WIND-1200', 60, 0),
            snapshot(ids.get('IND_DEMAND_01'), 'DEMAND-1200', 0, 130)
        };
    }

    @IsTest
    static void testAssets() {
        RestResponse res = call('/assets', null);

        System.assertEquals(200, res.statusCode);

        Map<String, Object> body =
            (Map<String, Object>)JSON.deserializeUntyped(
                res.responseBody.toString()
            );

        System.assertEquals(true, body.get('success'));
        System.assertNotEquals(null, body.get('correlationId'));
    }

    @IsTest
    static void testInvalidInterval() {
        Map<String, String> params = new Map<String, String>{
            'asOf' => '2026-10-08T12:00:00Z',
            'intervalMinutes' => '10',
            'maximumAgeMinutes' => '30'
        };

        RestResponse res = call('/portfolio', params);

        System.assertEquals(400, res.statusCode);

        Map<String, Object> body =
            (Map<String, Object>)JSON.deserializeUntyped(
                res.responseBody.toString()
            );

        System.assertEquals(
            'VALIDATION_ERROR',
            body.get('errorCode')
        );

        System.assertNotEquals(
            null,
            body.get('correlationId')
        );
    }

    @IsTest
    static void testMisalignedTime() {
        Map<String, String> params = new Map<String, String>{
            'asOf' => '2026-10-08T12:07:00Z',
            'intervalMinutes' => '15',
            'maximumAgeMinutes' => '30'
        };

        RestResponse res = call('/portfolio', params);

        System.assertEquals(400, res.statusCode);
    }

    @IsTest
    static void testUnknownEndpoint() {
        RestResponse res = call('/unknown', null);

        System.assertEquals(404, res.statusCode);

        Map<String, Object> body =
            (Map<String, Object>)JSON.deserializeUntyped(
                res.responseBody.toString()
            );

        System.assertEquals(
            'RESOURCE_NOT_FOUND',
            body.get('errorCode')
        );
    }

    private static RestResponse call(
        String path,
        Map<String, String> params
    ) {
        RestRequest req = new RestRequest();
        req.requestUri =
            '/services/apexrest/renewai/v1' + path;
        req.httpMethod = 'GET';

        if (params != null)
            for (String key : params.keySet())
                req.addParameter(key, params.get(key));

        RestContext.request = req;
        RestContext.response = new RestResponse();

        Test.startTest();
        RenewAIRestResource.doGet();
        Test.stopTest();

        return RestContext.response;
    }

    private static RenewAI_Energy_Asset__c asset(
        String code,
        String name,
        String type,
        Decimal capacity
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
        Id assetId,
        String key,
        Decimal generation,
        Decimal demand
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