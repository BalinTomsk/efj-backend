package com.fishfind.water.domain;

/**
 * Parsed USGS time-series payload ready for the legacy stored procedure.
 *
 * @param name variable name, for example {@code Streamflow}
 * @param unit variable unit, for example {@code ft^3/s}
 * @param xmlDoc XML payload in the legacy {@code <root><a d="..." v="..." /></root>} format
 */
public record UsSeriesReading(
        String name,
        String unit,
        String xmlDoc
) {}
