/**
 * Returns null when the name does not resolve, and throws when it resolves but cannot be
 * constructed. Callers need those apart, because the first means "not declared global" and the
 * second means "no usable constructor", and only they know which setting to name in the message.
 **/
public inherited sharing class GlobalClassFactory {
    private static Map<String, Object> instanceByClassName = new Map<String, Object>();

    public static Object newInstance(String className) {
        if (String.isBlank(className)) {
            return null;
        }
        if (!instanceByClassName.containsKey(className)) {
            instanceByClassName.put(className, constructOrRememberFailure(className));
        }
        return instanceByClassName.get(className);
    }

    private static Object constructOrRememberFailure(String className) {
        try {
            return Type.forName(className)?.newInstance();
        } catch (Exception constructorFailure) {
            instanceByClassName.put(className, null);
            throw constructorFailure;
        }
    }
}
