package com.fishfind.weather.service;

import static org.assertj.core.api.Assertions.assertThat;

import ch.qos.logback.classic.Level;
import ch.qos.logback.classic.spi.ILoggingEvent;
import ch.qos.logback.core.read.ListAppender;
import com.fishfind.weather.domain.StationRef;
import java.io.FileNotFoundException;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;

/**
 * Verifies the template-method exception handling in {@link StationProcessorBase}
 * by capturing the log events it emits.
 */
class StationProcessorBaseTest {

    private final StationRef station = new StationRef("MLI-1", 1.0, 2.0, "WA");
    private final Logger slf4jLogger = LoggerFactory.getLogger("station-base-test");
    private final ListAppender<ILoggingEvent> appender = new ListAppender<>();

    private Exception toThrow;
    private boolean processed;
    private TestProcessor processor;

    @BeforeEach
    void setUp() {
        ch.qos.logback.classic.Logger logback = (ch.qos.logback.classic.Logger) slf4jLogger;
        logback.detachAndStopAllAppenders();
        appender.start();
        logback.addAppender(appender);
        processor = new TestProcessor();
    }

    @Test
    void successPathDelegatesWithoutLogging() {
        processor.process(station);

        assertThat(processed).isTrue();
        assertThat(appender.list).isEmpty();
    }

    @Test
    void fileNotFoundLogsInfoSkipAndSwallows() {
        toThrow = new FileNotFoundException("no feed");

        processor.process(station);

        assertThat(appender.list).hasSize(1);
        ILoggingEvent event = appender.list.get(0);
        assertThat(event.getLevel()).isEqualTo(Level.INFO);
        assertThat(event.getFormattedMessage())
                .contains("Skipping")
                .contains("Open-Meteo source")
                .contains("MLI-1")
                .contains("WA");
    }

    @Test
    void otherExceptionLogsWarningAndSwallows() {
        toThrow = new IllegalStateException("kaboom");

        processor.process(station);

        assertThat(appender.list).hasSize(1);
        ILoggingEvent event = appender.list.get(0);
        assertThat(event.getLevel()).isEqualTo(Level.WARN);
        assertThat(event.getFormattedMessage())
                .contains("processing failed")
                .contains("MLI-1");
    }

    private class TestProcessor extends StationProcessorBase {
        @Override
        protected void processStation(StationRef s) throws Exception {
            if (toThrow != null) {
                throw toThrow;
            }
            processed = true;
        }

        @Override
        protected Logger logger() {
            return slf4jLogger;
        }

        @Override
        protected String country() {
            return "US";
        }

        @Override
        protected String missingSourceDescription() {
            return "Open-Meteo source";
        }
    }
}
