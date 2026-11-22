package com.fishfind.docapi.web;

import com.fasterxml.jackson.databind.ObjectMapper;
import com.fasterxml.jackson.databind.node.ObjectNode;
import com.fishfind.docapi.repo.CatchLog;
import com.fishfind.docapi.repo.CatchLogCommandRepository;
import org.junit.jupiter.api.Test;
import org.mockito.ArgumentCaptor;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.autoconfigure.web.servlet.WebMvcTest;
import org.springframework.boot.test.mock.mockito.MockBean;
import org.springframework.http.MediaType;
import org.springframework.test.web.servlet.MockMvc;

import java.time.LocalDate;

import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.anyInt;
import static org.mockito.ArgumentMatchers.anyString;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.verifyNoInteractions;
import static org.mockito.Mockito.when;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.patch;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.content;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.header;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

@WebMvcTest(CatchLogController.class)
class CatchLogControllerTest {

    private static final String ME = "0190aaaa-0000-7000-8000-000000000001";
    private static final String OTHER = "0190bbbb-0000-7000-8000-000000000002";
    private static final String LAKE = "0d012b12-849c-20c3-8532-2f7a21cfcc58";
    private static final String MEMO = "0190cccc-0000-7000-8000-000000000003";
    private static final String PHOTO = "0190dddd-0000-7000-8000-000000000004";
    private static final byte[] JPEG = {(byte) 0xFF, (byte) 0xD8, (byte) 0xFF, 0x01, 0x02};

    @Autowired
    private MockMvc mockMvc;

    @Autowired
    private ObjectMapper objectMapper;

    @MockBean
    private CatchLogCommandRepository repository;

    private CatchLog logBy(String userId) {
        return new CatchLog(MEMO, LAKE, userId, null, "Walleye", null, null, null, null, null, null, null, null,
                null, null, null, null, null, null, false, CatchLog.Weather.NONE);
    }

    @Test
    void everyRouteNeedsTheAccountCproxyNames() throws Exception {
        mockMvc.perform(get("/api/v1/catch/mine"))
                .andExpect(status().isUnauthorized())
                .andExpect(jsonPath("$.error.code").value("sign_in_required"));
        mockMvc.perform(post("/api/v1/catch").contentType(MediaType.APPLICATION_JSON).content("{\"lakeId\":\"" + LAKE + "\"}"))
                .andExpect(status().isUnauthorized());
        mockMvc.perform(get("/api/v1/catch/mine").header("X-Fish-User", "not-a-guid"))
                .andExpect(status().isUnauthorized());
        verifyNoInteractions(repository);
    }

    @Test
    void mineListsTheCallersLogsUncached() throws Exception {
        when(repository.mine(ME, 50)).thenReturn(objectMapper.readTree("[{\"catchLogId\":\"" + MEMO + "\"}]"));

        mockMvc.perform(get("/api/v1/catch/mine").header("X-Fish-User", ME.toUpperCase()))
                .andExpect(status().isOk())
                .andExpect(header().string("Cache-Control", "no-store"))
                .andExpect(jsonPath("$.data[0].catchLogId").value(MEMO));
        mockMvc.perform(get("/api/v1/catch/mine").header("X-Fish-User", ME).param("limit", "9999"));
        verify(repository).mine(ME, CatchLogController.MAX_LIMIT);
    }

    @Test
    void addStoresANewLogUnderTheCallerWithStationWeather() throws Exception {
        ObjectNode stored = objectMapper.createObjectNode().put("catchLogId", MEMO);
        when(repository.add(any())).thenReturn(stored);
        when(repository.stationWeather(eq(LAKE), any()))
                .thenReturn(new CatchLog.Weather(21.0, 1012.0, "Clear", "01d", null));

        mockMvc.perform(post("/api/v1/catch").header("X-Fish-User", ME).contentType(MediaType.APPLICATION_JSON)
                        .content("{\"lakeId\":\"" + LAKE + "\",\"species\":\"Walleye\",\"catchDate\":\"2026-11-15\","
                                + "\"weight\":2.4,\"weightUnit\":\"kg\",\"released\":true,\"lat\":43.4,\"lon\":-80.5}"))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.data.catchLogId").value(MEMO))
                .andExpect(jsonPath("$.data.stationWeather[0]").value("airTemp"));

        ArgumentCaptor<CatchLog> saved = ArgumentCaptor.forClass(CatchLog.class);
        verify(repository).add(saved.capture());
        CatchLog log = saved.getValue();
        org.junit.jupiter.api.Assertions.assertEquals(ME, log.userId());
        org.junit.jupiter.api.Assertions.assertEquals(LAKE, log.lakeId());
        org.junit.jupiter.api.Assertions.assertEquals(2.4, log.weight());
        org.junit.jupiter.api.Assertions.assertEquals(21.0, log.weather().temp());
        org.junit.jupiter.api.Assertions.assertEquals("Clear", log.weather().text());
        verify(repository).stationWeather(LAKE, LocalDate.of(2026, 11, 15));
    }

