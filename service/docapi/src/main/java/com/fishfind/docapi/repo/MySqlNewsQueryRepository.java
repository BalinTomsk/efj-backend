package com.fishfind.docapi.repo;

import com.fasterxml.jackson.core.JsonProcessingException;
import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.fasterxml.jackson.databind.node.ArrayNode;
import com.fasterxml.jackson.databind.node.ObjectNode;
import io.github.resilience4j.circuitbreaker.annotation.CircuitBreaker;
import io.github.resilience4j.retry.annotation.Retry;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.jdbc.core.PreparedStatementSetter;
import org.springframework.jdbc.core.ResultSetExtractor;
import org.springframework.jdbc.core.RowMapper;
import com.fishfind.docapi.web.NewsController.NewsFishPage;
import com.fishfind.docapi.web.NewsController.NewsRefItem;
import com.fishfind.docapi.web.NewsController.NewsLakePage;
import com.fishfind.docapi.web.NewsController.NewsListItem;
import com.fishfind.docapi.web.NewsController.NewsListPage;
import com.fishfind.docapi.web.NewsController.NewsSearchItem;
import com.fishfind.docapi.web.NewsController.NewsSearchPage;
import com.fishfind.docapi.web.NewsController.NewsSearchQuery;

import java.sql.Types;
import java.util.ArrayList;
import java.util.Collections;
import java.util.List;

