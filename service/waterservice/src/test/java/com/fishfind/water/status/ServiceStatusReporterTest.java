package com.fishfind.water.status;

import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import org.junit.jupiter.api.Test;
import org.springframework.boot.info.BuildProperties;

import java.time.Instant;
import java.util.Properties;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertFalse;
import static org.junit.jupiter.api.Assertions.assertTrue;

class ServiceStatusReporterTest {

    private static ServiceStatusReporter reporter(ServiceActivity activity, String url) {
        Properties props = new Properties();
        props.setProperty("version", "1.25.0");
        return new ServiceStatusReporter(activity, new BuildProperties(props), url, "u", "p", " Debian-JNode ", 60);
    }

    @Test
    void bodyFollowsTheServiceStatusContract() throws Exception {
        ServiceActivity activity = new ServiceActivity();
        activity.record("station 05BH004");

        JsonNode body = new ObjectMapper().readTree(
                reporter(activity, "https://mq").body("heartbeat", Instant.parse("2026-10-16T13:05:00Z")));

        assertEquals("fishfind.service-status.v1", body.get("type").asText());
        assertEquals("heartbeat", body.get("event").asText());
        assertEquals("waterservice", body.get("service").asText());
        assertEquals("debian-jnode", body.get("machine").asText());
        assertEquals("1.25.0", body.get("version").asText());
        assertEquals("2026-10-16T13:05:00Z", body.get("sentUtc").asText());
        assertEquals("station 05BH004", body.get("lastAction").asText());
        assertTrue(Instant.parse(body.get("processStartUtc").asText()).isBefore(Instant.now()));
    }

    @Test
    void bodyCarriesNullActionBeforeTheFirstRequest() throws Exception {
        JsonNode body = new ObjectMapper().readTree(
                reporter(new ServiceActivity(), "https://mq").body("start", Instant.now()));

        assertTrue(body.get("lastAction").isNull());
        assertTrue(body.get("lastActionUtc").isNull());
    }

    @Test
    void intervalIsNeverBelowOneMinute() {
        Properties props = new Properties();
        props.setProperty("version", "1.0.0");
        ServiceActivity a = new ServiceActivity();
        assertEquals(60, new ServiceStatusReporter(a, new BuildProperties(props), "https://mq", "u", "p", "h", 10).intervalSeconds());
        assertEquals(60, new ServiceStatusReporter(a, new BuildProperties(props), "https://mq", "u", "p", "h", 60).intervalSeconds());
        assertEquals(300, new ServiceStatusReporter(a, new BuildProperties(props), "https://mq", "u", "p", "h", 300).intervalSeconds());
    }

    @Test
    void disabledWithoutBrokerSettings() {
        ServiceStatusReporter off = reporter(new ServiceActivity(), " ");
        assertFalse(off.enabled());
        off.start();
        off.stop();
    }
}
