// Demo reset: removes all saved decisions and their actions.
delete [SELECT Id FROM Action__c];
delete [SELECT Id FROM Decision__c];
System.debug('Decisions and actions cleared.');
