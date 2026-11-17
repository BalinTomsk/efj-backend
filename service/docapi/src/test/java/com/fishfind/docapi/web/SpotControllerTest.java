package com.fishfind.docapi.web;

import com.fasterxml.jackson.databind.ObjectMapper;
import com.fishfind.docapi.repo.SpotRepository;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.autoconfigure.web.servlet.WebMvcTest;
import org.springframework.boot.test.mock.mockito.MockBean;
import org.springframework.http.MediaType;
import org.springframework.test.web.servlet.MockMvc;

import static org.mockito.ArgumentMatchers.anyDouble;
import static org.mockito.ArgumentMatchers.anyString;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.ArgumentMatchers.isNull;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.verifyNoInteractions;
import static org.mockito.Mockito.when;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.header;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

@WebMvcTest(SpotController.class)
class SpotControllerTest {

    private static final String ME = "0190aaaa-0000-7000-8000-000000000001";
    private static final String SPOT = "0190eeee-0000-7000-8000-000000000005";
    private static final String LAKE = "0d012b12-849c-20c3-8532-2f7a21cfcc58";

    @Autowired
    private MockMvc mockMvc;

    @Autowired
    private ObjectMapper objectMapper;

    @MockBean
    private SpotRepository repository;

    @Test
    void everyRouteNeedsTheAccountCproxyNames() throws Exception {
        mockMvc.perform(get("/api/v1/spot/mine")).andExpect(status().isUnauthorized())
                .andExpect(jsonPath("$.error.code").value("sign_in_required"));
        mockMvc.perform(post("/api/v1/spot/" + SPOT + "/delete")).andExpect(status().isUnauthorized());
        verifyNoInteractions(repository);
    }

    @Test
    void mineListsTheCallersSpotsUncached() throws Exception {
        when(repository.mine(ME)).thenReturn(objectMapper.readTree("[{\"spotId\":\"" + SPOT + "\",\"name\":\"Dock\"}]"));
        mockMvc.perform(get("/api/v1/spot/mine").header("X-Fish-User", ME))
                .andExpect(status().isOk())
                .andExpect(header().string("Cache-Control", "no-store"))
                .andExpect(jsonPath("$.data[0].name").value("Dock"));
    }

    @Test
    void saveCreatesWithTheClientsIdAndTrimsFields() throws Exception {
        when(repository.save(SPOT, ME, "Dock", 43.45, -80.49, LAKE, "Pike in May")).thenReturn(SpotRepository.INSERTED);
        mockMvc.perform(post("/api/v1/spot").header("X-Fish-User", ME).contentType(MediaType.APPLICATION_JSON)
                        .content("{\"spotId\":\"" + SPOT.toUpperCase() + "\",\"name\":\" Dock \",\"lat\":43.45,\"lon\":-80.49,"
                                + "\"lakeId\":\"" + LAKE + "\",\"note\":\"Pike in May\"}"))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.data.spotId").value(SPOT))
                .andExpect(jsonPath("$.data.created").value(true));
    }

    @Test
    void saveWithoutAnIdMakesOne() throws Exception {
        when(repository.save(anyString(), eq(ME), eq("Dock"), eq(1.0), eq(2.0), isNull(), isNull()))
                .thenReturn(SpotRepository.INSERTED);
        mockMvc.perform(post("/api/v1/spot").header("X-Fish-User", ME).contentType(MediaType.APPLICATION_JSON)
                        .content("{\"name\":\"Dock\",\"lat\":1,\"lon\":2}"))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.data.spotId").isNotEmpty());
    }

    @Test
    void badInputIsA400BeforeAnySql() throws Exception {
        String[] bodies = {"{\"lat\":1,\"lon\":2}", "{\"name\":\"x\",\"lat\":91,\"lon\":2}", "{\"name\":\"x\",\"lat\":1}",
                "{\"name\":\"x\",\"lat\":1,\"lon\":2,\"lakeId\":\"nope\"}", "[]"};
        for (String body : bodies) {
            mockMvc.perform(post("/api/v1/spot").header("X-Fish-User", ME).contentType(MediaType.APPLICATION_JSON).content(body))
                    .andExpect(status().isBadRequest());
        }
        verify(repository, never()).save(anyString(), anyString(), anyString(), anyDouble(), anyDouble(), any(), any());
    }

    @Test
    void anotherAccountsSpotIsNotFoundAndTheLimitIsAConflict() throws Exception {
        when(repository.save(eq(SPOT), eq(ME), anyString(), anyDouble(), anyDouble(), isNull(), isNull()))
                .thenReturn(SpotRepository.NOT_OWNER);
        mockMvc.perform(post("/api/v1/spot").header("X-Fish-User", ME).contentType(MediaType.APPLICATION_JSON)
                        .content("{\"spotId\":\"" + SPOT + "\",\"name\":\"x\",\"lat\":1,\"lon\":2}"))
                .andExpect(status().isNotFound());
        when(repository.save(eq(SPOT), eq(ME), anyString(), anyDouble(), anyDouble(), isNull(), isNull()))
                .thenReturn(SpotRepository.TOO_MANY);
        mockMvc.perform(post("/api/v1/spot").header("X-Fish-User", ME).contentType(MediaType.APPLICATION_JSON)
                        .content("{\"spotId\":\"" + SPOT + "\",\"name\":\"x\",\"lat\":1,\"lon\":2}"))
                .andExpect(status().isConflict())
                .andExpect(jsonPath("$.error.code").value("too_many_spots"));
    }

    @Test
    void deleteIsOwnerOnly() throws Exception {
        when(repository.delete(SPOT, ME)).thenReturn(true);
        mockMvc.perform(post("/api/v1/spot/" + SPOT + "/delete").header("X-Fish-User", ME))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.data.deleted").value(true));
        when(repository.delete(SPOT, ME)).thenReturn(false);
        mockMvc.perform(post("/api/v1/spot/" + SPOT + "/delete").header("X-Fish-User", ME))
                .andExpect(status().isNotFound());
    }

    private static <T> T any() {
        return org.mockito.ArgumentMatchers.any();
    }
}
