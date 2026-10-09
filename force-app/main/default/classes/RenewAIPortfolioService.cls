public with sharing class RenewAIPortfolioService {

    public static RenewAIDTO.PortfolioResponse getPortfolio(RenewAIDTO.PortfolioRequest request, String correlationId) {
        validateRequest(request);

        RenewAIDTO.PortfolioResponse response = new RenewAIDTO.PortfolioResponse();
        response.correlationId = correlationId;
        response.asOf = request.asOf;
        response.intervalMinutes = request.intervalMinutes;
        response.metrics = new RenewAIDTO.PortfolioMetrics();

        List<RenewAI_Energy_Asset__c> assets = [
            SELECT Id, Name, Asset_Code__c, Asset_Type__c, Capacity_MW__c, Status__c
            FROM RenewAI_Energy_Asset__c
            WHERE Status__c = 'Active'
            WITH USER_MODE
            ORDER BY Asset_Code__c
        ];

        if (assets.isEmpty()) {
            System.debug('No active energy assets were found.');
        }

        Set<Id> assetIds = new Map<Id, RenewAI_Energy_Asset__c>(assets).keySet();
        Map<Id, Operating_Snapshot__c> snapshotByAsset = findLatestSnapshots(assetIds, request.asOf, request.maximumAgeMinutes);
        Map<Id, Battery_State__c> batteryStateByAsset = findLatestBatteryStates(assetIds, request.asOf, request.maximumAgeMinutes);

        Decimal renewableTotalMW = 0;
        Decimal totalDemandMW = 0;
        Decimal availableBatteryEnergyMWh = 0;
        Decimal gridCapacityMW = 0;

        for (RenewAI_Energy_Asset__c asset : assets) {
            validateAssetAvailability(asset);

            Operating_Snapshot__c snapshot = snapshotByAsset.get(asset.Id);
            if (snapshot != null) {
                validateSnapshot(snapshot, request.asOf, request.maximumAgeMinutes);
            }

            Battery_State__c batteryState = batteryStateByAsset.get(asset.Id);
            response.assets.add(toAssetSummary(asset, snapshot, batteryState, request.asOf, request.maximumAgeMinutes));

            if (snapshot != null && (asset.Asset_Type__c == 'Solar' || asset.Asset_Type__c == 'Wind')) {
                renewableTotalMW += zeroIfNull(snapshot.Generation_MW__c);
            }
            if (snapshot != null && asset.Asset_Type__c == 'Industrial Demand') {
                totalDemandMW += zeroIfNull(snapshot.Demand_MW__c);
            }
            if (asset.Asset_Type__c == 'Battery' && batteryState != null) {
                validateBatteryState(batteryState, request.asOf, request.maximumAgeMinutes);
                availableBatteryEnergyMWh += zeroIfNull(batteryState.Available_Capacity__c);
            }
            if (asset.Asset_Type__c == 'Grid') {
                gridCapacityMW += zeroIfNull(asset.Capacity_MW__c);
            }
        }
        Market_Signal__c latestSignal = findLatestMarketSignal(
            request.asOf,
            request.maximumAgeMinutes
        );

        if (latestSignal != null) {
            response.metrics.energyPriceMWh =
                latestSignal.Energy_Price_MWh__c;
            response.metrics.priceTimestamp =
                latestSignal.Timestamp__c;
        }
        Decimal demandGapMW = totalDemandMW - renewableTotalMW;
        Decimal gridHeadroomMW = Math.max(gridCapacityMW - (demandGapMW > 0 ? demandGapMW : 0), 0);

        response.metrics.renewableTotalMW = renewableTotalMW.setScale(2);
        response.metrics.totalDemandMW = totalDemandMW.setScale(2);
        response.metrics.demandGapMW = demandGapMW.setScale(2);
        response.metrics.availableBatteryEnergyMWh = availableBatteryEnergyMWh.setScale(2);
        response.metrics.gridCapacityMW = gridCapacityMW.setScale(2);
        response.metrics.gridHeadroomMW = gridHeadroomMW.setScale(2);

        return response;
    }

    public static RenewAIDTO.AssetsResponse getAssets(String correlationId) {
        RenewAIDTO.AssetsResponse response = new RenewAIDTO.AssetsResponse();
        response.correlationId = correlationId;

        List<RenewAI_Energy_Asset__c> assets = [
            SELECT Id, Name, Asset_Code__c, Asset_Type__c, Capacity_MW__c, Status__c
            FROM RenewAI_Energy_Asset__c
            WITH USER_MODE
            ORDER BY Asset_Code__c
        ];

        for (RenewAI_Energy_Asset__c asset : assets) {
            response.assets.add(toAssetSummary(asset, null, null, null, null));
        }

        return response;
    }
    private static Market_Signal__c findLatestMarketSignal(
        Datetime asOf,
        Integer maximumAgeMinutes
    ) {
        Datetime oldestAccepted =
            asOf.addMinutes(-maximumAgeMinutes);

        List<Market_Signal__c> signals = [
            SELECT
                Id,
                Timestamp__c,
                Energy_Price_MWh__c
            FROM Market_Signal__c
            WHERE Timestamp__c <= :asOf
            AND Timestamp__c >= :oldestAccepted
            WITH USER_MODE
            ORDER BY Timestamp__c DESC
            LIMIT 1
        ];

        return signals.isEmpty() ? null : signals[0];
    }
    private static Map<Id, Operating_Snapshot__c> findLatestSnapshots(Set<Id> assetIds, Datetime asOf, Integer maximumAgeMinutes) {
        Map<Id, Operating_Snapshot__c> result = new Map<Id, Operating_Snapshot__c>();
        Datetime oldestAccepted = asOf.addMinutes(-maximumAgeMinutes);

        List<Operating_Snapshot__c> snapshots = [
            SELECT Id, Name, Timestamp__c, Energy_Asset__c, Generation_MW__c, Demand_MW__c,
                   Grid_Frequency_Hz__c, Weather_Score__c, Snapshot_Key__c
            FROM Operating_Snapshot__c
            WHERE Energy_Asset__c IN :assetIds
            AND Timestamp__c <= :asOf
            AND Timestamp__c >= :oldestAccepted
            WITH USER_MODE
            ORDER BY Energy_Asset__c, Timestamp__c DESC
        ];

        for (Operating_Snapshot__c snapshot : snapshots) {
            if (!result.containsKey(snapshot.Energy_Asset__c)) {
                result.put(snapshot.Energy_Asset__c, snapshot);
            }
        }

        return result;
    }

    private static Map<Id, Battery_State__c> findLatestBatteryStates(Set<Id> assetIds, Datetime asOf, Integer maximumAgeMinutes) {
        Map<Id, Battery_State__c> result = new Map<Id, Battery_State__c>();
        Datetime oldestAccepted = asOf.addMinutes(-maximumAgeMinutes);

        List<Battery_State__c> states = [
            SELECT Id, Energy_Asset__c, Timestamp__c, State_Of_Charge__c, Charge_MW__c,
                   Discharge_MW__c, Available_Capacity__c, Battery_State_Key__c
            FROM Battery_State__c
            WHERE Energy_Asset__c IN :assetIds
            AND Timestamp__c <= :asOf
            AND Timestamp__c >= :oldestAccepted
            WITH USER_MODE
            ORDER BY Energy_Asset__c, Timestamp__c DESC
        ];

        for (Battery_State__c stateRecord : states) {
            if (!result.containsKey(stateRecord.Energy_Asset__c)) {
                result.put(stateRecord.Energy_Asset__c, stateRecord);
            }
        }

        return result;
    }

    private static RenewAIDTO.AssetSummary toAssetSummary(
        RenewAI_Energy_Asset__c asset,
        Operating_Snapshot__c snapshot,
        Battery_State__c batteryState,
        Datetime asOf,
        Integer maximumAgeMinutes
    ) {
        RenewAIDTO.AssetSummary summary = new RenewAIDTO.AssetSummary();
        summary.assetCode = asset.Asset_Code__c;
        summary.assetName = asset.Name;
        summary.assetType = asset.Asset_Type__c;
        summary.capacityMW = asset.Capacity_MW__c;
        summary.status = asset.Status__c;

        if (snapshot != null) {
            summary.generationMW = snapshot.Generation_MW__c;
            summary.demandMW = snapshot.Demand_MW__c;
            summary.snapshotTimestamp = snapshot.Timestamp__c;
            summary.stale = asOf != null && maximumAgeMinutes != null &&
                snapshot.Timestamp__c < asOf.addMinutes(-maximumAgeMinutes);
        } else {
            summary.generationMW = 0;
            summary.demandMW = 0;
            summary.stale = null;
        }

        if (batteryState != null) {
            summary.stateOfChargePercent = batteryState.State_Of_Charge__c;
            summary.availableEnergyMWh = batteryState.Available_Capacity__c;
        }

        return summary;
    }

    private static Decimal zeroIfNull(Decimal value) {
        return value == null ? 0 : value;
    }

    private static void validateRequest(RenewAIDTO.PortfolioRequest request) {
        if (request == null || request.asOf == null || request.intervalMinutes == null ||
            request.intervalMinutes <= 0 || request.maximumAgeMinutes == null || request.maximumAgeMinutes < 0) {
            throw new AuraHandledException('Invalid portfolio request.');
        }
    }

    private static void validateAssetAvailability(RenewAI_Energy_Asset__c asset) {
        if (asset.Status__c != 'Active') {
            throw new AuraHandledException('Asset is not active.');
        }
    }

    private static void validateSnapshot(Operating_Snapshot__c snapshot, Datetime asOf, Integer maximumAgeMinutes) {
        Datetime oldestAccepted = asOf.addMinutes(-maximumAgeMinutes);
        if (snapshot.Timestamp__c == null || snapshot.Timestamp__c > asOf || snapshot.Timestamp__c < oldestAccepted) {
            throw new AuraHandledException('Snapshot is outside the accepted time range.');
        }
    }

    private static void validateBatteryState(Battery_State__c batteryState, Datetime asOf, Integer maximumAgeMinutes) {
        Datetime oldestAccepted = asOf.addMinutes(-maximumAgeMinutes);
        if (batteryState.Timestamp__c == null || batteryState.Timestamp__c > asOf || batteryState.Timestamp__c < oldestAccepted) {
            throw new AuraHandledException('Battery state is outside the accepted time range.');
        }
    }
}
