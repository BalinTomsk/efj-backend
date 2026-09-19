package com.fishfind.docapi.repo;

/**
 * The order {@code GET /api/v1/news/list} returns its rows in. The caller never chooses it: the
 * controller derives it from the caller's verified role, so this is not an API parameter.
 *
 * <ul>
 *   <li>{@link #DATE} — newest article <em>date</em> first ({@code news_stamp}). Registered users and
 *       guests.</li>
 *   <li>{@link #EDITED} — most recently <em>edited</em> article first ({@code news.edit_stamp}, falling
 *       back to the row's creation stamp for an article never edited since that column existed).
 *       Admins only, so that what they just saved is on top.</li>
 * </ul>
 *
 * <p>Both break ties on the row id, so the order is total and a pager never repeats or skips a row.
 */
public enum NewsListOrder {
    DATE("date", ""),
    EDITED("edited", "edited|");

    private final String sqlValue;
    private final String cacheKeyPrefix;

    NewsListOrder(String sqlValue, String cacheKeyPrefix) {
        this.sqlValue = sqlValue;
        this.cacheKeyPrefix = cacheKeyPrefix;
    }

    /** The {@code p_sort} argument of {@code sp_news_list_json}. */
    public String sqlValue() {
        return sqlValue;
    }

    /**
     * What {@link NewsQueryCache} prepends to a cached page's key so the two orders never share an
     * entry. Empty for {@link #DATE}, which keeps every pre-existing key exactly as it was.
     */
    String cacheKeyPrefix() {
        return cacheKeyPrefix;
    }
}
