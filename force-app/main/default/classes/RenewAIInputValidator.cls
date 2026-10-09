public with sharing class RenewAIInputValidator {

    public static final Integer INTERVAL_MINUTES = 15;
    public static final Integer MAX_AGE_MINUTES = 30;

    public static void validateRequest(RenewAIDTO.PortfolioRequest r) {
        List<RenewAIDTO.ErrorDetail> e = new List<RenewAIDTO.ErrorDetail>();

        if (r == null)
            throw exception('request', 'REQUIRED', 'Portfolio request is required.');

        if (r.asOf == null)
            e.add(detail('asOf', 'REQUIRED', 'asOf timestamp is required.'));

        if (r.intervalMinutes == null)
            e.add(detail('intervalMinutes', 'REQUIRED', 'Interval is required.'));
        else if (r.intervalMinutes != INTERVAL_MINUTES)
            e.add(detail('intervalMinutes', 'INVALID_INTERVAL', 'Only 15-minute intervals are supported.'));

        if (r.maximumAgeMinutes == null)
            e.add(detail('maximumAgeMinutes', 'REQUIRED', 'Maximum age is required.'));
        else if (r.maximumAgeMinutes < 1 || r.maximumAgeMinutes > 1440)
            e.add(detail('maximumAgeMinutes', 'OUT_OF_RANGE', 'Maximum age must be between 1 and 1440 minutes.'));

        if (r.asOf != null && r.intervalMinutes != null && !isIntervalAligned(r.asOf, r.intervalMinutes))
            e.add(detail('asOf', 'INTERVAL_MISALIGNED', 'Timestamp must align to the requested interval.'));

        throwErrors(e);
    }

    public static void validateAsset(RenewAI_Energy_Asset__c a) {
        List<RenewAIDTO.ErrorDetail> e = new List<RenewAIDTO.ErrorDetail>();

        if (a == null)
            throw exception('asset', 'MISSING_ASSET', 'Energy asset is required.');

        if (String.isBlank(a.Asset_Code__c))
            e.add(detail('Asset_Code__c', 'REQUIRED', 'Asset code is required.'));

        if (String.isBlank(a.Asset_Type__c))
            e.add(detail('Asset_Type__c', 'REQUIRED', 'Asset type is required.'));

        if (a.Capacity_MW__c == null)
            e.add(detail('Capacity_MW__c', 'REQUIRED', 'Capacity is required.'));
        else if (a.Capacity_MW__c <= 0)
            e.add(detail('Capacity_MW__c', 'OUT_OF_RANGE', 'Capacity must be greater than zero MW.'));

        if (String.isBlank(a.Status__c))
            e.add(detail('Status__c', 'REQUIRED', 'Asset status is required.'));
        else if (a.Status__c != 'Active')
            e.add(detail('Status__c', 'ASSET_UNAVAILABLE', 'Asset must be active.'));

        throwErrors(e);
    }

    public static void validateSnapshot(Operating_Snapshot__c s, Datetime asOf, Integer maxAge) {
        List<RenewAIDTO.ErrorDetail> e = new List<RenewAIDTO.ErrorDetail>();

        if (s == null)
            throw exception('snapshot', 'MISSING_SNAPSHOT', 'Operating snapshot is required.');

        if (s.Energy_Asset__c == null)
            e.add(detail('Energy_Asset__c', 'REQUIRED', 'Energy asset is required on the snapshot.'));

        if (s.Timestamp__c == null) {
            e.add(detail('Timestamp__c', 'REQUIRED', 'Snapshot timestamp is required.'));
        } else {
            if (asOf != null && maxAge != null && s.Timestamp__c < asOf.addMinutes(-maxAge))
                e.add(detail('Timestamp__c', 'STALE_DATA', 'Operating snapshot is stale.'));
            if (!isIntervalAligned(s.Timestamp__c, INTERVAL_MINUTES))
                e.add(detail('Timestamp__c', 'INTERVAL_MISALIGNED', 'Snapshot must align to a 15-minute interval.'));
        }

        if (s.Generation_MW__c != null && s.Generation_MW__c < 0)
            e.add(detail('Generation_MW__c', 'OUT_OF_RANGE', 'Generation cannot be negative.'));

        if (s.Demand_MW__c != null && s.Demand_MW__c < 0)
            e.add(detail('Demand_MW__c', 'OUT_OF_RANGE', 'Demand cannot be negative.'));

        if (s.Grid_Frequency_Hz__c != null && (s.Grid_Frequency_Hz__c < 45 || s.Grid_Frequency_Hz__c > 55))
            e.add(detail('Grid_Frequency_Hz__c', 'OUT_OF_RANGE', 'Grid frequency must be between 45 and 55 Hz.'));

        if (s.Weather_Score__c != null && (s.Weather_Score__c < 0 || s.Weather_Score__c > 100))
            e.add(detail('Weather_Score__c', 'OUT_OF_RANGE', 'Weather score must be between 0 and 100.'));

        throwErrors(e);
    }

    public static void validateBatteryState(Battery_State__c b, Datetime asOf, Integer maxAge) {
        List<RenewAIDTO.ErrorDetail> e = new List<RenewAIDTO.ErrorDetail>();

        if (b == null)
            throw exception('batteryState', 'MISSING_BATTERY_STATE', 'Battery state is required.');

        if (b.Timestamp__c == null) {
            e.add(detail('Timestamp__c', 'REQUIRED', 'Battery timestamp is required.'));
        } else {
            if (asOf != null && maxAge != null && b.Timestamp__c < asOf.addMinutes(-maxAge))
                e.add(detail('Timestamp__c', 'STALE_DATA', 'Battery state is stale.'));
            if (!isIntervalAligned(b.Timestamp__c, INTERVAL_MINUTES))
                e.add(detail('Timestamp__c', 'INTERVAL_MISALIGNED', 'Battery state must align to a 15-minute interval.'));
        }

        if (b.State_Of_Charge__c == null)
            e.add(detail('State_Of_Charge__c', 'REQUIRED', 'State of charge is required.'));
        else if (b.State_Of_Charge__c < 0 || b.State_Of_Charge__c > 100)
            e.add(detail('State_Of_Charge__c', 'SOC_OUT_OF_RANGE', 'SOC must be between 0 and 100 percent.'));

        if (b.Charge_MW__c != null && b.Charge_MW__c < 0)
            e.add(detail('Charge_MW__c', 'OUT_OF_RANGE', 'Charge MW cannot be negative.'));

        if (b.Discharge_MW__c != null && b.Discharge_MW__c < 0)
            e.add(detail('Discharge_MW__c', 'OUT_OF_RANGE', 'Discharge MW cannot be negative.'));

        if (b.Available_Capacity__c != null && b.Available_Capacity__c < 0)
            e.add(detail('Available_Capacity__c', 'OUT_OF_RANGE', 'Available capacity cannot be negative.'));

        throwErrors(e);
    }

    @TestVisible
    private static Boolean isIntervalAligned(Datetime dt, Integer minutes) {
        if (dt == null || minutes == null || minutes <= 0) return false;
        return Math.mod(dt.minute(), minutes) == 0 && dt.second() == 0;
    }

    private static RenewAIDTO.ErrorDetail detail(String field, String code, String message) {
        return new RenewAIDTO.ErrorDetail(field, code, message);
    }

    private static RenewAIValidationException exception(String field, String code, String message) {
        return new RenewAIValidationException(new List<RenewAIDTO.ErrorDetail>{ detail(field, code, message) });
    }

    private static void throwErrors(List<RenewAIDTO.ErrorDetail> errors) {
        if (!errors.isEmpty()) throw new RenewAIValidationException(errors);
    }
}
