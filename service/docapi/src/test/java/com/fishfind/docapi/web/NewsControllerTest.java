package com.fishfind.docapi.web;

import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.fasterxml.jackson.databind.node.ObjectNode;
import com.fishfind.docapi.domain.DocumentType;
import com.fishfind.docapi.repo.NewsListOrder;
import com.fishfind.docapi.repo.NewsQueryRepository;
import com.fishfind.docapi.service.DocumentNotFoundException;
import com.fishfind.docapi.service.InvalidDocumentException;
import com.fishfind.docapi.service.NewsDocumentService;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.autoconfigure.web.servlet.WebMvcTest;
import org.springframework.boot.test.mock.mockito.MockBean;
import org.springframework.http.MediaType;
import org.springframework.test.web.servlet.MockMvc;

import java.util.List;

import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.anyInt;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.when;
import static org.mockito.Mockito.verifyNoInteractions;
import static org.mockito.Mockito.verify;
import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.put;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.content;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.header;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

@WebMvcTest(NewsController.class)
class NewsControllerTest {

    @Autowired
    private MockMvc mockMvc;

    @Autowired
    private ObjectMapper objectMapper;

    @MockBean
    private NewsDocumentService service;

    @MockBean
    private NewsQueryRepository queryRepository;

    // ---- generic JSON-document CRUD (inherited from AbstractDocumentController) ----

    @Test
    void getReturnsTheDocumentNestedInTheEnvelope() throws Exception {
        when(service.get("7")).thenReturn(objectMapper.readTree("{\"title\":\"Opener\"}"));

        mockMvc.perform(get("/api/v1/news/7"))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.data.title").value("Opener"))
                .andExpect(jsonPath("$.error").doesNotExist())
                .andExpect(jsonPath("$.meta.timestamp").exists());
    }

    @Test
    void getUnknownIdReturns404WithErrorEnvelope() throws Exception {
        when(service.get("nope")).thenThrow(new DocumentNotFoundException(DocumentType.NEWS, "nope"));

        mockMvc.perform(get("/api/v1/news/nope"))
                .andExpect(status().isNotFound())
                .andExpect(jsonPath("$.error.code").value("not_found"))
                .andExpect(jsonPath("$.data").doesNotExist());
    }

    @Test
    void postReturns201WithNewId() throws Exception {
        when(service.add(any())).thenReturn("100");

        mockMvc.perform(post("/api/v1/news")
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("{\"title\":\"New\"}"))
                .andExpect(status().isCreated())
                .andExpect(jsonPath("$.data.id").value("100"));
    }

    @Test
    void postInvalidJsonReturns400() throws Exception {
        when(service.add(any())).thenThrow(new InvalidDocumentException("Request body is not well-formed JSON"));

        mockMvc.perform(post("/api/v1/news")
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("{not json"))
                .andExpect(status().isBadRequest())
                .andExpect(jsonPath("$.error.code").value("invalid_document"));
    }

    @Test
    void putReturnsTheUpdatedId() throws Exception {
        when(service.update(eq("7"), any())).thenReturn("7");

        mockMvc.perform(put("/api/v1/news/7")
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("{\"title\":\"Edit\"}"))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.data.id").value("7"));
    }

    // ---- News-page read queries (delegated to NewsQueryRepository) ----

    @Test
    void listWithEmptyRepositoryReturnsEmptyPageEchoingPaging() throws Exception {
        when(queryRepository.list(null, 5, 10, NewsListOrder.DATE))
                .thenReturn(new NewsController.NewsListPage(List.of(), 0L, 5, 10));

        mockMvc.perform(get("/api/v1/news/list").param("offset", "5").param("limit", "10"))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.data.items").isArray())
                .andExpect(jsonPath("$.data.items").isEmpty())
                .andExpect(jsonPath("$.data.total").value(0))
                .andExpect(jsonPath("$.data.offset").value(5))
                .andExpect(jsonPath("$.data.limit").value(10));
    }

    @Test
    void listRejectsANonTwoLetterCountryWith400() throws Exception {
        mockMvc.perform(get("/api/v1/news/list").param("country", "USA"))
                .andExpect(status().isBadRequest())
                .andExpect(jsonPath("$.error.code").value("invalid_document"));
    }

    @Test
    void defaultWithEmptyRepositoryReturnsEmptyItems() throws Exception {
        when(queryRepository.defaultNews())
                .thenReturn(objectMapper.createObjectNode().set("items", objectMapper.createArrayNode()));

        mockMvc.perform(get("/api/v1/news/default"))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.data.items").isArray())
                .andExpect(jsonPath("$.data.items").isEmpty());
    }

