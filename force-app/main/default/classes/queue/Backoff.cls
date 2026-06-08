public inherited sharing class Backoff {
    // System.enqueueJob caps delay at 10 integer minutes.
    public static final Integer MAX_DELAY_MINUTES = 10;

    public enum Strategy {
        FIXED,
        EXPONENTIAL,
        EXPONENTIAL_JITTER
    }

    private final Strategy strategyValue;
    private final Integer baseMinutes;

    private Backoff(Strategy strategyValue, Integer baseMinutes) {
        if (baseMinutes == null || baseMinutes < 0) {
            throw new Async.IllegalArgumentException(
                'Backoff base minutes must be a non-negative integer'
            );
        }
        this.strategyValue = strategyValue;
        this.baseMinutes = baseMinutes;
    }

    public static Backoff fixed(Integer minutes) {
        return new Backoff(Strategy.FIXED, minutes);
    }

    public static Backoff exponential(Integer baseMinutes) {
        return new Backoff(Strategy.EXPONENTIAL, baseMinutes);
    }

    public static Backoff exponentialWithJitter(Integer baseMinutes) {
        return new Backoff(Strategy.EXPONENTIAL_JITTER, baseMinutes);
    }

    public static Backoff fromName(String strategy, Integer baseMinutes) {
        Strategy parsed = parseStrategy(strategy);
        return parsed == null ? null : new Backoff(parsed, baseMinutes);
    }

    private static Strategy parseStrategy(String value) {
        if (String.isBlank(value)) {
            return null;
        }
        for (Strategy candidate : Strategy.values()) {
            if (candidate.name().equalsIgnoreCase(value)) {
                return candidate;
            }
        }
        return null;
    }

    public Integer delayMinutes(Integer attempt) {
        Integer delay;
        if (strategyValue == Strategy.FIXED) {
            delay = baseMinutes;
        } else {
            delay = baseMinutes * (Integer) Math.pow(2, attempt - 1);
            if (strategyValue == Strategy.EXPONENTIAL_JITTER) {
                delay += (Integer) Math.floor(Math.random() * (baseMinutes + 1));
            }
        }
        return Math.min(Math.max(delay, 0), MAX_DELAY_MINUTES);
    }
}
