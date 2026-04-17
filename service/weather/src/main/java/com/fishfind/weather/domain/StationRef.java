package com.fishfind.weather.domain;

/**
 * Represents a weather station scheduled for Open-Meteo processing.
 *
 * @param mli monitoring location identifier
 * @param latitude station latitude
 * @param longitude station longitude
 * @param state station state code
 */
public record StationRef(String mli, double latitude, double longitude, String state) {
}