    @Test
    void listMapsRepositoryResultsIntoTheEnvelope() throws Exception {
        NewsController.NewsListItem item = new NewsController.NewsListItem(1L, "n-id", "Title", "Source", "2026-07-27", "CA", true, 0);
        NewsController.NewsListPage page = new NewsController.NewsListPage(List.of(item), 8L, 0, 25);
        when(queryRepository.list(null, 0, 25, NewsListOrder.DATE)).thenReturn(page);

        mockMvc.perform(get("/api/v1/news/list"))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.data.items").isArray())
                .andExpect(jsonPath("$.data.items.length()").value(1))
                .andExpect(jsonPath("$.data.items[0].title").value("Title"))
                .andExpect(jsonPath("$.data.total").value(8));
    }

    // ---- /news/list by role: order, and the guest window --------------------------------------------

    private static NewsController.NewsListPage pageOf(long total, int offset, int limit) {
        return new NewsController.NewsListPage(List.of(), total, offset, limit);
    }

    @Test
    void anAdminGetsTheEditedOrderAndTheWholeListPaged() throws Exception {
        when(queryRepository.list(null, 150, 50, NewsListOrder.EDITED)).thenReturn(pageOf(4824, 150, 50));

        mockMvc.perform(get("/api/v1/news/list").param("offset", "150").param("limit", "50")
                        .header("X-Fish-Role", "admin"))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.data.total").value(4824))
                .andExpect(jsonPath("$.data.offset").value(150));

        verify(queryRepository).list(null, 150, 50, NewsListOrder.EDITED);
    }

    @Test
    void aRegisteredUserGetsTheDateOrderAndTheWholeListPaged() throws Exception {
        when(queryRepository.list("CA", 150, 50, NewsListOrder.DATE)).thenReturn(pageOf(4824, 150, 50));

        mockMvc.perform(get("/api/v1/news/list").param("country", "CA").param("offset", "150").param("limit", "50")
                        .header("X-Fish-Role", "user"))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.data.total").value(4824));

        verify(queryRepository).list("CA", 150, 50, NewsListOrder.DATE);
    }

    @Test
    void aGuestIsCappedToTheFirstHundredRowsAndTheTotalIsCappedWithIt() throws Exception {
        when(queryRepository.list("CA", 0, 100, NewsListOrder.DATE)).thenReturn(pageOf(4824, 0, 100));

        mockMvc.perform(get("/api/v1/news/list").param("country", "CA").param("limit", "200")
                        .header("X-Fish-Role", "guest"))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.data.total").value(100))
                .andExpect(jsonPath("$.data.limit").value(200));

        // 200 rows were asked for; only the first 100 were ever requested from the repository.
        verify(queryRepository).list("CA", 0, 100, NewsListOrder.DATE);
    }

    @Test
    void aGuestWindowThatStraddlesTheCapIsClippedToIt() throws Exception {
        when(queryRepository.list(null, 90, 10, NewsListOrder.DATE)).thenReturn(pageOf(4824, 90, 10));

        mockMvc.perform(get("/api/v1/news/list").param("offset", "90").param("limit", "50")
                        .header("X-Fish-Role", "guest"))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.data.offset").value(90))
                .andExpect(jsonPath("$.data.limit").value(50));

        verify(queryRepository).list(null, 90, 10, NewsListOrder.DATE);
    }

    @Test
    void aGuestWindowStartingAtOrPastTheCapIsEmptyAndNeverLeavesTheFirstHundred() throws Exception {
        when(queryRepository.list(null, 0, 1, NewsListOrder.DATE)).thenReturn(pageOf(4824, 0, 1));

        mockMvc.perform(get("/api/v1/news/list").param("offset", "100").param("limit", "25")
                        .header("X-Fish-Role", "guest"))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.data.items").isEmpty())
                .andExpect(jsonPath("$.data.total").value(100))
                .andExpect(jsonPath("$.data.offset").value(100));

        verify(queryRepository).list(null, 0, 1, NewsListOrder.DATE);
        verify(queryRepository, never()).list(any(), eq(100), anyInt(), any());
    }

    @Test
    void aGuestWithFewerThanAHundredRowsKeepsTheRealTotal() throws Exception {
        when(queryRepository.list("GB", 0, 25, NewsListOrder.DATE)).thenReturn(pageOf(37, 0, 25));

        mockMvc.perform(get("/api/v1/news/list").param("country", "GB").header("X-Fish-Role", "guest"))
                .andExpect(jsonPath("$.data.total").value(37));
    }