/**
 * News-page reads backed by the MySQL {@code news} table (Winhost, migrated 2026-08-31; see
 * {@code envfish-db/mysql/script02_Proc.sql} -> {@code sp_news_list_json}, {@code sp_news_default}).
 *
 * <p>Covers {@code /news/list}, {@code /news/default} (and its {@code /featured} + {@code /more}
 * projections), {@code GET /news/photo/{id}} and -- since 1.10.0 -- {@code /news/search}, which is
 * every read {@code News.aspx} and {@code Default.aspx} make. That completeness is the point: with
 * search on this side, no page of the portal needs a news query against SQL Server.
 *
 * <p>Since 2026-09-17 that also covers {@code GET /news/export/{id}}, the admin "Save JSON"
 * interchange document, against the new {@code sp_news_doc_export} -- see {@link #EXPORT_SQL}. It is
 * the one endpoint here that is not a portal page read, and it was the last news query of any kind
 * still answered by SQL Server.
 *
 * <p>{@code importNews} alone still delegates to the SQL-Server-backed repository. That is not an
 * oversight and not symmetry for its own sake: {@code POST /news/import} has no caller. The portal's
 * importing half is {@code Editor/AddNews.aspx}, which parses an uploaded document in the page and
 * writes it through the {@code sp_news_admin_*} procedures directly, never through this endpoint. So
 * the round trip an admin actually performs -- export here, re-import there -- is now entirely
 * MySQL; what is left pointing at {@code dbo.sp_news_import} is an unused endpoint, and porting it
 * would be writing a MySQL import nothing calls.
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

    /**
     * One article's lead photo, by primary key. Inlined rather than {@code CALL sp_news_get_by_id(?)}
     * for two reasons: that procedure returns all fifteen news columns when only one is wanted, and —
     * as {@link #DEFAULT_SQL} records at length — a named object existing in
     * {@code envfish-db/mysql} is no evidence it exists in the live Winhost database. This statement
     * depends on nothing but the {@code news} table itself.
     *
     * <p><strong>The BLOB hazard is respected.</strong> {@code news_photo0} is a {@code LONGBLOB} and
     * the live Winhost host hangs indefinitely on any query that references it while materializing
     * more than one row. This is a single-row lookup by primary key — the one access pattern
     * documented as safe against that column. Never widen it to a scan, a join, or an {@code IN} list.
     *
     * <p>{@code news_publish = 1} is part of the key predicate, not a filter applied afterwards: a
     * draft must be a miss here, not a photo served for an article whose text is unreachable.
     */
    static final String PHOTO_SQL =
            "SELECT news_photo0 FROM news WHERE news_id = ? AND news_publish = 1 LIMIT 1";

    /**
     * The lead photo's bytes, or {@code null}. Deliberately <em>not</em> cached in the
     * {@link NewsQueryCache} layer: these are megabyte-scale blobs whose caller (the frontend's
     * {@code NewsPhoto.ashx}) already caches them in its own process and hands the browser a
     * seven-day {@code max-age}, so a second copy here would buy a hit rate near zero at a real cost
     * in heap.
     */
    @Override
    @Retry(name = "sqlRetry")
    @CircuitBreaker(name = "sqlBreaker", fallbackMethod = "photoFallback")
    public byte[] newsPhoto(String id) {
        List<byte[]> found = mysqlJdbc.query(PHOTO_SQL, ps -> ps.setString(1, id), (rs, i) -> rs.getBytes(1));
        return found.isEmpty() ? null : found.get(0);
    }

    /**
     * The admin interchange document, mirroring {@code dbo.fn_news_json} field for field --
     * {@code envfish-db/mysql/script02_Proc.sql} documents the port, including the two places MySQL
     * cannot match SQL Server exactly (key order, which nothing reads positionally) and the one it
     * can only match deliberately (base64 line breaks, stripped in the procedure).
     *
     * <p><strong>The BLOB hazard is respected, at triple the usual stake.</strong> This is the only
     * statement in this class that reads {@code news_photo1} and {@code news_photo2} as well as
     * {@code news_photo0}, and the live Winhost host hangs indefinitely on any query touching those
     * columns while materializing more than one row. The procedure is a single-row lookup by primary
     * key with {@code LIMIT 1} -- the one access pattern documented as safe. See {@link #PHOTO_SQL}.
     *
     * <p>Unlike every other read here it does <em>not</em> filter on {@code news_publish}: an admin
     * must be able to export a draft, exactly as {@code fn_news_json} allowed. The endpoint is
     * admin-gated on the portal and day-key gated at the proxy; it is not a public route.
     */
    static final String EXPORT_SQL = "CALL sp_news_doc_export(?)";

    /**
     * One article as the interchange document, or {@code null} when the id is unknown -- which the
     * procedure expresses as an empty result set rather than a NULL scalar, the one shape difference
     * from {@code SELECT dbo.fn_news_json(?)}. Both land on the same 404 at the controller.
     */
    @Override
    @Retry(name = "sqlRetry")
    @CircuitBreaker(name = "sqlBreaker", fallbackMethod = "exportFallback")
    public JsonNode exportNews(String id) {
        List<String> rows = mysqlJdbc.query(EXPORT_SQL, ps -> ps.setString(1, id), (rs, i) -> rs.getString(1));
        String json = rows.isEmpty() ? null : rows.get(0);
        return (json == null || json.isBlank()) ? null : parseItem(json);
    }

    /**
     * Still delegates to the SQL-Server-backed repository -- see the class doc: {@code POST
     * /news/import} has no caller, so there is nothing here to port.
     */
    @Override
    public String importNews(String json) {
        return sqlServerDelegate.importNews(json);
    }

    /**
     * The columns a search result row is built from. Deliberately narrow: the paragraphs are
     * <em>searched</em> (in the WHERE clause) but never <em>selected</em>, so they never enter a sort
     * buffer -- see {@link #SEARCH_FROM_WHERE} for why that distinction is the whole design.
     */
    static final String SEARCH_SELECT =
            "SELECT news_id, news_title AS title, news_source AS source, "
                    + "DATE_FORMAT(news_stamp, '%Y-%m-%d') AS stamp, country, "
                    + "fish1_id, fish2_id, fish3_id ";

    /**
     * The shared {@code FROM}/{@code WHERE} of the two search statements, with {@code {COUNTRY}} and
     * {@code {FISH}} replaced per request. {@code ?} placeholders, in order: the country (when
     * filtering), then the {@code LIKE} pattern once per searchable text column, then every species
     * id once per slot.
     *
     * <p><strong>Why the term is matched column-by-column rather than against one concatenation.</strong>
     * {@code dbo.fn_news_search} concatenates every searchable column and runs a single {@code LIKE}
     * over the result. Here the columns are ORed separately, which short-circuits: a headline hit
     * never reads the three {@code LONGTEXT} paragraphs at all. This is the exact shape of
     * {@code sp_news_list_for_grid} / {@code sp_news_count} (envfish-db/mysql/script02_Proc.sql),
     * which have scanned every published row with paragraph {@code LIKE} filters on this host since
     * 2026-08-31.
     *
     * <p><strong>Why there is no window function here.</strong> {@code sp_news_list_json} computes
     * {@code rn}/{@code total} with {@code ROW_NUMBER() OVER}/{@code COUNT(*) OVER} because it needs a
     * global row number across a padded two-block union. This does not, and the difference matters:
     * a window function forces the plan to materialize rows, and on the live Winhost host an
     * off-page column referenced by a plan that buffers multiple rows hangs indefinitely (confirmed
     * 2026-08-31 for {@code news_photo0} -- see envfish-db/CLAUDE.md "news_photo0/1/2 are dangerous
     * at scale"). A plain filter plus {@code ORDER BY ... LIMIT} only ever buffers the narrow columns
     * of {@link #SEARCH_SELECT}, and the separate {@code COUNT(*)} buffers nothing.
     * <strong>Do not "simplify" these two statements back into one windowed query.</strong>
     *
     * <p>The photo BLOBs are not referenced at all, not even through {@code has_photo0}: a search
     * result row shows no image.
     */
    static final String SEARCH_FROM_WHERE = """
            FROM news
             WHERE news_publish = 1
               {COUNTRY}
               AND (    news_title      LIKE ? ESCAPE '\\\\'
                     OR news_source     LIKE ? ESCAPE '\\\\'
                     OR news_paragraph0 LIKE ? ESCAPE '\\\\'
                     OR news_paragraph1 LIKE ? ESCAPE '\\\\'
                     OR news_paragraph2 LIKE ? ESCAPE '\\\\'
                     OR news_photo_alt0 LIKE ? ESCAPE '\\\\'
                     OR news_photo_alt1 LIKE ? ESCAPE '\\\\'
                     OR news_photo_alt2 LIKE ? ESCAPE '\\\\'
                     {FISH})""";

    /** How many text columns {@link #SEARCH_FROM_WHERE} binds the {@code LIKE} pattern to. */
    private static final int SEARCH_TEXT_COLUMNS = 8;

    /** The three species slots an article can be tagged in. */
    private static final String[] FISH_SLOTS = {"fish1_id", "fish2_id", "fish3_id"};

    /**
     * News search over the MySQL {@code news} table. Replaces the SQL-Server delegation this method
     * used to be: {@code News.aspx}'s search box is news information like any other, so it now reads
     * the same table the rest of that page does, and the frontend needs no SQL Server query of its
     * own to answer it.
     *
     * <p><strong>Species names are matched by id, supplied by the caller.</strong> This database has
     * no {@code fish} table, so {@code fn_news_search}'s "walleye finds an article tagged with
     * walleye even when the headline doesn't say it" behaviour is preserved by having the caller
     * resolve the term to species ids against its own catalogue and pass them in
     * {@link NewsSearchQuery#fishIds()}. Resolving them here would make one news read span both
     * databases, which is exactly what the move to MySQL removed ({@code dbo.fn_news_ref_names_json},
     * docapi 1.8.0-1.8.1, dropped 2026-09-03).
     *
     * <p>{@code fishes} therefore comes back empty and {@code fishIds} carries the article's own tags,
     * for the caller to resolve the same way it already resolves {@code /news/list}'s and
     * {@code GET /news/{id}}'s bare guids.
     */
    @Override
    @Retry(name = "sqlRetry")
    @CircuitBreaker(name = "sqlBreaker", fallbackMethod = "searchFallback")
    public NewsSearchPage search(NewsSearchQuery request) {
        String country = request.country();
        List<String> fishIds = request.fishIds() == null ? List.of() : request.fishIds();

        String where = SEARCH_FROM_WHERE
                .replace("{COUNTRY}", country == null ? "" : "AND country = ?")
                .replace("{FISH}", fishClause(fishIds.size()));

        // The term is escaped for LIKE metacharacters and wrapped in % here, pairing with the
        // ESCAPE '\' in the statement. fn_news_search took the term unwrapped and wrapped it itself;
        // there is no function in the middle any more, so the whole pattern is built here.
        String pattern = "%" + escapeLike(request.query()) + "%";
        PreparedStatementSetter binder = ps -> {
            int i = 1;
            if (country != null) {
                ps.setString(i++, country);
            }
            for (int c = 0; c < SEARCH_TEXT_COLUMNS; c++) {
                ps.setString(i++, pattern);
            }
            // Each slot is compared against every id, so the ids are bound once per slot.
            for (int slot = 0; slot < FISH_SLOTS.length; slot++) {
                for (String fishId : fishIds) {
                    ps.setString(i++, fishId);
                }
            }
        };

        int total = Math.min(countMatches(where, binder), SEARCH_CAP);

        // A window past the cap yields an empty page rather than rows 100+. The cap is what
        // fn_news_search expressed as TOP 100, kept so a caller's pager never offers a page that
        // would come back empty.
        int offset = request.offset();
        int limit = Math.min(request.limit(), Math.max(SEARCH_CAP - offset, 0));

        if (limit < 1) {
            return new NewsSearchPage(List.of(), total, request.query(), offset, request.limit());
        }
        String sql = SEARCH_SELECT + where + " ORDER BY news_stamp DESC, news_id DESC LIMIT ?, ?";
        int tail = bindCount(country, fishIds.size());

        List<NewsSearchItem> items = mysqlJdbc.query(sql, ps -> {
            binder.setValues(ps);
            ps.setInt(tail + 1, offset);
            ps.setInt(tail + 2, limit);
        }, (rs, i) -> new NewsSearchItem(
                rs.getString("news_id"),
                rs.getString("title"),
                rs.getString("source"),
                rs.getString("stamp"),
                rs.getString("country"),
                List.of(),
                distinctIds(rs.getString("fish1_id"), rs.getString("fish2_id"), rs.getString("fish3_id"))));

        return new NewsSearchPage(items, total, request.query(), offset, request.limit());
    }

    /** The full match count for one search, before {@link #SEARCH_CAP} is applied. */
    private int countMatches(String where, PreparedStatementSetter binder) {
        Integer total = mysqlJdbc.query("SELECT COUNT(*) " + where, binder,
                (ResultSetExtractor<Integer>) rs -> rs.next() ? rs.getInt(1) : 0);
        return total == null ? 0 : total;
    }

    /**
     * The {@code OR fishN_id IN (...)} tail of the search predicate, or an empty string when the
     * caller passed no species ids -- in which case the tail must vanish entirely rather than become
     * an {@code IN ()}, which is a MySQL syntax error rather than an always-false predicate.
     */
    private static String fishClause(int idCount) {
        if (idCount < 1) {
            return "";
        }
        String placeholders = String.join(", ", Collections.nCopies(idCount, "?"));
        StringBuilder sb = new StringBuilder();
        for (String slot : FISH_SLOTS) {
            sb.append("OR ").append(slot).append(" IN (").append(placeholders).append(") ");
        }
        return sb.toString().trim();
    }

    /** How many placeholders {@link #SEARCH_FROM_WHERE} consumed, so the LIMIT pair binds after them. */
    private static int bindCount(String country, int idCount) {
        return (country == null ? 0 : 1) + SEARCH_TEXT_COLUMNS + (idCount * FISH_SLOTS.length);
    }

    /**
     * Escapes MySQL {@code LIKE} wildcards so a term matches literally. {@code [} is deliberately NOT
     * escaped, unlike {@code JdbcNewsQueryRepository.escapeLike}: MySQL's {@code LIKE} has no
     * character-class metacharacter, so a backslash before {@code [} would turn the pattern into
     * "backslash then bracket" and a term containing a bracket would stop matching.
     */
    private static String escapeLike(String s) {
        return s.replace("\\", "\\\\").replace("%", "\\%").replace("_", "\\_");
    }

    /** Distinct, non-blank ids in slot order (0-3). */
    private static List<String> distinctIds(String... ids) {
        List<String> out = new ArrayList<>();
        for (String id : ids) {
            if (id != null && !id.isBlank() && !out.contains(id)) {
                out.add(id);
            }
        }
        return List.copyOf(out);
    }

    /**
     * One water body's latest published articles. The MySQL {@code news} table carries the water body
     * as {@code lake_id CHAR(36)}, so this is a plain equality filter and needs no join -- and, as
     * everywhere else on this backing, no {@code fish} or {@code lake} table is consulted to turn an
     * id into a name.
     *
     * <p><strong>Narrow columns and a bare {@code ORDER BY ... LIMIT}, on purpose.</strong> Same rule
     * as {@link #SEARCH_FROM_WHERE}: no photo column is referenced, not even {@code has_photo0}, and
     * there is no window function, so the plan only ever buffers the five short columns selected here.
     * On the live Winhost host a plan that materializes multiple rows while referencing an off-page
     * column hangs indefinitely (confirmed 2026-08-31 for {@code news_photo0}). This runs on a public
     * page view, which is the last place to risk that.
     *
     * <p>{@code news_publish = 1} is part of the predicate rather than a filter applied afterwards, so
     * a draft is never counted toward the limit and then dropped. Note this is <em>stricter</em> than
     * the {@code dbo.fn_river_view_news} it replaces, which never checked the flag at all and could
     * therefore show an unpublished article's headline linking to an article the reader cannot open;
     * its sibling {@code dbo.fn_fish_view_news} did check it.
     *
     * <p>{@code news_id} is the tiebreaker after the timestamp so the order is total: these rows are
     * dealt alternately into two columns by the caller, and two articles sharing a timestamp swapping
     * places between requests would move a headline from one column to the other on a refresh.
     */
    static final String LAKE_SQL = """
            SELECT news_id, news_title AS title, news_source AS source,
                   DATE_FORMAT(news_stamp, '%Y-%m-%d') AS stamp, country
              FROM news
             WHERE news_publish = 1
               AND lake_id = ?
             ORDER BY news_stamp DESC, news_id DESC
             LIMIT ?""";

    /** The row shape {@link #LAKE_SQL} and {@link #FISH_SQL} share, so their columns cannot drift. */
    private static final RowMapper<NewsRefItem> REF_ROW_MAPPER = (rs, i) -> new NewsRefItem(
            rs.getString("news_id"),
            rs.getString("title"),
            rs.getString("source"),
            rs.getString("stamp"),
            rs.getString("country"));

    @Override
    @Retry(name = "sqlRetry")
    @CircuitBreaker(name = "sqlBreaker", fallbackMethod = "lakeNewsFallback")
    public NewsLakePage lakeNews(String lakeId, int limit) {
        List<NewsRefItem> items = mysqlJdbc.query(LAKE_SQL, ps -> {
            ps.setString(1, lakeId);
            ps.setInt(2, limit);
        }, REF_ROW_MAPPER);

        return new NewsLakePage(lakeId, limit, List.copyOf(items));
    }

    /** Circuit-breaker fallback for {@link #lakeNews}. */
    @SuppressWarnings("unused")
    public NewsLakePage lakeNewsFallback(String lakeId, int limit, Throwable ex) {
        throw new RuntimeException("MySQL lake-news query failed", ex);
    }

    /**
     * One species' latest published articles. Same statement as {@link #LAKE_SQL} but keyed on the
     * three species slots an article can be tagged in — {@code fn_fish_view_news}'s own
     * {@code fish1_id OR fish2_id OR fish3_id}, and the same three slots {@link #FISH_SLOTS} drives
     * for search.
     *
     * <p>Every constraint {@link #LAKE_SQL} documents applies here unchanged: narrow columns, no
     * photo column, no window function, {@code news_publish = 1} in the predicate, and
     * {@code news_id} as the tiebreaker so a two-column caller sees a stable order. This one runs on
     * a public page view too.
     */
    static final String FISH_SQL = """
            SELECT news_id, news_title AS title, news_source AS source,
                   DATE_FORMAT(news_stamp, '%Y-%m-%d') AS stamp, country
              FROM news
             WHERE news_publish = 1
               AND (fish1_id = ? OR fish2_id = ? OR fish3_id = ?)
             ORDER BY news_stamp DESC, news_id DESC
             LIMIT ?""";

    @Override
    @Retry(name = "sqlRetry")
    @CircuitBreaker(name = "sqlBreaker", fallbackMethod = "fishNewsFallback")
    public NewsFishPage fishNews(String fishId, int limit) {
        List<NewsRefItem> items = mysqlJdbc.query(FISH_SQL, ps -> {
            for (int slot = 1; slot <= FISH_SLOTS.length; slot++) {
                ps.setString(slot, fishId);
            }
            ps.setInt(FISH_SLOTS.length + 1, limit);
        }, REF_ROW_MAPPER);

        return new NewsFishPage(fishId, limit, List.copyOf(items));
    }

    /** Circuit-breaker fallback for {@link #fishNews}. */
    @SuppressWarnings("unused")
    public NewsFishPage fishNewsFallback(String fishId, int limit, Throwable ex) {
        throw new RuntimeException("MySQL fish-news query failed", ex);
    }

    /** Circuit-breaker fallback for {@link #search}. */
    @SuppressWarnings("unused")
    public NewsSearchPage searchFallback(NewsSearchQuery request, Throwable ex) {
        throw new RuntimeException("MySQL news-search query failed", ex);
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

    /**
     * Circuit-breaker fallback for {@link #newsPhoto}.
     */
    @SuppressWarnings("unused")
    public byte[] photoFallback(String id, Throwable ex) {
        throw new RuntimeException("MySQL news-photo query failed", ex);
    }

    /**
     * Circuit-breaker fallback for {@link #exportNews}.
     */
    @SuppressWarnings("unused")
    public JsonNode exportFallback(String id, Throwable ex) {
        throw new RuntimeException("MySQL news-export query failed for id " + id, ex);
    }

    private JsonNode parseItem(String json) {
        try {
            return objectMapper.readTree(json);
        } catch (JsonProcessingException ex) {
            throw new IllegalStateException("MySQL news JSON returned by the database is not valid JSON", ex);
        }
    }
}
