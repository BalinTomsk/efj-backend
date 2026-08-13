package com.fishfind.weather.canonical;

import com.fasterxml.jackson.annotation.JsonInclude;
import com.fasterxml.jackson.annotation.JsonPropertyOrder;
import com.fasterxml.jackson.databind.JsonNode;
import java.time.Instant;
import java.util.List;

/**
 * The canonical forecast envelope stored in {@code dbo.ows_meteo.ows}, whichever provider was fetched.
 *
 * <pre>
 * { "schema":"fishfind.weather.forecast/v1", "provider":"visual-crossing", "providerType":4,
 *   "mli":"13068500", "fetchedUtc":"2026-08-13T04:12:00Z",
 *   "days":[ … ],
 *   "raw":{ …the provider's original document… } }
 * </pre>
 *
 * <p><b>{@code raw} is not decoration.</b> Diagnosing the 2026-08-12 Visual Crossing outage only worked
 * because the provider's actual document was still in the table and could be replayed against the
 * procedure. Keeping it inside the envelope preserves that, and avoids an {@code ALTER TABLE} on a
 * replicated table. {@code sp_ows_meteo_canonical} ignores it.
 *
 * <p><b>{@code schema} is the contract.</b> The database routes on it and treats a version it does not
 * know as a no-op rather than a guess, so this service can be deployed ahead of the database without a
 * payload being half-parsed. Bump {@link #SCHEMA} only alongside a database that understands it.
 */
@JsonInclude(JsonInclude.Include.NON_NULL)
@JsonPropertyOrder({"schema", "provider", "providerType", "mli", "fetchedUtc", "days", "raw"})
public record CanonicalForecast(
        String schema,
        String provider,
        int providerType,
        String mli,
        Instant fetchedUtc,
        List<ForecastDay> days,
        JsonNode raw) {

    /** Envelope version understood by {@code dbo.sp_ows_meteo_canonical}. */
    public static final String SCHEMA = "fishfind.weather.forecast/v1";

    public CanonicalForecast(String provider, int providerType, String mli,
                             Instant fetchedUtc, List<ForecastDay> days, JsonNode raw) {
        this(SCHEMA, provider, providerType, mli, fetchedUtc, days, raw);
    }
}
