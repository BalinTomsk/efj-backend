package com.fishfind.docapi.web;

import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.fishfind.docapi.domain.DocumentType;
import com.fishfind.docapi.service.DocumentNotFoundException;
import com.fishfind.docapi.service.InvalidDocumentException;
import com.fishfind.docapi.service.NewsDocumentService;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.ObjectProvider;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.autoconfigure.web.servlet.WebMvcTest;
import org.springframework.boot.test.mock.mockito.MockBean;
import org.springframework.http.MediaType;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.jdbc.core.PreparedStatementSetter;
import org.springframework.jdbc.core.ResultSetExtractor;
import org.springframework.jdbc.core.RowMapper;
import org.springframework.test.web.servlet.MockMvc;

import java.sql.PreparedStatement;
import java.sql.ResultSet;
import java.util.List;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertThrows;
import static org.junit.jupiter.api.Assertions.assertTrue;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.put;
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

    // ---- News-page read queries (no DB in this slice, so results are empty) ----

    @Test
    void listWithNoDatabaseReturnsEmptyPageEchoingPaging() throws Exception {
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
    void defaultWithNoDatabaseReturnsEmptyItems() throws Exception {
        mockMvc.perform(get("/api/v1/news/default"))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.data.items").isArray())
                .andExpect(jsonPath("$.data.items").isEmpty());
    }

    // ---- News-page read queries with a JDBC backing (controller built directly, jdbc mocked) ----

    @Test
    void listMapsFnNewsListRowsAndReadsTheTotalOnce() throws Exception {
        JdbcTemplate jdbc = mock(JdbcTemplate.class);
        PreparedStatement ps = mock(PreparedStatement.class);
        NewsController controller = new NewsController(service, objectMapper, providerOf(jdbc));

        when(jdbc.query(any(String.class), any(PreparedStatementSetter.class), any(ResultSetExtractor.class)))
                .thenAnswer(invocation -> {
                    // country normalized to upper-case and paging bound as parameters 1..3
                    PreparedStatementSetter binder = invocation.getArgument(1);
                    binder.setValues(ps);

                    ResultSet rs = mock(ResultSet.class);
                    when(rs.next()).thenReturn(true, false);
                    when(rs.getLong("total")).thenReturn(8L);
                    when(rs.getLong("rn")).thenReturn(1L);
                    when(rs.getString("news_id")).thenReturn("n-guid");
                    when(rs.getString("title")).thenReturn("Opener");
                    when(rs.getString("source")).thenReturn("Gazette");
                    when(rs.getString("stamp")).thenReturn("2026-07-10");
                    when(rs.getString("flag")).thenReturn("CA");
                    when(rs.getBoolean("has_photo")).thenReturn(true);
                    when(rs.getInt("block_ord")).thenReturn(0);

                    ResultSetExtractor<?> extractor = invocation.getArgument(2);
                    return extractor.extractData(rs);
                });

        ApiResponse<NewsController.NewsListPage> response = controller.list("ca", 0, 25);
        NewsController.NewsListPage page = response.data();

        assertEquals(8L, page.total());
        assertEquals(1, page.items().size());
        NewsController.NewsListItem item = page.items().get(0);
        assertEquals("Opener", item.title());
        assertEquals("CA", item.flag());
        assertTrue(item.hasPhoto());

        verify(jdbc).query(eq(NewsController.LIST_SQL), any(PreparedStatementSetter.class), any(ResultSetExtractor.class));
        verify(ps).setString(1, "CA");   // "ca" normalized to upper-case
        verify(ps).setInt(2, 0);
        verify(ps).setInt(3, 25);
    }

    @Test
    void defaultAssemblesItemsFromTheDefaultNewsFunctions() {
        JdbcTemplate jdbc = mock(JdbcTemplate.class);
        NewsController controller = new NewsController(service, objectMapper, providerOf(jdbc));

        when(jdbc.query(any(String.class), any(RowMapper.class)))
                .thenReturn(List.of("{\"title\":\"Lead\",\"with_photo\":true}", "{\"title\":\"Small\",\"with_photo\":false}"));

        JsonNode data = controller.defaultNews().data();

        assertEquals(2, data.get("items").size());
        assertEquals("Lead", data.get("items").get(0).get("title").asText());
        verify(jdbc).query(eq(NewsController.DEFAULT_SQL), any(RowMapper.class));
    }

    @Test
    void listClampsOffsetAndLimitEvenWithNoDatabase() {
        NewsController controller = new NewsController(service, objectMapper, providerOf(null));

        NewsController.NewsListPage page = controller.list(null, -5, 999).data();

        assertEquals(0, page.offset());     // negative offset → 0
        assertEquals(200, page.limit());    // 999 capped at MAX_LIMIT
        assertTrue(page.items().isEmpty());
    }

    @Test
    void listRejectsANonTwoLetterCountryAtTheServiceLevel() {
        NewsController controller = new NewsController(service, objectMapper, providerOf(null));

        assertThrows(InvalidDocumentException.class, () -> controller.list("USA", 0, 25));
    }

    @SuppressWarnings("unchecked")
    private static ObjectProvider<JdbcTemplate> providerOf(JdbcTemplate jdbc) {
        ObjectProvider<JdbcTemplate> provider = mock(ObjectProvider.class);
        when(provider.getIfAvailable()).thenReturn(jdbc);
        return provider;
    }
}
