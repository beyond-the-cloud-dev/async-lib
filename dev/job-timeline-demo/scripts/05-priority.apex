Account order = [SELECT Id FROM Account WHERE Name = 'Northwind Order #10248' ORDER BY CreatedDate DESC LIMIT 1];
Async.queueable(new PriorityDemoJob()).name('Chained first').chainName('Priority set before start').linkRecord(order).chain();
Async.queueable(new PriorityDemoJob()).name('Chained second').linkRecord(order).chain();
Async.queueable(new PriorityDemoJob()).name('Chained last, priority 1').priority(1).linkRecord(order).enqueue();
