@isTest
private class RenewAISmokeTest {

    @isTest
    static void validateSchema() {

        System.assert(
            Schema.getGlobalDescribe()
                .containsKey('RenewAI_Energy_Asset__c')
        );

        System.assert(
            Schema.getGlobalDescribe()
                .containsKey('Operating_Snapshot__c')
        );

        System.assert(
            Schema.getGlobalDescribe()
                .containsKey('Battery_State__c')
        );
    }

    @isTest
    static void validateSeedData() {

        Integer assetCount =
        [SELECT COUNT()
         FROM RenewAI_Energy_Asset__c];

        System.assert(
            assetCount > 0,
            'Seed data missing'
        );
    }
}