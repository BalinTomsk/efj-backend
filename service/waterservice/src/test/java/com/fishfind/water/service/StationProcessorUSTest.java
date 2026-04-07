package com.fishfind.water.service;

import com.fishfind.water.domain.UsSeriesReading;
import com.fishfind.water.repo.WaterDataRepository;
import com.fishfind.water.repo.WaterStationRepository;
import org.junit.jupiter.api.Test;

import java.lang.reflect.Field;
import java.lang.reflect.Method;
import java.time.LocalDate;
import java.util.List;
import java.util.Map;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertNull;
import static org.mockito.Mockito.doThrow;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.times;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

class StationProcessorUSTest {
    private static final String REAL_USGS_SAMPLE = """
            <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
            <ns1:timeSeriesResponse xmlns:ns1="http://www.cuahsi.org/waterML/1.1/" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance">
              <ns1:timeSeries name="USGS:08313000:00010:00000">
                <ns1:variable ns1:oid="45807042">
                  <ns1:variableName>Temperature, water, &amp;#176;C</ns1:variableName>
                </ns1:variable>
                <ns1:values>
                  <ns1:value qualifiers="P" dateTime="2026-03-22T19:45:00.000-06:00">14.5</ns1:value>
                  <ns1:value qualifiers="P" dateTime="2026-03-23T19:00:00.000-06:00">15.1</ns1:value>
                </ns1:values>
              </ns1:timeSeries>
              <ns1:timeSeries name="USGS:08313000:00060:00000">
                <ns1:variable ns1:oid="45807197">
                  <ns1:variableName>Streamflow, ft&amp;#179;/s</ns1:variableName>
                </ns1:variable>
                <ns1:values>
                  <ns1:value qualifiers="P" dateTime="2026-03-22T19:45:00.000-06:00">617</ns1:value>
                  <ns1:value qualifiers="P" dateTime="2026-03-23T19:00:00.000-06:00">652</ns1:value>
                </ns1:values>
              </ns1:timeSeries>
              <ns1:timeSeries name="USGS:08313000:00065:00000">
                <ns1:variable ns1:oid="45807202">
                  <ns1:variableName>Gage height, ft</ns1:variableName>
                </ns1:variable>
                <ns1:values>
                  <ns1:value qualifiers="P" dateTime="2026-03-22T19:45:00.000-06:00">3.26</ns1:value>
                  <ns1:value qualifiers="P" dateTime="2026-03-23T19:00:00.000-06:00">3.32</ns1:value>
                </ns1:values>
              </ns1:timeSeries>
              <ns1:timeSeries name="USGS:08313000:63680:00000">
                <ns1:variable ns1:oid="51443524">
                  <ns1:variableName>Turbidity, water, unfiltered, monochrome near infra-red LED light, 780-900 nm, detection angle 90 &amp;#177;2.5&amp;#176;, formazin nephelometric units (FNU)</ns1:variableName>
                </ns1:variable>
                <ns1:values>
                  <ns1:value qualifiers="P" dateTime="2026-03-22T19:45:00.000-06:00">62.5</ns1:value>
                  <ns1:value qualifiers="P" dateTime="2026-03-23T19:00:00.000-06:00">61.4</ns1:value>
                </ns1:values>
              </ns1:timeSeries>
            </ns1:timeSeriesResponse>
            """;

    private final XmlFetcherUS fetcher = mock(XmlFetcherUS.class);
    private final WaterDataRepository dataRepo = mock(WaterDataRepository.class);
    private final WaterStationRepository stationRepo = mock(WaterStationRepository.class);
    private final StationProcessorUS processor = new StationProcessorUS(fetcher, dataRepo, stationRepo);

    @Test
    void processFetchesParsesAndSavesSeriesOnSuccess() throws Exception {
        when(fetcher.fetch("NM", "08313000")).thenReturn(REAL_USGS_SAMPLE);

        processor.process("08313000", "NM", -7);

        verify(dataRepo).saveUsStationData("08313000", "NM", List.of(
                new UsSeriesReading(
                        "Temperature",
                        "water, &#176;C",
                        "<root><a d=\"2026-03-22\" v=\"14.5\" /><a d=\"2026-03-23\" v=\"15.1\" /></root>"
                ),
                new UsSeriesReading(
                        "Streamflow",
                        "ft^3/s",
                        "<root><a d=\"2026-03-22\" v=\"617\" /><a d=\"2026-03-23\" v=\"652\" /></root>"
                ),
                new UsSeriesReading(
                        "Gage height",
                        "ft",
                        "<root><a d=\"2026-03-22\" v=\"3.26\" /><a d=\"2026-03-23\" v=\"3.32\" /></root>"
                ),
                new UsSeriesReading(
                        "Turbidity",
                        "water, unfiltered, monochrome near infra-red LED light, 780-900 nm, detection angle 90 &#177;2.5&#176;, formazin nephelometric units (FNU)",
                        "<root><a d=\"2026-03-22\" v=\"62.5\" /><a d=\"2026-03-23\" v=\"61.4\" /></root>"
                )
        ));
        verify(stationRepo, never()).disableStation("08313000");
        assertNull(failureStates().get("08313000"));
    }

