package com.fishfind.weather.canonical;

import static org.assertj.core.api.Assertions.assertThat;

import com.fasterxml.jackson.databind.ObjectMapper;
import java.util.Map;
import org.junit.jupiter.api.Test;
import org.springframework.context.annotation.AnnotationConfigApplicationContext;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;

/**
 * Every converter in this package must be instantiable <b>by Spring</b>, not merely by a test calling
 * {@code new}.
 *
 * <p>Nothing else in the suite covered that, and the gap shipped. Each converter exposes two public
 * constructors — the real one and a clock-pinning one for tests. Spring selects a constructor
 * implicitly only when there is exactly <em>one</em>; with two and no no-arg it falls back to a default
 * constructor that does not exist, and the context dies with {@code NoSuchMethodException: <init>()}.
 * weather-station-pusher 1.15.1 went to production that way and crash-looped roughly 800 times over
 * 4.5 hours with a fully green build, because every converter test constructs the class directly and
 * so never exercises Spring's choice.
 *
 * <p>This scans the package instead of naming the three classes, so a converter added later is covered
 * the day it appears: {@code refresh()} instantiates every scanned singleton eagerly and throws if any
 * of them cannot be wired.
 */
class ConverterBeanWiringTest {

    /** Stands in for Boot's JacksonAutoConfiguration, which supplies the real application's mapper. */
    @Configuration
    static class MapperConfig {
        @Bean
        ObjectMapper objectMapper() {
            return new ObjectMapper();
        }
    }

    @Test
    void everyConverterInThisPackageIsInstantiableBySpring() {
        try (AnnotationConfigApplicationContext context = new AnnotationConfigApplicationContext()) {
            context.register(MapperConfig.class);
            context.scan(ForecastConverter.class.getPackageName());

            context.refresh();

            Map<String, ForecastConverter> converters = context.getBeansOfType(ForecastConverter.class);
            assertThat(converters.values())
                    .extracting(ForecastConverter::provider)
                    .contains("open-meteo", "visual-crossing", "weather-gov");
        }
    }
}
