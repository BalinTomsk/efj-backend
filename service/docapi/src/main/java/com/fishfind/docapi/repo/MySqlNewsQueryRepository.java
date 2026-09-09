package com.fishfind.docapi.repo;

import com.fasterxml.jackson.core.JsonProcessingException;
import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.fasterxml.jackson.databind.node.ArrayNode;
import com.fasterxml.jackson.databind.node.ObjectNode;
import io.github.resilience4j.circuitbreaker.annotation.CircuitBreaker;
import io.github.resilience4j.retry.annotation.Retry;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.jdbc.core.ResultSetExtractor;
import com.fishfind.docapi.web.NewsController.NewsListItem;
import com.fishfind.docapi.web.NewsController.NewsListPage;
import com.fishfind.docapi.web.NewsController.NewsSearchPage;

import java.sql.Types;
import java.util.ArrayList;
import java.util.List;

/**
 * News-page reads ({@code /news/list}, {@code /news/default}) backed by the MySQL {@code news}
 * table (Winhost, migrated 2026-08-31; see {@code envfish-db/mysql/script02_Proc.sql} ->
 * {@code sp_news_list_json}, {@code sp_news_default}). Search/export/import stay on the
 * SQL-Server-backed delegate -- this MySQL database has no interchange ({@code fn_news_json}) or
 * full-text-search objects, and News.aspx (the only other MySQL news consumer) doesn't need them.
 */
public class MySqlNewsQueryRepository implements NewsQueryRepository {

    static final String LIST_SQL = "CALL sp_news_list_json(?, ?, ?)";

    /**
     * The home-page document set. This is the body of the {@code v_news_default_doc} view inlined
     * as a query, rather than {@code CALL sp_news_default()} (which is just
     * {@code SELECT doc FROM v_news_default_doc ORDER BY rn LIMIT 5}).
     *
     * <p><strong>Why inlined (2026-09-09).</strong> {@code v_news_default_doc} is defined in
     * {@code envfish-db/mysql/script01_createView.sql} but <em>does not exist</em> in the live
     * Winhost database — only its dependencies ({@code v_news_default_grp1..5},
     * {@code v_news_default_ranked}, {@code v_news_default_top}) were ever applied. So
     * {@code sp_news_default()} failed with
     * {@code Table 'mysql_111487_envfish.v_news_default_doc' doesn't exist}, and
     * {@code /news/default}, {@code /news/featured} and {@code /news/more} — which all share this
     * one assembly — returned 500 in production.
     *
     * <p>It is inlined rather than fixed in the database because the application's MySQL account
     * ({@code portos}) holds no {@code CREATE VIEW} or {@code CREATE ROUTINE} privilege
     * (only SELECT/DELETE/DROP/REFERENCES/INDEX/ALTER/LOCK TABLES/EXECUTE/SHOW VIEW/ALTER
     * ROUTINE/TRIGGER), so neither the view nor the procedure can be created or repaired from
     * here — that needs the Winhost control panel. This query depends only on objects that DO
     * exist and that {@code portos} can read.
     *
     * <p>Keep this in sync with {@code v_news_default_doc} in {@code script01_createView.sql}. If
     * that view is ever actually created in the live database, this can go back to
     * {@code CALL sp_news_default()}.
     */
    static final String DEFAULT_SQL = """
            SELECT JSON_OBJECT(
                       'news_id', n.news_id,
                       'date', DATE_FORMAT(n.news_stamp, '%Y-%m-%d'),
                       'country', n.country,
                       'flag', IF(n.country IS NULL OR n.country = '', 'empty.gif', CONCAT(n.country, '.png')),
                       'title', n.news_title,
                       'author', n.news_author,
                       'author_link', n.news_author_link,
                       'source', n.news_source,
                       'source_link', n.news_source_link,
                       'credit', n.news_photo_author0,
                       'photo_alt', n.news_photo_alt0,
                       'paragraph0', n.news_paragraph0,
                       'paragraph1', n.news_paragraph1,
                       'lake_id', n.lake_id,
                       'fish1_id', n.fish1_id,
                       'fish2_id', n.fish2_id,
                       'fish3_id', n.fish3_id,
                       'snippet', TRIM(SUBSTRING_INDEX(
                           REPLACE(COALESCE(NULLIF(n.news_paragraph0, ''), n.news_paragraph1, ''), '\\r', ''),
                           '\\n', 1)),
                       'photo', IF(r.rn <= 2 AND LENGTH(n.news_photo0) > 100, TO_BASE64(n.news_photo0), NULL),
                       'with_photo', IF(r.rn <= 2, TRUE, FALSE)
                   ) AS doc
              FROM v_news_default_ranked r
              JOIN news n ON n.news_id = r.news_id
             ORDER BY r.rn
             LIMIT 5""";

