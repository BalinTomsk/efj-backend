package com.fishfind.docapi.web;

import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.node.ArrayNode;
import com.fasterxml.jackson.databind.node.ObjectNode;
import com.fishfind.docapi.domain.DocumentType;
import com.fishfind.docapi.repo.CatchLog;
import com.fishfind.docapi.repo.CatchLogCommandRepository;
import com.fishfind.docapi.service.DocumentNotFoundException;
import com.fishfind.docapi.service.InvalidDocumentException;

import java.util.ArrayList;
import java.util.List;
import java.util.Locale;
import java.util.Set;

/**
 * Builds and stores a catch log from JSON arguments, shared by {@code POST /api/v1/catch} and {@code PATCH /api/v1/catch/{id}} (the routes the MCP server,
 * mcp-env, calls for add_catch_log and update_catch_log): the same fields, the
 * same checks (units go with their values, lat with lon, a known species, no future date) and the same weather
 * fill from the water body's station forecast. The caller decides who the author is and whether they may write.
 */
final class CatchLogWriter {

    private final CatchLogCommandRepository catchLogRepository;

    CatchLogWriter(CatchLogCommandRepository catchLogRepository) {
        this.catchLogRepository = catchLogRepository;
    }

    /**
     * A new log on {@code args.lakeId} by {@code userId} with a fresh id; weather values left out are filled from
     * the station forecast for the catch date unless {@code stationWeather} is false. Returns the stored log plus
     * {@code stationWeather}: the values that came from the station.
     */
    JsonNode add(String userId, JsonNode args) {
        String lakeId = CatchLogArgs.optionalText(args, "lakeId");
        if (lakeId == null) {
            throw new InvalidDocumentException("lakeId is required (get it from search_water_bodies / river/search)");
        }
        lakeId = RiverController.normalizeGuid(lakeId);
        CatchLog blank = new CatchLog(CatchLogArgs.uuidV7(), lakeId, userId, null, null, null, null, null, null, null, null, null,
                null, null, null, null, null, null, null, false, CatchLog.Weather.NONE);
        CatchLog log = merge(blank, args);
        List<String> fromStation = new ArrayList<>();
        if (log.catchDate() != null && !Boolean.FALSE.equals(CatchLogArgs.optionalBoolean(args, "stationWeather"))) {
            CatchLog.Weather given = log.weather();
            CatchLog.Weather station = catchLogRepository.stationWeather(lakeId, log.catchDate().toLocalDate());
            boolean text = given.text() == null && station.text() != null;
            if (given.temp() == null && station.temp() != null) fromStation.add("airTemp");
            if (text) fromStation.add("weather");
            if (given.water() == null && station.water() != null) fromStation.add("waterTemp");
            if (station.pressure() != null) fromStation.add("pressure");
            log = log.withWeather(new CatchLog.Weather(
                    given.temp() != null ? given.temp() : station.temp(),
                    station.pressure(),
                    text ? station.text() : given.text(),
                    text ? station.icon() : given.icon(),
                    given.water() != null ? given.water() : station.water()));
        }
        JsonNode stored = catchLogRepository.add(log);
        if (stored == null) {
            throw new DocumentNotFoundException(DocumentType.WATERBODY, lakeId);
        }
        if (stored instanceof ObjectNode out) {
            ArrayNode list = out.putArray("stationWeather");
            fromStation.forEach(list::add);
        }
        return stored;
    }

    /**
     * {@code base} with every catch-log field present in {@code args} replaced: a value sets it, JSON null clears
     * it, an absent key keeps {@code base}'s. Validates the result (units go with their values, lat with lon) and
     * the species, so nothing malformed reaches SQL.
     */
    CatchLog merge(CatchLog base, JsonNode args) {
        String fishId = base.fishId();
        if (args.has("fishId")) {
            fishId = CatchLogArgs.optionalText(args, "fishId");
            if (fishId != null) fishId = RiverController.normalizeGuid(fishId);
        }
        Double weight = args.has("weight") ? CatchLogArgs.optionalNumber(args, "weight", 0, 2000) : base.weight();
        String weightUnit = args.has("weightUnit") ? CatchLogArgs.unitValue(args, "weightUnit", Set.of("kg", "lb")) : base.weightUnit();
        Double length = args.has("length") ? CatchLogArgs.optionalNumber(args, "length", 0, 1000) : base.length();
        String lengthUnit = args.has("lengthUnit") ? CatchLogArgs.unitValue(args, "lengthUnit", Set.of("cm", "in")) : base.lengthUnit();
        CatchLogArgs.pair(weight, weightUnit, "weight", "weightUnit");
        CatchLogArgs.pair(length, lengthUnit, "length", "lengthUnit");
        Double lat = args.has("lat") ? CatchLogArgs.optionalNumber(args, "lat", -90, 90) : base.lat();
        Double lon = args.has("lon") ? CatchLogArgs.optionalNumber(args, "lon", -180, 180) : base.lon();
        if ((lat == null) != (lon == null)) {
            throw new InvalidDocumentException("lat and lon go together");
        }
        CatchLog.Weather w = base.weather();
        Double temp = args.has("airTemp") ? CatchLogArgs.optionalNumber(args, "airTemp", -60, 60) : w.temp();
        Double water = args.has("waterTemp") ? CatchLogArgs.optionalNumber(args, "waterTemp", -5, 45) : w.water();
        String text = w.text();
        String icon = w.icon();
        if (args.has("weather")) {
            text = CatchLogArgs.boundedText(args, "weather", 64);
            icon = text == null ? null : CatchLogArgs.WEATHER_ICONS.get(text.toLowerCase(Locale.ROOT));
        }
        CatchLog log = new CatchLog(base.id(), base.lakeId(), base.userId(), fishId,
                CatchLogArgs.text(args, "species", 120, base.species()), CatchLogArgs.text(args, "angler", 200, base.angler()),
                CatchLogArgs.text(args, "title", 200, base.title()), CatchLogArgs.text(args, "notes", 4000, base.text()),
                lat, lon, CatchLogArgs.text(args, "method", 200, base.method()), CatchLogArgs.text(args, "tackle", 200, base.tackle()),
                CatchLogArgs.text(args, "lure", 200, base.lure()),
                args.has("catchDate") ? CatchLogArgs.catchDate(CatchLogArgs.optionalText(args, "catchDate")) : base.catchDate(),
                weight, weightUnit, length, lengthUnit,
                args.has("released") ? CatchLogArgs.optionalBoolean(args, "released") : base.released(),
                args.has("private") ? Boolean.TRUE.equals(CatchLogArgs.optionalBoolean(args, "private")) : base.isPrivate(),
                new CatchLog.Weather(temp, w.pressure(), text, icon, water));
        // Checked before the write, outside it: an unknown species is the caller's mistake, never a breaker failure.
        if (fishId != null && !fishId.equalsIgnoreCase(base.fishId()) && !catchLogRepository.fishExists(fishId)) {
            throw new InvalidDocumentException("fishId " + fishId + " is not a known species (get it from search_fish / fish/search)");
        }
        return log;
    }

}
