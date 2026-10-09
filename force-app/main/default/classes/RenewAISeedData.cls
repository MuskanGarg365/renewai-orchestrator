public with sharing class RenewAISeedData {

    public static final Datetime DAY_START =
        Datetime.newInstanceGmt(2026, 10, 9, 0, 0, 0);
    public static final Integer INTERVALS = 96;

    public static void loadAll() {
        Map<String, RenewAI_Energy_Asset__c> assets = loadAssetsInternal();
        loadSnapshots(assets);
        loadBatteryStates(assets);
        loadMarketSignals();
    }

    public static void loadAssets() {
        loadAssetsInternal();
    }

    private static Map<String, RenewAI_Energy_Asset__c> loadAssetsInternal() {
        List<RenewAI_Energy_Asset__c> rows =
            new List<RenewAI_Energy_Asset__c>();

        for (Integer i = 1; i <= 5; i++) {
            rows.add(asset('SOLAR_MH_0' + i, 'Maharashtra Solar Farm ' + i,
                'Solar', 30));
        }
        rows.add(asset('WIND_MH_01', 'MH Wind Farm 1', 'Wind', 40));
        rows.add(asset('WIND_MH_02', 'MH Wind Farm 2', 'Wind', 30));
        rows.add(asset('WIND_MH_03', 'MH Wind Farm 3', 'Wind', 30));
        rows.add(asset('BATTERY_MH_01', 'Battery Storage 1', 'Battery', 20));
        rows.add(asset('BATTERY_MH_02', 'Battery Storage 2', 'Battery', 20));
        rows.add(asset('IND_DEMAND_01', 'Industrial Demand Aggregate',
            'Industrial Demand', 220));
        rows.add(asset('GRID_INDIA_01', 'Grid Connection', 'Grid', 150));

        upsert rows Asset_Code__c;

        Map<String, RenewAI_Energy_Asset__c> byCode =
            new Map<String, RenewAI_Energy_Asset__c>();
        for (RenewAI_Energy_Asset__c a : rows) {
            byCode.put(a.Asset_Code__c, a);
        }
        return byCode;
    }

    private static void loadSnapshots(
        Map<String, RenewAI_Energy_Asset__c> assets
    ) {
        List<Operating_Snapshot__c> rows = new List<Operating_Snapshot__c>();

        for (Integer i = 0; i < INTERVALS; i++) {
            Datetime ts = DAY_START.addMinutes(i * 15);
            Decimal hour = istHour(i / 4.0);

            for (Integer s = 1; s <= 5; s++) {
                String code = 'SOLAR_MH_0' + s;
                rows.add(snapshot(assets.get(code), code, ts,
                    solarMW(30, hour, s), 0, hour));
            }
            rows.add(snapshot(assets.get('WIND_MH_01'), 'WIND_MH_01', ts,
                windMW(40, hour, 0.0), 0, hour));
            rows.add(snapshot(assets.get('WIND_MH_02'), 'WIND_MH_02', ts,
                windMW(30, hour, 1.3), 0, hour));
            rows.add(snapshot(assets.get('WIND_MH_03'), 'WIND_MH_03', ts,
                windMW(30, hour, 2.6), 0, hour));
            rows.add(snapshot(assets.get('IND_DEMAND_01'), 'IND_DEMAND_01', ts,
                0, demandMW(hour), hour));
        }

        upsert rows Snapshot_Key__c;
    }

    private static void loadBatteryStates(
        Map<String, RenewAI_Energy_Asset__c> assets
    ) {
        List<Battery_State__c> rows = new List<Battery_State__c>();
        Set<String> keys = new Set<String>();

        for (String code : new List<String>{'BATTERY_MH_01', 'BATTERY_MH_02'}) {
            for (Integer i = 0; i < INTERVALS; i++) {
                Datetime ts = DAY_START.addMinutes(i * 15);
                Decimal hour = istHour(i / 4.0);
                Decimal soc = batterySoc(hour, code == 'BATTERY_MH_02');
                String key = code + '-' + ts.formatGmt('yyyyMMddHHmm');
                keys.add(key);

                rows.add(new Battery_State__c(
                    Name = key,
                    Battery_State_key__c = key,
                    Energy_Asset__c = assets.get(code).Id,
                    Timestamp__c = ts,
                    State_Of_Charge__c = soc,
                    Charge_MW__c = (hour >= 9 && hour < 15) ? 6 : 0,
                    Discharge_MW__c = (hour >= 18 && hour < 22) ? 8 : 0,
                    // 40 MWh usable energy per battery
                    Available_Capacity__c = (soc * 0.4).setScale(0)
                ));
            }
        }

        Map<String, Id> existing = new Map<String, Id>();
        for (Battery_State__c b : [
            SELECT Id, Battery_State_key__c
            FROM Battery_State__c
            WHERE Battery_State_key__c IN :keys
        ]) {
            existing.put(b.Battery_State_key__c, b.Id);
        }
        for (Battery_State__c b : rows) {
            b.Id = existing.get(b.Battery_State_key__c);
        }
        upsert rows;
    }

    private static void loadMarketSignals() {
        List<Market_Signal__c> rows = new List<Market_Signal__c>();

        for (Integer i = 0; i < INTERVALS; i++) {
            Datetime ts = DAY_START.addMinutes(i * 15);
            Decimal hour = istHour(i / 4.0);
            String key = 'MKT-' + ts.formatGmt('yyyyMMddHHmm');

            Decimal price = 3500 + 900 * Math.sin((hour - 14) * Math.PI / 12);
            if (hour >= 18 && hour < 22) price += 1200; // evening peak

            rows.add(new Market_Signal__c(
                Name = key,
                Market_Signal_Key__c = key,
                Timestamp__c = ts,
                Energy_Price_MWh__c = price.setScale(2),
                Volatility_Index__c = 20            
            ));
        }

        upsert rows Market_Signal_Key__c;
    }

    // ---- deterministic profiles ------------------------------------------

    private static Decimal istHour(Decimal utcHour) {
        Decimal h = utcHour + 5.5;
        return h >= 24 ? h - 24 : h;
    }

    private static Decimal solarMW(Decimal cap, Decimal hour, Integer farm) {
        if (hour < 6 || hour > 18) return 0;
        Decimal shade = 1 - (farm - 1) * 0.03;
        Decimal value = cap * 0.9 * shade * Math.sin((hour - 6) * Math.PI / 12);
        return value.setScale(2);
    }

    private static Decimal windMW(Decimal cap, Decimal hour, Decimal phase) {
        Decimal value = cap * (0.40 + 0.15 * Math.sin(hour * Math.PI / 12 + phase));
        return value.setScale(2);
    }

    private static Decimal demandMW(Decimal hour) {
        Decimal value = 140 + 30 * Math.sin((hour - 9) * Math.PI / 12);
        return value.setScale(2);
    }

    private static Decimal batterySoc(Decimal hour, Boolean second) {
        Decimal base = 55 + 25 * Math.sin((hour - 6) * Math.PI / 12);
        Decimal value = second ? base - 8 : base;
        return value.setScale(2);
    }


    private static RenewAI_Energy_Asset__c asset(
        String code, String name, String type, Decimal capacity
    ) {
        return new RenewAI_Energy_Asset__c(
            Asset_Code__c = code,
            Name = name,
            Asset_Type__c = type,
            Capacity_MW__c = capacity,
            Status__c = 'Active'
        );
    }

    private static Operating_Snapshot__c snapshot(
        RenewAI_Energy_Asset__c asset, String code, Datetime ts,
        Decimal generation, Decimal demand, Decimal hour
    ) {
        return new Operating_Snapshot__c(
            Snapshot_Key__c = code + '-' + ts.formatGmt('yyyyMMddHHmm'),
            Energy_Asset__c = asset.Id,
            Timestamp__c = ts,
            Generation_MW__c = generation,
            Demand_MW__c = demand,
            Grid_Frequency_Hz__c = 50,
            Weather_Score__c = (hour >= 6 && hour <= 18) ? 85 : 70
        );
    }
}