    @Test
    void aMissingOrUnknownRoleFailsClosedToGuest() throws Exception {
        when(queryRepository.list(null, 0, 100, NewsListOrder.DATE)).thenReturn(pageOf(4824, 0, 100));

        // no header at all: a request that did not come through cproxy
        mockMvc.perform(get("/api/v1/news/list").param("limit", "200"))
                .andExpect(jsonPath("$.data.total").value(100));
        // a value cproxy never sends
        mockMvc.perform(get("/api/v1/news/list").param("limit", "200").header("X-Fish-Role", "superuser"))
                .andExpect(jsonPath("$.data.total").value(100));

        verify(queryRepository, never()).list(any(), anyInt(), anyInt(), eq(NewsListOrder.EDITED));
    }

    @Test
    void theRoleHeaderIsMatchedCaseInsensitively() throws Exception {
        when(queryRepository.list(null, 0, 25, NewsListOrder.EDITED)).thenReturn(pageOf(10, 0, 25));

        mockMvc.perform(get("/api/v1/news/list").header("X-Fish-Role", " ADMIN "))
                .andExpect(status().isOk());

        verify(queryRepository).list(null, 0, 25, NewsListOrder.EDITED);
    }

    @Test
    void defaultAssemblesRepositoryItemsIntoTheEnvelope() throws Exception {
        JsonNode items = objectMapper.createArrayNode()
                .add(objectMapper.readTree("{\"title\":\"Lead\",\"with_photo\":true}"))
                .add(objectMapper.readTree("{\"title\":\"Small\",\"with_photo\":false}"));
        JsonNode root = objectMapper.createObjectNode().set("items", items);
        when(queryRepository.defaultNews()).thenReturn(root);

        mockMvc.perform(get("/api/v1/news/default"))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.data.items.length()").value(2))
                .andExpect(jsonPath("$.data.items[0].title").value("Lead"));
    }

    // ---- /news/featured and /news/more : the two halves of the home page ----------------------

    /** A realistic home page: 2 leads with photos, 3 compact right-column items. */
    private JsonNode homePage() throws Exception {
        return objectMapper.createObjectNode().set("items", objectMapper.createArrayNode()
                .add(objectMapper.readTree("""
                        {"news_id":"n1","title":"Muskie","with_photo":true,"photo":"AAAA",
                         "author":"Bob","source":"wired2fish","source_link":"http://w/1","date":"2026-08-18",
                         "paragraph0":"Lead body.","lake_name":"Lake Manitou",
                         "fishes":[{"id":"f1","name":"Muskellunge","latin":"Esox masquinongy"}]}"""))
                .add(objectMapper.readTree("""
                        {"news_id":"n2","title":"Nipissing","with_photo":true,"photo":"BBBB",
                         "author":"Jennifer","source":"nugget","source_link":"http://n/2","date":"2026-08-10",
                         "paragraph0":"Second lead.","lake_name":"Lake Nipissing","fishes":[]}"""))
                // paragraph0 is attached after parsing (see below): a Java text block turns \r into a
                // real carriage return, which is an illegal raw control character inside a JSON string.
                .add(((ObjectNode) objectMapper.readTree("""
                        {"news_id":"n3","title":"Striped Bass","with_photo":false,"photo":null,
                         "author":"Ann","source":"wired2fish","source_link":"http://w/3","date":"2026-08-27",
                         "paragraph1":"P1"}"""))
                        .put("paragraph0", "When Micah tied on a jig.\r\nSecond line hidden."))
                .add(objectMapper.readTree("""
                        {"news_id":"n4","title":"Rivers","with_photo":false,"photo":null,
                         "author":"Fallback Author","source":"","source_link":"http://q/4","date":"2026-08-10",
                         "paragraph0":"","paragraph1":"Body came from paragraph one."}"""))
                .add(objectMapper.readTree("""
                        {"news_id":"n5","title":"Fly fishing","with_photo":false,"photo":null,
                         "author":"Ed","source":"einnews","source_link":"http://e/5","date":"2026-08-11",
                         "snippet":"Teaser straight from the database.","paragraph0":"ignored"}""")));
    }

    @Test
    void featuredReturnsOnlyTheTwoLeadArticlesWithTheirFullDocument() throws Exception {
        when(queryRepository.defaultNews()).thenReturn(homePage());

        mockMvc.perform(get("/api/v1/news/featured"))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.data.items.length()").value(2))
                .andExpect(jsonPath("$.data.items[0].title").value("Muskie"))
                .andExpect(jsonPath("$.data.items[0].photo").value("AAAA"))
                .andExpect(jsonPath("$.data.items[0].lake_name").value("Lake Manitou"))
                .andExpect(jsonPath("$.data.items[0].fishes[0].name").value("Muskellunge"))
                .andExpect(jsonPath("$.data.items[1].title").value("Nipissing"));
    }

