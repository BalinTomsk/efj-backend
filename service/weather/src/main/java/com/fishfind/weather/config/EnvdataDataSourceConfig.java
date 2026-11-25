package com.fishfind.weather.config;

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
 * <p>{@code DB_URL} / {@code DB_USERNAME} / {@code DB_PASSWORD} stay in the shared env file as the SQL Server
 * connection (a rollback to 1.18.0 needs no file change) but are no longer read. Declaring the {@link DataSource}
 * bean makes Spring Boot's datasource auto-configuration back off. A missing {@code MYSQL_URL} fails startup.
 */
@Configuration
public class EnvdataDataSourceConfig {

    /** Seconds; the retention may delete many rows, but a cycle must never hang (C# twin: 120). */
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
        dataSource.setPoolName("weather-hikari");
        // Six provider workers, each one station at a time, plus post-processing and the usage ledger.
        dataSource.setMaximumPoolSize(8);
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
