package com.fishfind.docapi.repo;

import com.fishfind.docapi.web.FishController.FishSearchItem;
import com.fishfind.docapi.web.FishController.FishSearchPage;
import io.github.resilience4j.circuitbreaker.annotation.CircuitBreaker;
import io.github.resilience4j.retry.annotation.Retry;
import org.springframework.jdbc.core.JdbcTemplate;

import java.util.List;

/**
 * JDBC fish query repository backed by the SQL Server function {@code dbo.SearchFishList}.
 * All DB access for fish-catalogue search goes through here.
 * Guarded by Resilience4j retry + circuit breaker, matching {@link JdbcNewsQueryRepository}.
 */
public class JdbcFishQueryRepository implements FishQueryRepository {

    /**
     * Relevance-ranked species search. {@code dbo.SearchFishList} is a table-valued function that
     * normalizes the term itself and matches it against {@code fish_name}, {@code fish_latin} and the
     * {@code alt_name} synonyms, returning a lower {@code irank} for better matches — so ordering by
     * {@code irank} gives best-match-first, exactly like the Editor {@code FishList.aspx} search box.
     */
    static final String SEARCH_SQL =
            "SELECT fish_name, fish_latin, fish_id, irank FROM dbo.SearchFishList(?) ORDER BY irank ASC";

    private final JdbcTemplate jdbc;

    public JdbcFishQueryRepository(JdbcTemplate jdbc) {
        this.jdbc = jdbc;
    }

    @Override
    @Retry(name = "sqlRetry")
    @CircuitBreaker(name = "sqlBreaker", fallbackMethod = "searchFallback")
    public FishSearchPage search(String query) {
        // SearchFishList takes the raw term (varchar(64)) and normalizes it internally, so the term is
        // bound as a plain parameter with no LIKE-escaping — the function builds its own match variants.
        List<FishSearchItem> items = jdbc.query(
                SEARCH_SQL,
                ps -> ps.setString(1, query),
                (rs, i) -> new FishSearchItem(
                        rs.getString("fish_id"),
                        rs.getString("fish_name"),
                        rs.getString("fish_latin"),
                        rs.getInt("irank")));
        return new FishSearchPage(items, items.size(), query);
    }

    /**
     * Circuit-breaker fallback for {@link #search}.
     */
    @SuppressWarnings("unused")
    public FishSearchPage searchFallback(String query, Throwable ex) {
        throw new RuntimeException("SQL fish-search query failed", ex);
    }
}
