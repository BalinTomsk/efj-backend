package com.fishfind.water.service;

import com.fishfind.water.domain.UsSeriesReading;
import com.fishfind.water.repo.WaterDataRepository;
import org.junit.jupiter.api.Test;

import java.io.FileNotFoundException;
import java.lang.reflect.Method;
import java.util.List;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertThrows;
import static org.junit.jupiter.api.Assertions.assertTrue;
import static org.mockito.Mockito.doThrow;
import static org.mockito.Mockito.mock;
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
    private final StationProcessorUS processor = new StationProcessorUS(fetcher, dataRepo);

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
    }

    @Test
    void processDoesNotThrowWhenStationFetchFails() throws Exception {
        doThrow(new RuntimeException("fetch failed")).when(fetcher).fetch("NM", "08313000");

        processor.process("08313000", "NM", -7);
    }

    @Test
    void processDoesNotThrowWhenSourceWaterMlIsMissing() throws Exception {
        doThrow(new FileNotFoundException("HTTP error 404")).when(fetcher).fetch("NM", "08313000");

        processor.process("08313000", "NM", -7);
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
    void parseKeepsLatestSampleOfEachDayRegardlessOfDocumentOrder() throws Exception {
        // USGS does not guarantee document ordering; the daily value must be the latest sample by
        // timestamp, not whichever happens to appear last in the payload.
        String xml = """
                <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
                <ns1:timeSeriesResponse xmlns:ns1="http://www.cuahsi.org/waterML/1.1/">
                  <ns1:timeSeries name="USGS:01519200:00060:00000">
                    <ns1:variable>
                      <ns1:variableName>Discharge, ft&amp;#179;/s</ns1:variableName>
                    </ns1:variable>
                    <ns1:values>
                      <ns1:value qualifiers="P" dateTime="2026-03-23T20:00:00.000-04:00">999</ns1:value>
                      <ns1:value qualifiers="P" dateTime="2026-03-23T08:00:00.000-04:00">111</ns1:value>
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
                new UsSeriesReading("Discharge", "ft^3/s", "<root><a d=\"2026-03-23\" v=\"999\" /></root>")
        ), series);
    }

    @Test
    void parseRejectsXxePayloadInsteadOfExpandingEntities() throws Exception {
        // Classic XXE: a DOCTYPE declaring an external entity that, if expanded, would read a local file.
        String maliciousXml = """
                <?xml version="1.0" encoding="UTF-8"?>
                <!DOCTYPE timeSeriesResponse [
                  <!ENTITY xxe SYSTEM "file:///etc/passwd">
                ]>
                <ns1:timeSeriesResponse xmlns:ns1="http://www.cuahsi.org/waterML/1.1/">
                  <ns1:timeSeries name="USGS:00000000:00060:00000">
                    <ns1:variable>
                      <ns1:variableName>Discharge &xxe;, ft</ns1:variableName>
                    </ns1:variable>
                  </ns1:timeSeries>
                </ns1:timeSeriesResponse>
                """;

        Exception thrown = assertThrows(Exception.class, () -> invokePrivate(
                "parse",
                new Class<?>[]{String.class},
                maliciousXml
        ));

        Throwable cause = thrown instanceof java.lang.reflect.InvocationTargetException ite ? ite.getCause() : thrown;
        // disallow-doctype-decl makes the parser reject the document outright (it never expands the entity).
        assertTrue(cause instanceof org.xml.sax.SAXParseException,
                "expected the hardened parser to reject the DOCTYPE, got: " + cause);
    }

    private Object invokePrivate(String name, Class<?>[] parameterTypes, Object... args) throws Exception {
        Method method = StationProcessorUS.class.getDeclaredMethod(name, parameterTypes);
        method.setAccessible(true);
        return method.invoke(processor, args);
    }
}
