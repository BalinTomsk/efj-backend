package com.fishfind.water.service;

import ch.qos.logback.classic.Level;
import ch.qos.logback.classic.spi.ILoggingEvent;
import ch.qos.logback.core.read.ListAppender;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.http.HttpStatus;
import org.springframework.web.client.HttpServerErrorException;

import java.io.FileNotFoundException;
import java.io.IOException;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertFalse;
import static org.junit.jupiter.api.Assertions.assertNull;
import static org.junit.jupiter.api.Assertions.assertTrue;

class StationProcessorBaseTest {

    private final Logger slf4jLogger = LoggerFactory.getLogger("water-station-base-test");
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
    void successPathReturnsProcessed() {
        assertEquals(ProcessingOutcome.PROCESSED, processor.processWithOutcome("02JE025", "QC", -5));
        assertTrue(processor.process("02JE025", "QC", -5));
        assertTrue(processed);
    }

    @Test
    void fileNotFoundReturnsSkipped() {
        toThrow = new FileNotFoundException("no feed");

        assertEquals(ProcessingOutcome.SKIPPED, processor.processWithOutcome("02JE025", "QC", -5));
        assertFalse(processor.process("02JE025", "QC", -5));
    }

    @Test
    void ioExceptionWithHttp503ReturnsHttp503FailureWithoutStackTrace() {
        toThrow = new IOException("HTTP 503");

        assertEquals(ProcessingOutcome.FAILED_HTTP_503, processor.processWithOutcome("02JE025", "QC", -5));

        ILoggingEvent event = appender.list.get(0);
        assertEquals(Level.WARN, event.getLevel());
        assertTrue(event.getFormattedMessage().contains("HTTP 503"));
        assertNull(event.getThrowableProxy());
    }

    @Test
    void springHttp503ExceptionReturnsHttp503FailureWithoutStackTrace() {
        toThrow = new HttpServerErrorException(HttpStatus.SERVICE_UNAVAILABLE, "Service Unavailable");

        assertEquals(ProcessingOutcome.FAILED_HTTP_503, processor.processWithOutcome("08313000", "NY", -5));

        ILoggingEvent event = appender.list.get(0);
        assertEquals(Level.WARN, event.getLevel());
        assertTrue(event.getFormattedMessage().contains("HttpServerErrorException"));
        assertNull(event.getThrowableProxy());
    }

    private class TestProcessor extends StationProcessorBase {
        @Override
        protected void processStation(String mli, String state, int tz) throws Exception {
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
            return "CA";
        }

        @Override
        protected String missingSourceDescription() {
            return "hydrometric CSV";
        }
    }
}
