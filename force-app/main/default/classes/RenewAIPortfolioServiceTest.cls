@IsTest
private class RenewAIPortfolioServiceTest {

    static final Datetime AS_OF = Datetime.newInstanceGmt(2026, 10, 8, 12, 0, 0);

    @TestSetup
    static void setupData() {
        List<RenewAI_Energy_Asset__c> assets = new List<RenewAI_Energy_Asset__c>{
            asset('SOLAR_MH_01', 'Solar Asset', 'Solar', 50),
            asset('WIND_MH_01', 'Wind Asset', 'Wind', 75),
            asset('BATTERY_MH_01', 'Battery Asset', 'Battery', 20),
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

        insert new Battery_State__c(
            Energy_Asset__c = ids.get('BATTERY_MH_01'),
            Battery_State_Key__c = 'BATTERY-1200',
            Timestamp__c = AS_OF,
            State_Of_Charge__c = 70,
            Charge_MW__c = 0,
            Discharge_MW__c = 10,
            Available_Capacity__c = 14
        );
    }

    @IsTest
    static void marketPriceIsReturned() {
        insert new Market_Signal__c(
            Name = 'MKT-1200',
            Market_Signal_Key__c = 'MKT-1200',
            Timestamp__c = AS_OF,
            Energy_Price_MWh__c = 4200
        );
        RenewAIDTO.PortfolioResponse res = RenewAIPortfolioService.getPortfolio(request(AS_OF), 'TEST-002');
        System.assertEquals(4200, res.metrics.energyPriceMWh);
    }

    @IsTest
    static void validPortfolio() {
        Test.startTest();
        RenewAIDTO.PortfolioResponse res = RenewAIPortfolioService.getPortfolio(request(AS_OF), 'TEST-001');
        Test.stopTest();

        System.assertEquals(true, res.success);
        System.assertEquals(100, res.metrics.renewableTotalMW);
        System.assertEquals(130, res.metrics.totalDemandMW);
        System.assertEquals(30, res.metrics.demandGapMW);
        System.assertEquals(14, res.metrics.availableBatteryEnergyMWh);
        System.assertEquals(470, res.metrics.gridHeadroomMW);
        System.assertEquals(5, res.assets.size());
    }

    @IsTest
    static void nullRequest() {
        assertError(new ValidationCall('NULL_REQUEST'), 'REQUIRED');
    }

    @IsTest
    static void misalignedTimestamp() {
        assertError(new ValidationCall('MISALIGNED'), 'INTERVAL_MISALIGNED');
    }

    @IsTest
    static void staleSnapshot() {
        assertError(new ValidationCall('STALE'), 'STALE_DATA');
    }

    @IsTest
    static void invalidSoc() {
        assertError(new ValidationCall('SOC'), 'SOC_OUT_OF_RANGE');
    }

    private class ValidationCall {
        String testType;
        ValidationCall(String testType) { this.testType = testType; }

        void execute() {
            if (testType == 'NULL_REQUEST')
                RenewAIInputValidator.validateRequest(null);
            if (testType == 'MISALIGNED')
                RenewAIInputValidator.validateRequest(request(AS_OF.addMinutes(7)));
            if (testType == 'STALE')
                RenewAIInputValidator.validateSnapshot(snapshot(null, null, 20, 0, AS_OF.addMinutes(-45)), AS_OF, 30);
            if (testType == 'SOC')
                RenewAIInputValidator.validateBatteryState(battery(105), AS_OF, 30);
        }
    }

    private static void assertError(ValidationCall validationCall, String expectedCode) {
        try {
            validationCall.execute();
            System.assert(false, 'Expected validation exception.');
        } catch (RenewAIValidationException e) {
            System.assertEquals(expectedCode, e.validationErrors[0].code);
        }
    }

    private static RenewAIDTO.PortfolioRequest request(Datetime asOf) {
        RenewAIDTO.PortfolioRequest r = new RenewAIDTO.PortfolioRequest();
        r.asOf = asOf;
        r.intervalMinutes = 15;
        r.maximumAgeMinutes = 30;
        return r;
    }

    private static RenewAI_Energy_Asset__c asset(String code, String name, String type, Decimal capacity) {
        return new RenewAI_Energy_Asset__c(
            Name = name,
            Asset_Code__c = code,
            Asset_Type__c = type,
            Capacity_MW__c = capacity,
            Status__c = 'Active'
        );
    }

    private static Operating_Snapshot__c snapshot(Id assetId, String key, Decimal generation, Decimal demand) {
        return snapshot(assetId, key, generation, demand, AS_OF);
    }

    private static Operating_Snapshot__c snapshot(
        Id assetId, String key, Decimal generation, Decimal demand, Datetime timestampValue
    ) {
        return new Operating_Snapshot__c(
            Energy_Asset__c = assetId,
            Snapshot_Key__c = key,
            Timestamp__c = timestampValue,
            Generation_MW__c = generation,
            Demand_MW__c = demand,
            Grid_Frequency_Hz__c = 50,
            Weather_Score__c = 80
        );
    }

    private static Battery_State__c battery(Decimal soc) {
        return new Battery_State__c(
            Timestamp__c = AS_OF,
            State_Of_Charge__c = soc,
            Charge_MW__c = 0,
            Discharge_MW__c = 10,
            Available_Capacity__c = 14
        );
    }
}
