public with sharing class RenewAISeedData {
    public static void loadAssets() {

        List<RenewAI_Energy_Asset__c> assets =
            new List<RenewAI_Energy_Asset__c>();

        assets.add(new RenewAI_Energy_Asset__c(
            Name='Maharashtra Solar Farm 1',
            Asset_Code__c='SOLAR_MH_01',
            Asset_Type__c='Solar',
            Capacity_MW__c=50
        ));

        assets.add(new RenewAI_Energy_Asset__c(
            Name='MH Wind Farm',
            Asset_Code__c='WIND_MH_01',
            Asset_Type__c='Wind',
            Capacity_MW__c=75
        ));

        upsert assets Asset_Code__c;
    }
}