    @Test
    void addRefusesBadFieldsBeforeAnyWrite() throws Exception {
        mockMvc.perform(post("/api/v1/catch").header("X-Fish-User", ME).contentType(MediaType.APPLICATION_JSON)
                        .content("{\"lakeId\":\"" + LAKE + "\",\"weight\":2}"))
                .andExpect(status().isBadRequest())
                .andExpect(jsonPath("$.error.message").value("weightUnit is required with weight"));
        mockMvc.perform(post("/api/v1/catch").header("X-Fish-User", ME).contentType(MediaType.APPLICATION_JSON)
                        .content("{\"species\":\"Walleye\"}"))
                .andExpect(status().isBadRequest());
        verify(repository, never()).add(any());
    }

    @Test
    void addOnAMissingWaterBodyIs404() throws Exception {
        when(repository.add(any())).thenReturn(null);
        mockMvc.perform(post("/api/v1/catch").header("X-Fish-User", ME).contentType(MediaType.APPLICATION_JSON)
                        .content("{\"lakeId\":\"" + LAKE + "\"}"))
                .andExpect(status().isNotFound());
    }

    @Test
    void aPhotoGoesOnTheCallersOwnOpenLog() throws Exception {
        when(repository.canEdit(MEMO, ME)).thenReturn(true);
        when(repository.photoCount(MEMO)).thenReturn(1);
        ObjectNode stored = objectMapper.createObjectNode().put("catchLogId", MEMO).put("imageCount", 2);
        when(repository.addPhoto(MEMO, ME, JPEG, 1, "On the dock", null)).thenReturn(stored);

        mockMvc.perform(post("/api/v1/catch/" + MEMO + "/photo").header("X-Fish-User", ME)
                        .param("caption", " On the dock ").contentType(MediaType.IMAGE_JPEG).content(JPEG))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.data.imageCount").value(2));
    }

    @Test
    void someoneElsesLogIsNotFoundAndALockedOneIsForbidden() throws Exception {
        when(repository.canEdit(MEMO, ME)).thenReturn(false);
        when(repository.find(MEMO)).thenReturn(logBy(OTHER));
        mockMvc.perform(post("/api/v1/catch/" + MEMO + "/photo").header("X-Fish-User", ME)
                        .contentType(MediaType.IMAGE_JPEG).content(JPEG))
                .andExpect(status().isNotFound());

        when(repository.find(MEMO)).thenReturn(logBy(ME));
        mockMvc.perform(post("/api/v1/catch/" + MEMO + "/photo").header("X-Fish-User", ME)
                        .contentType(MediaType.IMAGE_JPEG).content(JPEG))
                .andExpect(status().isForbidden())
                .andExpect(jsonPath("$.error.code").value("locked"));
        verify(repository, never()).addPhoto(anyString(), anyString(), any(), anyInt(), any(), any());
    }

    @Test
    void aFourthPhotoOrANonJpegIsRefused() throws Exception {
        when(repository.canEdit(MEMO, ME)).thenReturn(true);
        when(repository.photoCount(MEMO)).thenReturn(3);
        mockMvc.perform(post("/api/v1/catch/" + MEMO + "/photo").header("X-Fish-User", ME)
                        .contentType(MediaType.IMAGE_JPEG).content(JPEG))
                .andExpect(status().isConflict());
        mockMvc.perform(post("/api/v1/catch/" + MEMO + "/photo").header("X-Fish-User", ME)
                        .contentType(MediaType.IMAGE_JPEG).content(new byte[]{1, 2, 3}))
                .andExpect(status().isBadRequest());
        verify(repository, never()).addPhoto(anyString(), anyString(), any(), anyInt(), any(), any());
    }

    @Test
    void onlyTheAuthorGetsAPhotosBytes() throws Exception {
        when(repository.find(MEMO)).thenReturn(logBy(ME));
        when(repository.photo(MEMO, PHOTO)).thenReturn(JPEG);
        mockMvc.perform(get("/api/v1/catch/photo/" + MEMO + "/" + PHOTO).header("X-Fish-User", ME))
                .andExpect(status().isOk())
                .andExpect(header().string("Content-Type", "image/jpeg"))
                .andExpect(content().bytes(JPEG));

        mockMvc.perform(get("/api/v1/catch/photo/" + MEMO + "/" + PHOTO).header("X-Fish-User", OTHER))
                .andExpect(status().isNotFound());
    }

