package com.fishfind.docapi.config;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.boot.ApplicationArguments;
import org.springframework.boot.ApplicationRunner;
import org.springframework.jdbc.core.JdbcTemplate;

/**
 * One-time (idempotent, safe to run every startup) creation of {@code news.idx_news_publish} on
 * the live MySQL database, since the application's own MySQL credential ({@code portos}) holds
 * {@code ALTER}/{@code INDEX} -- unlike {@code CREATE ROUTINE}, which is why the three
 * {@code sp_news_admin_*} procedures needed the Winhost control panel instead.
 *
 * <p>Exists because {@code sp_news_admin_draft_create}'s {@code DELETE FROM news WHERE
 * news_publish <> 1} was a full table scan with no index to use -- confirmed live 2026-09-15: on
 * this host, a scan touching the {@code news} table (~4,800 rows, several {@code LONGBLOB}/
 * {@code LONGTEXT} columns) hangs well past any reasonable timeout, the same class of hazard
 * {@code envfish-db/CLAUDE.md} already documents for {@code news_photo0}/{@code 1}/{@code 2} at
 * scale. {@code news_publish} is heavily skewed (the vast majority of rows are published), so an
 * index on it lets that DELETE seek straight to the rare unpublished rows instead.
 *
 * <p>The source of truth for this index is {@code envfish-db/mysql/script01_createTable.sql}
 * (inline on a fresh build, plus the same idempotent guarded block for an existing database) --
 * this bootstrap is what actually gets it onto the live Winhost database, since that repo's own
 * schema-apply workflow needs the control panel for anything {@code portos} cannot do itself, and
 * this genuinely is something it can. Checks {@code information_schema.statistics} first and
 * issues the {@code CREATE INDEX} only if missing, so re-running it (every deploy) after the first
 * success is a single cheap read and nothing else. Never load-bearing: any failure here (network,
 * a future privilege change, …) is logged and swallowed -- the write endpoints just keep failing
 * exactly as they already were, not a new outage.
 */
public class NewsIndexBootstrap implements ApplicationRunner {

    private static final Logger log = LoggerFactory.getLogger(NewsIndexBootstrap.class);

    private static final String CHECK_SQL =
            "SELECT COUNT(*) FROM information_schema.statistics "
                    + "WHERE table_schema = DATABASE() AND table_name = 'news' AND index_name = 'idx_news_publish'";
    private static final String CREATE_SQL = "CREATE INDEX idx_news_publish ON news (news_publish)";

    private final JdbcTemplate mysqlJdbc;

    public NewsIndexBootstrap(JdbcTemplate mysqlJdbc) {
        this.mysqlJdbc = mysqlJdbc;
    }

    @Override
    public void run(ApplicationArguments args) {
        try {
            Integer count = mysqlJdbc.queryForObject(CHECK_SQL, Integer.class);
            if (count != null && count > 0) {
                log.info("news.idx_news_publish already exists, nothing to do");
                return;
            }
            mysqlJdbc.execute(CREATE_SQL);
            log.info("Created news.idx_news_publish (was missing)");
        } catch (Exception ex) {
            log.warn("Could not ensure news.idx_news_publish exists -- sp_news_admin_draft_create's "
                    + "DELETE will keep hitting the unindexed full-table-scan hazard until this is "
                    + "resolved", ex);
        }
    }
}
