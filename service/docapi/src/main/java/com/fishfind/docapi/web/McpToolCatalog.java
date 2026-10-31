package com.fishfind.docapi.web;

import com.fasterxml.jackson.core.JsonProcessingException;
import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.fasterxml.jackson.databind.node.ArrayNode;
import com.fasterxml.jackson.databind.node.ObjectNode;
import com.fishfind.docapi.domain.DocumentType;
import com.fishfind.docapi.repo.CatchLog;
import com.fishfind.docapi.repo.CatchLogCommandRepository;
import com.fishfind.docapi.repo.FishQueryRepository;
import com.fishfind.docapi.repo.RegulationQueryRepository;
import com.fishfind.docapi.repo.RiverQueryRepository;
import com.fishfind.docapi.repo.RiverSearchCriteria;
import com.fishfind.docapi.service.DocumentNotFoundException;
import com.fishfind.docapi.service.InvalidDocumentException;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.stereotype.Component;

import java.security.SecureRandom;
import java.time.LocalDate;
import java.time.LocalDateTime;
import java.time.ZoneOffset;
import java.time.format.DateTimeParseException;
import java.util.ArrayList;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Locale;
import java.util.Map;
import java.util.Set;
import java.util.UUID;
import java.util.function.BiFunction;
import java.util.function.Function;
import java.util.regex.Pattern;

/**
 * The tools {@link McpController} offers an MCP client — READS of public water-body data, calling the same
 * repositories the REST endpoints do, plus (1.29.0) admin-only catch-log writes. No {@code /unfished} (an editorial
 * work queue), no news.
 *
 * <p><strong>The writes</strong> (1.29.0, on request): {@code add_catch_log} and {@code add_catch_log_photo}
 * add a catch log, e.g. one taken from a news article. They exist only for the key's owning account (cproxy
 * 0.27.0's {@value McpCaller#USER_HEADER}) when it is one of {@code docapi.mcp.write-users}, the portal's two
 * admin accounts; the log is recorded under it. Any other key, an operator key from {@code mcp-keys.py} (no
 * account) included, does not see them. {@code update_catch_log} (1.30.0) edits only a log the same account
 * authored; nothing here deletes: an MCP client is a model acting for someone, and the person reviews before it
 * writes.
 *
 * <p><strong>Weather</strong> (1.30.0) is filled the way the portal's catch-log form fills it: each value the
 * caller leaves out comes from the water body's station forecast for the catch date
 * ({@code fn_catch_weather_snapshot}; about 15 days are kept, so an older date gets nothing). The result's
 * {@code stationWeather} lists the values that came from the station, so a reviewer can tell them from stated ones.
 *
 * <p>Every argument is validated <strong>before</strong> a repository is called. A malformed GUID
 * passed through would be a SQL conversion error, i.e. a failure counted by the shared
 * {@code sqlBreaker}, and a model retrying a bad call in a loop could then open the breaker for the
 * whole API. A bad argument is an {@link InvalidDocumentException}, which the controller turns into a
 * tool error the model can read and correct.
 *
 * <p><strong>No tool returns a photo, nor any trace of one</strong> (user decision, 2026-09-30). The
 * description document carries an {@code images} gallery and the source/mouth documents a {@code pic},
 * and a future document may add another; rather than trimming each tool, every result passes through
 * {@link #stripPhotos} on its way out, so a new tool cannot leak one by omission. {@code add_catch_log_photo}
 * takes a photo IN (by URL, see {@link CatchPhotoFetcher}); its result, too, carries only a count. Results are also
 * shaped for a model's context window: {@code search_water_bodies} is capped at
 * {@value #SEARCH_MAX_LIMIT}.
 *
 * <p><strong>Canada and the USA</strong> (1.25.0). 1.21.0 limited every tool to Canadian water bodies (a CGNDB/CGNDM
 * code, or a source or mouth in Canada); that block was removed on request, so search, tributaries and the GUID lookups
 * cover every water body, and the regulation and species tools take country {@code CA} or {@code US}.
 *
 * <p><strong>Fish information is for admins only</strong> (1.21.0). The caller's role is cproxy's
 * {@code X-Fish-Role} (the MCP key's owning account; hand-made operator keys are admin). For anyone but
 * {@link ViewerRole#ADMIN} the fish tools ({@code adminOnly}) are absent from {@code tools/list} and unknown
 * to {@code tools/call}, and {@code get_water_body} drops its species list. A missing or unrecognised role is
 * GUEST: fail closed.
 *
 * <p><strong>One entry per species</strong> (1.20.1). {@code dbo.lake_fish}'s primary key is
 * {@code (lake_Id, fish_Id, probability)}, so a species can have several rows on one water body, one per
 * probability level, each a separate evidence entry. The REST endpoints return them all. A model reading
 * them as a list took them for duplicates, so the MCP tools return each species once: the
 * highest-probability row ({@link #uniqueSpecies}), applied to {@code get_water_body_fish} and to the
 * {@code fish} list inside {@code get_water_body}.
 */
@Component
public class McpToolCatalog {

    static final int SEARCH_DEFAULT_LIMIT = 20;
    static final int SEARCH_MAX_LIMIT = 50;

    /** Same bound as {@code FishController.MAX_TERM}. */
    static final int FISH_MAX_TERM = 64;

    static final int WATER_BODIES_DEFAULT_LIMIT = 20;
    static final int WATER_BODIES_MAX_LIMIT = 50;

    /**
     * Water-body type names a model may pass, mapped to {@code dbo.lake.locType} bits (see the column
     * comment in {@code envfish-db/mssql/script01_createTable.sql}). Names rather than numbers, because a
     * model cannot be expected to know the bitmask.
     */
    static final Map<String, Integer> WATER_BODY_TYPES = Map.ofEntries(
            Map.entry("lake", 1), Map.entry("river", 2), Map.entry("stream", 4), Map.entry("pond", 8),
            Map.entry("marsh", 16), Map.entry("backwater", 32), Map.entry("creek", 64),
            Map.entry("canal", 128), Map.entry("estuary", 256), Map.entry("shore", 512),
            Map.entry("drain", 1024), Map.entry("ditch", 2048), Map.entry("wetland", 4096),
            Map.entry("reservoir", 8192));


