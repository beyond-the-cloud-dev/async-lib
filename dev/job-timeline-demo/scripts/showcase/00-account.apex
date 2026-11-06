List<Account> existing = [SELECT Id FROM Account WHERE Name = 'Acme Order #00124' LIMIT 1];
if (existing.isEmpty()) insert new Account(Name = 'Acme Order #00124');
List<Account> lines = [SELECT Id FROM Account WHERE Name LIKE 'Line %'];
if (lines.size() < 24) {
    List<Account> missing = new List<Account>();
    for (Integer i = lines.size() + 1; i <= 24; i++) {
        missing.add(new Account(Name = 'Line ' + i));
    }
    insert missing;
}
