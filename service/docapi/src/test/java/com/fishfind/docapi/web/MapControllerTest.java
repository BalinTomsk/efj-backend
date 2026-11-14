package com.fishfind.docapi.web;

import com.fasterxml.jackson.databind.ObjectMapper;
import com.fishfind.docapi.repo.MapQueryRepository;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.autoconfigure.web.servlet.WebMvcTest;
import org.springframework.boot.test.mock.mockito.MockBean;
import org.springframework.test.web.servlet.MockMvc;

import static org.hamcrest.Matchers.containsString;
import static org.mockito.Mockito.verifyNoInteractions;
import static org.mockito.Mockito.when;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.header;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

@WebMvcTest(MapController.class)
class MapControllerTest {

    @Autowired
    private MockMvc mockMvc;

    @Autowired
    private ObjectMapper objectMapper;

    @MockBean
    private MapQueryRepository repository;

    @Test
    void shapesRoundsTheBoxAndReturnsTheDocument() throws Exception {
        when(repository.shapes(-114.6, 61.0, -113.8, 61.4, 10, 500)).thenReturn(objectMapper.readTree(
                "{\"type\":\"FeatureCollection\",\"truncated\":false,\"features\":[{\"type\":\"Feature\","
                        + "\"properties\":{\"kind\":\"outline\"},\"geometry\":{\"type\":\"Polygon\"}}]}"));

        mockMvc.perform(get("/api/v1/map/shapes").param("bbox", "-114.600001, 61, -113.8, 61.4").param("zoom", "10"))
                .andExpect(status().isOk())
                .andExpect(header().string("Cache-Control", "max-age=3600, private"))
                .andExpect(jsonPath("$.data.type").value("FeatureCollection"))
                .andExpect(jsonPath("$.data.features[0].properties.kind").value("outline"))
                .andExpect(jsonPath("$.error").doesNotExist());
    }

    @Test
    void limitIsCappedAndGarbageMeansTheDefault() throws Exception {
        when(repository.shapes(-1.0, 1.0, 0.0, 2.0, 12, 2000))
                .thenReturn(objectMapper.readTree("{\"type\":\"FeatureCollection\",\"limit\":2000,\"features\":[]}"));
        when(repository.shapes(-1.0, 1.0, 0.0, 2.0, 12, 500))
                .thenReturn(objectMapper.readTree("{\"type\":\"FeatureCollection\",\"limit\":500,\"features\":[]}"));

        mockMvc.perform(get("/api/v1/map/shapes").param("bbox", "-1,1,0,2").param("zoom", "12").param("limit", "99999"))
                .andExpect(jsonPath("$.data.limit").value(2000));
        mockMvc.perform(get("/api/v1/map/shapes").param("bbox", "-1,1,0,2").param("zoom", "12").param("limit", "x"))
                .andExpect(jsonPath("$.data.limit").value(500));
    }

    @Test
    void badBoxesAreA400WithoutTouchingTheDatabase() throws Exception {
        String[] bad = {"", "1,2,3", "a,b,c,d", "0,1,-1,2", "-1,2,0,1", "-181,1,-180,2", "-1,85,0,86", "-10,1,0,2"};
        for (String bbox : bad) {
            mockMvc.perform(get("/api/v1/map/shapes").param("bbox", bbox).param("zoom", "5"))
                    .andExpect(status().isBadRequest())
                    .andExpect(jsonPath("$.error.message", containsString("bbox")));
        }
        verifyNoInteractions(repository);
    }

    @Test
    void zoomIsRequiredAndBounded() throws Exception {
        for (String zoom : new String[] {"", "-1", "23", "x"}) {
            mockMvc.perform(get("/api/v1/map/shapes").param("bbox", "-1,1,0,2").param("zoom", zoom))
                    .andExpect(status().isBadRequest())
                    .andExpect(jsonPath("$.error.message", containsString("zoom")));
        }
        verifyNoInteractions(repository);
    }

    @Test
    void aBoxTooBigForTheZoomIsA400() throws Exception {
        // 1 degree = 2,913 px at zoom 12 (fine) and 5,825 px at zoom 13 (too big)
        when(repository.shapes(-1.0, 1.0, 0.0, 2.0, 12, 500))
                .thenReturn(objectMapper.readTree("{\"type\":\"FeatureCollection\",\"features\":[]}"));
        mockMvc.perform(get("/api/v1/map/shapes").param("bbox", "-1,1,0,2").param("zoom", "12"))
                .andExpect(status().isOk());
        mockMvc.perform(get("/api/v1/map/shapes").param("bbox", "-1,1,0,2").param("zoom", "13"))
                .andExpect(status().isBadRequest())
                .andExpect(jsonPath("$.error.message", containsString("too big for zoom 13")));
    }
}