    /** The sidebar must not drag the ~1 MB of base64 lead photos along with it. */
    @Test
    void moreReturnsTheCompactRightColumnWithoutPhotosOrParagraphs() throws Exception {
        when(queryRepository.defaultNews()).thenReturn(homePage());

        mockMvc.perform(get("/api/v1/news/more"))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.data.items.length()").value(3))
                .andExpect(jsonPath("$.data.items[0].title").value("Striped Bass"))
                .andExpect(jsonPath("$.data.items[0].link").value("http://w/3"))
                .andExpect(jsonPath("$.data.items[0].photo").doesNotExist())
                .andExpect(jsonPath("$.data.items[0].paragraph0").doesNotExist())
                .andExpect(jsonPath("$.data.items[0].paragraph1").doesNotExist());
    }

    /**
     * The snippet is derived from the body when the database does not supply one — which is what lets
     * /more work against a database without the snippet-producing view. CRLF must not leak through.
     */
    @Test
    void moreDerivesTheSnippetFromTheBodyAndPrefersTheDatabaseWhenItSuppliesOne() throws Exception {
        when(queryRepository.defaultNews()).thenReturn(homePage());

        mockMvc.perform(get("/api/v1/news/more"))
                .andExpect(status().isOk())
                // derived: first line of paragraph0, CR stripped, second line dropped
                .andExpect(jsonPath("$.data.items[0].snippet").value("When Micah tied on a jig."))
                // derived: paragraph0 blank, so it falls back to paragraph1
                .andExpect(jsonPath("$.data.items[1].snippet").value("Body came from paragraph one."))
                // supplied by the database: used as-is, body ignored
                .andExpect(jsonPath("$.data.items[2].snippet").value("Teaser straight from the database."));
    }

    /** The page shows the author when an article carries no source label; the API resolves that. */
    @Test
    void moreFallsBackToTheAuthorWhenTheSourceLabelIsBlank() throws Exception {
        when(queryRepository.defaultNews()).thenReturn(homePage());

        mockMvc.perform(get("/api/v1/news/more"))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.data.items[0].source").value("wired2fish"))
                .andExpect(jsonPath("$.data.items[1].source").value("Fallback Author"));
    }

    /** MySQL's JSON_OBJECT emits with_photo as 1/0, not true/false; both backings must split alike. */
    @Test
    void leadDetectionAcceptsTheIntegerWithPhotoMySqlEmits() throws Exception {
        JsonNode root = objectMapper.createObjectNode().set("items", objectMapper.createArrayNode()
                .add(objectMapper.readTree("{\"title\":\"Lead\",\"with_photo\":1}"))
                .add(objectMapper.readTree("{\"title\":\"Small\",\"with_photo\":0}")));
        when(queryRepository.defaultNews()).thenReturn(root);

        mockMvc.perform(get("/api/v1/news/featured"))
                .andExpect(jsonPath("$.data.items.length()").value(1))
                .andExpect(jsonPath("$.data.items[0].title").value("Lead"));
        mockMvc.perform(get("/api/v1/news/more"))
                .andExpect(jsonPath("$.data.items.length()").value(1))
                .andExpect(jsonPath("$.data.items[0].title").value("Small"));
    }

    /** No database (in-memory profile) must still yield a well-formed empty envelope, not a 500. */
    @Test
    void featuredAndMoreReturnEmptyItemsWhenThereIsNoHomePage() throws Exception {
        when(queryRepository.defaultNews())
                .thenReturn(objectMapper.createObjectNode().set("items", objectMapper.createArrayNode()));

        mockMvc.perform(get("/api/v1/news/featured"))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.data.items.length()").value(0));
        mockMvc.perform(get("/api/v1/news/more"))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.data.items.length()").value(0));
    }

    @Test
    void searchMapsRepositoryResultsIntoTheEnvelope() throws Exception {
        NewsController.NewsSearchItem item = new NewsController.NewsSearchItem(
                "n-id", "Walleye run peaks", "Outdoor Canada", "2026-05-14", "CA",
                List.of("Walleye"), List.of("f-1"));
        when(queryRepository.search(any(NewsController.NewsSearchQuery.class)))
                .thenReturn(new NewsController.NewsSearchPage(List.of(item), 1, "walleye", 0, 25));

        mockMvc.perform(get("/api/v1/news/search").param("q", "walleye"))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.data.query").value("walleye"))
                .andExpect(jsonPath("$.data.total").value(1))
                .andExpect(jsonPath("$.data.offset").value(0))
                .andExpect(jsonPath("$.data.limit").value(25))
                .andExpect(jsonPath("$.data.items[0].newsId").value("n-id"))
                .andExpect(jsonPath("$.data.items[0].title").value("Walleye run peaks"))
                .andExpect(jsonPath("$.data.items[0].fishes[0]").value("Walleye"))
                .andExpect(jsonPath("$.data.items[0].fishIds[0]").value("f-1"));
    }

