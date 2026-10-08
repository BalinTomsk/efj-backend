package com.fishfind.docapi.web;

import com.fasterxml.jackson.databind.ObjectMapper;
import com.fishfind.docapi.repo.RiverDescriptionCommandRepository;
import com.fishfind.docapi.repo.RiverFishCommandRepository;
import com.fishfind.docapi.repo.RiverLinkCommandRepository;
import com.fishfind.docapi.repo.RiverQueryRepository;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.autoconfigure.web.servlet.WebMvcTest;
import org.springframework.boot.test.mock.mockito.MockBean;
import org.springframework.test.web.servlet.MockMvc;

import static org.hamcrest.Matchers.containsString;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.anyInt;
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

    @MockBean
    private RiverDescriptionCommandRepository descriptionCommandRepository;

    @MockBean
    private RiverLinkCommandRepository linkCommandRepository;

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

    // ---- PATCH description (merge patch) ----

    @Test
    void patchDescriptionReturnsTheResultNestedInTheEnvelope() throws Exception {
        String body = "{\"link\":\"http://x\",\"description\":\"a small stream\"}";
        when(descriptionCommandRepository.patchDescription("0c5343a8-849c-20c3-f4d1-0003eb237498", body))
                .thenReturn(objectMapper.readTree(
                        "{\"lakeId\":\"0C5343A8-…\",\"updated\":[{\"field\":\"link\"},{\"field\":\"description\"}],\"ignored\":[],\"protectedFields\":[]}"));

        mockMvc.perform(patch("/api/v1/river/description/0c5343a8-849c-20c3-f4d1-0003eb237498")
                        .contentType("application/json").content(body))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.data.updated[0].field").value("link"))
                .andExpect(jsonPath("$.error").doesNotExist());
    }

    @Test
    void patchDescriptionUnknownLakeGuidReturns404() throws Exception {
        when(descriptionCommandRepository.patchDescription(eq("00000000-0000-0000-0000-000000000000"), anyString()))
                .thenReturn(null);

        mockMvc.perform(patch("/api/v1/river/description/00000000-0000-0000-0000-000000000000")
                        .contentType("application/json").content("{\"link\":\"http://x\"}"))
                .andExpect(status().isNotFound())
                .andExpect(jsonPath("$.error.code").value("not_found"));
    }

    @Test
    void patchDescriptionEmptyObjectReturns400WithoutCallingTheRepository() throws Exception {
        mockMvc.perform(patch("/api/v1/river/description/0c5343a8-849c-20c3-f4d1-0003eb237498")
                        .contentType("application/json").content("{}"))
                .andExpect(status().isBadRequest())
                .andExpect(jsonPath("$.error.code").value("invalid_document"));

        verify(descriptionCommandRepository, never()).patchDescription(anyString(), anyString());
    }

    @Test
    void patchDescriptionArrayBodyReturns400() throws Exception {
        mockMvc.perform(patch("/api/v1/river/description/0c5343a8-849c-20c3-f4d1-0003eb237498")
                        .contentType("application/json").content("[{\"link\":\"http://x\"}]"))
                .andExpect(status().isBadRequest())
                .andExpect(jsonPath("$.error.code").value("invalid_document"));
    }

    @Test
    void patchDescriptionMissingBodyReturns400() throws Exception {
        mockMvc.perform(patch("/api/v1/river/description/0c5343a8-849c-20c3-f4d1-0003eb237498")
                        .contentType("application/json"))
                .andExpect(status().isBadRequest())
                .andExpect(jsonPath("$.error.code").value("invalid_document"));
    }

    @Test
    void patchDescriptionOversizedBodyReturns400() throws Exception {
        StringBuilder body = new StringBuilder("{");
        for (int i = 0; i < RiverController.MAX_PATCH_FIELDS + 1; i++) {
            if (i > 0) body.append(',');
            body.append("\"field").append(i).append("\":\"x\"");
        }
        body.append('}');

        mockMvc.perform(patch("/api/v1/river/description/0c5343a8-849c-20c3-f4d1-0003eb237498")
                        .contentType("application/json").content(body.toString()))
                .andExpect(status().isBadRequest())
                .andExpect(jsonPath("$.error.code").value("invalid_document"));

        verify(descriptionCommandRepository, never()).patchDescription(anyString(), anyString());
    }

    // ---- source ----

    @Test
    void sourceReturnsTheDocumentNestedInTheEnvelope() throws Exception {
        when(queryRepository.source("0c5343a8-849c-20c3-f4d1-0003eb237498")).thenReturn(
                objectMapper.readTree("{\"guid\":\"0C5343A8-…\",\"lakeName\":\"Undersill Lake\",\"sources\":[{\"pointName\":\"Origin Creek\"}]}"));

        mockMvc.perform(get("/api/v1/river/source/0c5343a8-849c-20c3-f4d1-0003eb237498"))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.data.lakeName").value("Undersill Lake"))
                .andExpect(jsonPath("$.data.sources[0].pointName").value("Origin Creek"))
                .andExpect(jsonPath("$.error").doesNotExist())
                .andExpect(jsonPath("$.meta.timestamp").exists());
    }

    @Test
    void sourceUnknownGuidReturns404() throws Exception {
        when(queryRepository.source("00000000-0000-0000-0000-000000000000")).thenReturn(null);

        mockMvc.perform(get("/api/v1/river/source/00000000-0000-0000-0000-000000000000"))
                .andExpect(status().isNotFound())
                .andExpect(jsonPath("$.error.code").value("not_found"))
                .andExpect(jsonPath("$.data").doesNotExist());
    }

    // ---- mouth ----

    @Test
    void mouthReturnsTheDocumentNestedInTheEnvelope() throws Exception {
        when(queryRepository.mouth("0c5343a8-849c-20c3-f4d1-0003eb237498")).thenReturn(
                objectMapper.readTree("{\"guid\":\"0C5343A8-…\",\"lakeName\":\"Undersill Lake\",\"mouths\":[{\"pointName\":\"Outlet Bay\"}]}"));

        mockMvc.perform(get("/api/v1/river/mouth/0c5343a8-849c-20c3-f4d1-0003eb237498"))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.data.mouths[0].pointName").value("Outlet Bay"))
                .andExpect(jsonPath("$.error").doesNotExist())
                .andExpect(jsonPath("$.meta.timestamp").exists());
    }

    @Test
    void mouthUnknownGuidReturns404() throws Exception {
        when(queryRepository.mouth("00000000-0000-0000-0000-000000000000")).thenReturn(null);

        mockMvc.perform(get("/api/v1/river/mouth/00000000-0000-0000-0000-000000000000"))
                .andExpect(status().isNotFound())
                .andExpect(jsonPath("$.error.code").value("not_found"))
                .andExpect(jsonPath("$.data").doesNotExist());
    }

    // ---- tributaries (1.22.0) ----

    @Test
    void tributariesNormalizeTheGuidAndDefaultTheLimit() throws Exception {
        when(queryRepository.tributaries("4094e667-bbe3-11d8-92e2-080020a0f4c9", RiverController.SEARCH_DEFAULT_LIMIT))
                .thenReturn(objectMapper.readTree("{\"guid\":\"4094E667-BBE3-11D8-92E2-080020A0F4C9\","
                        + "\"lakeName\":\"Humber River\",\"total\":1,\"limit\":50,"
                        + "\"tributaries\":[{\"lakeName\":\"East Humber River\",\"link\":\"mouth\"}]}"));

        mockMvc.perform(get("/api/v1/river/tributaries/4094E667BBE311D892E2080020A0F4C9"))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.data.total").value(1))
                .andExpect(jsonPath("$.data.tributaries[0].lakeName").value("East Humber River"))
                .andExpect(jsonPath("$.error").doesNotExist());
    }

    @Test
    void tributariesCapTheLimitAndTreatGarbageAsTheDefault() throws Exception {
        String id = "4094e667-bbe3-11d8-92e2-080020a0f4c9";
        when(queryRepository.tributaries(eq(id), anyInt())).thenReturn(objectMapper.readTree("{\"tributaries\":[]}"));

        mockMvc.perform(get("/api/v1/river/tributaries/" + id).param("limit", "5000")).andExpect(status().isOk());
        mockMvc.perform(get("/api/v1/river/tributaries/" + id).param("limit", "x")).andExpect(status().isOk());

        verify(queryRepository).tributaries(id, RiverController.SEARCH_MAX_LIMIT);
        verify(queryRepository).tributaries(id, RiverController.SEARCH_DEFAULT_LIMIT);
    }

    @Test
    void tributariesOfAnUnknownGuidAre404() throws Exception {
        when(queryRepository.tributaries("00000000-0000-0000-0000-000000000000", RiverController.SEARCH_DEFAULT_LIMIT))
                .thenReturn(null);

        mockMvc.perform(get("/api/v1/river/tributaries/00000000-0000-0000-0000-000000000000"))
                .andExpect(status().isNotFound())
                .andExpect(jsonPath("$.error.code").value("not_found"));
    }

    @Test
    void tributariesOfAMalformedGuidAre400AndNeverQuery() throws Exception {
        mockMvc.perform(get("/api/v1/river/tributaries/not-a-guid"))
                .andExpect(status().isBadRequest())
                .andExpect(jsonPath("$.error.code").value("invalid_document"));

        verify(queryRepository, never()).tributaries(anyString(), anyInt());
    }

    // ---- PATCH source (merge patch) ----

    @Test
    void patchSourceReturnsTheResultNestedInTheEnvelope() throws Exception {
        String body = "{\"lat\":52.1,\"lon\":-95.4}";
        when(linkCommandRepository.patchSource("0c5343a8-849c-20c3-f4d1-0003eb237498", body))
                .thenReturn(objectMapper.readTree(
                        "{\"lakeId\":\"0C5343A8-…\",\"updated\":[{\"field\":\"lat\"},{\"field\":\"lon\"}],\"ignored\":[],\"protectedFields\":[]}"));

        mockMvc.perform(patch("/api/v1/river/source/0c5343a8-849c-20c3-f4d1-0003eb237498")
                        .contentType("application/json").content(body))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.data.updated[0].field").value("lat"))
                .andExpect(jsonPath("$.error").doesNotExist());
    }

    @Test
    void patchSourceProtectsIdentityFields() throws Exception {
        String body = "{\"lakeName\":\"Hijacked\",\"pointId\":\"00000000-0000-0000-0000-000000000000\"}";
        when(linkCommandRepository.patchSource("0c5343a8-849c-20c3-f4d1-0003eb237498", body))
                .thenReturn(objectMapper.readTree(
                        "{\"lakeId\":\"0C5343A8-…\",\"updated\":[],\"ignored\":[],"
                                + "\"protectedFields\":[{\"field\":\"lakeName\"},{\"field\":\"pointId\"}]}"));

        mockMvc.perform(patch("/api/v1/river/source/0c5343a8-849c-20c3-f4d1-0003eb237498")
                        .contentType("application/json").content(body))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.data.updated").isEmpty())
                .andExpect(jsonPath("$.data.protectedFields[0].field").value("lakeName"))
                .andExpect(jsonPath("$.data.protectedFields[1].field").value("pointId"));
    }

    @Test
    void patchSourceUnknownLakeGuidReturns404() throws Exception {
        when(linkCommandRepository.patchSource(eq("00000000-0000-0000-0000-000000000000"), anyString()))
                .thenReturn(null);

        mockMvc.perform(patch("/api/v1/river/source/00000000-0000-0000-0000-000000000000")
                        .contentType("application/json").content("{\"lat\":1}"))
                .andExpect(status().isNotFound())
                .andExpect(jsonPath("$.error.code").value("not_found"));
    }

    @Test
    void patchSourceEmptyObjectReturns400WithoutCallingTheRepository() throws Exception {
        mockMvc.perform(patch("/api/v1/river/source/0c5343a8-849c-20c3-f4d1-0003eb237498")
                        .contentType("application/json").content("{}"))
                .andExpect(status().isBadRequest())
                .andExpect(jsonPath("$.error.code").value("invalid_document"));

        verify(linkCommandRepository, never()).patchSource(anyString(), anyString());
    }

    @Test
    void patchSourceMissingBodyReturns400() throws Exception {
        mockMvc.perform(patch("/api/v1/river/source/0c5343a8-849c-20c3-f4d1-0003eb237498")
                        .contentType("application/json"))
                .andExpect(status().isBadRequest())
                .andExpect(jsonPath("$.error.code").value("invalid_document"));
    }

    // ---- PATCH mouth (merge patch) ----

    @Test
    void patchMouthReturnsTheResultNestedInTheEnvelope() throws Exception {
        String body = "{\"lat\":51.9,\"lon\":-94.8}";
        when(linkCommandRepository.patchMouth("0c5343a8-849c-20c3-f4d1-0003eb237498", body))
                .thenReturn(objectMapper.readTree(
                        "{\"lakeId\":\"0C5343A8-…\",\"updated\":[{\"field\":\"lat\"},{\"field\":\"lon\"}],\"ignored\":[],\"protectedFields\":[]}"));

        mockMvc.perform(patch("/api/v1/river/mouth/0c5343a8-849c-20c3-f4d1-0003eb237498")
                        .contentType("application/json").content(body))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.data.updated[0].field").value("lat"))
                .andExpect(jsonPath("$.error").doesNotExist());
    }

    @Test
    void patchMouthUnknownLakeGuidReturns404() throws Exception {
        when(linkCommandRepository.patchMouth(eq("00000000-0000-0000-0000-000000000000"), anyString()))
                .thenReturn(null);

        mockMvc.perform(patch("/api/v1/river/mouth/00000000-0000-0000-0000-000000000000")
                        .contentType("application/json").content("{\"lat\":1}"))
                .andExpect(status().isNotFound())
                .andExpect(jsonPath("$.error.code").value("not_found"));
    }

    @Test
    void patchMouthEmptyObjectReturns400WithoutCallingTheRepository() throws Exception {
        mockMvc.perform(patch("/api/v1/river/mouth/0c5343a8-849c-20c3-f4d1-0003eb237498")
                        .contentType("application/json").content("{}"))
                .andExpect(status().isBadRequest())
                .andExpect(jsonPath("$.error.code").value("invalid_document"));

        verify(linkCommandRepository, never()).patchMouth(anyString(), anyString());
    }

    @Test
    void patchMouthArrayBodyReturns400() throws Exception {
        mockMvc.perform(patch("/api/v1/river/mouth/0c5343a8-849c-20c3-f4d1-0003eb237498")
                        .contentType("application/json").content("[{\"lat\":1}]"))
                .andExpect(status().isBadRequest())
                .andExpect(jsonPath("$.error.code").value("invalid_document"));
    }

    @Test
    void searchByNameWrapsTheItemsWithTheEchoedQuery() throws Exception {
        when(queryRepository.search("Humber", null, null, null, null, 50)).thenReturn(objectMapper.readTree(
                "[{\"lakeId\":\"abc\",\"lakeName\":\"Humber River\",\"CGNDB\":\"FEFUL\",\"mli\":[\"02HC024\"]}]"));

        mockMvc.perform(get("/api/v1/river/search").param("name", "  Humber "))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.data.items[0].lakeName").value("Humber River"))
                .andExpect(jsonPath("$.data.items[0].mli[0]").value("02HC024"))
                .andExpect(jsonPath("$.data.total").value(1))
                .andExpect(jsonPath("$.data.limit").value(50))
                .andExpect(jsonPath("$.data.query.name").value("Humber"))
                .andExpect(jsonPath("$.data.query.guid").doesNotExist());
    }

    @Test
    void searchNormalizesGuidCgndbAndAcceptsUpperCaseParamNames() throws Exception {
        when(queryRepository.search(any(), any(), any(), any(), any(), anyInt()))
                .thenReturn(objectMapper.createArrayNode());

        mockMvc.perform(get("/api/v1/river/search")
                        .param("guid", "{0C5210DB849C20C357F421FF96A2047B}")
                        .param("CGNDB", "feful").param("MLI", "02HC024").param("limit", "999"))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.data.items").isEmpty())
                .andExpect(jsonPath("$.data.total").value(0))
                .andExpect(jsonPath("$.data.limit").value(200));
        verify(queryRepository).search(null, "0c5210db-849c-20c3-57f4-21ff96a2047b", "FEFUL", null, "02HC024", 200);
    }

    @Test
    void searchByStateIdPassesItThroughAndEchoesIt() throws Exception {
        when(queryRepository.search(null, null, null, "39325", null, 50)).thenReturn(objectMapper.readTree(
                "[{\"lakeId\":\"abc\",\"lakeName\":\"Fraser River\",\"stateId\":\"39325\"}]"));

        mockMvc.perform(get("/api/v1/river/search").param("stateid", " 39325 "))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.data.items[0].stateId").value("39325"))
                .andExpect(jsonPath("$.data.query.stateId").value("39325"))
                .andExpect(jsonPath("$.data.query.cgndb").doesNotExist());
    }

    @Test
    void searchRejectsMalformedStateId() throws Exception {
        mockMvc.perform(get("/api/v1/river/search").param("stateId", "39 325"))
                .andExpect(status().isBadRequest())
                .andExpect(jsonPath("$.error.message", containsString("stateId")));
        mockMvc.perform(get("/api/v1/river/search").param("stateId", "1".repeat(33)))
                .andExpect(status().isBadRequest());
        verify(queryRepository, never()).search(any(), any(), any(), any(), any(), anyInt());
    }

    @Test
    void searchWithNoCriteriaIs400() throws Exception {
        mockMvc.perform(get("/api/v1/river/search").param("name", " ").param("limit", "5"))
                .andExpect(status().isBadRequest())
                .andExpect(jsonPath("$.error.code").value("invalid_document"));
        verify(queryRepository, never()).search(any(), any(), any(), any(), any(), anyInt());
    }

    @Test
    void searchRejectsMalformedCriteria() throws Exception {
        mockMvc.perform(get("/api/v1/river/search").param("guid", "932853209432094"))
                .andExpect(status().isBadRequest());
        mockMvc.perform(get("/api/v1/river/search").param("cgndb", "FEFULX"))
                .andExpect(status().isBadRequest());
        mockMvc.perform(get("/api/v1/river/search").param("name", "a"))
                .andExpect(status().isBadRequest());
        mockMvc.perform(get("/api/v1/river/search").param("mli", "x".repeat(65)))
                .andExpect(status().isBadRequest());
        verify(queryRepository, never()).search(any(), any(), any(), any(), any(), anyInt());
    }
}
