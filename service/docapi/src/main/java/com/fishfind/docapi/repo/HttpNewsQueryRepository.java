package com.fishfind.docapi.repo;

import com.fasterxml.jackson.databind.JsonNode;
import com.fishfind.docapi.web.NewsController.NewsFishPage;
import com.fishfind.docapi.web.NewsController.NewsLakePage;
import com.fishfind.docapi.web.NewsController.NewsListPage;
import com.fishfind.docapi.web.NewsController.NewsSearchPage;
import com.fishfind.docapi.web.NewsController.NewsSearchQuery;

/**
 * Every news read -- list, home page, photo, search, lake/fish panels and the interchange export -- from
 * csnews-env's news data API (docapi 1.44.0). Replaces {@code MySqlNewsQueryRepository}: the SQL, and the
 * Winhost hazards it works around (the LONGBLOB scan hang, the missing {@code v_news_default_doc} view), now
 * live in csnews-env's {@code MySqlNewsStore}.
 *
 * <p>{@link NewsQueryCache} sits in front of this bean, exactly as it sat in front of the MySQL one, so a cache
 * hit never leaves docapi. csnews-env answers in docapi's own record shapes, so binding is direct.
 */
public class HttpNewsQueryRepository implements NewsQueryRepository {

    private final CsNewsClient csnews;

    public HttpNewsQueryRepository(CsNewsClient csnews) {
        this.csnews = csnews;
    }

    @Override
    public NewsListPage list(String country, int offset, int limit, NewsListOrder order) {
        StringBuilder path = new StringBuilder("/list?offset=").append(offset).append("&limit=").append(limit)
                .append("&order=").append(order.sqlValue());
        if (country != null) {
            path.append("&country=").append(CsNewsClient.enc(country));
        }
        return csnews.bind(required(csnews.get(path.toString()), "list"), NewsListPage.class, "news list");
    }

    /** {@code {items:[...]}}, each item the home-page document of one article. */
    @Override
    public JsonNode defaultNews() {
        return required(csnews.get("/default"), "default");
    }

    @Override
    public byte[] newsPhoto(String id) {
        return csnews.getBytes("/photo/" + CsNewsClient.enc(id));
    }

    @Override
    public JsonNode exportNews(String id) {
        JsonNode doc = csnews.get("/export/" + CsNewsClient.enc(id));
        return doc == null || doc.isNull() ? null : doc;
    }

    @Override
    public NewsSearchPage search(NewsSearchQuery request) {
        StringBuilder path = new StringBuilder("/search?q=").append(CsNewsClient.enc(request.query()))
                .append("&offset=").append(request.offset()).append("&limit=").append(request.limit());
        if (request.country() != null) {
            path.append("&country=").append(CsNewsClient.enc(request.country()));
        }
        if (request.fishIds() != null) {
            for (String fishId : request.fishIds()) {
                path.append("&fishId=").append(CsNewsClient.enc(fishId));
            }
        }
        return csnews.bind(required(csnews.get(path.toString()), "search"), NewsSearchPage.class, "news search");
    }

    @Override
    public NewsLakePage lakeNews(String lakeId, int limit) {
        return csnews.bind(required(csnews.get("/lake/" + CsNewsClient.enc(lakeId) + "?limit=" + limit), "lake"),
                NewsLakePage.class, "lake news");
    }

    @Override
    public NewsFishPage fishNews(String fishId, int limit) {
        return csnews.bind(required(csnews.get("/fish/" + CsNewsClient.enc(fishId) + "?limit=" + limit), "fish"),
                NewsFishPage.class, "fish news");
    }

    /** A list route never 404s on csnews-env; a missing body is a contract break → 503. */
    private static JsonNode required(JsonNode data, String route) {
        if (data == null || data.isNull()) {
            throw new CsNewsUnavailableException("csnews-env /" + route + " returned no data", null);
        }
        return data;
    }
}
