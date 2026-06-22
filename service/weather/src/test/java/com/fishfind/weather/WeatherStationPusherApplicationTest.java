package com.fishfind.weather;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.when;

import io.github.cdimascio.dotenv.Dotenv;
import java.util.HashMap;
import java.util.Map;
import org.junit.jupiter.api.AfterEach;
import org.junit.jupiter.api.Test;

/**
 * Covers the dotenv credential-fallback decision logic. Note these keys are chosen to be
 * absent from the real process environment.
 */
class WeatherStationPusherApplicationTest {

    private static final String KEY = "WEATHER_TEST_FALLBACK_KEY";

    @AfterEach
    void clearProperty() {
        System.clearProperty(KEY);
    }

    @Test
    void addsDotenvValueWhenNotOtherwisePresent() {
        Dotenv dotenv = mock(Dotenv.class);
        when(dotenv.get(KEY)).thenReturn("from-dotenv");
        Map<String, Object> fallback = new HashMap<>();

        WeatherStationPusherApplication.addIfMissing(dotenv, fallback, KEY);

        assertThat(fallback).containsEntry(KEY, "from-dotenv");
    }

    @Test
    void skipsWhenSystemPropertyAlreadySet() {
        System.setProperty(KEY, "from-sysprop");
        Dotenv dotenv = mock(Dotenv.class);
        Map<String, Object> fallback = new HashMap<>();

        WeatherStationPusherApplication.addIfMissing(dotenv, fallback, KEY);

        assertThat(fallback).doesNotContainKey(KEY);
    }

    @Test
    void skipsWhenDotenvValueBlankOrNull() {
        Dotenv dotenv = mock(Dotenv.class);
        when(dotenv.get(KEY)).thenReturn("   ");
        Map<String, Object> fallback = new HashMap<>();

        WeatherStationPusherApplication.addIfMissing(dotenv, fallback, KEY);

        assertThat(fallback).isEmpty();
    }
}
