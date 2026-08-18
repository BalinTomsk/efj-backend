package com.fishfind.docapi.repo;

import com.fasterxml.jackson.core.JsonProcessingException;
import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.fishfind.docapi.web.FishController.FishSearchItem;
import com.fishfind.docapi.web.FishController.FishSearchPage;
import io.github.resilience4j.circuitbreaker.annotation.CircuitBreaker;
import io.github.resilience4j.retry.annotation.Retry;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.jdbc.core.PreparedStatementSetter;

import java.util.List;

/**
 * JDBC fish query repository backed by the SQL Server function {@code dbo.SearchFishList}.
 * All DB access for fish-catalogue search goes through here.
 * Guarded by Resilience4j retry + circuit breaker, matching {@link JdbcNewsQueryRepository}.
 */
public class JdbcFishQueryRepository implements FishQueryRepository {

    /**
     * Relevance-ranked species search. {@code dbo.SearchFishList} is a table-valued function that
     * normalizes the term itself and matches it against {@code fish_name}, {@code fish_latin} and the
     * {@code alt_name} synonyms, returning a lower {@code irank} for better matches — so ordering by
     * {@code irank} gives best-match-first, exactly like the Editor {@code FishList.aspx} search box.
     */
    static final String SEARCH_SQL =
            "SELECT fish_name, fish_latin, fish_id, irank FROM dbo.SearchFishList(?) ORDER BY irank ASC";

    /**
     * Regional code -> Latin name for one province. The whole document is built by the function, so the
     * repository only moves the string. {@code @codes} is a JSON array (not a delimited string) because
     * 762 of the 1041 species names contain a comma, and because OPENJSON exposes the element index,
     * which is what preserves the caller's ordering. A NULL third argument means "the whole province".
     */
    static final String CODE_LATIN_SQL = "SELECT dbo.fn_fish_code_latin_json(?, ?, ?)";

    /**
     * Batch common-name -> Latin name. Same JSON-array argument for the same reasons; the function
     * returns one element per requested name, in order, echoing the request in {@code query}.
     */
    static final String NAME_LATIN_SQL = "SELECT dbo.fn_fish_latin_json(?)";

    private final JdbcTemplate jdbc;
    private final ObjectMapper objectMapper;

    public JdbcFishQueryRepository(JdbcTemplate jdbc, ObjectMapper objectMapper) {
        this.jdbc = jdbc;
        this.objectMapper = objectMapper;
    }

    @Override
    @Retry(name = "sqlRetry")
    @CircuitBreaker(name = "sqlBreaker", fallbackMethod = "searchFallback")
    public FishSearchPage search(String query) {
        // SearchFishList takes the raw term (varchar(64)) and normalizes it internally, so the term is
        // bound as a plain parameter with no LIKE-escaping — the function builds its own match variants.
        List<FishSearchItem> items = jdbc.query(
                SEARCH_SQL,
                ps -> ps.setString(1, query),
                (rs, i) -> new FishSearchItem(
                        rs.getString("fish_id"),
                        rs.getString("fish_name"),
                        rs.getString("fish_latin"),
                        rs.getInt("irank")));
        return new FishSearchPage(items, items.size(), query);
    }

    @Override
    @Retry(name = "sqlRetry")
    @CircuitBreaker(name = "sqlBreaker", fallbackMethod = "codesFallback")
    public JsonNode codesToLatin(String country, String province, List<String> codes) {
        // A null country means "any" and a null code list means "the whole province"; both are passed
        // through as SQL NULLs rather than being branched on here, so the function owns the semantics.
        String codesJson = (codes == null) ? null : toJsonArray(codes);
        return queryJsonArray(CODE_LATIN_SQL, ps -> {
            ps.setString(1, country);
            ps.setString(2, province);
            ps.setString(3, codesJson);
        });
    }

    @Override
    @Retry(name = "sqlRetry")
    @CircuitBreaker(name = "sqlBreaker", fallbackMethod = "namesFallback")
    public JsonNode namesToLatin(List<String> names) {
        String namesJson = toJsonArray(names);
        return queryJsonArray(NAME_LATIN_SQL, ps -> ps.setString(1, namesJson));
    }

    /**
     * Runs a scalar-JSON query and parses the result. Both functions are written to return {@code '[]'}
     * rather than NULL, but a NULL/blank scalar is still mapped to an empty array so a caller can never
     * receive something unparseable.
     */
    private JsonNode queryJsonArray(String sql, PreparedStatementSetter binder) {
        List<String> rows = jdbc.query(sql, binder, (rs, i) -> rs.getString(1));
        String json = rows.isEmpty() ? null : rows.get(0);
        return (json == null || json.isBlank()) ? objectMapper.createArrayNode() : parseItem(json);
    }

    /**
     * Renders the caller's list as a JSON array argument. Jackson does the escaping, so a name carrying
     * a quote or a backslash cannot terminate its own string and change the shape of the argument.
     */
    private String toJsonArray(List<String> values) {
        try {
            return objectMapper.writeValueAsString(values);
        } catch (JsonProcessingException ex) {
            throw new IllegalStateException("Could not render the lookup list as JSON", ex);
        }
    }

    private JsonNode parseItem(String json) {
        try {
            return objectMapper.readTree(json);
        } catch (JsonProcessingException ex) {
            throw new IllegalStateException("Malformed JSON returned by the fish lookup function", ex);
        }
    }

    /**
     * Circuit-breaker fallback for {@link #search}.
     */
    @SuppressWarnings("unused")
    public FishSearchPage searchFallback(String query, Throwable ex) {
        throw new RuntimeException("SQL fish-search query failed", ex);
    }

    /**
     * Circuit-breaker fallback for {@link #codesToLatin}.
     */
    @SuppressWarnings("unused")
    public JsonNode codesFallback(String country, String province, List<String> codes, Throwable ex) {
        throw new RuntimeException("SQL fish-code lookup failed", ex);
    }

    /**
     * Circuit-breaker fallback for {@link #namesToLatin}.
     */
    @SuppressWarnings("unused")
    public JsonNode namesFallback(List<String> names, Throwable ex) {
        throw new RuntimeException("SQL fish-name lookup failed", ex);
    }
}
