package com.fishfind.docapi.web;

import java.util.Locale;

/**
 * Who is asking, as stamped on the request by <strong>cproxy</strong> in the {@value #HEADER} header.
 *
 * <p>cproxy verifies the caller's signed credential and looks the account up in its own mirror —
 * {@code guest} when the token carries no registered user, {@code admin} when the mirror holds a live
 * superAdmin, {@code user} otherwise — and <em>strips any inbound copy of this header before setting
 * its own</em>. docapi therefore treats the header as fact, and that is the whole trust model: it
 * holds only while docapi is reachable through cproxy alone (it listens on localhost and the VPC
 * private address, never publicly). Do not add a second way in, and never read a role from a request
 * parameter or body.
 *
 * <p><strong>Fails closed.</strong> A missing or unrecognised value is {@link #GUEST}, the most
 * restricted role: a request that did not come through cproxy (a hand-run {@code curl} on the box, a
 * cproxy older than 0.17.0) gets the guest window rather than the full list.
 *
 * <p>Today this drives {@code GET /news/list} only — the order (admin: last edited; everyone else: article
 * date) and the guest cap. See {@link NewsController#list}.
 */
public enum ViewerRole {
    GUEST,
    USER,
    ADMIN;

    /** The request header cproxy sets. */
    public static final String HEADER = "X-Fish-Role";

    /**
     * @param headerValue the raw header value, possibly null
     * @return the role it names, case-insensitively; {@link #GUEST} for null, blank or unknown
     */
    public static ViewerRole fromHeader(String headerValue) {
        if (headerValue == null) {
            return GUEST;
        }
        switch (headerValue.trim().toLowerCase(Locale.ROOT)) {
            case "admin":
                return ADMIN;
            case "user":
                return USER;
            default:
                return GUEST;
        }
    }
}
