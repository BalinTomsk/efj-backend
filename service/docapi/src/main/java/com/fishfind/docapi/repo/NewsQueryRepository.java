package com.fishfind.docapi.repo;

import com.fasterxml.jackson.databind.JsonNode;
import com.fishfind.docapi.web.NewsController.NewsListPage;
import com.fishfind.docapi.web.NewsController.NewsSearchPage;

import java.util.List;

/**
 * Query repository for news-page read operations, backed by SQL functions in the DB.
 * Separates HTTP/controller concerns from DB access logic.
 */
public interface NewsQueryRepository {

    /**
     * One page of the latest news with optional country filter and pagination.
     *
     * @param country ISO-2 code (null/blank = all countries; a thin non-CA country is padded with CA news to 100)
     * @param offset rows to skip (non-negative)
     * @param limit page size (already clamped)
     * @return paginated news list + grand total
     */
    NewsListPage list(String country, int offset, int limit);

    /**
     * The assembled home page: lead articles then right-column items, in display order.
     *
     * @return root JSON object with "items" array, each element is the JSON document for one news item
     */
    JsonNode defaultNews();

    /**
     * Resolves the water body and fish species ids a news article <em>mentions</em>
     * ({@code news.lake_id}, {@code news.fish1_id}…{@code fish3_id}) to their display names — the tag
     * row Default.aspx renders under each lead article.
     *
     * <p>This exists only because the news rows moved to MySQL (2026-08-31) and that database holds
     * <strong>only</strong> the {@code news} table: no {@code lake}, no {@code fish}. So
     * {@link MySqlNewsQueryRepository#defaultNews()} gets bare guids back and calls this on its
     * SQL-Server-backed delegate to fill the names in — one round trip for the whole home page
     * (up to 2 lake ids + 6 fish ids), not one call per tag. The SQL-Server-only path
     * ({@code dbo.fn_default_news_json}) resolves them inline and never calls this.
     *
     * @param lakeIds water-body ids to resolve, in the order the caller wants them back (may be empty)
     * @param fishIds species ids to resolve, in the order the caller wants them back (may be empty)
     * @return {@code {"lakes":[{"id","name"}],"fishes":[{"id","name","latin"}]}} — never null, and 1:1
     *         with the request in the order asked; an id that resolves to nothing keeps its element
     *         with a null {@code name}
     */
    JsonNode resolveRefNames(List<String> lakeIds, List<String> fishIds);

    /**
     * Exports one article as the {@code fn_news_json} interchange document — every field needed to
     * re-create it, with the 3 paragraph photos embedded as base64. This is the same shape the
     * News.aspx "Save JSON" link and the AddNews "Import from JSON" round-trip use.
     *
     * @param id the article id
     * @return the article as a JSON tree, or {@code null} if no article exists for the id
     */
    JsonNode exportNews(String id);

    /**
     * Imports one article from an {@code fn_news_json} interchange document, creating a new published
     * article (base64 photos decoded to binary).
     *
     * @param json the interchange JSON body (validated well-formed upstream)
     * @return the id assigned to the newly created article
     */
    String importNews(String json);

    /**
     * Searches published news for a term across the headline, source, paragraphs, photo alts, and the
     * names of the mentioned fishes. Up to 100 matches, newest first.
     *
     * @param query the (trimmed, non-blank) search term
     * @return the matching news list
     */
    NewsSearchPage search(String query);
}