    @Test
    void searchTrimsTheTermBeforeQuerying() throws Exception {
        when(queryRepository.search(any(NewsController.NewsSearchQuery.class)))
                .thenReturn(new NewsController.NewsSearchPage(List.of(), 0, "pike", 0, 25));

        mockMvc.perform(get("/api/v1/news/search").param("q", "  pike  "))
                .andExpect(status().isOk());

        assertEquals("pike", captureSearch().query());
    }

    /** The {@code fish} parameter is what lets a MySQL-only backing match species names. */
    @Test
    void searchParsesTheFishParameterIntoDistinctCappedIds() throws Exception {
        when(queryRepository.search(any(NewsController.NewsSearchQuery.class)))
                .thenReturn(new NewsController.NewsSearchPage(List.of(), 0, "walleye", 0, 25));

        mockMvc.perform(get("/api/v1/news/search")
                        .param("q", "walleye")
                        .param("fish", " f1 , f2 ,, f1 , f3 , f4 "))
                .andExpect(status().isOk());

        assertEquals(List.of("f1", "f2", "f3"), captureSearch().fishIds());
    }

    @Test
    void searchWithNoFishParameterPassesAnEmptyIdList() throws Exception {
        when(queryRepository.search(any(NewsController.NewsSearchQuery.class)))
                .thenReturn(new NewsController.NewsSearchPage(List.of(), 0, "walleye", 0, 25));

        mockMvc.perform(get("/api/v1/news/search").param("q", "walleye"))
                .andExpect(status().isOk());

        assertEquals(List.of(), captureSearch().fishIds());
    }

    @Test
    void searchClampsThePageWindowAndUpperCasesTheCountry() throws Exception {
        when(queryRepository.search(any(NewsController.NewsSearchQuery.class)))
                .thenReturn(new NewsController.NewsSearchPage(List.of(), 0, "walleye", 0, 200));

        mockMvc.perform(get("/api/v1/news/search")
                        .param("q", "walleye").param("country", "ca")
                        .param("offset", "-5").param("limit", "9999"))
                .andExpect(status().isOk());

        NewsController.NewsSearchQuery sent = captureSearch();
        assertEquals("CA", sent.country());
        assertEquals(0, sent.offset());
        assertEquals(200, sent.limit());
    }

    @Test
    void searchWithABadCountryReturns400() throws Exception {
        mockMvc.perform(get("/api/v1/news/search").param("q", "walleye").param("country", "CAN"))
                .andExpect(status().isBadRequest())
                .andExpect(jsonPath("$.error.code").value("invalid_document"));

        org.mockito.Mockito.verify(queryRepository, org.mockito.Mockito.never())
                .search(any(NewsController.NewsSearchQuery.class));
    }

    /** The {@link NewsController.NewsSearchQuery} the controller actually handed the repository. */
    private NewsController.NewsSearchQuery captureSearch() {
        org.mockito.ArgumentCaptor<NewsController.NewsSearchQuery> captor =
                org.mockito.ArgumentCaptor.forClass(NewsController.NewsSearchQuery.class);
        org.mockito.Mockito.verify(queryRepository).search(captor.capture());
        return captor.getValue();
    }

    @Test
    void searchWithBlankTermReturns400() throws Exception {
        mockMvc.perform(get("/api/v1/news/search").param("q", "   "))
                .andExpect(status().isBadRequest())
                .andExpect(jsonPath("$.error.code").value("invalid_document"));
    }

    @Test
    void searchWithMissingTermReturns400() throws Exception {
        mockMvc.perform(get("/api/v1/news/search"))
                .andExpect(status().isBadRequest())
                .andExpect(jsonPath("$.error.code").value("invalid_document"));
    }

    @Test
    void newsAddCreatesTheDocument() throws Exception {
        when(service.add(any())).thenReturn("42");

        mockMvc.perform(post("/api/v1/news")
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("{\"name\":\"news\"}"))
                .andExpect(status().isCreated())
                .andExpect(jsonPath("$.data.id").exists());
    }

    // ---- interchange export / import (fn_news_json shape) ----

    @Test
    void exportReturnsTheInterchangeDocumentNestedInTheEnvelope() throws Exception {
        when(queryRepository.exportNews("7"))
                .thenReturn(objectMapper.readTree("{\"title\":\"Opener\",\"photo0\":\"AQIDBAU=\"}"));

        mockMvc.perform(get("/api/v1/news/export/7"))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.data.title").value("Opener"))
                .andExpect(jsonPath("$.data.photo0").value("AQIDBAU="))
                .andExpect(jsonPath("$.error").doesNotExist());
    }