    /** Output keys that hold a photo or a gallery, at any depth (matched case-insensitively). */
    private static final Set<String> PHOTO_KEYS = Set.of("pic", "pics", "img", "imgs", "image", "images", "picture", "pictures");

    /** Every tool here reads public data and touches nothing outside this service's database. */
    private static final String READ_ONLY_ANNOTATIONS =
            "{\"readOnlyHint\":true,\"destructiveHint\":false,\"idempotentHint\":true,\"openWorldHint\":false}";

    /** The writes add a row and never change or remove one; a repeated call adds another. */
    private static final String OPEN_WORLD_FALSE =
            "{\"readOnlyHint\":false,\"destructiveHint\":false,\"idempotentHint\":false,\"openWorldHint\":false}";

    /** {@code update_catch_log}: replaces the values it is given; the same call twice leaves the same log. */
    private static final String UPDATE_ANNOTATIONS =
            "{\"readOnlyHint\":false,\"destructiveHint\":true,\"idempotentHint\":true,\"openWorldHint\":false}";

    /**
     * The portal form's conditions ({@code ddlWeatherCondition}, {@code icon:text}): a {@code weather} value
     * naming one of them (any case) is stored with its icon, anything else as free text with none.
     */
    private static final Map<String, String> WEATHER_ICONS = Map.of(
            "clear", "01d", "partly cloudy", "02d", "cloudy", "03d", "overcast", "04d",
            "rain", "10d", "thunderstorm", "11d", "snow", "13d", "fog", "50d");

    /** As {@link #OPEN_WORLD_FALSE}, and it reaches outside this service (downloads a URL). */
    private static final String OPEN_WORLD_TRUE =
            "{\"readOnlyHint\":false,\"destructiveHint\":false,\"idempotentHint\":false,\"openWorldHint\":true}";

    /** The catch-log fields add_catch_log and update_catch_log share, as JSON-schema properties. */
    private static final String CATCH_LOG_FIELDS = """
                      "species":{"type":"string","maxLength":120,"description":"Species as the source names it, e.g. largemouth bass"},
                      "angler":{"type":"string","maxLength":200,"description":"Who caught it, as the source names them; omit when not named"},
                      "title":{"type":"string","maxLength":200,"description":"Short headline for the log"},
                      "notes":{"type":"string","maxLength":4000,"description":"Every other stated detail, one 'Label: value' per line"},
                      "catchDate":{"type":"string","description":"When it was caught: YYYY-MM-DD, or YYYY-MM-DDTHH:MM local time. Omit when not stated"},
                      "weight":{"type":"number","exclusiveMinimum":0,"maximum":2000},
                      "weightUnit":{"type":"string","enum":["kg","lb"],"description":"Required with weight"},
                      "length":{"type":"number","exclusiveMinimum":0,"maximum":1000},
                      "lengthUnit":{"type":"string","enum":["cm","in"],"description":"Required with length"},
                      "method":{"type":"string","maxLength":200,"description":"How it was caught, e.g. from the bank, trolling, fly"},
                      "tackle":{"type":"string","maxLength":200,"description":"Rod, reel, line"},
                      "lure":{"type":"string","maxLength":200,"description":"Lure or bait"},
                      "airTemp":{"type":"number","minimum":-60,"maximum":60,"description":"Air temperature, degrees C"},
                      "weather":{"type":"string","maxLength":64,"description":"Conditions. Clear, Partly Cloudy, Cloudy, Overcast, Rain, Thunderstorm, Snow or Fog show the portal's icon; other text is stored as given"},
                      "waterTemp":{"type":"number","minimum":-5,"maximum":45,"description":"Water temperature, degrees C"},
                      "released":{"type":"boolean","description":"true released, false kept; omit when not stated"},
                      "lat":{"type":"number","minimum":-90,"maximum":90,"description":"Catch point, only when the source gives it"},
                      "lon":{"type":"number","minimum":-180,"maximum":180},
                      "private":{"type":"boolean","default":false,"description":"true: only the author and admins see it"}""";

    private static final SecureRandom RANDOM = new SecureRandom();

    /**
     * One MCP tool: the metadata {@code tools/list} publishes and the handler {@code tools/call} runs.
     *
     * @param name        the stable tool name a client calls
     * @param title       a human-readable display name
     * @param description what the tool returns, written for the model choosing between tools
     * @param inputSchema JSON Schema of the {@code arguments} object
     * @param annotations behaviour hints (read-only etc.)
     * @param adminOnly   true for fish information: listed and callable for {@link ViewerRole#ADMIN} only
     * @param write       true for the catch-log writes: listed and callable only for the accounts in
     *                    {@code docapi.mcp.write-users}, whatever the role
     * @param handler     (arguments, caller) → result object; throws {@link InvalidDocumentException} or
     *                    {@link DocumentNotFoundException} for a caller mistake
     */
    public record Tool(String name, String title, String description, JsonNode inputSchema,
                       JsonNode annotations, boolean adminOnly, boolean write,
                       BiFunction<JsonNode, McpCaller, JsonNode> handler) {
    }

    private final RiverQueryRepository riverRepository;
    private final RegulationQueryRepository regulationRepository;
    private final FishQueryRepository fishRepository;
    private final CatchLogCommandRepository catchLogRepository;
    private final CatchPhotoFetcher photoFetcher;
    private final ObjectMapper objectMapper;
    private final Set<String> writeUsers;
    private final Map<String, Tool> tools = new LinkedHashMap<>();

