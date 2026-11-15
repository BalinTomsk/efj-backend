package com.fishfind.docapi.web;

import com.fasterxml.jackson.databind.ObjectMapper;
import com.fishfind.docapi.repo.NewsNearRepository;
import com.fishfind.docapi.repo.NewsNearRepository.TaggedNews;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.autoconfigure.web.servlet.WebMvcTest;
import org.springframework.boot.test.mock.mockito.MockBean;
import org.springframework.test.annotation.DirtiesContext;
import org.springframework.test.web.servlet.MockMvc;

import java.util.List;

import static org.hamcrest.Matchers.containsString;
import static org.mockito.ArgumentMatchers.anyDouble;
import static org.mockito.ArgumentMatchers.anyInt;
import static org.mockito.ArgumentMatchers.anyString;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.times;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.verifyNoInteractions;
import static org.mockito.Mockito.when;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.header;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

// The controller caches answers and the tagged list for 5 minutes: a fresh context per test keeps tests apart.
@WebMvcTest(NewsNearController.class)
@DirtiesContext(classMode = DirtiesContext.ClassMode.AFTER_EACH_TEST_METHOD)
class NewsNearControllerTest {

    private static final String NEAR_LAKE = "0c44dfc7-849c-20c3-9db6-f2c06fc97a1f";
    private static final String MID_LAKE = "fc0d917b-d053-11d8-92e2-080020a0f4c9";
    private static final String FAR_LAKE = "11111111-2222-3333-4444-555555555555";

    @Autowired
    private MockMvc mockMvc;

    @Autowired
    private ObjectMapper objectMapper;

    @MockBean
    private NewsNearRepository repository;

    private void stories() throws Exception {
        when(repository.taggedNews(NewsNearController.TAGGED_WINDOW)).thenReturn(List.of(
                new TaggedNews("n1", "Newest, on the river", "src", "2026-11-14", "CA", MID_LAKE.toUpperCase()),
                new TaggedNews("n2", "On the creek", "src", "2026-11-10", "CA", NEAR_LAKE),
                new TaggedNews("n3", "Far away", "src", "2026-11-09", "US", FAR_LAKE),
                new TaggedNews("n4", "Older, on the river", "src", "2026-10-01", "CA", MID_LAKE)));
        when(repository.lakesNear(anyString(), eq(43.45), eq(-80.49), eq(100))).thenReturn(objectMapper.readTree(
                "[{\"lakeId\":\"" + NEAR_LAKE.toUpperCase() + "\",\"lakeName\":\"Laurel Creek\",\"distanceKm\":3.1},"
                        + "{\"lakeId\":\"" + MID_LAKE.toUpperCase() + "\",\"lakeName\":\"Grand River\",\"distanceKm\":4.0}]"));
    }

    @Test
    void nearestWaterBodyFirstThenNewestStory() throws Exception {
        stories();

        mockMvc.perform(get("/api/v1/news/near").param("lat", "43.4512").param("lon", "-80.4899"))
                .andExpect(status().isOk())
                .andExpect(header().string("Cache-Control", "max-age=300, private"))
                .andExpect(jsonPath("$.data.lat").value(43.45))
                .andExpect(jsonPath("$.data.radiusKm").value(100))
                .andExpect(jsonPath("$.data.total").value(3))
                .andExpect(jsonPath("$.data.items[0].newsId").value("n2"))
                .andExpect(jsonPath("$.data.items[0].lakeName").value("Laurel Creek"))
                .andExpect(jsonPath("$.data.items[0].distanceKm").value(3.1))
                .andExpect(jsonPath("$.data.items[1].newsId").value("n1"))
                .andExpect(jsonPath("$.data.items[2].newsId").value("n4"))
                .andExpect(jsonPath("$.data.items.length()").value(3));
    }

    @Test
    void sendsEachWaterBodyOnceAndCachesTheAnswer() throws Exception {
        stories();

        mockMvc.perform(get("/api/v1/news/near").param("lat", "43.45").param("lon", "-80.49").param("limit", "2"))
                .andExpect(jsonPath("$.data.items.length()").value(2))
                .andExpect(jsonPath("$.data.total").value(3));
        mockMvc.perform(get("/api/v1/news/near").param("lat", "43.449").param("lon", "-80.491").param("limit", "2"))
                .andExpect(status().isOk());

        verify(repository, times(1)).taggedNews(anyInt());
        verify(repository, times(1)).lakesNear(
                eq("[\"" + MID_LAKE + "\",\"" + NEAR_LAKE + "\",\"" + FAR_LAKE + "\"]"), anyDouble(), anyDouble(), anyInt());
    }

    @Test
    void noTaggedStoriesSkipsTheDistanceQuery() throws Exception {
        when(repository.taggedNews(anyInt())).thenReturn(List.of());

        mockMvc.perform(get("/api/v1/news/near").param("lat", "10").param("lon", "10"))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.data.total").value(0))
                .andExpect(jsonPath("$.data.items.length()").value(0));
    }

    @Test
    void radiusAndLimitAreCapped() throws Exception {
        when(repository.taggedNews(anyInt())).thenReturn(List.of());
        mockMvc.perform(get("/api/v1/news/near").param("lat", "1").param("lon", "1").param("radius", "9999").param("limit", "x"))
                .andExpect(jsonPath("$.data.radiusKm").value(NewsNearController.MAX_RADIUS_KM))
                .andExpect(jsonPath("$.data.limit").value(NewsNearController.DEFAULT_LIMIT));
    }

    @Test
    void aMissingOrBadPointIsA400WithoutTouchingTheDatabase() throws Exception {
        mockMvc.perform(get("/api/v1/news/near").param("lon", "-80"))
                .andExpect(status().isBadRequest())
                .andExpect(jsonPath("$.error.message", containsString("lat is required")));
        mockMvc.perform(get("/api/v1/news/near").param("lat", "91").param("lon", "-80"))
                .andExpect(status().isBadRequest());
        mockMvc.perform(get("/api/v1/news/near").param("lat", "43").param("lon", "x"))
                .andExpect(status().isBadRequest());
        verifyNoInteractions(repository);
    }
}
