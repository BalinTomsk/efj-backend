package com.fishfind.docapi.repo;

/**
 * Creates and replaces news articles -- the storage behind {@code POST /api/v1/news},
 * {@code PUT /api/v1/news/{id}} and {@code POST /api/v1/news/import}.
 *
 * <p>Under the {@code jdbc} profile this is {@link MySqlNewsWriteRepository}, against the same MySQL
 * {@code news} table every news read uses. Since docapi 1.16.0 nothing in docapi writes SQL Server's
 * {@code dbo.news}.
 */
public interface NewsWriteRepository {

    /**
     * Creates one new, published article.
     *
     * @param write the parsed article; {@code stamp} {@code null} means now
     * @return the generated article id
     */
    String insert(NewsWrite write);

    /**
     * Replaces one article's text fields and its slot-0 photo metadata (full replace -- a
     * {@code null} field is stored as {@code null}), except that a {@code null} stamp keeps the
     * stored stamp and {@code null} slot-0 bytes keep the stored photo. Never changes whether the
     * article is published, and never touches photo slots 1 and 2.
     *
     * @return {@code false} when no article exists for {@code id} -- nothing is written in that case
     */
    boolean update(String id, NewsWrite write);
}
