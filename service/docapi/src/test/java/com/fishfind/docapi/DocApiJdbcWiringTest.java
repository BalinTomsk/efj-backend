package com.fishfind.docapi;

import org.junit.jupiter.api.Test;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.test.context.ActiveProfiles;
import org.springframework.test.context.TestPropertySource;

/**
 * Verifies the {@code jdbc} profile still wires cleanly: JDBC auto-configuration is re-enabled, a
 * datasource is created (H2 stands in for SQL Server here), and the JDBC-backed stores are injected
 * into the services. No stored procedures are invoked at startup, so H2's lack of them is irrelevant.
 */
@SpringBootTest
@ActiveProfiles({"test", "jdbc"})
@TestPropertySource(properties = {
        "spring.datasource.url=jdbc:h2:mem:docapi-jdbc-test;MODE=MSSQLServer;DB_CLOSE_DELAY=-1;DB_CLOSE_ON_EXIT=FALSE",
        "spring.datasource.username=sa",
        "spring.datasource.password=",
        "spring.datasource.driver-class-name=org.h2.Driver"
})
class DocApiJdbcWiringTest {

    @Test
    void contextLoadsUnderJdbcProfile() {
    }
}
