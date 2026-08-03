package com.fishfind.docapi.web;

import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.fishfind.docapi.domain.DocumentType;
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
import static org.mockito.ArgumentMatchers.eq;
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
        when(queryRepository.list(null, 5, 10))
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
        when(queryRepository.list(null, 0, 25)).thenReturn(page);

        mockMvc.perform(get("/api/v1/news/list"))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.data.items").isArray())
                .andExpect(jsonPath("$.data.items.length()").value(1))
                .andExpect(jsonPath("$.data.items[0].title").value("Title"))
                .andExpect(jsonPath("$.data.total").value(8));
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

    @Test
    void searchMapsRepositoryResultsIntoTheEnvelope() throws Exception {
        NewsController.NewsSearchItem item = new NewsController.NewsSearchItem(
                "n-id", "Walleye run peaks", "Outdoor Canada", "2026-05-14", "CA", List.of("Walleye"));
        when(queryRepository.search("walleye"))
                .thenReturn(new NewsController.NewsSearchPage(List.of(item), 1, "walleye"));

        mockMvc.perform(get("/api/v1/news/search").param("q", "walleye"))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.data.query").value("walleye"))
                .andExpect(jsonPath("$.data.total").value(1))
                .andExpect(jsonPath("$.data.items[0].newsId").value("n-id"))
                .andExpect(jsonPath("$.data.items[0].title").value("Walleye run peaks"))
                .andExpect(jsonPath("$.data.items[0].fishes[0]").value("Walleye"));
    }

    @Test
    void searchTrimsTheTermBeforeQuerying() throws Exception {
        when(queryRepository.search("pike"))
                .thenReturn(new NewsController.NewsSearchPage(List.of(), 0, "pike"));

        mockMvc.perform(get("/api/v1/news/search").param("q", "  pike  "))
                .andExpect(status().isOk());
        // verified via the stub: the controller must have passed the trimmed term
        org.mockito.Mockito.verify(queryRepository).search("pike");
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
        when(queryRepository.importNews(any())).thenReturn("abc-123");

        mockMvc.perform(post("/api/v1/news/import")
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("{\"title\":\"Imported\"}"))
                .andExpect(status().isCreated())
                .andExpect(jsonPath("$.data.id").value("abc-123"));
    }

    @Test
    void importInvalidJsonReturns400() throws Exception {
        mockMvc.perform(post("/api/v1/news/import")
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("{not json"))
                .andExpect(status().isBadRequest())
                .andExpect(jsonPath("$.error.code").value("invalid_document"));
    }

    @Test
    void importEmptyBodyReturns400() throws Exception {
        mockMvc.perform(post("/api/v1/news/import")
                        .contentType(MediaType.APPLICATION_JSON)
                        .content(""))
                .andExpect(status().isBadRequest())
                .andExpect(jsonPath("$.error.code").value("invalid_document"));
    }
}
