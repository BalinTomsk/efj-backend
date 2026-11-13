package com.fishfind.docapi.web;

import com.fasterxml.jackson.databind.ObjectMapper;
import com.fishfind.docapi.repo.ForecastQueryRepository;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.autoconfigure.web.servlet.WebMvcTest;
import org.springframework.boot.test.mock.mockito.MockBean;
import org.springframework.test.web.servlet.MockMvc;

import static org.hamcrest.Matchers.containsString;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.anyDouble;
import static org.mockito.ArgumentMatchers.anyInt;
import static org.mockito.ArgumentMatchers.anyString;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.ArgumentMatchers.isNull;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.verifyNoInteractions;
import static org.mockito.Mockito.when;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.header;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

@WebMvcTest(ForecastController.class)
class ForecastControllerTest {

    private static final String FISH = "2cffb500-3e59-4120-9460-055856e9ac5c";

    @Autowired
    private MockMvc mockMvc;

    @Autowired
    private ObjectMapper objectMapper;

    @MockBean
    private ForecastQueryRepository repository;

    @Test
    void stationsPassesNormalizedArgumentsAndReturnsTheDocument() throws Exception {
        when(repository.stations(FISH, 43.46, -80.49, 100, null, 50)).thenReturn(objectMapper.readTree(
                "{\"total\":1,\"stations\":[{\"sid\":266353,\"today\":64,\"marker\":5,\"distanceKm\":1.2}]}"));

        mockMvc.perform(get("/api/v1/forecast/stations")
                        .param("fish", "{2CFFB500-3E59-4120-9460-055856E9AC5C}")
                        .param("lat", "43.4567").param("lon", "-80.4912"))
                .andExpect(status().isOk())
                .andExpect(header().string("Cache-Control", "max-age=300, private"))
                .andExpect(jsonPath("$.data.stations[0].sid").value(266353))
                .andExpect(jsonPath("$.data.stations[0].today").value(64))
                .andExpect(jsonPath("$.error").doesNotExist());
    }

    @Test
    void stationsCapsRadiusAndLimitAndUpperCasesCountry() throws Exception {
        when(repository.stations(FISH, 45.0, -75.0, 500, "US", 200))
                .thenReturn(objectMapper.readTree("{\"total\":0,\"stations\":[]}"));

        mockMvc.perform(get("/api/v1/forecast/stations").param("fish", FISH).param("lat", "45").param("lon", "-75")
                        .param("radius", "9000").param("limit", "100000").param("country", "us"))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.data.total").value(0));
        verify(repository).stations(FISH, 45.0, -75.0, 500, "US", 200);
    }

    @Test
    void stationsGarbageRadiusAndLimitFallBackToTheDefaults() throws Exception {
        when(repository.stations(eq(FISH), anyDouble(), anyDouble(), eq(100), isNull(), eq(50)))
                .thenReturn(objectMapper.readTree("{\"total\":0,\"stations\":[]}"));

        mockMvc.perform(get("/api/v1/forecast/stations").param("fish", FISH).param("lat", "45").param("lon", "-75")
                        .param("radius", "far").param("limit", "-3"))
                .andExpect(status().isOk());
        verify(repository).stations(FISH, 45.0, -75.0, 100, null, 50);
    }

    @Test
    void stationsUnknownFishIs404() throws Exception {
        when(repository.stations(anyString(), anyDouble(), anyDouble(), anyInt(), any(), anyInt())).thenReturn(null);

        mockMvc.perform(get("/api/v1/forecast/stations").param("fish", FISH).param("lat", "45").param("lon", "-75"))
                .andExpect(status().isNotFound());
    }

