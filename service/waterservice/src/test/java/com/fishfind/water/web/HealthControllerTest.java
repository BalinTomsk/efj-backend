package com.fishfind.water.web;

import org.junit.jupiter.api.Test;
import org.springframework.boot.info.BuildProperties;

import java.util.Map;
import java.util.Properties;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertTrue;

class HealthControllerTest {

    @Test
    void healthReportsVersionFromBuildPropertiesNotAHardcodedConstant() {
        Properties props = new Properties();
        props.setProperty("version", "9.9.9");
        HealthController controller = new HealthController(new BuildProperties(props));

        Map<String, Object> body = controller.health();

        assertEquals("UP", body.get("status"));
        assertEquals("9.9.9", body.get("version"));
        assertTrue((long) body.get("uptime") >= 0);
    }

    @Test
    void healthFallsBackToUnknownVersionWhenBuildInfoIsAbsent() {
        HealthController controller = new HealthController(null);

        Map<String, Object> body = controller.health();

        assertEquals("UP", body.get("status"));
        assertEquals("unknown", body.get("version"));
    }
}
