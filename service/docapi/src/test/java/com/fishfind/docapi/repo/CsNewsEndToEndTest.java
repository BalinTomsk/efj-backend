package com.fishfind.docapi.repo;

import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.fishfind.docapi.web.NewsController.NewsListPage;
import com.fishfind.docapi.web.NewsController.NewsSearchPage;
import com.fishfind.docapi.web.NewsController.NewsSearchQuery;
import io.github.resilience4j.circuitbreaker.CircuitBreaker;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.condition.EnabledIfEnvironmentVariable;

import java.sql.Timestamp;
import java.time.Duration;
import java.time.LocalDateTime;
import java.util.List;
import java.util.UUID;

import static org.assertj.core.api.Assertions.assertThat;

/**
 * docapi's HTTP news repositories against a LIVE csnews-env backed by a THROWAWAY MySQL (it writes rows): the
 * real Java ↔ C# JSON contract, end to end. Opt-in: set {@code CSNEWS_E2E_URL} (e.g. {@code http://127.0.0.1:8080})
 * to a csnews-env whose {@code MYSQL_NEWS_URL} points at a mysql:8.0 container loaded from
 * {@code envfish-db/mysql/script01_createTable.sql}, {@code script01_createView.sql}, {@code script02_Proc.sql}.
 */
@EnabledIfEnvironmentVariable(named = "CSNEWS_E2E_URL", matches = "http.+")
class CsNewsEndToEndTest {

    private final ObjectMapper om = new ObjectMapper().findAndRegisterModules();
    private final CsNewsClient client = new CsNewsClient(System.getenv("CSNEWS_E2E_URL"), Duration.ofSeconds(2),
            Duration.ofSeconds(8), om, CircuitBreaker.ofDefaults("e2e"));

    @Test
    void writeThenReadEverythingThroughCsNews() {
        String lake = UUID.randomUUID().toString();
        String fish = UUID.randomUUID().toString();
        byte[] photo = new byte[256];
        for (int i = 0; i < photo.length; i++) {
            photo[i] = (byte) i;
        }
        NewsWrite write = new NewsWrite("E2E walleye " + lake.substring(0, 8), "Ann", null, "Bugle", null, null,
                "Opening day: 100% of anglers_limit reached.", "p1", null, "CA",
                Timestamp.valueOf(LocalDateTime.of(2026, 11, 22, 7, 15, 30)), lake, fish, null, null,
                new NewsWrite.Photo(photo, "credit", "alt"), null, null);

        HttpNewsWriteRepository writes = new HttpNewsWriteRepository(client);
        HttpNewsQueryRepository reads = new HttpNewsQueryRepository(client);
        String id = writes.insert(write);

        String doc = new HttpNewsDocumentRepository(client).getDocument(id);
        assertThat(doc).contains(id);
        assertThat(reads.exportNews(id)).isNotNull();
        assertThat(reads.newsPhoto(id)).containsExactly(photo);

        NewsListPage list = reads.list(null, 0, 20, NewsListOrder.DATE);
        assertThat(list.items()).anyMatch(i -> i.newsId().equals(id) && i.hasPhoto());
        assertThat(reads.list("CA", 0, 20, NewsListOrder.EDITED).total()).isPositive();

        NewsSearchPage hit = reads.search(new NewsSearchQuery("100% of anglers_", List.of(), "CA", 0, 10));
        assertThat(hit.items()).anyMatch(i -> i.newsId().equals(id));
        NewsSearchPage byFish = reads.search(new NewsSearchQuery("no-such-text", List.of(fish), null, 0, 10));
        assertThat(byFish.items()).anyMatch(i -> i.newsId().equals(id) && i.fishIds().equals(List.of(fish)));

        assertThat(reads.lakeNews(lake, 10).items()).anyMatch(i -> i.newsId().equals(id));
        assertThat(reads.fishNews(fish, 10).items()).anyMatch(i -> i.newsId().equals(id));
        JsonNode home = reads.defaultNews();
        assertThat(home.get("items").isArray()).isTrue();

        List<NewsNearRepository.TaggedNews> tagged =
                new JdbcNewsNearRepository(null, client, om).taggedNews(2000);
        assertThat(tagged).anyMatch(t -> t.newsId().equals(id) && t.lakeId().equals(lake));

        assertThat(writes.update(id, write)).isTrue();
        assertThat(writes.update(UUID.randomUUID().toString(), write)).isFalse();

        HttpNewsAdminCommandRepository admin = new HttpNewsAdminCommandRepository(client);
        String draft = admin.createDraft();
        assertThat(admin.publish(new NewsAdminCommandRepository.NewsAdminPublishRequest(draft, "E2E draft", null,
                null, null, null, Timestamp.valueOf(LocalDateTime.of(2026, 11, 22, 9, 0)), null, "p0", null, null,
                "US", null, null, null, null)).action()).isEqualTo("updated");
        assertThat(admin.updatePhoto(draft, 1, new byte[]{1, 2}, null, "a"))
                .isEqualTo(new NewsAdminCommandRepository.PhotoUpdateResult(true, true));

        assertThat(client.reachable()).isTrue();
    }
}