    @Test
    void processDisablesStationAfterThreeConsecutiveFailedDays() throws Exception {
        doThrow(new RuntimeException("fetch failed")).when(fetcher).fetch("NM", "08313000");
        Map<String, Object> states = failureStates();

        processor.process("08313000", "NM", -7);
        states.put("08313000", newFailureState(LocalDate.now().minusDays(1), 2));
        processor.process("08313000", "NM", -7);

        verify(stationRepo, times(1)).disableStation("08313000");
        assertNull(failureStates().get("08313000"));
    }

    @Test
    void parseBuildsPayloadsFromRealUsgsSample() throws Exception {
        @SuppressWarnings("unchecked")
        List<UsSeriesReading> series = (List<UsSeriesReading>) invokePrivate(
                "parse",
                new Class<?>[]{String.class},
                REAL_USGS_SAMPLE
        );

        assertEquals(List.of(
                new UsSeriesReading("Temperature", "water, &#176;C", "<root><a d=\"2026-03-22\" v=\"14.5\" /><a d=\"2026-03-23\" v=\"15.1\" /></root>"),
                new UsSeriesReading("Streamflow", "ft^3/s", "<root><a d=\"2026-03-22\" v=\"617\" /><a d=\"2026-03-23\" v=\"652\" /></root>"),
                new UsSeriesReading("Gage height", "ft", "<root><a d=\"2026-03-22\" v=\"3.26\" /><a d=\"2026-03-23\" v=\"3.32\" /></root>"),
                new UsSeriesReading("Turbidity", "water, unfiltered, monochrome near infra-red LED light, 780-900 nm, detection angle 90 &#177;2.5&#176;, formazin nephelometric units (FNU)", "<root><a d=\"2026-03-22\" v=\"62.5\" /><a d=\"2026-03-23\" v=\"61.4\" /></root>")
        ), series);
    }

    @Test
    void parseSkipsNonNumericDailyValuesBeforeBuildingLegacyXml() throws Exception {
        String xml = """
                <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
                <ns1:timeSeriesResponse xmlns:ns1="http://www.cuahsi.org/waterML/1.1/">
                  <ns1:timeSeries name="USGS:01519200:00060:00000">
                    <ns1:variable>
                      <ns1:variableName>Discharge, ft&amp;#179;/s</ns1:variableName>
                    </ns1:variable>
                    <ns1:values>
                      <ns1:value qualifiers="P" dateTime="2026-03-23T08:00:00.000-04:00">152</ns1:value>
                      <ns1:value qualifiers="P" dateTime="2026-03-23T08:15:00.000-04:00">Ice</ns1:value>
                      <ns1:value qualifiers="P" dateTime="2026-03-24T08:00:00.000-04:00">160</ns1:value>
                    </ns1:values>
                  </ns1:timeSeries>
                </ns1:timeSeriesResponse>
                """;

        @SuppressWarnings("unchecked")
        List<UsSeriesReading> series = (List<UsSeriesReading>) invokePrivate(
                "parse",
                new Class<?>[]{String.class},
                xml
        );

        assertEquals(List.of(
                new UsSeriesReading(
                        "Discharge",
                        "ft^3/s",
                        "<root><a d=\"2026-03-23\" v=\"152\" /><a d=\"2026-03-24\" v=\"160\" /></root>"
                )
        ), series);
    }

    @Test
    void incrementFailureCountDoesNotIncreaseTwiceOnSameDay() throws Exception {
        Map<String, Object> states = failureStates();
        states.put("08313000", newFailureState(LocalDate.now(), 2));

        int failures = (int) invokePrivate("incrementFailureCount", new Class<?>[]{String.class}, "08313000");

        assertEquals(2, failures);
    }

    @Test
    void incrementFailureCountIncreasesForConsecutiveDay() throws Exception {
        Map<String, Object> states = failureStates();
        states.put("08313000", newFailureState(LocalDate.now().minusDays(1), 2));

        int failures = (int) invokePrivate("incrementFailureCount", new Class<?>[]{String.class}, "08313000");

        assertEquals(3, failures);
    }

    @Test
    void incrementFailureCountResetsWhenDayGapExists() throws Exception {
        Map<String, Object> states = failureStates();
        states.put("08313000", newFailureState(LocalDate.now().minusDays(2), 7));

        int failures = (int) invokePrivate("incrementFailureCount", new Class<?>[]{String.class}, "08313000");

        assertEquals(1, failures);
    }

    @SuppressWarnings("unchecked")
    private Map<String, Object> failureStates() throws Exception {
        Field field = StationProcessorBase.class.getDeclaredField("failureStates");
        field.setAccessible(true);
        return (Map<String, Object>) field.get(processor);
    }

    private Object invokePrivate(String name, Class<?>[] parameterTypes, Object... args) throws Exception {
        Class<?> owner = "incrementFailureCount".equals(name) ? StationProcessorBase.class : StationProcessorUS.class;
        Method method = owner.getDeclaredMethod(name, parameterTypes);
        method.setAccessible(true);
        return method.invoke(processor, args);
    }

    private Object newFailureState(LocalDate day, int count) throws Exception {
        Class<?> type = Class.forName("com.fishfind.water.service.StationProcessorBase$FailureState");
        var constructor = type.getDeclaredConstructor(LocalDate.class, int.class);
        constructor.setAccessible(true);
        return constructor.newInstance(day, count);
    }
}
