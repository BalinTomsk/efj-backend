package com.fishfind.docapi.web;

import com.fasterxml.jackson.databind.ObjectMapper;
import com.fishfind.docapi.domain.DocumentType;
import com.fishfind.docapi.repo.FishQueryRepository;
import com.fishfind.docapi.service.DocumentNotFoundException;
import com.fishfind.docapi.service.FishDocumentService;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.autoconfigure.web.servlet.WebMvcTest;
import org.springframework.boot.test.mock.mockito.MockBean;
import org.springframework.test.web.servlet.MockMvc;

import java.util.List;

import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

@WebMvcTest(FishController.class)
class FishControllerTest {

    @Autowired
    private MockMvc mockMvc;

    @Autowired
    private ObjectMapper objectMapper;

    @MockBean
    private FishDocumentService service;

    @MockBean
    private FishQueryRepository queryRepository;

    // ---- generic JSON-document CRUD (inherited from AbstractDocumentController) ----

    @Test
    void getReturnsTheDocumentNestedInTheEnvelope() throws Exception {
        when(service.get("7")).thenReturn(objectMapper.readTree("{\"name\":\"Walleye\"}"));

        mockMvc.perform(get("/api/v1/fish/7"))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.data.name").value("Walleye"))
                .andExpect(jsonPath("$.error").doesNotExist())
                .andExpect(jsonPath("$.meta.timestamp").exists());
    }

    @Test
    void getUnknownIdReturns404WithErrorEnvelope() throws Exception {
        when(service.get("nope")).thenThrow(new DocumentNotFoundException(DocumentType.FISH, "nope"));

        mockMvc.perform(get("/api/v1/fish/nope"))
                .andExpect(status().isNotFound())
                .andExpect(jsonPath("$.error.code").value("not_found"))
                .andExpect(jsonPath("$.data").doesNotExist());
    }

    // ---- species-catalogue search (delegated to FishQueryRepository) ----

    @Test
    void searchMapsRepositoryResultsIntoTheEnvelope() throws Exception {
        FishController.FishSearchItem item = new FishController.FishSearchItem(
                "f-id", "Bluegill", "Lepomis macrochirus", 0);
        when(queryRepository.search("rosefish"))
                .thenReturn(new FishController.FishSearchPage(List.of(item), 1, "rosefish"));

        mockMvc.perform(get("/api/v1/fish/search").param("q", "rosefish"))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.data.query").value("rosefish"))
                .andExpect(jsonPath("$.data.total").value(1))
                .andExpect(jsonPath("$.data.items[0].fishId").value("f-id"))
                .andExpect(jsonPath("$.data.items[0].name").value("Bluegill"))
                .andExpect(jsonPath("$.data.items[0].latin").value("Lepomis macrochirus"))
                .andExpect(jsonPath("$.data.items[0].rank").value(0));
    }

    @Test
    void searchTrimsTheTermBeforeQuerying() throws Exception {
        when(queryRepository.search("pike"))
                .thenReturn(new FishController.FishSearchPage(List.of(), 0, "pike"));

        mockMvc.perform(get("/api/v1/fish/search").param("q", "  pike  "))
                .andExpect(status().isOk());
        // verified via the stub: the controller must have passed the trimmed term
        verify(queryRepository).search("pike");
    }

    @Test
    void searchWithEmptyRepositoryReturnsEmptyPageEchoingTheQuery() throws Exception {
        when(queryRepository.search("nothing"))
                .thenReturn(new FishController.FishSearchPage(List.of(), 0, "nothing"));

        mockMvc.perform(get("/api/v1/fish/search").param("q", "nothing"))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.data.items").isArray())
                .andExpect(jsonPath("$.data.items").isEmpty())
                .andExpect(jsonPath("$.data.total").value(0))
                .andExpect(jsonPath("$.data.query").value("nothing"));
    }

    @Test
    void searchWithBlankTermReturns400() throws Exception {
        mockMvc.perform(get("/api/v1/fish/search").param("q", "   "))
                .andExpect(status().isBadRequest())
                .andExpect(jsonPath("$.error.code").value("invalid_document"));
    }

    @Test
    void searchWithMissingTermReturns400() throws Exception {
        mockMvc.perform(get("/api/v1/fish/search"))
                .andExpect(status().isBadRequest())
                .andExpect(jsonPath("$.error.code").value("invalid_document"));
    }
}
