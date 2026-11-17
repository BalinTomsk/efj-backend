package com.fishfind.docapi.web;

import com.fasterxml.jackson.databind.ObjectMapper;
import com.fishfind.docapi.repo.FollowRepository;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.autoconfigure.web.servlet.WebMvcTest;
import org.springframework.boot.test.mock.mockito.MockBean;
import org.springframework.http.MediaType;
import org.springframework.test.web.servlet.MockMvc;

import static org.mockito.ArgumentMatchers.anyBoolean;
import static org.mockito.ArgumentMatchers.anyInt;
import static org.mockito.ArgumentMatchers.anyString;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.verifyNoInteractions;
import static org.mockito.Mockito.when;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.header;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

@WebMvcTest(FollowController.class)
class FollowControllerTest {

    private static final String ME = "0190aaaa-0000-7000-8000-000000000001";
    private static final String LAKE = "0d012b12-849c-20c3-8532-2f7a21cfcc58";

    @Autowired
    private MockMvc mockMvc;

    @Autowired
    private ObjectMapper objectMapper;

    @MockBean
    private FollowRepository repository;

    @Test
    void everyRouteNeedsTheAccountCproxyNames() throws Exception {
        mockMvc.perform(get("/api/v1/follow/mine")).andExpect(status().isUnauthorized())
                .andExpect(jsonPath("$.error.code").value("sign_in_required"));
        mockMvc.perform(post("/api/v1/follow").contentType(MediaType.APPLICATION_JSON)
                        .content("{\"kind\":\"water\",\"id\":\"" + LAKE + "\",\"follow\":true}"))
                .andExpect(status().isUnauthorized());
        verifyNoInteractions(repository);
    }

    @Test
    void mineListsBothKindsUncached() throws Exception {
        when(repository.mine(ME)).thenReturn(objectMapper.readTree(
                "{\"waters\":[{\"lakeId\":\"" + LAKE + "\",\"lakeName\":\"Laurel Creek\"}],\"fish\":[]}"));
        mockMvc.perform(get("/api/v1/follow/mine").header("X-Fish-User", ME))
                .andExpect(status().isOk())
                .andExpect(header().string("Cache-Control", "no-store"))
                .andExpect(jsonPath("$.data.waters[0].lakeName").value("Laurel Creek"))
                .andExpect(jsonPath("$.data.fish").isEmpty());
    }

    @Test
    void followAndUnfollowNormalizeTheId() throws Exception {
        when(repository.set(ME, FollowRepository.WATER, LAKE, true)).thenReturn(FollowRepository.FOLLOWED);
        mockMvc.perform(post("/api/v1/follow").header("X-Fish-User", ME).contentType(MediaType.APPLICATION_JSON)
                        .content("{\"kind\":\"Water\",\"id\":\"0D012B12849C20C385322F7A21CFCC58\",\"follow\":true}"))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.data.following").value(true))
                .andExpect(jsonPath("$.data.id").value(LAKE));

        when(repository.set(ME, FollowRepository.FISH, LAKE, false)).thenReturn(FollowRepository.NOT_FOLLOWED);
        mockMvc.perform(post("/api/v1/follow").header("X-Fish-User", ME).contentType(MediaType.APPLICATION_JSON)
                        .content("{\"kind\":\"fish\",\"id\":\"" + LAKE + "\",\"follow\":false}"))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.data.following").value(false));
    }

    @Test
    void unknownTargetIs404AndTooManyIs409() throws Exception {
        when(repository.set(ME, FollowRepository.WATER, LAKE, true)).thenReturn(FollowRepository.INVALID);
        mockMvc.perform(post("/api/v1/follow").header("X-Fish-User", ME).contentType(MediaType.APPLICATION_JSON)
                        .content("{\"kind\":\"water\",\"id\":\"" + LAKE + "\",\"follow\":true}"))
                .andExpect(status().isNotFound());

        when(repository.set(ME, FollowRepository.WATER, LAKE, true)).thenReturn(FollowRepository.TOO_MANY);
        mockMvc.perform(post("/api/v1/follow").header("X-Fish-User", ME).contentType(MediaType.APPLICATION_JSON)
                        .content("{\"kind\":\"water\",\"id\":\"" + LAKE + "\",\"follow\":true}"))
                .andExpect(status().isConflict())
                .andExpect(jsonPath("$.error.code").value("too_many_follows"));
    }

    @Test
    void badBodiesAre400AndNeverQuery() throws Exception {
        for (String body : new String[] {
                "{\"kind\":\"lake\",\"id\":\"" + LAKE + "\",\"follow\":true}",
                "{\"kind\":\"water\",\"follow\":true}",
                "{\"kind\":\"water\",\"id\":\"not-a-guid\",\"follow\":true}",
                "{\"kind\":\"water\",\"id\":\"" + LAKE + "\",\"follow\":\"yes\"}",
                "[1]"}) {
            mockMvc.perform(post("/api/v1/follow").header("X-Fish-User", ME).contentType(MediaType.APPLICATION_JSON)
                            .content(body))
                    .andExpect(status().isBadRequest());
        }
        verify(repository, never()).set(anyString(), anyInt(), anyString(), anyBoolean());
    }
}
