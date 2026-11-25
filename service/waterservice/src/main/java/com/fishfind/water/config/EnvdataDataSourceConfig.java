package com.fishfind.water.config;

import com.zaxxer.hikari.HikariDataSource;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.jdbc.core.JdbcTemplate;

import javax.sql.DataSource;

/**
 * The one datasource of this service: the MySQL {@code envdata} database, from {@code MYSQL_URL} /
 * {@code MYSQL_USERNAME} / {@code MYSQL_PASSWORD} (the C# twin's keys).
 *
 * <p>Built in code, not from {@code spring.datasource.*}: {@code application.yml} is git-ignored and still maps
 * {@code spring.datasource} to the SQL Server {@code DB_*} keys, which stay in the shared env file as the SQL Server
 * connection (a rollback to 1.14.0 needs no file change). Declaring the {@link DataSource} bean makes Spring Boot's
 * datasource auto-configuration back off, so those keys are never used. A missing {@code MYSQL_URL} fails startup.
 */
@Configuration
public class EnvdataDataSourceConfig {

    /** Seconds; sp_clean_old_water_data may reorganise a partition, but a cycle must never hang (C# twin: 120). */
    static final int QUERY_TIMEOUT_SECONDS = 120;

    @Bean(destroyMethod = "close")
    public HikariDataSource dataSource(@Value("${MYSQL_URL:}") String url,
                                       @Value("${MYSQL_USERNAME:}") String username,
                                       @Value("${MYSQL_PASSWORD:}") String password) {
        HikariDataSource dataSource = new HikariDataSource();
        dataSource.setJdbcUrl(MySqlUrl.normalize(url));
        if (!username.isBlank()) {
            dataSource.setUsername(username);
        }
        if (!password.isBlank()) {
            dataSource.setPassword(password);
        }
        dataSource.setPoolName("water-hikari");
        // Two parallel country passes + post-processing; 4 leaves headroom without exhausting the server.
        dataSource.setMaximumPoolSize(4);
        dataSource.setMinimumIdle(1);
        dataSource.setConnectionTimeout(30_000);
        // Retire connections before the server/network idle timeout closes them out from under the pool.
        dataSource.setMaxLifetime(1_740_000);
        dataSource.setKeepaliveTime(300_000);
        dataSource.setValidationTimeout(5_000);
        return dataSource;
    }

    @Bean
    public JdbcTemplate jdbcTemplate(DataSource dataSource) {
        JdbcTemplate jdbc = new JdbcTemplate(dataSource);
        jdbc.setQueryTimeout(QUERY_TIMEOUT_SECONDS);
        return jdbc;
    }
}
