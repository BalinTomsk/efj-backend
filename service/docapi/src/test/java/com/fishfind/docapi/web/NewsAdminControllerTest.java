package com.fishfind.docapi.web;

import com.fishfind.docapi.repo.NewsAdminCommandRepository;
import com.fishfind.docapi.repo.NewsAdminCommandRepository.NewsAdminPublishRequest;
import com.fishfind.docapi.repo.NewsAdminCommandRepository.PhotoUpdateResult;
import com.fishfind.docapi.repo.NewsAdminCommandRepository.PublishResult;
import com.fishfind.docapi.repo.NewsDocumentCache;
import com.fishfind.docapi.repo.NewsQueryCache;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.autoconfigure.web.servlet.WebMvcTest;
import org.springframework.boot.test.mock.mockito.MockBean;
import org.springframework.test.web.servlet.MockMvc;

import java.sql.Timestamp;
import java.time.Instant;
import java.time.temporal.ChronoUnit;
import java.util.Base64;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.within;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.anyInt;
import static org.mockito.ArgumentMatchers.anyString;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.patch;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

@WebMvcTest(NewsAdminController.class)
class NewsAdminControllerTest {

    private static final String ID = "0c5343a8-849c-20c3-f4d1-0003eb237498";

    @Autowired
    private MockMvc mockMvc;

    @MockBean
    private NewsAdminCommandRepository commandRepository;

    @MockBean
    private NewsQueryCache queryRepository;

    @MockBean(name = "newsStore")
    private NewsDocumentCache newsStore;

    // ---- POST /draft ----

    @Test
    void createDraftReturns201WithTheNewId() throws Exception {
        when(commandRepository.createDraft()).thenReturn(ID);

        mockMvc.perform(post("/api/v1/news/admin/draft"))
                .andExpect(status().isCreated())
                .andExpect(jsonPath("$.data.id").value(ID))
                .andExpect(jsonPath("$.error").doesNotExist());
    }

    // ---- PATCH /{id} (publish) ----

    @Test
    void publishMapsEveryFieldAndReturnsTheResult() throws Exception {
        when(commandRepository.publish(any())).thenReturn(new PublishResult(ID, "updated"));

        String body = "{"
                + "\"title\":\"A Title\",\"author\":\"An Author\",\"source\":\"A Source\","
                + "\"sourceLink\":\"https://s.example\",\"authorLink\":\"https://a.example\","
                + "\"stamp\":\"2026-01-02T03:04:05\",\"videoLink\":\"https://v.example\","
                + "\"paragraph0\":\"P0\",\"paragraph1\":\"P1\",\"paragraph2\":\"P2\",\"country\":\"CA\","
                + "\"lakeId\":\"b0000000-0000-0000-0000-00000000000b\","
                + "\"fish1Id\":\"f1000000-0000-0000-0000-0000000000f1\","
                + "\"fish2Id\":\"not-a-guid\"}";

        mockMvc.perform(patch("/api/v1/news/admin/" + ID)
                        .contentType("application/json").content(body))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.data.id").value(ID))
                .andExpect(jsonPath("$.data.action").value("updated"))
                .andExpect(jsonPath("$.error").doesNotExist());

        org.mockito.ArgumentCaptor<NewsAdminPublishRequest> captor =
                org.mockito.ArgumentCaptor.forClass(NewsAdminPublishRequest.class);
        verify(commandRepository).publish(captor.capture());
        NewsAdminPublishRequest r = captor.getValue();
        assertThat(r.newsId()).isEqualTo(ID);
        assertThat(r.title()).isEqualTo("A Title");
        assertThat(r.author()).isEqualTo("An Author");
        assertThat(r.source()).isEqualTo("A Source");
        assertThat(r.sourceLink()).isEqualTo("https://s.example");
        assertThat(r.authorLink()).isEqualTo("https://a.example");
        assertThat(r.stamp()).isEqualTo(Timestamp.valueOf("2026-01-02 03:04:05"));
        assertThat(r.videoLink()).isEqualTo("https://v.example");
        assertThat(r.paragraph0()).isEqualTo("P0");
        assertThat(r.paragraph1()).isEqualTo("P1");
        assertThat(r.paragraph2()).isEqualTo("P2");
        assertThat(r.country()).isEqualTo("CA");
        assertThat(r.lakeId()).isEqualTo("b0000000-0000-0000-0000-00000000000b");
        assertThat(r.fish1Id()).isEqualTo("f1000000-0000-0000-0000-0000000000f1");
        // "not-a-guid" is not a canonical GUID, so it is dropped rather than stored verbatim.
        assertThat(r.fish2Id()).isNull();
        assertThat(r.fish3Id()).isNull();
    }

