delete [SELECT Id FROM AsyncResult__c];
delete [
    SELECT Id FROM Account
    WHERE Name LIKE 'Northwind Order%' OR Name LIKE 'Contoso Order%' OR Name LIKE 'Fabrikam Order%' OR Name LIKE 'Acme Order%' OR Name LIKE 'Line %'
];
System.debug('CLEANED');
