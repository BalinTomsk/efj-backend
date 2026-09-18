package com.fishfind.docapi.config;

import org.springframework.boot.context.properties.ConfigurationProperties;

/**
 * Entry bounds for the news caches, bound from {@code docapi.cache.*}.
 *
 * <p>These were {@code static final} constants in {@link com.fishfind.docapi.repo.NewsQueryCache} and
 * {@link com.fishfind.docapi.repo.NewsDocumentCache} until 2026-09-18. They are configuration now for
 * one reason: <strong>heap</strong>. The two heavy caches hold roughly 13 MB ({@code photo}) and
 * 25–35 MB ({@code export}) when full, the container sets no {@code -Xmx}, and 25 was an agreed number
 * rather than a measured ceiling — so the number most likely to need changing under memory pressure
 * was the one that required a rebuild and a redeploy to change. It is now an environment variable.
 *
 * <p>Every value is a count of <strong>entries</strong>, not bytes; an entry's size varies enormously
 * between caches (a list page is a few KB, a lead photo about half a megabyte), which is why each one
 * is tunable separately instead of a single shared bound. {@code 0} makes a cache evict on write and
 * therefore always miss, which is a legitimate way to switch one off without a code change.
 *
 * <p>Defaults reproduce the constants exactly, so an unconfigured service behaves as it did before.
 */
@ConfigurationProperties(prefix = "docapi.cache")
public class NewsCacheProperties {

    /** News-by-species panels — {@code GET /news/fish/{guid}}, keyed {@code guid|limit}. */
    private int fish = 25;

    /** News-by-water-body panels — {@code GET /news/lake/{guid}}, keyed {@code guid|limit}. */
    private int waterBody = 25;

    private final News news = new News();

    public int getFish() {
        return fish;
    }

    public void setFish(int fish) {
        this.fish = fish;
    }

    public int getWaterBody() {
        return waterBody;
    }

    public void setWaterBody(int waterBody) {
        this.waterBody = waterBody;
    }

    public News getNews() {
        return news;
    }

    /** The caches keyed by news article rather than by lake or species. */
    public static class News {

        /** Whole documents — {@code GET /news/{id}}, keyed by lower-cased guid. */
        private int document = 25;

        /**
         * Ids known not to resolve, held for {@code NewsDocumentCache.MISS_TTL_MS}.
         *
         * <p>Larger than the others on purpose: entries are a guid and a timestamp, and the point is to
         * absorb a crawler walking guids, which needs room for far more distinct keys than the document
         * cache holds.
         */
        private int miss = 500;

        /** {@code GET /news/list} responses outside the US/CA row buckets, keyed {@code country|offset|limit}. */
        private int list = 100;

        /**
         * Interchange documents — {@code GET /news/export/{id}}.
         *
         * <p>The heaviest cache here after {@code photo}: a parsed {@code JsonNode} whose base64 photo
         * strings cost two bytes per character, so roughly 1–1.5 MB apiece. Lower this first under
         * memory pressure.
         */
        private int export = 25;

        /** Whole search pages — {@code GET /news/search}, keyed {@code query|fishIds|country|offset|limit}. */
        private int search = 25;

        /** Raw lead-photo blobs — {@code GET /news/photo/{id}}. About 0.5 MB each, measured live. */
        private int photo = 25;

        public int getDocument() {
            return document;
        }

        public void setDocument(int document) {
            this.document = document;
        }

        public int getMiss() {
            return miss;
        }

        public void setMiss(int miss) {
            this.miss = miss;
        }

        public int getList() {
            return list;
        }

        public void setList(int list) {
            this.list = list;
        }

        public int getExport() {
            return export;
        }

        public void setExport(int export) {
            this.export = export;
        }

        public int getSearch() {
            return search;
        }

        public void setSearch(int search) {
            this.search = search;
        }

        public int getPhoto() {
            return photo;
        }

        public void setPhoto(int photo) {
            this.photo = photo;
        }
    }
}
