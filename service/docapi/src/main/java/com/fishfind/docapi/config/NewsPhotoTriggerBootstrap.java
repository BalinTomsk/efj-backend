package com.fishfind.docapi.config;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.boot.ApplicationArguments;
import org.springframework.boot.ApplicationRunner;
import org.springframework.jdbc.core.JdbcTemplate;

/**
 * One-time (idempotent, safe to run every startup) creation of the two {@code news.has_photo0}
 * maintenance triggers on the live MySQL database, for the same reason {@link NewsIndexBootstrap}
 * exists: {@code portos} holds {@code TRIGGER} (confirmed in the same grant list that documents
 * {@code ALTER}/{@code INDEX} -- see that class's javadoc) even though it holds no
 * {@code CREATE ROUTINE}, so this is something the app can fix itself without the Winhost control
 * panel.
 *
 * <p>Confirmed live 2026-09-15: an article published through {@code sp_news_admin_publish} (and,
 * separately, re-confirmed by directly re-applying its photo through {@code
 * sp_news_admin_photo_update} alone) came out of both paths with {@code has_photo0 = 0} despite a
 * real, substantial photo in {@code news_photo0} -- which hid it from {@code News.aspx}'s "first
 * article with a photo" default-lead pick. A first theory blamed {@code sp_news_admin_publish}'s
 * old {@code INSERT ... ON DUPLICATE KEY UPDATE} shape (see its CHANGELOG/script entry) and was
 * disproven by this same symptom surviving a repair through the always-plain-{@code UPDATE}
 * {@code sp_news_admin_photo_update} too. The remaining explanation: {@code
 * envfish-db/mysql/script01_createTable.sql}'s {@code TR_news_has_photo0_ins}/{@code _upd} triggers
 * were never actually applied to the live Winhost database in the first place -- the news-admin
 * write path is the first thing that has ever run an {@code INSERT}/{@code UPDATE} against this
 * table from application code (every write before 2026-09-14 came from a separate, out-of-band
 * migration process, per {@code envfish-db/CLAUDE.md}'s own account of the original 2026-08-31
 * backfill), so a missing trigger would have been invisible until now.
 *
 * <p>The source of truth for both triggers is {@code script01_createTable.sql}; this bootstrap gets
 * them onto the live database the same way {@link NewsIndexBootstrap} gets the index there. Both
 * are re-created (DROP + CREATE) on every startup rather than existence-checked first -- cheap for
 * two trigger definitions, and it means a future edit to either trigger's body here is guaranteed to
 * actually reach the live database, unlike the index (whose CREATE has no equivalent "replace"
 * form). Never load-bearing: any failure here is logged and swallowed.
 */
public class NewsPhotoTriggerBootstrap implements ApplicationRunner {

    private static final Logger log = LoggerFactory.getLogger(NewsPhotoTriggerBootstrap.class);

    private static final String DROP_INS = "DROP TRIGGER IF EXISTS TR_news_has_photo0_ins";
    private static final String CREATE_INS =
            "CREATE TRIGGER TR_news_has_photo0_ins BEFORE INSERT ON news "
                    + "FOR EACH ROW SET NEW.has_photo0 = (NEW.news_photo0 IS NOT NULL)";
    private static final String DROP_UPD = "DROP TRIGGER IF EXISTS TR_news_has_photo0_upd";
    private static final String CREATE_UPD =
            "CREATE TRIGGER TR_news_has_photo0_upd BEFORE UPDATE ON news "
                    + "FOR EACH ROW SET NEW.has_photo0 = (NEW.news_photo0 IS NOT NULL)";

    private final JdbcTemplate mysqlJdbc;

    public NewsPhotoTriggerBootstrap(JdbcTemplate mysqlJdbc) {
        this.mysqlJdbc = mysqlJdbc;
    }

    @Override
    public void run(ApplicationArguments args) {
        try {
            mysqlJdbc.execute(DROP_INS);
            mysqlJdbc.execute(CREATE_INS);
            mysqlJdbc.execute(DROP_UPD);
            mysqlJdbc.execute(CREATE_UPD);
            log.info("news.has_photo0 maintenance triggers (re)created");
        } catch (Exception ex) {
            log.warn("Could not (re)create the news.has_photo0 maintenance triggers -- has_photo0 "
                    + "will keep drifting from news_photo0 on writes until this is resolved", ex);
        }
    }
}
