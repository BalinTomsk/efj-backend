package com.fishfind.docapi.web;

import java.time.OffsetDateTime;
import java.util.LinkedHashMap;
import java.util.Map;

/**
 * Standard response envelope used by every endpoint: {@code { data, error, meta }} (the platform-wide
 * API convention documented in {@code waterservice}'s architectural rules). Exactly one of {@code data}
 * / {@code error} is populated; {@code meta} always carries a response timestamp.
 *
 * @param data the payload on success (a JSON document, an {@code {id}} node, …); {@code null} on error
 * @param error the error descriptor on failure; {@code null} on success
 * @param meta response metadata (always present)
 * @param <T> payload type
 */
public record ApiResponse<T>(T data, ApiError error, Map<String, Object> meta) {

    /** Machine-readable error code plus a human-readable message. */
    public record ApiError(String code, String message) {}

    /**
     * @param data the success payload
     * @return an envelope carrying {@code data} and a null error
     */
    public static <T> ApiResponse<T> ok(T data) {
        return new ApiResponse<>(data, null, newMeta());
    }

    /**
     * @param code stable machine-readable error code (e.g. {@code not_found})
     * @param message human-readable explanation
     * @return an envelope carrying an error and null data
     */
    public static ApiResponse<Void> fail(String code, String message) {
        return new ApiResponse<>(null, new ApiError(code, message), newMeta());
    }

    private static Map<String, Object> newMeta() {
        Map<String, Object> meta = new LinkedHashMap<>();
        meta.put("timestamp", OffsetDateTime.now().toString());
        return meta;
    }
}