    @Test
    void exportUnknownIdReturns404() throws Exception {
        when(queryRepository.exportNews("nope")).thenReturn(null);

        mockMvc.perform(get("/api/v1/news/export/nope"))
                .andExpect(status().isNotFound())
                .andExpect(jsonPath("$.error.code").value("not_found"))
                .andExpect(jsonPath("$.data").doesNotExist());
    }

    @Test
    void importReturns201WithNewId() throws Exception {
        when(service.importInterchange("{\"title\":\"Imported\"}")).thenReturn("abc-123");

        mockMvc.perform(post("/api/v1/news/import")
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("{\"title\":\"Imported\"}"))
                .andExpect(status().isCreated())
                .andExpect(jsonPath("$.data.id").value("abc-123"));
        // The write goes through the service (-> MySQL), never through the read repository.
        verify(service).importInterchange("{\"title\":\"Imported\"}");
        verifyNoInteractions(queryRepository);
    }

    /** Validation lives in NewsDocumentService (see NewsDocumentServiceTest); here, only the 400 mapping. */
    @Test
    void importValidationFailureReturns400() throws Exception {
        when(service.importInterchange(any()))
                .thenThrow(new InvalidDocumentException("Request body is not well-formed JSON"));

        mockMvc.perform(post("/api/v1/news/import")
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("{not json"))
                .andExpect(status().isBadRequest())
                .andExpect(jsonPath("$.error.code").value("invalid_document"));
    }

    @Test
    void importEmptyBodyReachesTheServiceAsNull() throws Exception {
        when(service.importInterchange(null))
                .thenThrow(new InvalidDocumentException("Request body must be a non-empty JSON document"));

        mockMvc.perform(post("/api/v1/news/import")
                        .contentType(MediaType.APPLICATION_JSON)
                        .content(""))
                .andExpect(status().isBadRequest())
                .andExpect(jsonPath("$.error.code").value("invalid_document"));
    }

    // ---- /news/photo/{id} : the lead photo as raw bytes ----------------------------------------

    /** A minimal but genuine JPEG header — the sniffer reads the first three bytes. */
    private static final byte[] JPEG = new byte[] {(byte) 0xFF, (byte) 0xD8, (byte) 0xFF, (byte) 0xE0, 1, 2, 3};
    /** A minimal but genuine PNG signature. */
    private static final byte[] PNG = new byte[] {(byte) 0x89, 'P', 'N', 'G', 13, 10, 26, 10, 9};

    @Test
    void photoReturnsTheRawBytesWithTheSniffedContentType() throws Exception {
        when(queryRepository.newsPhoto("a1")).thenReturn(JPEG);

        mockMvc.perform(get("/api/v1/news/photo/a1"))
                .andExpect(status().isOk())
                .andExpect(content().contentType(MediaType.IMAGE_JPEG))
                .andExpect(content().bytes(JPEG));
    }

    /**
     * The column holds whatever was uploaded, so the type must come from the bytes and not from a
     * hard-coded guess — the old inline markup said PNG for a library that is mostly JPEG.
     */
    @Test
    void photoContentTypeFollowsTheBytesNotAFixedDefault() throws Exception {
        when(queryRepository.newsPhoto("a2")).thenReturn(PNG);

        mockMvc.perform(get("/api/v1/news/photo/a2"))
                .andExpect(status().isOk())
                .andExpect(content().contentType(MediaType.IMAGE_PNG));
    }

    @Test
    void photoIsPubliclyCacheableAndCarriesAnEtagOfIdAndLength() throws Exception {
        when(queryRepository.newsPhoto("A3")).thenReturn(JPEG);

        mockMvc.perform(get("/api/v1/news/photo/A3"))
                .andExpect(status().isOk())
                .andExpect(header().string("ETag", "\"a3-" + JPEG.length + "\""))
                .andExpect(header().string("Cache-Control", "max-age=604800, public"));
    }

    @Test
    void photoRevalidationWithAMatchingEtagIs304() throws Exception {
        when(queryRepository.newsPhoto("a4")).thenReturn(JPEG);

        mockMvc.perform(get("/api/v1/news/photo/a4").header("If-None-Match", "\"a4-" + JPEG.length + "\""))
                .andExpect(status().isNotModified())
                .andExpect(content().bytes(new byte[0]));
    }

    /**
     * Replacing an article's photo keeps its id but changes the length, so the caller's ETag stops
     * matching and it is sent the new bytes. That is the whole reason length is part of the tag.
     */
    @Test
    void photoRevalidationWithAStaleEtagSendsTheNewBytes() throws Exception {
        when(queryRepository.newsPhoto("a5")).thenReturn(JPEG);

        mockMvc.perform(get("/api/v1/news/photo/a5").header("If-None-Match", "\"a5-999\""))
                .andExpect(status().isOk())
                .andExpect(content().bytes(JPEG));
    }