    @Test
    void aPngPhotoIsStoredAsAJpeg() throws Exception {
        when(repository.canEdit(MEMO, ME)).thenReturn(true);
        when(repository.photoCount(MEMO)).thenReturn(0);
        when(repository.addPhoto(eq(MEMO), eq(ME), any(), eq(0), any(), eq("Wired2Fish")))
                .thenReturn(objectMapper.createObjectNode().put("catchLogId", MEMO).put("imageCount", 1));
        java.io.ByteArrayOutputStream png = new java.io.ByteArrayOutputStream();
        javax.imageio.ImageIO.write(new java.awt.image.BufferedImage(3, 2, java.awt.image.BufferedImage.TYPE_INT_ARGB), "png", png);

        mockMvc.perform(post("/api/v1/catch/" + MEMO + "/photo").header("X-Fish-User", ME).param("credit", "Wired2Fish")
                        .contentType(MediaType.IMAGE_PNG).content(png.toByteArray()))
                .andExpect(status().isOk());
        ArgumentCaptor<byte[]> stored = ArgumentCaptor.forClass(byte[].class);
        verify(repository).addPhoto(eq(MEMO), eq(ME), stored.capture(), eq(0), any(), eq("Wired2Fish"));
        org.junit.jupiter.api.Assertions.assertTrue(CatchPhotoImage.isJpeg(stored.getValue()));
    }

    @Test
    void patchChangesOnlyTheGivenFieldsOfTheCallersOpenLog() throws Exception {
        when(repository.find(MEMO)).thenReturn(logBy(ME));
        when(repository.canEdit(MEMO, ME)).thenReturn(true);
        when(repository.add(any())).thenReturn(objectMapper.createObjectNode().put("catchLogId", MEMO));

        mockMvc.perform(patch("/api/v1/catch/" + MEMO).header("X-Fish-User", ME)
                        .contentType(MediaType.APPLICATION_JSON).content("{\"weight\":2.5,\"weightUnit\":\"kg\",\"species\":null}"))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.data.catchLogId").value(MEMO));
        ArgumentCaptor<CatchLog> saved = ArgumentCaptor.forClass(CatchLog.class);
        verify(repository).add(saved.capture());
        org.junit.jupiter.api.Assertions.assertEquals(2.5, saved.getValue().weight());
        org.junit.jupiter.api.Assertions.assertNull(saved.getValue().species());
        org.junit.jupiter.api.Assertions.assertEquals(LAKE, saved.getValue().lakeId());
        org.junit.jupiter.api.Assertions.assertEquals(ME, saved.getValue().userId());
    }

    @Test
    void patchRefusesSomeoneElsesLockedOrMalformedChanges() throws Exception {
        when(repository.find(MEMO)).thenReturn(logBy(OTHER));
        mockMvc.perform(patch("/api/v1/catch/" + MEMO).header("X-Fish-User", ME)
                        .contentType(MediaType.APPLICATION_JSON).content("{\"title\":\"x\"}"))
                .andExpect(status().isNotFound());

        when(repository.find(MEMO)).thenReturn(logBy(ME));
        when(repository.canEdit(MEMO, ME)).thenReturn(false);
        mockMvc.perform(patch("/api/v1/catch/" + MEMO).header("X-Fish-User", ME)
                        .contentType(MediaType.APPLICATION_JSON).content("{\"title\":\"x\"}"))
                .andExpect(status().isForbidden());

        when(repository.canEdit(MEMO, ME)).thenReturn(true);
        mockMvc.perform(patch("/api/v1/catch/" + MEMO).header("X-Fish-User", ME)
                        .contentType(MediaType.APPLICATION_JSON).content("{\"weight\":2.5}"))
                .andExpect(status().isBadRequest());
        mockMvc.perform(patch("/api/v1/catch/" + MEMO).header("X-Fish-User", ME)
                        .contentType(MediaType.APPLICATION_JSON).content("{\"lakeId\":\"" + LAKE + "\"}"))
                .andExpect(status().isBadRequest());
        mockMvc.perform(patch("/api/v1/catch/" + MEMO).contentType(MediaType.APPLICATION_JSON).content("{}"))
                .andExpect(status().isUnauthorized());
        verify(repository, never()).add(any());
    }
}
