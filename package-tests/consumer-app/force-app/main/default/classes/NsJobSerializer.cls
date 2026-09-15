global class NsJobSerializer implements btcdev.Async.JobSerializer {
    public String serialize(btcdev.QueueableJob job) {
        insert new Account(Name = 'NS-SERIALIZE', Description = job.className);
        return JSON.serialize(job);
    }

    public btcdev.QueueableJob deserialize(String className, String payload) {
        insert new Account(Name = 'NS-DESERIALIZE', Description = className);
        return (btcdev.QueueableJob) JSON.deserialize(payload, Type.forName(className));
    }
}