    /** Missing, unpublished, or simply photo-less all arrive here as null and must read the same. */
    @Test
    void photoReturns404WhenTheRepositoryHasNothing() throws Exception {
        when(queryRepository.newsPhoto("gone")).thenReturn(null);

        mockMvc.perform(get("/api/v1/news/photo/gone"))
                .andExpect(status().isNotFound());
    }

    @Test
    void photoReturns404ForAnEmptyBlobRatherThanAZeroLengthImage() throws Exception {
        when(queryRepository.newsPhoto("empty")).thenReturn(new byte[0]);

        mockMvc.perform(get("/api/v1/news/photo/empty"))
                .andExpect(status().isNotFound());
    }

    /** Unrecognised bytes are served honestly rather than mislabelled as an image. */
    @Test
    void photoOfAnUnrecognisedFormatIsOctetStream() throws Exception {
        when(queryRepository.newsPhoto("odd")).thenReturn(new byte[] {1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12});

        mockMvc.perform(get("/api/v1/news/photo/odd"))
                .andExpect(status().isOk())
                .andExpect(content().contentType(MediaType.APPLICATION_OCTET_STREAM));
    }

    // ---- /news/lake/{guid} (the water-body page's news panel) ------------------------------------

    private static final String LAKE = "fc0d917b-d053-11d8-92e2-080020a0f4c9";

    @Test
    void lakeNewsMapsRepositoryResultsIntoTheEnvelope() throws Exception {
        NewsController.NewsRefItem item =
                new NewsController.NewsRefItem("n-id", "Ice out on the Grand", "Outdoor Canada", "2026-05-14", "CA");
        when(queryRepository.lakeNews(LAKE, 12))
                .thenReturn(new NewsController.NewsLakePage(LAKE, 12, List.of(item)));

        mockMvc.perform(get("/api/v1/news/lake/" + LAKE))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.data.lakeId").value(LAKE))
                .andExpect(jsonPath("$.data.limit").value(12))
                .andExpect(jsonPath("$.data.items.length()").value(1))
                .andExpect(jsonPath("$.data.items[0].newsId").value("n-id"))
                .andExpect(jsonPath("$.data.items[0].title").value("Ice out on the Grand"))
                .andExpect(jsonPath("$.data.items[0].stamp").value("2026-05-14"));
    }

    /** A water body with no news is an ordinary empty answer, never a 404. */
    @Test
    void lakeNewsWithNoArticlesIsAnEmptyListNotA404() throws Exception {
        when(queryRepository.lakeNews(LAKE, 12))
                .thenReturn(new NewsController.NewsLakePage(LAKE, 12, List.of()));

        mockMvc.perform(get("/api/v1/news/lake/" + LAKE))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.data.items").isArray())
                .andExpect(jsonPath("$.data.items").isEmpty())
                .andExpect(jsonPath("$.error").doesNotExist());
    }

    @Test
    void lakeNewsClampsTheLimitAndLowerCasesTheGuid() throws Exception {
        when(queryRepository.lakeNews(any(), org.mockito.ArgumentMatchers.anyInt()))
                .thenReturn(new NewsController.NewsLakePage(LAKE, 12, List.of()));

        mockMvc.perform(get("/api/v1/news/lake/" + LAKE.toUpperCase()).param("limit", "9999"))
                .andExpect(status().isOk());
        mockMvc.perform(get("/api/v1/news/lake/" + LAKE).param("limit", "0"))
                .andExpect(status().isOk());

        org.mockito.ArgumentCaptor<String> id = org.mockito.ArgumentCaptor.forClass(String.class);
        org.mockito.ArgumentCaptor<Integer> limit = org.mockito.ArgumentCaptor.forClass(Integer.class);
        org.mockito.Mockito.verify(queryRepository, org.mockito.Mockito.times(2))
                .lakeNews(id.capture(), limit.capture());

        assertEquals(LAKE, id.getAllValues().get(0));
        assertEquals(NewsController.MAX_LIMIT, limit.getAllValues().get(0));
        assertEquals(NewsController.LAKE_DEFAULT_LIMIT, limit.getAllValues().get(1));
    }

    /** Junk in the path is a 400, and — as on every other validating route — no query is run. */
    @Test
    void lakeNewsRejectsANonGuidWith400AndNeverQueries() throws Exception {
        mockMvc.perform(get("/api/v1/news/lake/not-a-guid"))
                .andExpect(status().isBadRequest())
                .andExpect(jsonPath("$.error.code").value("invalid_document"));

        org.mockito.Mockito.verify(queryRepository, org.mockito.Mockito.never())
                .lakeNews(any(), org.mockito.ArgumentMatchers.anyInt());
    }