    public McpToolCatalog(RiverQueryRepository riverRepository,
                          RegulationQueryRepository regulationRepository,
                          FishQueryRepository fishRepository,
                          CatchLogCommandRepository catchLogRepository,
                          CatchPhotoFetcher photoFetcher,
                          ObjectMapper objectMapper,
                          @Value("${docapi.mcp.write-users:}") String writeUsers) {
        this.riverRepository = riverRepository;
        this.regulationRepository = regulationRepository;
        this.fishRepository = fishRepository;
        this.catchLogRepository = catchLogRepository;
        this.photoFetcher = photoFetcher;
        this.objectMapper = objectMapper;
        this.writeUsers = parseWriteUsers(writeUsers);

        add("search_water_bodies", "Search and rank water bodies",
                "Finds lakes, rivers and other water bodies in Canada and the USA by part of a name, by CGNDB code "
                        + "(a water body in two provinces has one per province, both searchable), "
                        + "by the province's own id for the water body (`stateId`, e.g. a BC Geographical "
                        + "Names id or an Alberta FWMIS waterbody id), by the MLI id of a linked "
                        + "hydrometric station, or by the country/province/state its source or mouth is in "
                        + "(no name needed). Every criterion given must match; `types` narrows the result. "
                        + "`sort` ranks it in this one call: length_desc / length_asc (length, km), area_desc "
                        + "(area, km2), depth_desc (depth, m) — each leaves out water bodies with no value, so "
                        + "{state:ME, types:[river], sort:length_desc, limit:1} is the longest river in Maine. "
                        + "`length` is whole km; equal km are ordered by `lengthM`, the mapped centre line in "
                        + "metres (null when not mapped). Returns `total` (every match) and up to `limit` items "
                        + "from `offset`, each with both codes (`CGNDB`, `CGNDM`) and its `lakeId` GUID — pass "
                        + "that GUID to the other water-body tools.",
                """
                {"type":"object","properties":{
                  "name":{"type":"string","minLength":2,"maxLength":64,
                          "description":"Part of the English, alternative or French name"},
                  "cgndb":{"type":"string","maxLength":10,
                           "description":"National non-GUID id: Canadian Geographical Names Database code (e.g. FEFUL) or US GNIS feature id (e.g. 566885)"},
                  "stateId":{"type":"string","maxLength":32,
                             "description":"The province's own id for the water body, e.g. 39325 (BC Geographical Names id of the Fraser River)"},
                  "mli":{"type":"string","maxLength":64,
                         "description":"Id of a water station linked to the water body, e.g. 02HC024"},
                  "country":{"type":"string","enum":["CA","US","ca","us"],
                             "description":"CA (Canada) or US (USA): water bodies whose source or mouth is there"},
                  "state":{"type":"string","pattern":"^[A-Za-z]{2}$",
                           "description":"Province/territory/state code, e.g. ME, ON or BC: water bodies whose source or mouth is there"},
                  "types":{"type":"array","items":{"type":"string","enum":["lake","river","stream","pond","marsh",
                           "backwater","creek","canal","estuary","shore","drain","ditch","wetland","reservoir"]},
                           "description":"Water-body types to include; omit for all"},
                  "sort":{"type":"string","enum":["name","length_desc","length_asc","area_desc","depth_desc"],"default":"name",
                          "description":"name: best name match first. The others rank by length, area or depth and leave out water bodies without that value"},
                  "offset":{"type":"integer","minimum":0,"default":0,"description":"Items to skip, for the next page"},
                  "limit":{"type":"integer","minimum":1,"maximum":50,"default":20}
                },"additionalProperties":false}""",
                false, (args, role) -> searchWaterBodies(args));

        add("get_water_body", "Water body details",
                "The description of one water body: names, type, description text, physical "
                        + "statistics (length, depth, area, volume), location (lat/lon, province/state, "
                        + "region), source and mouth (with the nearest named road to the mouth, within 10 km), "
                        + "and its waterfalls and dams.",
                guidSchema(), false, this::description);

        add("get_water_body_fish", "Fish species in a water body",
                "Every fish species recorded in one water body, listed once each: the entry with the "
                        + "highest probability (0-100) that the species is present, with its conservation "
                        + "status, last recorded catch and the source link for that entry.",
                guidSchema(), true,
                (args, role) -> uniqueSpecies(found(riverRepository.fish(requireGuid(args)), args)));

        add("get_water_body_links", "Water body source and mouth",
                "Where one water body starts (source) and where it drains (mouth): the linked water "
                        + "body or point for each end, with coordinates, elevation and location.",
                guidSchema(), false, (args, role) -> links(args));

        add("get_water_body_tributaries", "Water bodies flowing into a water body",
                "The rivers, creeks and other water bodies that flow INTO one water body (its "
                        + "tributaries), by name: those whose mouth is this water body, plus the inflows "
                        + "recorded on a lake. `link` says which (mouth / inflow); lat/lon is where it joins. "
                        + "Returns `total` (how many) and up to `limit` of them, each with its `lakeId`. "
                        + "Only direct tributaries: call again on one to go "
                        + "further upstream.",
                """
                {"type":"object","properties":{
                  "guid":{"type":"string","description":"The water body's lakeId GUID, from search_water_bodies"},
                  "limit":{"type":"integer","minimum":1,"maximum":50,"default":20}
                },"required":["guid"],"additionalProperties":false}""",
                false, (args, role) -> tributaries(args));

        add("get_water_body_barriers", "Waterfalls and dams of a water body",
                "The waterfalls and dams on one water body (a river, or the outlet of a lake): name "
                        + "(null for unnamed ones), type, lat/lon, CGNDB code, province and how it was tied "
                        + "to the water body (`linkMethod`). Named ones first.",
                guidSchema(), false,
                (args, role) -> found(riverRepository.barriers(requireGuid(args)), args));

        add("get_water_body_regulations", "Water body fishing regulations",
                "The fishing regulations specific to one water body. Province/state-wide rules also "
                        + "apply; get them with get_region_regulations.",
                guidSchema(), false,
                (args, role) -> found(regulationRepository.lakeRegulation(requireGuid(args)), args));

        add("get_region_regulations", "Regional fishing regulations",
                "Fishing regulations for Canada or the USA, or for one province, territory or state. Country-wide "
                        + "rules and province/state rules are separate sets — the province/state set does not "
                        + "repeat the country rules.",
                """
                {"type":"object","properties":{
                  "country":{"type":"string","enum":["CA","US","ca","us"],"description":"CA (Canada) or US (USA)"},
                  "state":{"type":"string","pattern":"^[A-Za-z]{2}$",
                           "description":"Province/territory/state code, e.g. ON, QC or MN; omit for country-wide rules"}
                },"required":["country"],"additionalProperties":false}""",
                false, (args, role) -> regionRegulations(args));

        add("search_fish", "Search fish species",
                "Finds fish species by common, alternative or Latin name, best match first, each with "
                        + "its `fishId` GUID.",
                """
                {"type":"object","properties":{
                  "query":{"type":"string","minLength":1,"maxLength":64,"description":"e.g. walleye, Sander vitreus"}
                },"required":["query"],"additionalProperties":false}""",
                true, (args, role) -> searchFish(args));

        add("get_fish", "Fish species details",
                "Everything recorded about one fish species except pictures: names, family, description and uses; "
                        + "type (sport, commercial, invading...), water types and habitat with its water conditions "
                        + "(temperature C, pH, oxygen, depth m...); zoology (size in cm/kg, longevity, colours, "
                        + "morphology); spawning (maturity age, egg counts, spawn months with their habitat and "
                        + "conditions); food; the provinces' and states' own species codes and top-species ranks; "
                        + "the monthly catch index (baseline month = 100) and the 28-day lunar catch probability "
                        + "(day 1 new moon, 14 full; only some species have these); moon sensitivity and migration; "
                        + "predators and prey; record catches (lb, in). Get the fishId from search_fish first.",
                """
                {"type":"object","properties":{
                  "fishId":{"type":"string","description":"The species' fishId GUID, from search_fish"}
                },"required":["fishId"],"additionalProperties":false}""",
                true, (args, role) -> fishInfo(args));

        add("find_water_bodies_by_fish", "Water bodies with a fish species",
                "Finds the water bodies where one fish species is recorded, optionally limited to a country (CA or US) "
                        + "and a province/territory/state and water-body types. Returns `total` (how many "
                        + "match) and up to `limit` of them, each once, highest probability first. Get "
                        + "the species' fishId from search_fish first. Probability is that of the "
                        + "species' strongest record there; 0 means a weak or unconfirmed record, so set "
                        + "min_probability (e.g. 50) when you want only well-supported records.",
                """
                {"type":"object","properties":{
                  "fishId":{"type":"string","description":"The species' fishId GUID, from search_fish"},
                  "country":{"type":"string","enum":["CA","US","ca","us"],"description":"CA (Canada) or US (USA); omit for both"},
                  "state":{"type":"string","pattern":"^[A-Za-z]{2}$","description":"Province/territory/state code, e.g. ON or MN"},
                  "types":{"type":"array","items":{"type":"string","enum":["lake","river","stream","pond","marsh",
                           "backwater","creek","canal","estuary","shore","drain","ditch","wetland","reservoir"]},
                           "description":"Water-body types to include; omit for all"},
                  "min_probability":{"type":"integer","minimum":0,"maximum":100,"default":0},
                  "limit":{"type":"integer","minimum":1,"maximum":50,"default":20}
                },"required":["fishId"],"additionalProperties":false}""",
                true, (args, role) -> waterBodiesByFish(args));

        addWrite("add_catch_log", "Add a catch log",
                "Adds a catch log (a caught fish) to one water body, authored by the account that owns this MCP key. "
                        + "Store ONLY what the source states: leave out every field it does not give, never estimate "
                        + "one (no species from a photo, no date from the publication date, no unit conversion). "
                        + "`angler` is who caught it as the source names them (the log is authored by the key's "
                        + "admin account). Details without a field of their own (age, girth, "
                        + "county, record status, source URL) go in `notes`, one per line. Get lakeId from search_water_bodies and, "
                        + "if the species is known, fishId from search_fish. Returns the stored log with its "
                        + "`catchLogId`; pass that to add_catch_log_photo for a picture. Weather: any of airTemp, "
                        + "weather, waterTemp left out is filled from the water body's station forecast for catchDate, "
                        + "as the portal form does (only about 15 days of forecasts are kept); the result's "
                        + "`stationWeather` lists what came from the station. Pass stationWeather false to store only "
                        + "what you give. Not idempotent: calling it twice stores two logs; fix a stored log with "
                        + "update_catch_log.",
                """
                {"type":"object","properties":{
                  "lakeId":{"type":"string","description":"The water body's lakeId GUID, from search_water_bodies"},
                  "fishId":{"type":"string","description":"The species' fishId GUID, from search_fish; omit when unsure"},
%s,
                  "stationWeather":{"type":"boolean","default":true,"description":"Fill weather values left out from the station forecast for catchDate"}
                },"required":["lakeId"],"additionalProperties":false}""".formatted(CATCH_LOG_FIELDS),
                OPEN_WORLD_FALSE, this::addCatchLog);

        addWrite("update_catch_log", "Correct a catch log",
                "Changes a catch log this MCP key's account added (add_catch_log): give catchLogId and only the "
                        + "fields to change; every other value stays as stored. A field set to null is cleared "
                        + "(angler cannot be cleared). Same fields and rules as add_catch_log; the water body and "
                        + "the author cannot change, and nothing is filled from the station. Returns the log as "
                        + "stored. Show the user the change and get a yes first.",
                """
                {"type":"object","properties":{
                  "catchLogId":{"type":"string","description":"From add_catch_log"},
                  "fishId":{"type":["string","null"],"description":"The species' fishId GUID, from search_fish"},
%s
                },"required":["catchLogId"],"additionalProperties":false}""".formatted(nullable(CATCH_LOG_FIELDS)),
                UPDATE_ANNOTATIONS, this::updateCatchLog);

        addWrite("add_catch_log_photo", "Add a photo to a catch log",
                "Downloads one image from an https URL and attaches it to a catch log made with add_catch_log "
                        + "(at most 3 photos per log; call once per photo). The server fetches the image itself; never "
                        + "pass image data. `credit` is required: the photographer or publisher, as the source credits "
                        + "it. JPEG, WebP or PNG up to 5 MB; WebP and PNG are stored as JPEG.",
                """
                {"type":"object","properties":{
                  "catchLogId":{"type":"string","description":"From add_catch_log"},
                  "imageUrl":{"type":"string","maxLength":2048,"description":"https URL of the JPEG, WebP or PNG"},
                  "credit":{"type":"string","maxLength":200,"description":"Photo credit as the source gives it"},
                  "caption":{"type":"string","maxLength":500,"description":"Caption as the source gives it"}
                },"required":["catchLogId","imageUrl","credit"],"additionalProperties":false}""",
                OPEN_WORLD_TRUE, this::addCatchLogPhoto);
    }