    @Test
    void stationsBadInputIs400AndNeverReachesTheRepository() throws Exception {
        mockMvc.perform(get("/api/v1/forecast/stations").param("lat", "45").param("lon", "-75"))
                .andExpect(status().isBadRequest())
                .andExpect(jsonPath("$.error.message", containsString("fish")));
        mockMvc.perform(get("/api/v1/forecast/stations").param("fish", "trout").param("lat", "45").param("lon", "-75"))
                .andExpect(status().isBadRequest());
        mockMvc.perform(get("/api/v1/forecast/stations").param("fish", FISH).param("lon", "-75"))
                .andExpect(status().isBadRequest())
                .andExpect(jsonPath("$.error.message", containsString("lat")));
        mockMvc.perform(get("/api/v1/forecast/stations").param("fish", FISH).param("lat", "91").param("lon", "-75"))
                .andExpect(status().isBadRequest());
        mockMvc.perform(get("/api/v1/forecast/stations").param("fish", FISH).param("lat", "45").param("lon", "NaN"))
                .andExpect(status().isBadRequest());
        mockMvc.perform(get("/api/v1/forecast/stations").param("fish", FISH).param("lat", "45").param("lon", "-75")
                        .param("country", "MX"))
                .andExpect(status().isBadRequest());
        verifyNoInteractions(repository);
    }

    @Test
    void plotReturnsTheDocument() throws Exception {
        when(repository.plot(266353, FISH)).thenReturn(objectMapper.readTree(
                "{\"sid\":266353,\"plot\":{\"place\":\"X\"},\"calendar\":[],\"week\":[{\"probability\":64}]}"));

        mockMvc.perform(get("/api/v1/forecast/plot/266353").param("fish", FISH.toUpperCase()))
                .andExpect(status().isOk())
                .andExpect(header().string("Cache-Control", "max-age=300, private"))
                .andExpect(jsonPath("$.data.plot.place").value("X"))
                .andExpect(jsonPath("$.data.week[0].probability").value(64));
    }

    @Test
    void plotUnknownStationOrFishIs404() throws Exception {
        when(repository.plot(anyInt(), anyString())).thenReturn(null);

        mockMvc.perform(get("/api/v1/forecast/plot/1").param("fish", FISH))
                .andExpect(status().isNotFound());
    }

    @Test
    void plotBadSidOrFishIs400AndNeverReachesTheRepository() throws Exception {
        mockMvc.perform(get("/api/v1/forecast/plot/abc").param("fish", FISH)).andExpect(status().isBadRequest());
        mockMvc.perform(get("/api/v1/forecast/plot/0").param("fish", FISH)).andExpect(status().isBadRequest());
        mockMvc.perform(get("/api/v1/forecast/plot/266353")).andExpect(status().isBadRequest());
        verify(repository, never()).plot(anyInt(), anyString());
    }

    @Test
    void reasoningDefaultsToTodayAndPassesTheDay() throws Exception {
        when(repository.reasoning(266353, FISH, 0)).thenReturn(objectMapper.readTree("{\"today\":64}"));
        when(repository.reasoning(266353, FISH, 6)).thenReturn(objectMapper.readTree("{\"today\":40}"));

        mockMvc.perform(get("/api/v1/forecast/reasoning/266353").param("fish", FISH))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.data.today").value(64));
        mockMvc.perform(get("/api/v1/forecast/reasoning/266353").param("fish", FISH).param("day", "6"))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.data.today").value(40));
    }

    @Test
    void reasoningBadDayIs400AndUnknownIs404() throws Exception {
        mockMvc.perform(get("/api/v1/forecast/reasoning/266353").param("fish", FISH).param("day", "7"))
                .andExpect(status().isBadRequest());
        mockMvc.perform(get("/api/v1/forecast/reasoning/266353").param("fish", FISH).param("day", "-1"))
                .andExpect(status().isBadRequest());
        verify(repository, never()).reasoning(anyInt(), anyString(), anyInt());

        when(repository.reasoning(anyInt(), anyString(), anyInt())).thenReturn(null);
        mockMvc.perform(get("/api/v1/forecast/reasoning/5").param("fish", FISH))
                .andExpect(status().isNotFound());
    }
}
