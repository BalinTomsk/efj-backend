package com.fishfind.docapi.web;

/**
 * Who is calling an MCP tool, as cproxy stamped it: the role ({@value ViewerRole#HEADER}) and, since cproxy
 * 0.27.0, the account that owns the MCP key ({@value #USER_HEADER}). cproxy drops any inbound copy of either
 * header, so both are facts here (see {@link ViewerRole} for the trust model).
 *
 * @param role   the caller's role; GUEST when the header is missing
 * @param userId the owning account's id in canonical GUID form, or {@code null}: a hand-made operator key
 *               belongs to no account, and a write tool refuses to run without one
 */
public record McpCaller(ViewerRole role, String userId) {

    /** The request header cproxy sets for a self-service MCP key. */
    public static final String USER_HEADER = "X-Fish-User";

    /** The caller from the two raw header values; a {@code userId} that is not a GUID is dropped. */
    public static McpCaller fromHeaders(String roleHeader, String userHeader) {
        String user = null;
        if (userHeader != null && !userHeader.isBlank()) {
            try {
                user = RiverController.normalizeGuid(userHeader.trim());
            } catch (RuntimeException ex) {
                user = null;
            }
        }
        return new McpCaller(ViewerRole.fromHeader(roleHeader), user);
    }
}
