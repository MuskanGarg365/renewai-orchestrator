Set<String> keep = new Set<String>{
    'SOLAR_MH_01', 'SOLAR_MH_02', 'SOLAR_MH_03', 'SOLAR_MH_04', 'SOLAR_MH_05',
    'WIND_MH_01', 'WIND_MH_02', 'WIND_MH_03',
    'BATTERY_MH_01', 'BATTERY_MH_02',
    'IND_DEMAND_01', 'GRID_INDIA_01'
};

List<RenewAI_Energy_Asset__c> extra = [
    SELECT Id, Name, Asset_Code__c
    FROM RenewAI_Energy_Asset__c
    WHERE Status__c = 'Active'
    AND (Asset_Code__c = null OR Asset_Code__c NOT IN :keep)
];

for (RenewAI_Energy_Asset__c a : extra) {
    a.Status__c = 'Inactive';
}

List<Database.SaveResult> results = Database.update(extra, false);
Integer failed = 0;
for (Integer i = 0; i < results.size(); i++) {
    if (!results[i].isSuccess()) {
        failed++;
        System.debug('FAILED ' + extra[i].Name + ': ' + results[i].getErrors()[0].getMessage());
    }
}
System.debug('Deactivated: ' + (extra.size() - failed) + ', failed: ' + failed);