    /** The tools {@code caller} may use, in publication order. */
    public List<Tool> tools(McpCaller caller) {
        return tools.values().stream().filter(t -> allowed(t, caller)).toList();
    }

    /** The tool called {@code name} if {@code caller} may use it, else {@code null} (as if it did not exist). */
    public Tool find(String name, McpCaller caller) {
        Tool tool = name == null ? null : tools.get(name);
        return tool != null && allowed(tool, caller) ? tool : null;
    }

    /**
     * A write only for the accounts in {@code docapi.mcp.write-users} (the portal's two admin accounts, the same
     * list as its {@code TDbLayer} admin ids; user decision 2026-10-30), a fish tool only for an admin role,
     * everything else for every caller.
     */
    private boolean allowed(Tool tool, McpCaller caller) {
        if (tool.write()) return caller.userId() != null && writeUsers.contains(caller.userId());
        return !tool.adminOnly() || caller.role() == ViewerRole.ADMIN;
    }

    /** Comma/semicolon-separated GUIDs, canonical form; anything else is a startup error, not a silent skip. */
    static Set<String> parseWriteUsers(String value) {
        java.util.Set<String> ids = new java.util.HashSet<>();
        for (String part : value == null ? new String[0] : value.split("[,;]")) {
            if (!part.isBlank()) ids.add(RiverController.normalizeGuid(part.trim()));
        }
        return Set.copyOf(ids);
    }

