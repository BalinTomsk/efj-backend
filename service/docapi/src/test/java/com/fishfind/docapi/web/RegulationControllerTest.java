package com.fishfind.docapi.web;

import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.fishfind.docapi.repo.RegulationCommandRepository;
import com.fishfind.docapi.repo.RegulationQueryRepository;
import org.junit.jupiter.api.Test;
import org.mockito.ArgumentCaptor;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.autoconfigure.web.servlet.WebMvcTest;
import org.springframework.boot.test.mock.mockito.MockBean;
import org.springframework.test.web.servlet.MockMvc;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.ArgumentMatchers.anyString;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.patch;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

@WebMvcTest(RegulationController.class)
class RegulationControllerTest {

    @Autowired
    private MockMvc mockMvc;

    @Autowired
    private ObjectMapper objectMapper;

    @MockBean
    private RegulationQueryRepository queryRepository;

    @MockBean
    private RegulationCommandRepository commandRepository;

    // ---- GET /river/regulation/{guid} ----

    @Test
    void lakeRegulationReturnsTheDocumentNestedInTheEnvelope() throws Exception {
        when(queryRepository.lakeRegulation("0c5343a8-849c-20c3-f4d1-0003eb237498")).thenReturn(
                objectMapper.readTree("{\"guid\":\"0C5343A8-…\",\"lakeName\":\"Undersill Lake\",\"regulations\":[]}"));

        mockMvc.perform(get("/api/v1/river/regulation/0c5343a8-849c-20c3-f4d1-0003eb237498"))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.data.lakeName").value("Undersill Lake"))
                .andExpect(jsonPath("$.error").doesNotExist());
    }

    @Test
    void lakeRegulationUnknownGuidReturns404() throws Exception {
        when(queryRepository.lakeRegulation("00000000-0000-0000-0000-000000000000")).thenReturn(null);

        mockMvc.perform(get("/api/v1/river/regulation/00000000-0000-0000-0000-000000000000"))
                .andExpect(status().isNotFound())
                .andExpect(jsonPath("$.error.code").value("not_found"));
    }

    // ---- PATCH /river/regulation/{guid} ----

    @Test
    void patchLakeRegulationInjectsLakeIdFromThePathAndStripsZoneId() throws Exception {
        when(commandRepository.upsert(anyString()))
                .thenReturn(objectMapper.readTree("{\"id\":1,\"action\":\"inserted\",\"scope\":\"waterBody\"}"));

        mockMvc.perform(patch("/api/v1/river/regulation/0c5343a8-849c-20c3-f4d1-0003eb237498")
                        .contentType("application/json")
                        // zoneId here should be stripped -- lakeId from the path always wins the scope
                        .content("{\"lakeId\":\"attacker-supplied\",\"zoneId\":99,\"year\":2026,\"sport\":4}"))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.data.action").value("inserted"))
                .andExpect(jsonPath("$.data.scope").value("waterBody"));

        ArgumentCaptor<String> sent = ArgumentCaptor.forClass(String.class);
        verify(commandRepository).upsert(sent.capture());
        JsonNode body = objectMapper.readTree(sent.getValue());
        assertThat(body.get("lakeId").asText()).isEqualTo("0c5343a8-849c-20c3-f4d1-0003eb237498");
        assertThat(body.has("zoneId")).isFalse();
        assertThat(body.get("year").asInt()).isEqualTo(2026);
        assertThat(body.get("sport").asInt()).isEqualTo(4);
    }

    @Test
    void patchLakeRegulationMissingBodyReturns400() throws Exception {
        mockMvc.perform(patch("/api/v1/river/regulation/0c5343a8-849c-20c3-f4d1-0003eb237498")
                        .contentType("application/json"))
                .andExpect(status().isBadRequest())
                .andExpect(jsonPath("$.error.code").value("invalid_document"));

        verify(commandRepository, never()).upsert(anyString());
    }