    /** {@code /lake/…} must win over the templated {@code /{id}} document fetch. */
    @Test
    void lakeNewsPathIsMatchedAheadOfTheDocumentFetch() throws Exception {
        when(queryRepository.lakeNews(LAKE, 12))
                .thenReturn(new NewsController.NewsLakePage(LAKE, 12, List.of()));

        mockMvc.perform(get("/api/v1/news/lake/" + LAKE))
                .andExpect(status().isOk());

        org.mockito.Mockito.verifyNoInteractions(service);
    }

    // ---- /news/fish/{guid} (the species page's news panel) ----------------------------------------

    private static final String FISH = "a85ebf22-4ab9-4a91-a14a-cef6c8e64d97";

    @Test
    void fishNewsMapsRepositoryResultsIntoTheEnvelope() throws Exception {
        NewsController.NewsRefItem item =
                new NewsController.NewsRefItem("n-id", "Walleye run peaks", "Outdoor Canada", "2026-05-14", "CA");
        when(queryRepository.fishNews(FISH, 10))
                .thenReturn(new NewsController.NewsFishPage(FISH, 10, List.of(item)));

        mockMvc.perform(get("/api/v1/news/fish/" + FISH))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.data.fishId").value(FISH))
                .andExpect(jsonPath("$.data.limit").value(10))
                .andExpect(jsonPath("$.data.items.length()").value(1))
                .andExpect(jsonPath("$.data.items[0].newsId").value("n-id"))
                .andExpect(jsonPath("$.data.items[0].title").value("Walleye run peaks"))
                .andExpect(jsonPath("$.data.items[0].stamp").value("2026-05-14"));
    }

    /** A species with no news is an ordinary empty answer, never a 404. */
    @Test
    void fishNewsWithNoArticlesIsAnEmptyListNotA404() throws Exception {
        when(queryRepository.fishNews(FISH, 10))
                .thenReturn(new NewsController.NewsFishPage(FISH, 10, List.of()));

        mockMvc.perform(get("/api/v1/news/fish/" + FISH))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.data.items").isArray())
                .andExpect(jsonPath("$.data.items").isEmpty())
                .andExpect(jsonPath("$.error").doesNotExist());
    }

    @Test
    void fishNewsClampsTheLimitAndLowerCasesTheGuid() throws Exception {
        when(queryRepository.fishNews(any(), org.mockito.ArgumentMatchers.anyInt()))
                .thenReturn(new NewsController.NewsFishPage(FISH, 10, List.of()));

        mockMvc.perform(get("/api/v1/news/fish/" + FISH.toUpperCase()).param("limit", "9999"))
                .andExpect(status().isOk());
        mockMvc.perform(get("/api/v1/news/fish/" + FISH).param("limit", "0"))
                .andExpect(status().isOk());

        org.mockito.ArgumentCaptor<String> id = org.mockito.ArgumentCaptor.forClass(String.class);
        org.mockito.ArgumentCaptor<Integer> limit = org.mockito.ArgumentCaptor.forClass(Integer.class);
        org.mockito.Mockito.verify(queryRepository, org.mockito.Mockito.times(2))
                .fishNews(id.capture(), limit.capture());

        assertEquals(FISH, id.getAllValues().get(0));
        assertEquals(NewsController.MAX_LIMIT, limit.getAllValues().get(0));
        assertEquals(NewsController.FISH_DEFAULT_LIMIT, limit.getAllValues().get(1));
    }

    /** Junk in the path is a 400, and — as on every other validating route — no query is run. */
    @Test
    void fishNewsRejectsANonGuidWith400AndNeverQueries() throws Exception {
        mockMvc.perform(get("/api/v1/news/fish/not-a-guid"))
                .andExpect(status().isBadRequest())
                .andExpect(jsonPath("$.error.code").value("invalid_document"));

        org.mockito.Mockito.verify(queryRepository, org.mockito.Mockito.never())
                .fishNews(any(), org.mockito.ArgumentMatchers.anyInt());
    }

    /** {@code /fish/…} must win over the templated {@code /{id}} document fetch. */
    @Test
    void fishNewsPathIsMatchedAheadOfTheDocumentFetch() throws Exception {
        when(queryRepository.fishNews(FISH, 10))
                .thenReturn(new NewsController.NewsFishPage(FISH, 10, List.of()));

        mockMvc.perform(get("/api/v1/news/fish/" + FISH))
                .andExpect(status().isOk());

        org.mockito.Mockito.verifyNoInteractions(service);
    }
}
