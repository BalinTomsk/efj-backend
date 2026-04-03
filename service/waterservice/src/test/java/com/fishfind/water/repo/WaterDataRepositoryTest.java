package com.fishfind.water.repo;

import com.fishfind.water.domain.Reading;
import com.fishfind.water.domain.UsSeriesReading;
import org.junit.jupiter.api.Test;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.jdbc.core.PreparedStatementCallback;

import java.lang.reflect.Method;
import java.sql.Timestamp;
import java.time.Instant;
import java.time.OffsetDateTime;
import java.time.ZoneOffset;
import java.util.Arrays;
import java.util.List;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertInstanceOf;
import static org.junit.jupiter.api.Assertions.assertThrows;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.times;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.verifyNoInteractions;

class WaterDataRepositoryTest {

    private final JdbcTemplate jdbc = mock(JdbcTemplate.class);
    private final WaterDataRepository repository = new WaterDataRepository(jdbc);

    @Test
    void saveStationDataRejectsBlankMli() {
        IllegalArgumentException ex = assertThrows(
                IllegalArgumentException.class,
                () -> repository.saveStationData(" ", List.of())
        );

        assertEquals("mli must not be null or blank", ex.getMessage());
    }

    @Test
    void saveStationDataSkipsEmptyInput() {
        repository.saveStationData("02JE025", List.of());

        verifyNoInteractions(jdbc);
    }

    @Test
    void saveStationDataUpsertsOnlyValidReadings() {
        Reading valid = new Reading(
                "02JE025",
                OffsetDateTime.of(2024, 1, 2, 3, 4, 0, 0, ZoneOffset.UTC),
                1.2,
                3.4
        );
        Reading missingStamp = new Reading("02JE025", null, 2.0, 4.0);

        repository.saveStationData("02JE025", Arrays.asList(valid, null, missingStamp));

        verify(jdbc, times(1)).update(
                eq("EXEC dbo.sp_UpdateWaterData ?, ?, ?, ?"),
                eq("02JE025"),
                any(),
                eq(1.2),
                eq(3.4)
        );
    }

    @Test
    void saveStationDataDeduplicatesMatchingTimestampsWithinBatch() {
        OffsetDateTime stamp = OffsetDateTime.of(2024, 1, 2, 3, 4, 0, 0, ZoneOffset.UTC);
        Reading first = new Reading("02JE025", stamp, 1.2, 3.4);
        Reading duplicate = new Reading("02JE025", stamp, 9.9, 8.8);

        repository.saveStationData("02JE025", List.of(first, duplicate));

        verify(jdbc, times(1)).update(
                eq("EXEC dbo.sp_UpdateWaterData ?, ?, ?, ?"),
                eq("02JE025"),
                any(),
                eq(9.9),
                eq(8.8)
        );
    }

    @Test
    void fallbackWrapsOriginalException() {
        RuntimeException ex = assertThrows(
                RuntimeException.class,
                () -> repository.fallback("02JE025", List.of(), new IllegalStateException("sql failed"))
        );

        assertEquals("SQL save failed for station 02JE025", ex.getMessage());
        assertInstanceOf(IllegalStateException.class, ex.getCause());
    }

    @Test
    void toTimestampConvertsInstant() throws Exception {
        Instant instant = Instant.parse("2024-01-02T03:04:05Z");

        Timestamp timestamp = (Timestamp) invokePrivate("toTimestamp", new Class<?>[]{Instant.class}, instant);

        assertEquals(Timestamp.from(instant), timestamp);
    }

    @Test
    void saveUsStationDataRejectsBlankState() {
        IllegalArgumentException ex = assertThrows(
                IllegalArgumentException.class,
                () -> repository.saveUsStationData("08313000", " ", List.of())
        );

        assertEquals("state must not be null or blank", ex.getMessage());
    }

    @Test
    void saveUsStationDataExecutesStoredProcedurePerValidSeries() {
        repository.saveUsStationData("08313000", "NY", List.of(
                new UsSeriesReading("Streamflow", "ft^3/s", "<root><a d=\"2024-01-02\" v=\"1.2\" /></root>"),
                new UsSeriesReading(" ", "ft", "<root><a d=\"2024-01-02\" v=\"1.2\" /></root>"),
                new UsSeriesReading("Gage height", "ft", "<root><a d=\"2024-01-02\" v=\"7.8\" /></root>")
        ));

        verify(jdbc, times(2)).execute(
                eq("EXEC dbo.sp_push_us_water_data ?, ?, ?, ?, ?"),
                org.mockito.ArgumentMatchers.<PreparedStatementCallback<Object>>any()
        );
    }

    @Test
    void fallbackUsWrapsOriginalException() {
        RuntimeException ex = assertThrows(
                RuntimeException.class,
                () -> repository.fallbackUs("08313000", "NY", List.of(), new IllegalStateException("sql failed"))
        );

        assertEquals("SQL save failed for US station 08313000", ex.getMessage());
        assertInstanceOf(IllegalStateException.class, ex.getCause());
    }

    private Object invokePrivate(String name, Class<?>[] parameterTypes, Object... args) throws Exception {
        Method method = WaterDataRepository.class.getDeclaredMethod(name, parameterTypes);
        method.setAccessible(true);
        return method.invoke(repository, args);
    }
}
