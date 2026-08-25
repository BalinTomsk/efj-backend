package com.fishfind.docapi.web;

import com.fasterxml.jackson.databind.ObjectMapper;
import com.fishfind.docapi.repo.RiverFishCommandRepository;
import com.fishfind.docapi.repo.RiverQueryRepository;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.autoconfigure.web.servlet.WebMvcTest;
import org.springframework.boot.test.mock.mockito.MockBean;
import org.springframework.test.web.servlet.MockMvc;

import static org.mockito.ArgumentMatchers.anyString;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.patch;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

@WebMvcTest(RiverController.class)
class RiverControllerTest {

    @Autowired
    private MockMvc mockMvc;

    @Autowired
    private ObjectMapper objectMapper;

    @MockBean
    private RiverQueryRepository queryRepository;

    @MockBean
    private RiverFishCommandRepository fishCommandRepository;

    @Test
    void unfishedMapsTheRepositoryResultIntoTheEnvelope() throws Exception {
        when(queryRepository.unfished("CA", "NL", 2)).thenReturn(objectMapper.readTree(
                "{\"found\":true,\"country\":\"CA\",\"state\":\"NL\",\"river\":2,"
                        + "\"lake_id\":\"abc\",\"lake_name\":\"Some River\",\"mouth_name\":\"Sea\","
                        + "\"CGNDB\":\"AAAAA\",\"throwing\":\"BBBBB,CCCCC\"}"));

        mockMvc.perform(get("/api/v1/river/unfished")
                        .param("country", "CA").param("state", "NL").param("river", "2"))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.data.found").value(true))
                .andExpect(jsonPath("$.data.lake_id").value("abc"))
                .andExpect(jsonPath("$.data.lake_name").value("Some River"))
                .andExpect(jsonPath("$.data.throwing").value("BBBBB,CCCCC"))
                .andExpect(jsonPath("$.error").doesNotExist())
                .andExpect(jsonPath("$.meta.timestamp").exists());
    }

    @Test
    void missingParamsFallBackToTheDefaults() throws Exception {
        when(queryRepository.unfished("CA", "ON", 2))
                .thenReturn(objectMapper.readTree("{\"found\":false,\"country\":\"CA\",\"state\":\"ON\",\"river\":2}"));

        mockMvc.perform(get("/api/v1/river/unfished"))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.data.found").value(false));
        verify(queryRepository).unfished("CA", "ON", 2);  // CA / ON / 2 defaults
    }

    @Test
    void badCodesAndRiverAreCleanedNotRejected() throws Exception {
        when(queryRepository.unfished("CA", "ON", 2))
                .thenReturn(objectMapper.createObjectNode().put("found", false));

        // country "usa" (3 chars) -> CA; state "n1" (digit) -> ON; river 999 (not a valid locType) -> 2
        mockMvc.perform(get("/api/v1/river/unfished")
                        .param("country", "usa").param("state", "n1").param("river", "999"))
                .andExpect(status().isOk());
        verify(queryRepository).unfished("CA", "ON", 2);
    }

    @Test
    void lowercaseStateIsUpperCased() throws Exception {
        when(queryRepository.unfished("CA", "BC", 4))
                .thenReturn(objectMapper.createObjectNode().put("found", false));

        mockMvc.perform(get("/api/v1/river/unfished")
                        .param("state", "bc").param("river", "4"))
                .andExpect(status().isOk());
        verify(queryRepository).unfished("CA", "BC", 4);
    }

    // ---- description ----

    @Test
    void descriptionReturnsTheDocumentNestedInTheEnvelope() throws Exception {
        when(queryRepository.description("0c5343a8-849c-20c3-f4d1-0003eb237498")).thenReturn(
                objectMapper.readTree("{\"guid\":\"0C5343A8-…\",\"lakeName\":\"Undersill Lake\",\"cgndb\":\"FCYVT\"}"));

        mockMvc.perform(get("/api/v1/river/description/0c5343a8-849c-20c3-f4d1-0003eb237498"))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.data.lakeName").value("Undersill Lake"))
                .andExpect(jsonPath("$.data.cgndb").value("FCYVT"))
                .andExpect(jsonPath("$.error").doesNotExist())
                .andExpect(jsonPath("$.meta.timestamp").exists());
    }

    @Test
    void descriptionUnknownGuidReturns404() throws Exception {
        when(queryRepository.description("00000000-0000-0000-0000-000000000000")).thenReturn(null);

        mockMvc.perform(get("/api/v1/river/description/00000000-0000-0000-0000-000000000000"))
                .andExpect(status().isNotFound())
                .andExpect(jsonPath("$.error.code").value("not_found"))
                .andExpect(jsonPath("$.data").doesNotExist());
    }

    // ---- fish ----