    private void add(String name, String title, String description, String inputSchema, boolean adminOnly,
                     BiFunction<JsonNode, ViewerRole, JsonNode> handler) {
        BiFunction<JsonNode, McpCaller, JsonNode> byRole = (args, caller) -> handler.apply(args, caller.role());
        tools.put(name, new Tool(name, title, description, json(inputSchema), json(READ_ONLY_ANNOTATIONS),
                adminOnly, false, byRole.andThen(McpToolCatalog::stripPhotos)));
    }

    /** A write: only for {@link #writeUsers}, and its handler gets the whole caller (it needs the account). */
    private void addWrite(String name, String title, String description, String inputSchema, String annotations,
                          BiFunction<JsonNode, McpCaller, JsonNode> handler) {
        tools.put(name, new Tool(name, title, description, json(inputSchema), json(annotations),
                true, true, handler.andThen(McpToolCatalog::stripPhotos)));
    }

    private JsonNode json(String text) {
        try {
            return objectMapper.readTree(text);
        } catch (JsonProcessingException ex) {
            throw new IllegalStateException("Malformed MCP tool metadata: " + text, ex);
        }
    }

    private static String guidSchema() {
        return """
                {"type":"object","properties":{
                  "guid":{"type":"string","description":"The water body's lakeId GUID, from search_water_bodies"}
                },"required":["guid"],"additionalProperties":false}""";
    }

    // ---- handlers ------------------------------------------------------------------------------

    private JsonNode searchWaterBodies(JsonNode args) {
        String name = optionalText(args, "name");
        String cgndb = optionalText(args, "cgndb");
        String stateId = optionalText(args, "stateId");
        String mli = optionalText(args, "mli");
        String country = requireCountry(optionalText(args, "country"));
        String state = optionalText(args, "state");
        state = state == null ? null : RegulationController.requireCode(state, "state");
        if (name == null && cgndb == null && stateId == null && mli == null && country == null && state == null) {
            throw new InvalidDocumentException("Give at least one of name, cgndb, stateId, mli, country, state");
        }
        if (name != null && (name.length() < RiverController.SEARCH_MIN_NAME
                || name.length() > RiverController.SEARCH_MAX_TERM)) {
            throw new InvalidDocumentException("name must be " + RiverController.SEARCH_MIN_NAME + " to "
                    + RiverController.SEARCH_MAX_TERM + " characters");
        }
        if (cgndb != null) {
            cgndb = cgndb.toUpperCase(Locale.ROOT);
            if (!RiverController.CGNDB_PATTERN.matcher(cgndb).matches()) {
                throw new InvalidDocumentException("cgndb must be 1 to 10 letters or digits");
            }
        }
        if (stateId != null) {
            RiverController.checkStateId(stateId);
        }
        if (mli != null && mli.length() > RiverController.SEARCH_MAX_TERM) {
            throw new InvalidDocumentException("mli must not exceed " + RiverController.SEARCH_MAX_TERM + " characters");
        }
        Integer locType = waterBodyTypes(args.get("types"));
        String sort = RiverController.requireSort(optionalText(args, "sort"));
        int offset = boundedInt(args, "offset", 0, 0, RiverController.SEARCH_MAX_OFFSET);
        int limit = limit(args);

        JsonNode result = riverRepository.search(new RiverSearchCriteria(name, null, cgndb, stateId, mli,
                country, state, locType, sort, offset, limit));
        if (result instanceof ObjectNode out) {
            ObjectNode query = out.putObject("query");
            query.put("country", country);
            query.put("state", state);
            query.put("locType", locType);
            query.put("sort", sort);
        }
        return result;
    }

    private JsonNode description(JsonNode args, ViewerRole role) {
        JsonNode doc = uniqueSpecies(found(riverRepository.description(requireGuid(args)), args));
        if (role != ViewerRole.ADMIN && doc instanceof ObjectNode o) {
            o.remove("fish");   // fish information is for admins only
        }
        return doc;
    }

    /**
     * Collapses the document's {@code fish} array to one entry per {@code fishId}, keeping the entry with
     * the highest {@code probability}; on a tie, or where there is no probability (the description's list
     * has none), the first one. First-appearance order is kept, so the SQL's name order survives. Entries
     * without a {@code fishId} are kept as they are. Mutates and returns {@code document}.
     */
    static JsonNode uniqueSpecies(JsonNode document) {
        if (!(document instanceof ObjectNode doc) || !(doc.get("fish") instanceof ArrayNode fish)) {
            return document;
        }
        Map<String, JsonNode> best = new LinkedHashMap<>();
        int unkeyed = 0;
        for (JsonNode entry : fish) {
            String id = entry.path("fishId").asText("");
            if (id.isEmpty()) {
                best.put("#unkeyed-" + unkeyed++, entry);
                continue;
            }
            String key = id.toLowerCase(Locale.ROOT);
            JsonNode kept = best.get(key);
            if (kept == null || probability(entry) > probability(kept)) {
                best.put(key, entry);
            }
        }
        ArrayNode unique = doc.arrayNode();
        best.values().forEach(unique::add);
        doc.set("fish", unique);
        return doc;
    }