    @Test
    void publishEvictsBothNewsCachesOnSuccess() throws Exception {
        when(commandRepository.publish(any())).thenReturn(new PublishResult(ID, "updated"));

        mockMvc.perform(patch("/api/v1/news/admin/" + ID)
                        .contentType("application/json").content("{\"title\":\"A Title\"}"))
                .andExpect(status().isOk());

        verify(queryRepository).clear();
        verify(newsStore).clear();
    }

    @Test
    void publishMissingTitleIs400AndRepositoryIsNeverCalled() throws Exception {
        mockMvc.perform(patch("/api/v1/news/admin/" + ID)
                        .contentType("application/json").content("{\"author\":\"An Author\"}"))
                .andExpect(status().isBadRequest())
                .andExpect(jsonPath("$.error.code").value("invalid_document"))
                .andExpect(jsonPath("$.data").doesNotExist());
        verify(commandRepository, never()).publish(any());
    }

    @Test
    void publishBlankTitleIs400() throws Exception {
        mockMvc.perform(patch("/api/v1/news/admin/" + ID)
                        .contentType("application/json").content("{\"title\":\"   \"}"))
                .andExpect(status().isBadRequest());
        verify(commandRepository, never()).publish(any());
    }

    @Test
    void publishMissingBodyIs400() throws Exception {
        mockMvc.perform(patch("/api/v1/news/admin/" + ID).contentType("application/json"))
                .andExpect(status().isBadRequest());
        verify(commandRepository, never()).publish(any());
    }

    @Test
    void publishMalformedJsonIs400() throws Exception {
        mockMvc.perform(patch("/api/v1/news/admin/" + ID)
                        .contentType("application/json").content("{not json"))
                .andExpect(status().isBadRequest());
        verify(commandRepository, never()).publish(any());
    }

    @Test
    void publishInvalidIdIs400() throws Exception {
        mockMvc.perform(patch("/api/v1/news/admin/not-a-guid")
                        .contentType("application/json").content("{\"title\":\"A Title\"}"))
                .andExpect(status().isBadRequest());
        verify(commandRepository, never()).publish(any());
    }

    @Test
    void publishMissingStampDefaultsToNow() throws Exception {
        when(commandRepository.publish(any())).thenReturn(new PublishResult(ID, "inserted"));

        mockMvc.perform(patch("/api/v1/news/admin/" + ID)
                        .contentType("application/json").content("{\"title\":\"A Title\"}"))
                .andExpect(status().isOk());

        org.mockito.ArgumentCaptor<NewsAdminPublishRequest> captor =
                org.mockito.ArgumentCaptor.forClass(NewsAdminPublishRequest.class);
        verify(commandRepository).publish(captor.capture());
        Instant stamp = captor.getValue().stamp().toInstant();
        assertThat(stamp).isCloseTo(Instant.now(), within(30, ChronoUnit.SECONDS));
    }

    @Test
    void publishFutureStampIsClampedToNow() throws Exception {
        when(commandRepository.publish(any())).thenReturn(new PublishResult(ID, "inserted"));

        mockMvc.perform(patch("/api/v1/news/admin/" + ID)
                        .contentType("application/json")
                        .content("{\"title\":\"A Title\",\"stamp\":\"2099-01-01T00:00:00\"}"))
                .andExpect(status().isOk());

        org.mockito.ArgumentCaptor<NewsAdminPublishRequest> captor =
                org.mockito.ArgumentCaptor.forClass(NewsAdminPublishRequest.class);
        verify(commandRepository).publish(captor.capture());
        Instant stamp = captor.getValue().stamp().toInstant();
        assertThat(stamp).isCloseTo(Instant.now(), within(30, ChronoUnit.SECONDS));
    }

    // ---- PATCH /{id}/photo/{index} ----