    @Test
    void fishReturnsTheDocumentNestedInTheEnvelope() throws Exception {
        when(queryRepository.fish("0c5343a8-849c-20c3-f4d1-0003eb237498")).thenReturn(
                objectMapper.readTree("{\"lake_id\":\"0c5343a8-…\",\"fish\":[{\"name\":\"Walleye\",\"latin\":\"Stizostedion vitreum\"}]}"));

        mockMvc.perform(get("/api/v1/river/fish/0c5343a8-849c-20c3-f4d1-0003eb237498"))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.data.fish[0].name").value("Walleye"))
                .andExpect(jsonPath("$.error").doesNotExist())
                .andExpect(jsonPath("$.meta.timestamp").exists());
    }

    @Test
    void fishUnknownGuidReturns404() throws Exception {
        when(queryRepository.fish("00000000-0000-0000-0000-000000000000")).thenReturn(null);

        mockMvc.perform(get("/api/v1/river/fish/00000000-0000-0000-0000-000000000000"))
                .andExpect(status().isNotFound())
                .andExpect(jsonPath("$.error.code").value("not_found"))
                .andExpect(jsonPath("$.data").doesNotExist());
    }

    // ---- PATCH fish (batch upsert) ----

    @Test
    void patchFishReturnsTheUpsertResultsNestedInTheEnvelope() throws Exception {
        String body = "[{\"fishId\":\"a85ebf22-4ab9-4a91-a14a-cef6c8e64d97\",\"link\":\"http://x\",\"trustLevel\":0}]";
        when(fishCommandRepository.upsertFish("0c5343a8-849c-20c3-f4d1-0003eb237498", "[{\"fishId\":\"a85ebf22-4ab9-4a91-a14a-cef6c8e64d97\",\"link\":\"http://x\",\"trustLevel\":0}]"))
                .thenReturn(objectMapper.readTree(
                        "[{\"fishId\":\"A85EBF22-4AB9-4A91-A14A-CEF6C8E64D97\",\"fishName\":\"Bass, Largemouth\",\"action\":\"inserted\"}]"));

        mockMvc.perform(patch("/api/v1/river/fish/0c5343a8-849c-20c3-f4d1-0003eb237498")
                        .contentType("application/json").content(body))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.data[0].action").value("inserted"))
                .andExpect(jsonPath("$.data[0].fishName").value("Bass, Largemouth"))
                .andExpect(jsonPath("$.error").doesNotExist());
    }

    @Test
    void patchFishUnknownLakeGuidReturns404() throws Exception {
        when(fishCommandRepository.upsertFish(eq("00000000-0000-0000-0000-000000000000"), anyString()))
                .thenReturn(null);

        mockMvc.perform(patch("/api/v1/river/fish/00000000-0000-0000-0000-000000000000")
                        .contentType("application/json")
                        .content("[{\"fishId\":\"a85ebf22-4ab9-4a91-a14a-cef6c8e64d97\"}]"))
                .andExpect(status().isNotFound())
                .andExpect(jsonPath("$.error.code").value("not_found"));
    }

    @Test
    void patchFishEmptyArrayReturns400WithoutCallingTheRepository() throws Exception {
        mockMvc.perform(patch("/api/v1/river/fish/0c5343a8-849c-20c3-f4d1-0003eb237498")
                        .contentType("application/json").content("[]"))
                .andExpect(status().isBadRequest())
                .andExpect(jsonPath("$.error.code").value("invalid_document"));

        verify(fishCommandRepository, never()).upsertFish(anyString(), anyString());
    }

    @Test
    void patchFishNonArrayBodyReturns400() throws Exception {
        mockMvc.perform(patch("/api/v1/river/fish/0c5343a8-849c-20c3-f4d1-0003eb237498")
                        .contentType("application/json").content("{\"fishId\":\"a85ebf22-4ab9-4a91-a14a-cef6c8e64d97\"}"))
                .andExpect(status().isBadRequest())
                .andExpect(jsonPath("$.error.code").value("invalid_document"));
    }

    @Test
    void patchFishMissingBodyReturns400() throws Exception {
        mockMvc.perform(patch("/api/v1/river/fish/0c5343a8-849c-20c3-f4d1-0003eb237498")
                        .contentType("application/json"))
                .andExpect(status().isBadRequest())
                .andExpect(jsonPath("$.error.code").value("invalid_document"));
    }

    @Test
    void patchFishOversizedBatchReturns400() throws Exception {
        StringBuilder body = new StringBuilder("[");
        for (int i = 0; i < RiverController.MAX_FISH_BATCH + 1; i++) {
            if (i > 0) body.append(',');
            body.append("{\"fishId\":\"a85ebf22-4ab9-4a91-a14a-cef6c8e64d97\"}");
        }
        body.append(']');

        mockMvc.perform(patch("/api/v1/river/fish/0c5343a8-849c-20c3-f4d1-0003eb237498")
                        .contentType("application/json").content(body.toString()))
                .andExpect(status().isBadRequest())
                .andExpect(jsonPath("$.error.code").value("invalid_document"));

        verify(fishCommandRepository, never()).upsertFish(anyString(), anyString());
    }
}
