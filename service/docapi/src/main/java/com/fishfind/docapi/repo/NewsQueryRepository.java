package com.fishfind.docapi.repo;

import com.fasterxml.jackson.databind.JsonNode;
import com.fishfind.docapi.web.NewsController.NewsFishPage;
import com.fishfind.docapi.web.NewsController.NewsLakePage;
import com.fishfind.docapi.web.NewsController.NewsListPage;
import com.fishfind.docapi.web.NewsController.NewsSearchPage;
import com.fishfind.docapi.web.NewsController.NewsSearchQuery;

/**
 * Query repository for news-page read operations, backed by SQL functions in the DB.
 * Separates HTTP/controller concerns from DB access logic.
 */
public interface NewsQueryRepository {

    /**
     * Hard cap on how many matches a {@link #search} considers, before {@code offset}/{@code limit}
     * page them. This is {@code dbo.fn_news_search}'s own {@code TOP 100} promoted to a contract, so
     * the MySQL backing — which has no such function to inherit it from — caps identically and a
     * caller's pager total means the same thing whichever backing answered it.
     */
    int SEARCH_CAP = 100;

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
     * The lead photo ({@code news_photo0}) of one published article, as the raw bytes that were
     * uploaded — no base64, no envelope. This is the by-URL counterpart of the base64 photo embedded
     * in {@link #defaultNews()}: the home page renders its leads from that embedded copy, and the
     * browser then fetches the very same bytes through this endpoint on a cache miss, so the frontend
     * needs no database connection of its own to show a news photo.
     *
     * <p>Unpublished articles return {@code null} here exactly as their text is invisible everywhere
     * else, so a draft's photo can never be reached by guessing its id.
     *
     * @param id the article id
     * @return the photo bytes, or {@code null} when the article is missing, unpublished, or has no photo
     */
    byte[] newsPhoto(String id);

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
     * Searches published news for a term across the headline, source, paragraphs and photo alts, plus
     * any article tagged with one of the species named in {@link NewsSearchQuery#fishIds()}. Newest
     * first, capped and paged as the request asks.
     *
     * @param request the term, species ids, country filter and page window
     * @return the matching page of news plus the grand total
     */
    NewsSearchPage search(NewsSearchQuery request);

    /**
     * The latest published articles that name one water body, newest first.
     *
     * <p>This is the news half of the public water-body pages ({@code Resources/wfRiverViewer.aspx}),
     * which until now read SQL Server's {@code dbo.fn_river_view_news} directly. The column split
     * that function performs ({@code @col = num % 2}, one call per rendered column) is presentation
     * and is deliberately <em>not</em> reproduced here: this returns one ordered list and the caller
     * lays it out.
     *
     * <p>Species and the water body itself come back as they do everywhere else on this API — the
     * caller already holds the name it is rendering, so nothing here joins another database to
     * resolve one.
     *
     * @param lakeId the water body's guid, as the caller's canonical 8-4-4-4-12 text form
     * @param limit how many articles at most (already clamped)
     * @return the articles, newest first — empty (never null) when the water body has none
     */
    NewsLakePage lakeNews(String lakeId, int limit);

    /**
     * The latest published articles that mention one species, newest first.
     *
     * <p>{@link #lakeNews}'s counterpart for {@code Resources/wfFishViewer.aspx}, which read
     * {@code dbo.fn_fish_view_news} directly. An article carries up to three species tags and
     * matching any one of them counts, the same three-slot rule {@link #search} applies to its
     * {@code fishIds}.
     *
     * @param fishId the species guid, as the caller's canonical 8-4-4-4-12 text form
     * @param limit how many articles at most (already clamped)
     * @return the articles, newest first — empty (never null) when the species has none
     */
    NewsFishPage fishNews(String fishId, int limit);
}
