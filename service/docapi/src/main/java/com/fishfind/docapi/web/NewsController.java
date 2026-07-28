package com.fishfind.docapi.web;

import com.fasterxml.jackson.core.JsonProcessingException;
import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.fasterxml.jackson.databind.node.ArrayNode;
import com.fasterxml.jackson.databind.node.ObjectNode;
import com.fishfind.docapi.service.InvalidDocumentException;
import com.fishfind.docapi.service.NewsDocumentService;
import io.github.resilience4j.circuitbreaker.annotation.CircuitBreaker;
import io.github.resilience4j.retry.annotation.Retry;
import org.springframework.beans.factory.ObjectProvider;
import org.springframework.http.MediaType;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.jdbc.core.PreparedStatementSetter;
import org.springframework.jdbc.core.ResultSetExtractor;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

import java.sql.Types;
import java.util.ArrayList;
import java.util.List;
import java.util.Locale;

/**
 * News endpoints under {@code /api/v1/news}. Inherits the generic JSON-document CRUD
 * ({@code GET/POST/PUT /{id}}) from {@link AbstractDocumentController} and adds the two News-page read
 * queries, which call the SQL functions created in {@code envfish-db}:
 *
 * <ul>
 *   <li>{@code GET /api/v1/news/list} — one page of the latest news (country filter + pagination),
 *       backed by {@code dbo.fn_news_list(@country, @offset, @fetch)};</li>
 *   <li>{@code GET /api/v1/news/default} — the assembled home page, backed by
 *       {@code dbo.fn_default_news_ids()} + {@code dbo.fn_default_news_json(@news_id, @with_photo)}.</li>
 * </ul>
 *
 * <p>The literal {@code /list} and {@code /default} paths are matched ahead of the templated
 * {@code /{id}} handler, so they never collide with a document fetch.
 *
 * <p>Consistent with the rest of the service, the {@link JdbcTemplate} is present only under the
 * {@code jdbc} profile; in the default (no-database) profile it is absent and the two queries return
 * empty results so the service still runs end-to-end with no DB. All reads go through table-valued /
 * scalar functions (never base tables), and each DB call is guarded by Resilience4j retry
 * ({@code sqlRetry}) + circuit breaker ({@code sqlBreaker}), matching {@code JdbcDocumentRepository}.
 */
@RestController
@RequestMapping(value = "/api/v1/news", produces = MediaType.APPLICATION_JSON_VALUE)
public class NewsController extends AbstractDocumentController {

    /** Default page size (matches News.aspx {@code nPage}). */
    static final int DEFAULT_LIMIT = 25;
    /** Upper bound on page size (mirrors the clamp inside {@code dbo.fn_news_list}). */
    static final int MAX_LIMIT = 200;

    static final String LIST_SQL =
            "SELECT rn, news_id, title, source, stamp, flag, has_photo, block_ord, total "
                    + "FROM dbo.fn_news_list(?, ?, ?) ORDER BY rn";

    static final String DEFAULT_SQL =
            "SELECT dbo.fn_default_news_json(news_id, with_photo) "
                    + "FROM dbo.fn_default_news_ids() ORDER BY ord";

    private final ObjectMapper objectMapper;
    private final JdbcTemplate jdbc; // null under the default (no-DB) profile

    public NewsController(NewsDocumentService service, ObjectMapper objectMapper,
                          ObjectProvider<JdbcTemplate> jdbcProvider) {
        super(service, objectMapper);
        this.objectMapper = objectMapper;
        this.jdbc = jdbcProvider.getIfAvailable();
    }

    /**
     * One page of the latest news (see {@code dbo.fn_news_list}).
     *
     * @param country ISO-2 code to filter by, or omitted/blank for all countries (a thin non-CA country
     *                is padded with Canadian news up to 100)
     * @param offset rows to skip (null/negative → 0)
     * @param limit page size (null/&lt;1 → {@value #DEFAULT_LIMIT}; capped at {@value #MAX_LIMIT})
     * @return the page rows plus the grand total, in the response envelope
     * @throws InvalidDocumentException if {@code country} is present but not a 2-letter code (→ 400)
     */
    @GetMapping("/list")
    @Retry(name = "sqlRetry")
    @CircuitBreaker(name = "sqlBreaker", fallbackMethod = "listFallback")
    public ApiResponse<NewsListPage> list(
            @RequestParam(required = false) String country,
            @RequestParam(required = false) Integer offset,
            @RequestParam(required = false) Integer limit) {
        String normalizedCountry = normalizeCountry(country);
        int safeOffset = (offset == null || offset < 0) ? 0 : offset;
        int safeLimit = (limit == null || limit < 1) ? DEFAULT_LIMIT : Math.min(limit, MAX_LIMIT);

        if (jdbc == null) {
            return ApiResponse.ok(new NewsListPage(List.of(), 0L, safeOffset, safeLimit));
        }

        PreparedStatementSetter binder = ps -> {
            if (normalizedCountry == null) {
                ps.setNull(1, Types.CHAR);
            } else {
                ps.setString(1, normalizedCountry);
            }
            ps.setInt(2, safeOffset);
            ps.setInt(3, safeLimit);
        };

        ResultSetExtractor<NewsListPage> extractor = rs -> {
            List<NewsListItem> items = new ArrayList<>();
            long total = 0L;
            while (rs.next()) {
                // total is COUNT(*) OVER() -- identical on every row; read it once.
                if (items.isEmpty()) {
                    total = rs.getLong("total");
                }
                items.add(new NewsListItem(
                        rs.getLong("rn"),
                        rs.getString("news_id"),
                        rs.getString("title"),
                        rs.getString("source"),
                        rs.getString("stamp"),
                        rs.getString("flag"),
                        rs.getBoolean("has_photo"),
                        rs.getInt("block_ord")));
            }
            return new NewsListPage(items, total, safeOffset, safeLimit);
        };

        return ApiResponse.ok(jdbc.query(LIST_SQL, binder, extractor));
    }

