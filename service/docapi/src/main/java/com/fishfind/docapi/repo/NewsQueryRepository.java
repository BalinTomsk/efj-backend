package com.fishfind.docapi.repo;

import com.fasterxml.jackson.databind.JsonNode;
import com.fishfind.docapi.web.NewsController.NewsListPage;

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
}
