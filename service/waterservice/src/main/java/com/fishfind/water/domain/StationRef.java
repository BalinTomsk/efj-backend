package com.fishfind.water.domain;

/**
 * Lightweight station reference loaded from the WaterStation table.
 *
 * @param mli station identifier
 * @param state Canadian province code used in the CSV URL
 * @param tz timezone offset metadata stored with the station
 */
public record StationRef(String mli, String state, int tz) {}
