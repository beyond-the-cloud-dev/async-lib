public class ChainJob1 extends btcdev.QueueableJob {
    public override void work() {
    }
}

public class ChainJob2 extends btcdev.QueueableJob {
    public override void work() {
    }
}

public class ChainJob3 extends btcdev.QueueableJob {
    public override void work() {
    }
}

btcdev.Async.Result ar = btcdev.Async.queueable(new ChainJob1())
    .chain(new ChainJob2())
    .chain(new ChainJob3())
    .enqueue();

System.assertNotEquals(null, ar);
System.assertNotEquals(null, ar.salesforceJobId);
System.assertEquals(btcdev.Async.AsyncType.QUEUEABLE, ar.asyncType);
System.assertNotEquals(null, ar.queueableChainState);
System.assertNotEquals(null, ar.queueableChainState.jobs);
System.debug('PASS: ns-test-queueable-chain');
