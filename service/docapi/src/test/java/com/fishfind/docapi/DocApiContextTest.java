package com.fishfind.docapi;

import org.junit.jupiter.api.Test;
import org.springframework.boot.test.context.SpringBootTest;

/**
 * Boots the full application context against the H2 test datasource to prove the bean graph
 * (controllers → services → repositories → JdbcTemplate) wires cleanly.
 */
@SpringBootTest
class DocApiContextTest {

    @Test
    void contextLoadsWithTestConfiguration() {
    }
}