    /** An entry's probability, or -1 where it has none, so any real value outranks a missing one. */
    private static int probability(JsonNode entry) {
        JsonNode p = entry.get("probability");
        return p != null && p.canConvertToInt() ? p.asInt() : -1;
    }

    private JsonNode links(JsonNode args) {
        String guid = requireGuid(args);
        JsonNode source = riverRepository.source(guid);
        if (source == null) {
            throw new DocumentNotFoundException(DocumentType.WATERBODY, guid);
        }
        ObjectNode out = objectMapper.createObjectNode();
        out.set("source", source);
        out.set("mouth", riverRepository.mouth(guid));
        return out;
    }

    /** The direct tributaries of one water body; {@code total} counts every one, {@code limit} caps the list. */
    private JsonNode tributaries(JsonNode args) {
        String guid = requireGuid(args);
        int limit = boundedInt(args, "limit", SEARCH_DEFAULT_LIMIT, 1, SEARCH_MAX_LIMIT);
        return found(riverRepository.tributaries(guid, limit), args);
    }

    private JsonNode regionRegulations(JsonNode args) {
        String country = requireCountry(optionalText(args, "country"));
        if (country == null) {
            throw new InvalidDocumentException("country is required (CA or US)");
        }
        String state = optionalText(args, "state");
        return regulationRepository.region(country,
                state == null ? null : RegulationController.requireCode(state, "state"));
    }

    private JsonNode searchFish(JsonNode args) {
        String query = optionalText(args, "query");
        if (query == null) {
            throw new InvalidDocumentException("query is required");
        }
        if (query.length() > FISH_MAX_TERM) {
            query = query.substring(0, FISH_MAX_TERM);
        }
        return objectMapper.valueToTree(fishRepository.search(query));
    }

    /**
     * One species' document, the same as {@code GET /api/v1/fish/{guid}} ({@link FishController#species}); no images,
     * and {@link #stripPhotos} still runs over it on the way out.
     */
    private JsonNode fishInfo(JsonNode args) {
        String fishId = optionalText(args, "fishId");
        if (fishId == null) {
            throw new InvalidDocumentException("fishId is required (get it from search_fish)");
        }
        return FishController.species(fishRepository, fishId);
    }

    // ---- write handlers (1.29.0) ---------------------------------------------------------------

