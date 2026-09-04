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