    @Test
    void photoUpdateDecodesBase64AndReturnsTheResult() throws Exception {
        when(commandRepository.updatePhoto(eq(ID), eq(0), any(), eq("Credit"), eq("Alt Text")))
                .thenReturn(new PhotoUpdateResult(true, true));

        byte[] bytes = {(byte) 0x89, 0x50, 0x4E, 0x47};
        String body = "{\"photoBase64\":\"" + Base64.getEncoder().encodeToString(bytes)
                + "\",\"author\":\"Credit\",\"alt\":\"Alt Text\"}";

        mockMvc.perform(patch("/api/v1/news/admin/" + ID + "/photo/0")
                        .contentType("application/json").content(body))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.data.id").value(ID))
                .andExpect(jsonPath("$.data.index").value(0))
                .andExpect(jsonPath("$.data.updated").value(true));

        org.mockito.ArgumentCaptor<byte[]> photoCaptor = org.mockito.ArgumentCaptor.forClass(byte[].class);
        verify(commandRepository).updatePhoto(eq(ID), eq(0), photoCaptor.capture(), eq("Credit"), eq("Alt Text"));
        assertThat(photoCaptor.getValue()).isEqualTo(bytes);
    }

    @Test
    void photoUpdateOmittedAuthorAndAltArePassedAsNull() throws Exception {
        when(commandRepository.updatePhoto(eq(ID), eq(1), any(), eq(null), eq(null)))
                .thenReturn(new PhotoUpdateResult(true, true));

        mockMvc.perform(patch("/api/v1/news/admin/" + ID + "/photo/1")
                        .contentType("application/json").content("{\"photoBase64\":\"AAAA\"}"))
                .andExpect(status().isOk());

        verify(commandRepository).updatePhoto(eq(ID), eq(1), any(), eq(null), eq(null));
    }

    @Test
    void photoUpdateEvictsBothNewsCachesOnSuccess() throws Exception {
        when(commandRepository.updatePhoto(eq(ID), eq(0), any(), any(), any()))
                .thenReturn(new PhotoUpdateResult(true, true));

        mockMvc.perform(patch("/api/v1/news/admin/" + ID + "/photo/0")
                        .contentType("application/json").content("{\"photoBase64\":\"AAAA\"}"))
                .andExpect(status().isOk());

        verify(queryRepository).clear();
        verify(newsStore).clear();
    }

    @Test
    void photoUpdateUnknownIdDoesNotEvictCaches() throws Exception {
        when(commandRepository.updatePhoto(eq(ID), eq(0), any(), any(), any()))
                .thenReturn(new PhotoUpdateResult(false, false));

        mockMvc.perform(patch("/api/v1/news/admin/" + ID + "/photo/0")
                        .contentType("application/json").content("{\"photoBase64\":\"AAAA\"}"))
                .andExpect(status().isNotFound());

        verify(queryRepository, never()).clear();
        verify(newsStore, never()).clear();
    }

    @Test
    void photoUpdateOutOfRangeIndexIs400AndRepositoryIsNeverCalled() throws Exception {
        mockMvc.perform(patch("/api/v1/news/admin/" + ID + "/photo/3")
                        .contentType("application/json").content("{\"photoBase64\":\"AAAA\"}"))
                .andExpect(status().isBadRequest());
        verify(commandRepository, never()).updatePhoto(anyString(), anyInt(), any(), any(), any());
    }

    @Test
    void photoUpdateMissingPhotoBase64Is400() throws Exception {
        mockMvc.perform(patch("/api/v1/news/admin/" + ID + "/photo/0")
                        .contentType("application/json").content("{}"))
                .andExpect(status().isBadRequest());
        verify(commandRepository, never()).updatePhoto(anyString(), anyInt(), any(), any(), any());
    }

    @Test
    void photoUpdateInvalidBase64Is400() throws Exception {
        mockMvc.perform(patch("/api/v1/news/admin/" + ID + "/photo/0")
                        .contentType("application/json").content("{\"photoBase64\":\"not base64!!\"}"))
                .andExpect(status().isBadRequest());
        verify(commandRepository, never()).updatePhoto(anyString(), anyInt(), any(), any(), any());
    }

    @Test
    void photoUpdateUnknownIdIs404() throws Exception {
        when(commandRepository.updatePhoto(eq(ID), eq(0), any(), any(), any()))
                .thenReturn(new PhotoUpdateResult(false, false));

        mockMvc.perform(patch("/api/v1/news/admin/" + ID + "/photo/0")
                        .contentType("application/json").content("{\"photoBase64\":\"AAAA\"}"))
                .andExpect(status().isNotFound())
                .andExpect(jsonPath("$.error.code").value("not_found"));
    }

    @Test
    void photoUpdateInvalidIdIs400() throws Exception {
        mockMvc.perform(patch("/api/v1/news/admin/not-a-guid/photo/0")
                        .contentType("application/json").content("{\"photoBase64\":\"AAAA\"}"))
                .andExpect(status().isBadRequest());
        verify(commandRepository, never()).updatePhoto(anyString(), anyInt(), any(), any(), any());
    }
}
