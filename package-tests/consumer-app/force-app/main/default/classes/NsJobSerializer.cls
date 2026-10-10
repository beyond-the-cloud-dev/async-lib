/**
 * Copyright (c) 2026 Beyond The Cloud Sp. z o.o. (BeyondTheCloud.Dev)
 * Licensed under the MIT License (https://github.com/beyond-the-cloud-dev/async-lib/blob/main/LICENSE)
 *
 * v3.0.0
 **/
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