    @Test
    void patchLakeRegulationArrayBodyReturns400() throws Exception {
        mockMvc.perform(patch("/api/v1/river/regulation/0c5343a8-849c-20c3-f4d1-0003eb237498")
                        .contentType("application/json").content("[{\"year\":2026}]"))
                .andExpect(status().isBadRequest())
                .andExpect(jsonPath("$.error.code").value("invalid_document"));
    }

    // ---- GET /region/regulation/{country}[/{state}] ----

    @Test
    void regionRegulationCountryOnlyQueriesWithNullState() throws Exception {
        when(queryRepository.region("US", null)).thenReturn(
                objectMapper.readTree("{\"country\":\"US\",\"state\":null,\"regulations\":[]}"));

        mockMvc.perform(get("/api/v1/region/regulation/us"))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.data.country").value("US"));

        verify(queryRepository).region("US", null);
    }

    @Test
    void regionRegulationCountryAndStateAreUpperCased() throws Exception {
        when(queryRepository.region("CA", "ON")).thenReturn(
                objectMapper.readTree("{\"country\":\"CA\",\"state\":\"ON\",\"regulations\":[]}"));

        mockMvc.perform(get("/api/v1/region/regulation/ca/on"))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.data.state").value("ON"));

        verify(queryRepository).region("CA", "ON");
    }

    @Test
    void regionRegulationInvalidCountryReturns400() throws Exception {
        mockMvc.perform(get("/api/v1/region/regulation/usa"))
                .andExpect(status().isBadRequest())
                .andExpect(jsonPath("$.error.code").value("invalid_document"));
    }

    // ---- PATCH /region/regulation/{country}[/{state}] ----

    @Test
    void patchRegionRegulationCountryOnlyStripsStateZoneAndLake() throws Exception {
        when(commandRepository.upsert(anyString()))
                .thenReturn(objectMapper.readTree("{\"id\":2,\"action\":\"inserted\",\"scope\":\"region\"}"));

        mockMvc.perform(patch("/api/v1/region/regulation/us")
                        .contentType("application/json")
                        .content("{\"state\":\"attacker\",\"zoneId\":5,\"lakeId\":\"x\",\"year\":2026,\"sport\":5}"))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.data.scope").value("region"));

        ArgumentCaptor<String> sent = ArgumentCaptor.forClass(String.class);
        verify(commandRepository).upsert(sent.capture());
        JsonNode body = objectMapper.readTree(sent.getValue());
        assertThat(body.get("country").asText()).isEqualTo("US");
        assertThat(body.has("state")).isFalse();
        assertThat(body.has("zoneId")).isFalse();
        assertThat(body.has("lakeId")).isFalse();
    }

    @Test
    void patchRegionRegulationCountryAndStateSetsBoth() throws Exception {
        when(commandRepository.upsert(anyString()))
                .thenReturn(objectMapper.readTree("{\"id\":3,\"action\":\"inserted\",\"scope\":\"region\"}"));

        mockMvc.perform(patch("/api/v1/region/regulation/ca/on")
                        .contentType("application/json")
                        .content("{\"year\":2026,\"sport\":3}"))
                .andExpect(status().isOk());

        ArgumentCaptor<String> sent = ArgumentCaptor.forClass(String.class);
        verify(commandRepository).upsert(sent.capture());
        JsonNode body = objectMapper.readTree(sent.getValue());
        assertThat(body.get("country").asText()).isEqualTo("CA");
        assertThat(body.get("state").asText()).isEqualTo("ON");
    }

    @Test
    void patchRegionRegulationInvalidStateReturns400() throws Exception {
        mockMvc.perform(patch("/api/v1/region/regulation/ca/ontario")
                        .contentType("application/json").content("{\"year\":2026}"))
                .andExpect(status().isBadRequest())
                .andExpect(jsonPath("$.error.code").value("invalid_document"));

        verify(commandRepository, never()).upsert(anyString());
    }
}