    /**
     * The assembled home page: {@code { "items": [ <news>, ... ] }} in display order (lead articles
     * first, then the right-column items). Each item is the JSON document returned by
     * {@code dbo.fn_default_news_json}, nested as real JSON (not an escaped string).
     *
     * @return the home-page JSON tree in the response envelope
     */
    @GetMapping("/default")
    @Retry(name = "sqlRetry")
    @CircuitBreaker(name = "sqlBreaker", fallbackMethod = "defaultFallback")
    public ApiResponse<JsonNode> defaultNews() {
        ArrayNode items = objectMapper.createArrayNode();
        if (jdbc != null) {
            for (String json : jdbc.query(DEFAULT_SQL, (rs, i) -> rs.getString(1))) {
                if (json == null || json.isBlank()) {
                    continue;
                }
                items.add(parseItem(json));
            }
        }
        ObjectNode root = objectMapper.createObjectNode();
        root.set("items", items);
        return ApiResponse.ok(root);
    }

    /**
     * Circuit-breaker fallback for {@link #list}: surfaces the failure as an unchecked exception (→ 500).
     * A bad-request ({@link InvalidDocumentException}) is rethrown unchanged so it still maps to 400.
     */
    @SuppressWarnings("unused")
    public ApiResponse<NewsListPage> listFallback(String country, Integer offset, Integer limit, Throwable ex) {
        if (ex instanceof InvalidDocumentException ide) {
            throw ide;
        }
        throw new RuntimeException("SQL news-list query failed", ex);
    }

    /**
     * Circuit-breaker fallback for {@link #defaultNews}.
     */
    @SuppressWarnings("unused")
    public ApiResponse<JsonNode> defaultFallback(Throwable ex) {
        throw new RuntimeException("SQL default-news query failed", ex);
    }

    private JsonNode parseItem(String json) {
        try {
            return objectMapper.readTree(json);
        } catch (JsonProcessingException ex) {
            // A malformed document coming back from the DB is a server-side data problem, not a client error.
            throw new IllegalStateException("Home-page news JSON returned by the database is not valid JSON", ex);
        }
    }

    private String normalizeCountry(String country) {
        if (country == null) {
            return null;
        }
        String trimmed = country.trim();
        if (trimmed.isEmpty()) {
            return null;
        }
        if (trimmed.length() != 2 || !trimmed.chars().allMatch(Character::isLetter)) {
            throw new InvalidDocumentException("country must be a 2-letter ISO code (e.g. 'CA', 'US')");
        }
        return trimmed.toUpperCase(Locale.ROOT);
    }

    /**
     * One row of the paged latest-news list ({@code dbo.fn_news_list}).
     *
     * @param rn 1-based global position in the ordered+padded list
     * @param newsId the article id
     * @param title the headline
     * @param source the publication/source label
     * @param stamp the publish date as an ISO {@code yyyy-MM-dd} string
     * @param flag the ISO-2 country code of the article
     * @param hasPhoto whether the article carries a real (&gt; 100-byte) lead photo
     * @param blockOrd 0 = the requested country's own news; 1 = Canadian padding to fill up to 100
     */
    public record NewsListItem(
            long rn,
            String newsId,
            String title,
            String source,
            String stamp,
            String flag,
            boolean hasPhoto,
            int blockOrd) {
    }

    /**
     * One page of the latest-news list plus the grand total, so a numbered pager can be rendered from a
     * single call.
     *
     * @param items the rows on this page (newest first; country block then any CA padding)
     * @param total the full row count of the filtered+padded list
     * @param offset the (clamped) row offset this page started at
     * @param limit the (clamped) page size used
     */
    public record NewsListPage(
            List<NewsListItem> items,
            long total,
            int offset,
            int limit) {
    }
}
