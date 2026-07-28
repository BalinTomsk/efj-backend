package com.fishfind.docapi.web;

import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.fishfind.docapi.repo.NewsQueryRepository;
import com.fishfind.docapi.service.InvalidDocumentException;
import com.fishfind.docapi.service.NewsDocumentService;
import org.springframework.http.MediaType;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

import java.util.List;
import java.util.Locale;

/**
 * News endpoints under {@code /api/v1/news}. Inherits the generic JSON-document CRUD
 * ({@code GET/POST/PUT /{id}}) from {@link AbstractDocumentController} and adds the two News-page read
 * queries:
 *
 * <ul>
 *   <li>{@code GET /api/v1/news/list} — one page of the latest news (country filter + pagination);</li>
 *   <li>{@code GET /api/v1/news/default} — the assembled home page.</li>
 * </ul>
 *
 * <p>Both queries are delegated to {@link NewsQueryRepository}, which handles DB access via SQL
 * functions and provides in-memory implementations for the no-database profile. The literal
 * {@code /list} and {@code /default} paths are matched ahead of the templated {@code /{id}} handler,
 * so they never collide with a document fetch.
 */
@RestController
@RequestMapping(value = "/api/v1/news", produces = MediaType.APPLICATION_JSON_VALUE)
public class NewsController extends AbstractDocumentController {

    /** Default page size (matches News.aspx {@code nPage}). */
    static final int DEFAULT_LIMIT = 25;
    /** Upper bound on page size. */
    static final int MAX_LIMIT = 200;

    private final NewsQueryRepository queryRepository;

    public NewsController(NewsDocumentService service, ObjectMapper objectMapper,
                          NewsQueryRepository queryRepository) {
        super(service, objectMapper);
        this.queryRepository = queryRepository;
    }

    /**
     * One page of the latest news with optional country filter and pagination.
     *
     * @param country ISO-2 code to filter by, or omitted/blank for all countries (a thin non-CA country
     *                is padded with Canadian news up to 100)
     * @param offset rows to skip (null/negative → 0)
     * @param limit page size (null/&lt;1 → {@value #DEFAULT_LIMIT}; capped at {@value #MAX_LIMIT})
     * @return the page rows plus the grand total, in the response envelope
     * @throws InvalidDocumentException if {@code country} is present but not a 2-letter code (→ 400)
     */
    @GetMapping("/list")
    public ApiResponse<NewsListPage> list(
            @RequestParam(required = false) String country,
            @RequestParam(required = false) Integer offset,
            @RequestParam(required = false) Integer limit) {
        String normalizedCountry = normalizeCountry(country);
        int safeOffset = (offset == null || offset < 0) ? 0 : offset;
        int safeLimit = (limit == null || limit < 1) ? DEFAULT_LIMIT : Math.min(limit, MAX_LIMIT);

        return ApiResponse.ok(queryRepository.list(normalizedCountry, safeOffset, safeLimit));
    }

    /**
     * The assembled home page in display order (lead articles first, then right-column items).
     *
     * @return {@code { "items": [ <news>, ... ] }} in the response envelope
     */
    @GetMapping("/default")
    public ApiResponse<JsonNode> defaultNews() {
        return ApiResponse.ok(queryRepository.defaultNews());
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
