// Clears everything the demo creates (actions, decisions, scenarios).
// Keeps the seeded assets, snapshots, battery states and market signals.
delete [SELECT Id FROM Action__c];
delete [SELECT Id FROM Decision__c];
delete [SELECT Id FROM Scenario__c];
System.debug('RenewAI demo data cleared.');
