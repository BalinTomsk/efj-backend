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

import javax.xml.XMLConstants;
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
 * Coordinates fetch, parse, save, and shared exception handling for one US station at a time.
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
     *
     * @param mli station identifier
     * @param state US state code
     * @param tz station timezone metadata from the database
     */
    @Override
    protected void processStation(String mli, String state, int tz) throws Exception {
        String xml = fetcher.fetch(state, mli);
        List<UsSeriesReading> seriesList = parse(xml);

        log.debug("Saving station readings. country={} station={} state={} series={}", country(), mli, state, seriesList.size());
        dataRepo.saveUsStationData(mli, state, seriesList);
        log.debug("Saved station readings. country={} station={} state={} series={}", country(), mli, state, seriesList.size());
    }

    @Override
    protected Logger logger() {
        return log;
    }

    @Override
    protected String country() {
        return "US";
    }

    @Override
    protected String missingSourceDescription() {
        return "WaterML";
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

        DocumentBuilderFactory factory = newSecureDocumentBuilderFactory();
        Document document = factory.newDocumentBuilder().parse(new InputSource(new StringReader(xml)));

        var xpathFactory = XPathFactory.newInstance();
        xpathFactory.setFeature(XMLConstants.FEATURE_SECURE_PROCESSING, true);
        var xpath = xpathFactory.newXPath();
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

    /**
     * Builds a {@link DocumentBuilderFactory} hardened against XXE attacks for parsing untrusted USGS payloads.
     *
     * <p>External DTDs and entities are disabled so a malicious or tampered WaterML document cannot read
     * local files, reach internal services (SSRF), or trigger entity-expansion denial of service.
     *
     * @return a namespace-aware factory with external entity processing disabled
     * @throws Exception when a security feature cannot be applied by the underlying parser
     */
    private DocumentBuilderFactory newSecureDocumentBuilderFactory() throws Exception {
        DocumentBuilderFactory factory = DocumentBuilderFactory.newInstance();
        factory.setFeature(XMLConstants.FEATURE_SECURE_PROCESSING, true);
        factory.setFeature("http://apache.org/xml/features/disallow-doctype-decl", true);
        factory.setFeature("http://xml.org/sax/features/external-general-entities", false);
        factory.setFeature("http://xml.org/sax/features/external-parameter-entities", false);
        factory.setFeature("http://apache.org/xml/features/nonvalidating/load-external-dtd", false);
        factory.setXIncludeAware(false);
        factory.setExpandEntityReferences(false);
        factory.setNamespaceAware(true);
        return factory;
    }

    private String buildLegacyXml(javax.xml.xpath.XPath xpath, Node timeSeriesNode) throws Exception {
        NodeList valueNodes = (NodeList) xpath.evaluate(
                "./*[local-name()='values']/*[local-name()='value']",
                timeSeriesNode,
                XPathConstants.NODESET
        );

        // USGS does not guarantee sample ordering, so keep the latest sample of each day by timestamp
        // rather than whichever value happens to appear last in the document.
        Map<LocalDate, DailySample> samplesByDay = new LinkedHashMap<>();
        for (int i = 0; i < valueNodes.getLength(); i++) {
            Node valueNode = valueNodes.item(i);
            Node dateTimeAttribute = valueNode.getAttributes() == null ? null : valueNode.getAttributes().getNamedItem("dateTime");
            if (dateTimeAttribute == null) {
                continue;
            }

            OffsetDateTime stamp = parseTimestamp(dateTimeAttribute.getNodeValue());
            String value = normalizeNumericValue(valueNode.getTextContent());
            if (stamp == null || value == null) {
                continue;
            }

            LocalDate day = stamp.toLocalDate();
            DailySample existing = samplesByDay.get(day);
            if (existing == null || stamp.isAfter(existing.stamp())) {
                samplesByDay.put(day, new DailySample(stamp, value));
            }
        }

        StringBuilder xml = new StringBuilder("<root>");
        for (Map.Entry<LocalDate, DailySample> entry : samplesByDay.entrySet()) {
            xml.append("<a d=\"")
                    .append(entry.getKey())
                    .append("\" v=\"")
                    .append(escapeXml(entry.getValue().value()))
                    .append("\" />");
        }
        xml.append("</root>");
        return xml.toString();
    }

    private record DailySample(OffsetDateTime stamp, String value) {
    }

    private OffsetDateTime parseTimestamp(String text) {
        try {
            return OffsetDateTime.parse(text);
        } catch (Exception ignored) {
        }

        try {
            return ZonedDateTime.parse(text).toOffsetDateTime();
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
