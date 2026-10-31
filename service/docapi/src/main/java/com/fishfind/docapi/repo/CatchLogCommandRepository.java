package com.fishfind.docapi.repo;

import com.fasterxml.jackson.databind.JsonNode;

import java.time.LocalDate;

/** Writes catch logs ({@code dbo.catch_memo}) and their photos; used by the MCP write tools only. */
public interface CatchLogCommandRepository {

    /** Max visible photos per catch log, the limit {@code dbo.sp_add_catch_memo_photo} enforces. */
    int MAX_PHOTOS = 3;

    /** Whether {@code fishId} is a species in {@code dbo.fish}. */
    boolean fishExists(String fishId);

    /** Visible photos on catch log {@code catchLogId}, or -1 when the log does not exist. */
    int photoCount(String catchLogId);

    /** Catch log {@code catchLogId} as stored, or {@code null} when it does not exist. */
    CatchLog find(String catchLogId);

    /**
     * The water body's station forecast for {@code date}, the snapshot the portal stamps on a catch log;
     * {@link CatchLog.Weather#NONE} when the water body has no station or the date has no forecast on file
     * (about 15 days are kept). Never fails: a lookup error is logged and treated as no forecast.
     */
    CatchLog.Weather stationWeather(String lakeId, LocalDate date);

    /**
     * Stores {@code log} (an update when its id exists: every column is replaced, except that a {@code null}
     * angler keeps the stored one) and returns it as read back from the table, or {@code null} when its water body does
     * not exist. The species is the caller's to check first ({@link #fishExists}): a caller mistake must never
     * reach the shared breaker as a failure.
     */
    JsonNode add(CatchLog log);

    /**
     * Attaches a JPEG at position {@code ord} to catch log {@code catchLogId} and returns the log as read back,
     * or {@code null} when the log does not exist. The {@link #MAX_PHOTOS} limit is the caller's to check first
     * ({@link #photoCount}).
     */
    JsonNode addPhoto(String catchLogId, String userId, byte[] jpeg, int ord, String description, String author);
}