    private JsonNode addCatchLog(JsonNode args, McpCaller caller) {
        String userId = requireAuthor(caller);
        String lakeId = optionalText(args, "lakeId");
        if (lakeId == null) {
            throw new InvalidDocumentException("lakeId is required (get it from search_water_bodies)");
        }
        lakeId = RiverController.normalizeGuid(lakeId);
        CatchLog blank = new CatchLog(uuidV7(), lakeId, userId, null, null, null, null, null, null, null, null, null,
                null, null, null, null, null, null, null, false, CatchLog.Weather.NONE);
        CatchLog log = merge(blank, args);
        List<String> fromStation = new ArrayList<>();
        if (log.catchDate() != null && !Boolean.FALSE.equals(optionalBoolean(args, "stationWeather"))) {
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

    private JsonNode updateCatchLog(JsonNode args, McpCaller caller) {
        String userId = requireAuthor(caller);
        String catchLogId = optionalText(args, "catchLogId");
        if (catchLogId == null) {
            throw new InvalidDocumentException("catchLogId is required (from add_catch_log)");
        }
        catchLogId = RiverController.normalizeGuid(catchLogId);
        CatchLog current = catchLogRepository.find(catchLogId);
        if (current == null) {
            throw new InvalidDocumentException("No catch log " + catchLogId);
        }
        if (!userId.equalsIgnoreCase(current.userId())) {
            throw new InvalidDocumentException("Catch log " + catchLogId + " was not added by this key's account; "
                    + "only its author's key can change it here (use the portal)");
        }
        JsonNode stored = catchLogRepository.add(merge(current, args));
        if (stored == null) {
            throw new InvalidDocumentException("No catch log " + catchLogId);
        }
        return stored;
    }

    /**
     * {@code base} with every catch-log field present in {@code args} replaced: a value sets it, JSON null clears
     * it, an absent key keeps {@code base}'s. Validates the result (units go with their values, lat with lon) and
     * the species, so nothing malformed reaches SQL.
     */
    private CatchLog merge(CatchLog base, JsonNode args) {
        String fishId = base.fishId();
        if (args.has("fishId")) {
            fishId = optionalText(args, "fishId");
            if (fishId != null) fishId = RiverController.normalizeGuid(fishId);
        }
        Double weight = args.has("weight") ? optionalNumber(args, "weight", 0, 2000) : base.weight();
        String weightUnit = args.has("weightUnit") ? unitValue(args, "weightUnit", Set.of("kg", "lb")) : base.weightUnit();
        Double length = args.has("length") ? optionalNumber(args, "length", 0, 1000) : base.length();
        String lengthUnit = args.has("lengthUnit") ? unitValue(args, "lengthUnit", Set.of("cm", "in")) : base.lengthUnit();
        pair(weight, weightUnit, "weight", "weightUnit");
        pair(length, lengthUnit, "length", "lengthUnit");
        Double lat = args.has("lat") ? optionalNumber(args, "lat", -90, 90) : base.lat();
        Double lon = args.has("lon") ? optionalNumber(args, "lon", -180, 180) : base.lon();
        if ((lat == null) != (lon == null)) {
            throw new InvalidDocumentException("lat and lon go together");
        }
        CatchLog.Weather w = base.weather();
        Double temp = args.has("airTemp") ? optionalNumber(args, "airTemp", -60, 60) : w.temp();
        Double water = args.has("waterTemp") ? optionalNumber(args, "waterTemp", -5, 45) : w.water();
        String text = w.text();
        String icon = w.icon();
        if (args.has("weather")) {
            text = boundedText(args, "weather", 64);
            icon = text == null ? null : WEATHER_ICONS.get(text.toLowerCase(Locale.ROOT));
        }
        CatchLog log = new CatchLog(base.id(), base.lakeId(), base.userId(), fishId,
                text(args, "species", 120, base.species()), text(args, "angler", 200, base.angler()),
                text(args, "title", 200, base.title()), text(args, "notes", 4000, base.text()),
                lat, lon, text(args, "method", 200, base.method()), text(args, "tackle", 200, base.tackle()),
                text(args, "lure", 200, base.lure()),
                args.has("catchDate") ? catchDate(optionalText(args, "catchDate")) : base.catchDate(),
                weight, weightUnit, length, lengthUnit,
                args.has("released") ? optionalBoolean(args, "released") : base.released(),
                args.has("private") ? Boolean.TRUE.equals(optionalBoolean(args, "private")) : base.isPrivate(),
                new CatchLog.Weather(temp, w.pressure(), text, icon, water));
        // Checked before the write, outside it: an unknown species is the caller's mistake, never a breaker failure.
        if (fishId != null && !fishId.equalsIgnoreCase(base.fishId()) && !catchLogRepository.fishExists(fishId)) {
            throw new InvalidDocumentException("fishId " + fishId + " is not a known species (get it from search_fish)");
        }
        return log;
    }

    /** A text field: {@code fallback} when the key is absent, else the bounded value (null clears it). */
    private static String text(JsonNode args, String key, int max, String fallback) {
        return args.has(key) ? boundedText(args, key, max) : fallback;
    }

    private JsonNode addCatchLogPhoto(JsonNode args, McpCaller caller) {
        String userId = requireAuthor(caller);
        String catchLogId = optionalText(args, "catchLogId");
        if (catchLogId == null) {
            throw new InvalidDocumentException("catchLogId is required (from add_catch_log)");
        }
        catchLogId = RiverController.normalizeGuid(catchLogId);
        String imageUrl = boundedText(args, "imageUrl", 2048);
        if (imageUrl == null) {
            throw new InvalidDocumentException("imageUrl is required");
        }
        String credit = boundedText(args, "credit", 200);
        if (credit == null) {
            throw new InvalidDocumentException("credit is required: the photographer or publisher the source credits");
        }
        String caption = boundedText(args, "caption", 500);
        CatchPhotoFetcher.check(imageUrl);   // refuse a bad URL before touching the database
        int photos = catchLogRepository.photoCount(catchLogId);
        if (photos < 0) {
            throw new InvalidDocumentException("No catch log " + catchLogId);
        }
        if (photos >= CatchLogCommandRepository.MAX_PHOTOS) {
            throw new InvalidDocumentException("Catch log " + catchLogId + " already has "
                    + CatchLogCommandRepository.MAX_PHOTOS + " photos");
        }
        byte[] jpeg = photoFetcher.fetch(imageUrl);
        JsonNode stored = catchLogRepository.addPhoto(catchLogId, userId, jpeg, photos, caption, credit);
        if (stored == null) {
            throw new InvalidDocumentException("No catch log " + catchLogId);
        }
        return stored;
    }

    /** The account a write is recorded under; a key that belongs to no account cannot write. */
    private static String requireAuthor(McpCaller caller) {
        if (caller.userId() == null) {
            throw new InvalidDocumentException("Adding catch logs needs an MCP key created on the portal (Profile, "
                    + "MCP tab) by one of the two admin accounts; this key belongs to no account");
        }
        return caller.userId();
    }

    /** YYYY-MM-DD (stored as midnight) or YYYY-MM-DDTHH:MM[:SS]; null when absent; never in the future. */
    static LocalDateTime catchDate(String value) {
        if (value == null) return null;
        LocalDateTime parsed;
        try {
            parsed = value.length() <= 10 ? LocalDate.parse(value).atStartOfDay() : LocalDateTime.parse(value);
        } catch (DateTimeParseException ex) {
            throw new InvalidDocumentException("catchDate must be YYYY-MM-DD or YYYY-MM-DDTHH:MM");
        }
        if (parsed.isAfter(LocalDateTime.now(ZoneOffset.UTC).plusDays(1))) {
            throw new InvalidDocumentException("catchDate is in the future");
        }
        return parsed;
    }

    /** A unit argument, lower-cased and checked against {@code allowed}; null when absent or JSON null. */
    private static String unitValue(JsonNode args, String key, Set<String> allowed) {
        String unit = optionalText(args, key);
        if (unit == null) return null;
        unit = unit.toLowerCase(Locale.ROOT);
        if (!allowed.contains(unit)) {
            throw new InvalidDocumentException(key + " must be one of " + String.join(", ", new java.util.TreeSet<>(allowed)));
        }
        return unit;
    }

    /** A unit must come with its value and only with it. */
    private static void pair(Double value, String unit, String valueKey, String unitKey) {
        if (value != null && unit == null) throw new InvalidDocumentException(unitKey + " is required with " + valueKey);
        if (value == null && unit != null) throw new InvalidDocumentException(unitKey + " given without " + valueKey);
    }

    /**
     * The shared field schema for {@code update_catch_log}, where JSON null clears a field: every
     * {@code "type":"string"} / {@code "number"} / {@code "boolean"} also admits null.
     */
    static String nullable(String fields) {
        return fields.replaceAll("\\{\"type\":\"(string|number|boolean)\"", "{\"type\":[\"$1\",\"null\"]");
    }

    /** A trimmed string of at most {@code max} characters, or null; longer is a caller error, never cut. */
    private static String boundedText(JsonNode args, String key, int max) {
        String v = optionalText(args, key);
        if (v != null && v.length() > max) {
            throw new InvalidDocumentException(key + " must not exceed " + max + " characters");
        }
        return v;
    }

    /** A number in (min, max] for 0 minimums, [min, max] otherwise; null when absent. */
    private static Double optionalNumber(JsonNode args, String key, double min, double max) {
        JsonNode node = args.get(key);
        if (node == null || node.isNull()) return null;
        if (!node.isNumber()) {
            throw new InvalidDocumentException(key + " must be a number");
        }
        double v = node.asDouble();
        boolean low = min == 0 ? v <= 0 : v < min;
        if (low || v > max || Double.isNaN(v)) {
            throw new InvalidDocumentException(key + " must be " + (min == 0 ? "above 0" : "at least " + min)
                    + " and at most " + max);
        }
        return v;
    }

    private static Boolean optionalBoolean(JsonNode args, String key) {
        JsonNode node = args.get(key);
        if (node == null || node.isNull()) return null;
        if (!node.isBoolean()) {
            throw new InvalidDocumentException(key + " must be true or false");
        }
        return node.asBoolean();
    }

    /** A time-ordered (version 7) UUID, like the portal's {@code Guid.CreateVersion7()} for catch logs. */
    static String uuidV7() {
        long millis = System.currentTimeMillis();
        long rand = RANDOM.nextLong();
        long msb = (millis << 16) | 0x7000L | (RANDOM.nextInt() & 0x0fffL);
        long lsb = (rand & 0x3fffffffffffffffL) | 0x8000000000000000L;
        return new UUID(msb, lsb).toString();
    }

    /**
     * Removes every photo from a result, in place, at any depth: a key in {@link #PHOTO_KEYS}, or any key
     * starting with {@code photo} ({@code photo}, {@code photos}, {@code photo0}, {@code photoBase64}...).
     */
    static JsonNode stripPhotos(JsonNode node) {
        if (node instanceof ObjectNode object) {
            object.properties().removeIf(e -> isPhotoKey(e.getKey()));
            object.forEach(McpToolCatalog::stripPhotos);
        } else if (node != null && node.isArray()) {
            node.forEach(McpToolCatalog::stripPhotos);
        }
        return node;
    }

    private static boolean isPhotoKey(String key) {
        String k = key.toLowerCase(Locale.ROOT);
        return PHOTO_KEYS.contains(k) || k.startsWith("photo");
    }

    private JsonNode waterBodiesByFish(JsonNode args) {
        String fishId = requireFishId(args);
        String country = requireCountry(optionalText(args, "country"));   // null = both countries
        String state = optionalText(args, "state");
        state = state == null ? null : RegulationController.requireCode(state, "state");
        Integer locType = waterBodyTypes(args.get("types"));
        int minProbability = boundedInt(args, "min_probability", 0, 0, 100);
        int limit = boundedInt(args, "limit", WATER_BODIES_DEFAULT_LIMIT, 1, WATER_BODIES_MAX_LIMIT);

        JsonNode result = fishRepository.waterBodies(fishId, country, state, locType, minProbability, limit);
        if (result instanceof ObjectNode out) {
            ObjectNode query = out.putObject("query");
            query.put("fishId", fishId);
            query.put("country", country);
            query.put("state", state);
            query.put("locType", locType);
            query.put("minProbability", minProbability);
        }
        return result;
    }

    /** The {@code types} names as a locType bitmask; {@code null} when absent or empty (= any type). */
    private static Integer waterBodyTypes(JsonNode node) {
        if (node == null || node.isNull()) return null;
        if (!node.isArray()) {
            throw new InvalidDocumentException("types must be an array of water-body type names");
        }
        int mask = 0;
        for (JsonNode t : node) {
            Integer bit = t.isTextual() ? WATER_BODY_TYPES.get(t.asText().trim().toLowerCase(Locale.ROOT)) : null;
            if (bit == null) {
                throw new InvalidDocumentException("Unknown water-body type '" + t.asText()
                        + "'; use: " + String.join(", ", new java.util.TreeSet<>(WATER_BODY_TYPES.keySet())));
            }
            mask |= bit;
        }
        return mask == 0 ? null : mask;
    }

    /** An integer argument: default when absent, a caller error when not an integer, clamped to min..max. */
    private static int boundedInt(JsonNode args, String key, int fallback, int min, int max) {
        JsonNode node = args.get(key);
        if (node == null || node.isNull()) return fallback;
        int n;
        if (node.canConvertToInt() && node.isIntegralNumber()) {
            n = node.asInt();
        } else if (node.isTextual()) {
            try {
                n = Integer.parseInt(node.asText().trim());
            } catch (NumberFormatException ex) {
                throw new InvalidDocumentException(key + " must be an integer");
            }
        } else {
            throw new InvalidDocumentException(key + " must be an integer");
        }
        return Math.max(min, Math.min(n, max));
    }

    // ---- argument helpers ----------------------------------------------------------------------

    /** A water-body document, or a not-found for the GUID the caller gave. */
    private static JsonNode found(JsonNode document, JsonNode args) {
        if (document == null) {
            throw new DocumentNotFoundException(DocumentType.WATERBODY, args.path("guid").asText());
        }
        return document;
    }

    /** {@code CA} or {@code US} (any case), {@code null} when absent; anything else is a caller error. */
    private static String requireCountry(String country) {
        if (country == null) return null;
        String c = country.trim().toUpperCase(Locale.ROOT);
        if (c.equals("CA") || c.equals("US")) return c;
        throw new InvalidDocumentException("country must be CA or US");
    }

    /** The {@code guid} argument in canonical form; anything that is not a GUID never reaches SQL. */
    private static String requireGuid(JsonNode args) {
        String guid = optionalText(args, "guid");
        if (guid == null) {
            throw new InvalidDocumentException("guid is required");
        }
        return RiverController.normalizeGuid(guid);
    }

    /** The {@code fishId} argument in canonical form; anything that is not a GUID never reaches SQL. */
    private static String requireFishId(JsonNode args) {
        String fishId = optionalText(args, "fishId");
        if (fishId == null) {
            throw new InvalidDocumentException("fishId is required (get it from search_fish)");
        }
        return RiverController.normalizeGuid(fishId);
    }

    /** A trimmed string argument, or {@code null} when absent/blank; a non-string is a caller error. */
    private static String optionalText(JsonNode args, String key) {
        JsonNode node = args.get(key);
        if (node == null || node.isNull()) return null;
        if (!node.isTextual()) {
            throw new InvalidDocumentException(key + " must be a string");
        }
        String v = node.asText().trim();
        return v.isEmpty() ? null : v;
    }

    /** {@code limit}: default {@value #SEARCH_DEFAULT_LIMIT}, clamped to 1..{@value #SEARCH_MAX_LIMIT}. */
    private static int limit(JsonNode args) {
        JsonNode node = args.get("limit");
        if (node == null || node.isNull()) return SEARCH_DEFAULT_LIMIT;
        if (!node.canConvertToInt() && !node.isTextual()) {
            throw new InvalidDocumentException("limit must be an integer");
        }
        int n;
        try {
            n = node.isTextual() ? Integer.parseInt(node.asText().trim()) : node.asInt();
        } catch (NumberFormatException ex) {
            throw new InvalidDocumentException("limit must be an integer");
        }
        return Math.max(1, Math.min(n, SEARCH_MAX_LIMIT));
    }
}
