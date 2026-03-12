package info.fishfind.auth.api;

public final class AuthPaths {
    /**
     * Prevents instantiation of the path constants holder.
     */
    private AuthPaths() {
    }

    public static final String API = "/api";
    public static final String AUTH = API + "/auth";
    public static final String HEALTH = API + "/health";

    public static final String REGISTER = AUTH + "/register";
    public static final String ACTIVATE = AUTH + "/activate/{activationToken}";
    public static final String LOGIN = AUTH + "/login";
    public static final String VALIDATE = AUTH + "/validate";
    public static final String PROFILE = AUTH + "/profile";
    public static final String CHANGE_PASSWORD = AUTH + "/change-password";
    public static final String ACCOUNT = AUTH + "/account";
}
