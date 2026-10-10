/**
 * Copyright (c) 2026 Beyond The Cloud Sp. z o.o. (BeyondTheCloud.Dev)
 * Licensed under the MIT License (https://github.com/beyond-the-cloud-dev/async-lib/blob/main/LICENSE)
 *
 * v3.1.0
 **/
// Must stay a top-level class. Inside Async the static property `Async.Backoff` shadows the
// Backoff type, so a delegation written there resolves back to the property and recurses until
// the stack limit. Here the name is unambiguous.
public inherited sharing class BackoffFactory {
    public Backoff fixed(Integer minutes) {
        return Backoff.fixed(minutes);
    }

    public Backoff exponential(Integer baseMinutes) {
        return Backoff.exponential(baseMinutes);
    }

    public Backoff exponentialWithJitter(Integer baseMinutes) {
        return Backoff.exponentialWithJitter(baseMinutes);
    }
}
