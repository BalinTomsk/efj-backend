package com.fishfind.docapi.web;

import java.util.ArrayList;
import java.util.List;

/**
 * One account-type flag. {@code dbo.Users.userType} (envfish-db) is a <strong>bitmask</strong> of these, so an
 * account can be several at once; an admin always also holds paid, scientist and editor (the database enforces it).
 * cproxy 0.32.0 forwards the mask in decimal as {@value #HEADER}; same trust model as {@link ViewerRole}: cproxy drops
 * any inbound copy, so the header is a fact here. It grants nothing on its own: admin is still {@link ViewerRole#ADMIN}.
 * Read by {@link MeController}. Keep the bits in step with {@code dbo.UserType}.
 */
public enum UserType {
    ADMIN("admin", 32),
    REGISTERED("registered", 1),
    PAID("paid", 2),
    SCIENTIST("scientist", 4),
    EDITOR("editor", 8),
    AI_AGENT("ai_agent", 16);

    /** The request header cproxy sets: the mask in decimal. */
    public static final String HEADER = "X-Fish-User-Type";

    /** Every bit this enum knows; a mask with any other bit is not trusted. */
    public static final int KNOWN = 63;

    private final String code;
    private final int bit;

    UserType(String code, int bit) {
        this.code = code;
        this.bit = bit;
    }

    /** @return the name of the bit, as {@code dbo.UserType.code} */
    public String code() {
        return code;
    }

    /** @return the bit value, as {@code dbo.UserType.bit} */
    public int bit() {
        return bit;
    }

    /** @return true when {@code mask} has this bit */
    public boolean in(int mask) {
        return (mask & bit) != 0;
    }

    /**
     * @param headerValue the raw header value, possibly null
     * @return the mask it carries, or {@code null} for null, blank, non-numeric, zero or a mask with unknown bits
     */
    public static Integer maskFromHeader(String headerValue) {
        if (headerValue == null || headerValue.isBlank()) {
            return null;
        }
        try {
            int mask = Integer.parseInt(headerValue.trim());
            return mask > 0 && (mask & ~KNOWN) == 0 ? mask : null;
        } catch (NumberFormatException ex) {
            return null;
        }
    }

    /** @return the codes of the bits in {@code mask}, in display order (admin first) */
    public static List<String> codes(int mask) {
        List<String> codes = new ArrayList<>();
        for (UserType type : values()) {
            if (type.in(mask)) {
                codes.add(type.code);
            }
        }
        return codes;
    }
}
