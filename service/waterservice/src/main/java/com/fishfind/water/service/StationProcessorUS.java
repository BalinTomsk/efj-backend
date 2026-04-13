package com.fishfind.water.service;

import com.fishfind.water.domain.UsSeriesReading;
import com.fishfind.water.repo.WaterDataRepository;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.stereotype.Service;
import org.w3c.dom.Document;
import org.w3c.dom.Node;
import org.w3c.dom.NodeList;
import org.xml.sax.InputSource;

import javax.xml.parsers.DocumentBuilderFactory;
import javax.xml.xpath.XPathConstants;
import javax.xml.xpath.XPathFactory;
import java.io.StringReader;
import java.time.LocalDate;
import java.time.OffsetDateTime;
import java.time.ZonedDateTime;
import java.util.ArrayList;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;

/**
 * Coordinates fetch, parse, save, and failure tracking for one US station at a time.
 */
@Service
public class StationProcessorUS extends StationProcessorBase {
    private static final Logger log = LoggerFactory.getLogger(StationProcessorUS.class);

    private final XmlFetcherUS fetcher;
    private final WaterDataRepository dataRepo;

    /**
     * Creates a processor with the collaborators required for US station handling.
     *
     * @param fetcher XML fetcher used to download source data
     * @param dataRepo repository used to persist parsed series
     */
    public StationProcessorUS(XmlFetcherUS fetcher,
                              WaterDataRepository dataRepo) {
        this.fetcher = fetcher;
        this.dataRepo = dataRepo;
    }

    /**
     * Processes one US station by downloading its WaterML document, parsing variables, and persisting them.
     * Repeated failures are tracked as a consecutive-day streak for logging.
     *
     * @param mli station identifier
     * @param state US state code
     * @param tz station timezone metadata from the database
     */
    @Override
    protected void processStation(String mli, String state, int tz) throws Exception {
        String xml = fetcher.fetch(state, mli);
        List<UsSeriesReading> seriesList = parse(xml);

        log.debug("Saving US station readings. station={} state={} series={}", mli, state, seriesList.size());
        dataRepo.saveUsStationData(mli, state, seriesList);
        log.debug("Saved US station readings. station={} state={} series={}", mli, state, seriesList.size());
    }

    @Override
    protected Logger logger() {
        return log;
    }

    @Override
    protected String processingFailureMessage() {
        return "US station processing failed. station={} state={} failureStreakDays={}";
    }

    /**
     * Parses USGS WaterML into stored-procedure payloads, one payload per variable.
     *
     * @param xml raw WaterML document
     * @return parsed series payloads
     * @throws Exception when XML parsing fails
     */
    List<UsSeriesReading> parse(String xml) throws Exception {
        if (xml == null || xml.isBlank()) {
            return List.of();
        }

        DocumentBuilderFactory factory = DocumentBuilderFactory.newInstance();
        factory.setNamespaceAware(true);
        Document document = factory.newDocumentBuilder().parse(new InputSource(new StringReader(xml)));

        var xpath = XPathFactory.newInstance().newXPath();
        NodeList timeSeriesNodes = (NodeList) xpath.evaluate(
                "/*[local-name()='timeSeriesResponse']/*[local-name()='timeSeries']",
                document,
                XPathConstants.NODESET
        );

        List<UsSeriesReading> results = new ArrayList<>();
        for (int i = 0; i < timeSeriesNodes.getLength(); i++) {
            Node timeSeriesNode = timeSeriesNodes.item(i);
            String fullName = xpath.evaluate(
                    "./*[local-name()='variable']/*[local-name()='variableName']/text()",
                    timeSeriesNode
            );
            if (fullName == null || fullName.isBlank()) {
                continue;
            }

            String[] pieces = fullName.split(",", 2);
            String name = pieces[0].trim();
            String unit = pieces.length > 1 ? normalizeUnit(pieces[1].trim()) : null;
            String xmlDoc = buildLegacyXml(xpath, timeSeriesNode);

            if (!xmlDoc.equals("<root></root>")) {
                results.add(new UsSeriesReading(name, unit, xmlDoc));
            }
        }

        return results;
    }

    private String buildLegacyXml(javax.xml.xpath.XPath xpath, Node timeSeriesNode) throws Exception {
        NodeList valueNodes = (NodeList) xpath.evaluate(
                "./*[local-name()='values']/*[local-name()='value']",
                timeSeriesNode,
                XPathConstants.NODESET
        );

        Map<LocalDate, String> valuesByDay = new LinkedHashMap<>();
        for (int i = 0; i < valueNodes.getLength(); i++) {
            Node valueNode = valueNodes.item(i);
            Node dateTimeAttribute = valueNode.getAttributes() == null ? null : valueNode.getAttributes().getNamedItem("dateTime");
            if (dateTimeAttribute == null) {
                continue;
            }

            LocalDate day = parseDate(dateTimeAttribute.getNodeValue());
            String value = normalizeNumericValue(valueNode.getTextContent());
            if (day == null || value == null) {
                continue;
            }

            valuesByDay.put(day, value);
        }

        StringBuilder xml = new StringBuilder("<root>");
        for (Map.Entry<LocalDate, String> entry : valuesByDay.entrySet()) {
            xml.append("<a d=\"")
                    .append(entry.getKey())
                    .append("\" v=\"")
                    .append(escapeXml(entry.getValue()))
                    .append("\" />");
        }
        xml.append("</root>");
        return xml.toString();
    }

    private LocalDate parseDate(String text) {
        try {
            return OffsetDateTime.parse(text).toLocalDate();
        } catch (Exception ignored) {
        }

        try {
            return ZonedDateTime.parse(text).toLocalDate();
        } catch (Exception ignored) {
        }

        return null;
    }

    private String normalizeUnit(String unit) {
        return unit.replace("&#179;", "^3").replace("³", "^3");
    }

    private String normalizeNumericValue(String value) {
        if (value == null) {
            return null;
        }

        String trimmed = value.trim();
        if (trimmed.isEmpty()) {
            return null;
        }

        try {
            Double.parseDouble(trimmed);
            return trimmed;
        } catch (NumberFormatException ignored) {
            return null;
        }
    }

    private String escapeXml(String value) {
        return value
                .replace("&", "&amp;")
                .replace("\"", "&quot;")
                .replace("<", "&lt;")
                .replace(">", "&gt;");
    }

}