    private final JdbcTemplate mysqlJdbc;
    private final ObjectMapper objectMapper;
    private final NewsQueryRepository sqlServerDelegate;

    public MySqlNewsQueryRepository(JdbcTemplate mysqlJdbc, ObjectMapper objectMapper,
                                    NewsQueryRepository sqlServerDelegate) {
        this.mysqlJdbc = mysqlJdbc;
        this.objectMapper = objectMapper;
        this.sqlServerDelegate = sqlServerDelegate;
    }

    @Override
    @Retry(name = "sqlRetry")
    @CircuitBreaker(name = "sqlBreaker", fallbackMethod = "listFallback")
    public NewsListPage list(String country, int offset, int limit) {
        ResultSetExtractor<NewsListPage> extractor = rs -> {
            List<NewsListItem> items = new ArrayList<>();
            long total = 0L;
            while (rs.next()) {
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
            return new NewsListPage(items, total, offset, limit);
        };

        return mysqlJdbc.query(LIST_SQL, ps -> {
            if (country == null) {
                ps.setNull(1, Types.CHAR);
            } else {
                ps.setString(1, country);
            }
            ps.setInt(2, offset);
            ps.setInt(3, limit);
        }, extractor);
    }

    @Override
    @Retry(name = "sqlRetry")
    @CircuitBreaker(name = "sqlBreaker", fallbackMethod = "defaultFallback")
    public JsonNode defaultNews() {
        ArrayNode items = objectMapper.createArrayNode();
        for (String json : mysqlJdbc.query(DEFAULT_SQL, (rs, i) -> rs.getString(1))) {
            if (json == null || json.isBlank()) {
                continue;
            }
            items.add(parseItem(json));
        }
        ObjectNode root = objectMapper.createObjectNode();
        root.set("items", items);
        return root;
    }

    /** Not in scope for the MySQL move -- delegates to the SQL-Server-backed repository unchanged. */
    @Override
    public JsonNode exportNews(String id) {
        return sqlServerDelegate.exportNews(id);
    }

    /** Not in scope for the MySQL move -- delegates to the SQL-Server-backed repository unchanged. */
    @Override
    public String importNews(String json) {
        return sqlServerDelegate.importNews(json);
    }

    /** Not in scope for the MySQL move -- delegates to the SQL-Server-backed repository unchanged. */
    @Override
    public NewsSearchPage search(String query) {
        return sqlServerDelegate.search(query);
    }

    /**
     * Circuit-breaker fallback for {@link #list}.
     */
    @SuppressWarnings("unused")
    public NewsListPage listFallback(String country, int offset, int limit, Throwable ex) {
        throw new RuntimeException("MySQL news-list query failed", ex);
    }

    /**
     * Circuit-breaker fallback for {@link #defaultNews}.
     */
    @SuppressWarnings("unused")
    public JsonNode defaultFallback(Throwable ex) {
        throw new RuntimeException("MySQL default-news query failed", ex);
    }

    private JsonNode parseItem(String json) {
        try {
            return objectMapper.readTree(json);
        } catch (JsonProcessingException ex) {
            throw new IllegalStateException("MySQL home-page news JSON returned by the database is not valid JSON", ex);
        }
    }
}
