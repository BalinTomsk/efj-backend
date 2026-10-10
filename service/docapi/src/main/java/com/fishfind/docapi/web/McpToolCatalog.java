package com.fishfind.docapi.web;

import com.fasterxml.jackson.core.JsonProcessingException;
import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.fasterxml.jackson.databind.node.ArrayNode;
import com.fasterxml.jackson.databind.node.ObjectNode;
import com.fishfind.docapi.domain.DocumentType;
import com.fishfind.docapi.repo.FishQueryRepository;
import com.fishfind.docapi.repo.RegulationQueryRepository;
import com.fishfind.docapi.repo.RiverQueryRepository;
import com.fishfind.docapi.service.DocumentNotFoundException;
import com.fishfind.docapi.service.InvalidDocumentException;
import org.springframework.stereotype.Component;

import java.util.LinkedHashMap;
import java.util.List;
import java.util.Locale;
import java.util.Map;
import java.util.Set;
import java.util.function.BiFunction;
import java.util.function.Function;
import java.util.regex.Pattern;

/**
 * The tools {@link McpController} offers an MCP client — every one a READ of public water-body data,
 * calling the same repositories the REST endpoints do. No write, no {@code /unfished} (an editorial
 * work queue), no news: an MCP client is a model acting for someone, and nothing here should let it
 * change data.
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
 * {@link #stripPhotos} on its way out, so a new tool cannot leak one by omission. Results are also
 * shaped for a model's context window: {@code search_water_bodies} is capped at
 * {@value #SEARCH_MAX_LIMIT}.
 *
 * <p><strong>Canadian water bodies only</strong> (1.21.0). A water body is shown when it has a CGNDB or CGNDM code or
 * its source or mouth is in Canada ({@code dbo.fn_lake_canadian_ids_json}, through
 * {@link RiverQueryRepository#canadianIds}). Search and tributary results are filtered; a lookup by a non-Canadian GUID is
 * answered like an unknown one; regulations and the species tool accept country {@code CA} only.
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

    private static final Pattern CGNDB_PATTERN = Pattern.compile("[A-Z0-9]{1,5}");

    /** Output keys that hold a photo or a gallery, at any depth (matched case-insensitively). */
    private static final Set<String> PHOTO_KEYS = Set.of("pic", "pics", "image", "images", "picture", "pictures");

    /** Every tool here reads public data and touches nothing outside this service's database. */
    private static final String READ_ONLY_ANNOTATIONS =
            "{\"readOnlyHint\":true,\"destructiveHint\":false,\"idempotentHint\":true,\"openWorldHint\":false}";

    /**
     * One MCP tool: the metadata {@code tools/list} publishes and the handler {@code tools/call} runs.
     *
     * @param name        the stable tool name a client calls
     * @param title       a human-readable display name
     * @param description what the tool returns, written for the model choosing between tools
     * @param inputSchema JSON Schema of the {@code arguments} object
     * @param annotations behaviour hints (read-only etc.)
     * @param adminOnly   true for fish information: listed and callable for {@link ViewerRole#ADMIN} only
     * @param handler     (arguments, caller role) → result object; throws {@link InvalidDocumentException} or
     *                    {@link DocumentNotFoundException} for a caller mistake
     */
    public record Tool(String name, String title, String description, JsonNode inputSchema,
                       JsonNode annotations, boolean adminOnly, BiFunction<JsonNode, ViewerRole, JsonNode> handler) {

        /** Whether {@code role} may see and call this tool. */
        public boolean allowedFor(ViewerRole role) {
            return !adminOnly || role == ViewerRole.ADMIN;
        }
    }

    private final RiverQueryRepository riverRepository;
    private final RegulationQueryRepository regulationRepository;
    private final FishQueryRepository fishRepository;
    private final ObjectMapper objectMapper;
    private final Map<String, Tool> tools = new LinkedHashMap<>();

    public McpToolCatalog(RiverQueryRepository riverRepository,
                          RegulationQueryRepository regulationRepository,
                          FishQueryRepository fishRepository,
                          ObjectMapper objectMapper) {
        this.riverRepository = riverRepository;
        this.regulationRepository = regulationRepository;
        this.fishRepository = fishRepository;
        this.objectMapper = objectMapper;

        add("search_water_bodies", "Search water bodies",
                "Finds Canadian lakes, rivers and other water bodies by part of a name, by CGNDB code "
                        + "(a water body in two provinces has one per province, both searchable), "
                        + "by the province's own id for the water body (`stateId`, e.g. a BC Geographical "
                        + "Names id or an Alberta FWMIS waterbody id), or by the MLI id of a linked "
                        + "hydrometric station. Every criterion given must match. Only Canadian water bodies "
                        + "are returned (a CGNDB code, or a source or mouth in Canada). Items carry both codes "
                        + "(`CGNDB`, `CGNDM`). Returns up to `limit` "
                        + "matches, exact name first, each with its `lakeId` GUID — pass that GUID to the "
                        + "other water-body tools.",
                """
                {"type":"object","properties":{
                  "name":{"type":"string","minLength":2,"maxLength":64,
                          "description":"Part of the English, alternative or French name"},
                  "cgndb":{"type":"string","maxLength":5,
                           "description":"Canadian Geographical Names Database code, e.g. FEFUL"},
                  "stateId":{"type":"string","maxLength":32,
                             "description":"The province's own id for the water body, e.g. 39325 (BC Geographical Names id of the Fraser River)"},
                  "mli":{"type":"string","maxLength":64,
                         "description":"Id of a water station linked to the water body, e.g. 02HC024"},
                  "limit":{"type":"integer","minimum":1,"maximum":50,"default":20}
                },"additionalProperties":false}""",
                false, (args, role) -> searchWaterBodies(args));

        add("get_water_body", "Water body details",
                "The description of one water body: names, type, description text, physical "
                        + "statistics (length, depth, area, volume), location (lat/lon, province/state, "
                        + "region), source and mouth, and its waterfalls and dams. Canadian water bodies only.",
                guidSchema(), false, this::description);

        add("get_water_body_fish", "Fish species in a water body",
                "Every fish species recorded in one water body, listed once each: the entry with the "
                        + "highest probability (0-100) that the species is present, with its conservation "
                        + "status, last recorded catch and the source link for that entry.",
                guidSchema(), true,
                (args, role) -> uniqueSpecies(found(riverRepository.fish(requireCanadianGuid(args)), args)));

        add("get_water_body_links", "Water body source and mouth",
                "Where one water body starts (source) and where it drains (mouth): the linked water "
                        + "body or point for each end, with coordinates, elevation and location.",
                guidSchema(), false, (args, role) -> links(args));

        add("get_water_body_tributaries", "Water bodies flowing into a water body",
                "The rivers, creeks and other water bodies that flow INTO one water body (its "
                        + "tributaries), by name: those whose mouth is this water body, plus the inflows "
                        + "recorded on a lake. `link` says which (mouth / inflow); lat/lon is where it joins. "
                        + "Returns `total` (how many) and up to `limit` of them, each with its `lakeId`. "
                        + "Canadian water bodies only. Only direct tributaries: call again on one to go "
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
                        + "to the water body (`linkMethod`). Named ones first. Canadian water bodies only.",
                guidSchema(), false,
                (args, role) -> found(riverRepository.barriers(requireCanadianGuid(args)), args));

        add("get_water_body_regulations", "Water body fishing regulations",
                "The fishing regulations specific to one water body. Province/state-wide rules also "
                        + "apply; get them with get_region_regulations.",
                guidSchema(), false,
                (args, role) -> found(regulationRepository.lakeRegulation(requireCanadianGuid(args)), args));

        add("get_region_regulations", "Regional fishing regulations",
                "Fishing regulations for Canada, or for one province or territory. Country-wide "
                        + "rules and province rules are separate sets — the province set does not "
                        + "repeat the country rules.",
                """
                {"type":"object","properties":{
                  "country":{"type":"string","enum":["CA","ca"],"description":"Always CA: this server covers Canada"},
                  "state":{"type":"string","pattern":"^[A-Za-z]{2}$",
                           "description":"Province/territory code, e.g. ON or QC; omit for country-wide rules"}
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

        add("find_water_bodies_by_fish", "Water bodies with a fish species",
                "Finds the Canadian water bodies where one fish species is recorded, optionally limited "
                        + "to a province/territory and water-body types. Returns `total` (how many "
                        + "match) and up to `limit` of them, each once, highest probability first. Get "
                        + "the species' fishId from search_fish first. Probability is that of the "
                        + "species' strongest record there; 0 means a weak or unconfirmed record, so set "
                        + "min_probability (e.g. 50) when you want only well-supported records.",
                """
                {"type":"object","properties":{
                  "fishId":{"type":"string","description":"The species' fishId GUID, from search_fish"},
                  "country":{"type":"string","enum":["CA","ca"],"description":"Always CA: this server covers Canada"},
                  "state":{"type":"string","pattern":"^[A-Za-z]{2}$","description":"Province/territory code, e.g. ON"},
                  "types":{"type":"array","items":{"type":"string","enum":["lake","river","stream","pond","marsh",
                           "backwater","creek","canal","estuary","shore","drain","ditch","wetland","reservoir"]},
                           "description":"Water-body types to include; omit for all"},
                  "min_probability":{"type":"integer","minimum":0,"maximum":100,"default":0},
                  "limit":{"type":"integer","minimum":1,"maximum":50,"default":20}
                },"required":["fishId"],"additionalProperties":false}""",
                true, (args, role) -> waterBodiesByFish(args));
    }

    /** The tools {@code role} may use, in publication order. */
    public List<Tool> tools(ViewerRole role) {
        return tools.values().stream().filter(t -> t.allowedFor(role)).toList();
    }

    /** The tool called {@code name} if {@code role} may use it, else {@code null} (as if it did not exist). */
    public Tool find(String name, ViewerRole role) {
        Tool tool = name == null ? null : tools.get(name);
        return tool != null && tool.allowedFor(role) ? tool : null;
    }

    private void add(String name, String title, String description, String inputSchema, boolean adminOnly,
                     BiFunction<JsonNode, ViewerRole, JsonNode> handler) {
        tools.put(name, new Tool(name, title, description, json(inputSchema), json(READ_ONLY_ANNOTATIONS),
                adminOnly, handler.andThen(McpToolCatalog::stripPhotos)));
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
        if (name == null && cgndb == null && stateId == null && mli == null) {
            throw new InvalidDocumentException("Give at least one of name, cgndb, stateId, mli");
        }
        if (name != null && (name.length() < RiverController.SEARCH_MIN_NAME
                || name.length() > RiverController.SEARCH_MAX_TERM)) {
            throw new InvalidDocumentException("name must be " + RiverController.SEARCH_MIN_NAME + " to "
                    + RiverController.SEARCH_MAX_TERM + " characters");
        }
        if (cgndb != null) {
            cgndb = cgndb.toUpperCase(Locale.ROOT);
            if (!CGNDB_PATTERN.matcher(cgndb).matches()) {
                throw new InvalidDocumentException("cgndb must be 1 to 5 letters or digits");
            }
        }
        if (stateId != null) {
            RiverController.checkStateId(stateId);
        }
        if (mli != null && mli.length() > RiverController.SEARCH_MAX_TERM) {
            throw new InvalidDocumentException("mli must not exceed " + RiverController.SEARCH_MAX_TERM + " characters");
        }
        int limit = limit(args);
        // Ask for the most the search allows, keep the Canadian ones, then cut to the caller's limit -- so a
        // name shared with US water bodies still fills the page with Canadian matches.
        JsonNode candidates = riverRepository.search(name, null, cgndb, stateId, mli, RiverController.SEARCH_MAX_LIMIT);
        List<String> ids = new java.util.ArrayList<>();
        candidates.forEach(c -> ids.add(c.path("lakeId").asText("")));
        java.util.Set<String> canadian = riverRepository.canadianIds(ids.stream().filter(i -> !i.isEmpty()).toList());
        ArrayNode items = objectMapper.createArrayNode();
        for (JsonNode c : candidates) {
            if (items.size() >= limit) break;
            if (canadian.contains(c.path("lakeId").asText("").toUpperCase(Locale.ROOT))) items.add(c);
        }
        ObjectNode out = objectMapper.createObjectNode();
        out.set("items", items);
        out.put("total", items.size());
        out.put("limit", limit);
        return out;
    }

    private JsonNode description(JsonNode args, ViewerRole role) {
        JsonNode doc = uniqueSpecies(found(riverRepository.description(requireCanadianGuid(args)), args));
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
        String guid = requireCanadianGuid(args);
        JsonNode source = riverRepository.source(guid);
        if (source == null) {
            throw new DocumentNotFoundException(DocumentType.WATERBODY, guid);
        }
        ObjectNode out = objectMapper.createObjectNode();
        out.set("source", source);
        out.set("mouth", riverRepository.mouth(guid));
        return out;
    }

    /**
     * The direct tributaries of one Canadian water body. Asks for the most the function allows, keeps the
     * Canadian ones (as {@code search_water_bodies} does, so no item leads to a lookup that is then refused), then
     * cuts to the caller's limit. {@code total} counts the Canadian ones among those examined; when the water body
     * has more inflows than one query returns, {@code totalIsLowerBound} says so.
     */
    private JsonNode tributaries(JsonNode args) {
        String guid = requireCanadianGuid(args);
        int limit = boundedInt(args, "limit", SEARCH_DEFAULT_LIMIT, 1, SEARCH_MAX_LIMIT);
        JsonNode doc = found(riverRepository.tributaries(guid, RiverController.SEARCH_MAX_LIMIT), args);

        JsonNode candidates = doc.path("tributaries");
        List<String> ids = new java.util.ArrayList<>();
        candidates.forEach(c -> ids.add(c.path("lakeId").asText("")));
        Set<String> canadian = riverRepository.canadianIds(ids.stream().filter(i -> !i.isEmpty()).toList());
        ArrayNode items = objectMapper.createArrayNode();
        int total = 0;
        for (JsonNode c : candidates) {
            if (canadian.contains(c.path("lakeId").asText("").toUpperCase(Locale.ROOT))) {
                if (items.size() < limit) items.add(c);
                total++;
            }
        }
        ObjectNode out = objectMapper.createObjectNode();
        out.set("guid", doc.get("guid"));
        out.set("lakeName", doc.get("lakeName"));
        out.put("total", total);
        if (doc.path("total").asInt(0) > candidates.size()) {
            out.put("totalIsLowerBound", true);
        }
        out.put("limit", limit);
        out.set("tributaries", items);
        return out;
    }

    private JsonNode regionRegulations(JsonNode args) {
        String country = requireCanada(optionalText(args, "country"));
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
        String fishText = optionalText(args, "fishId");
        if (fishText == null) {
            throw new InvalidDocumentException("fishId is required (get it from search_fish)");
        }
        String fishId = RiverController.normalizeGuid(fishText);
        String country = requireCanada(optionalText(args, "country"));   // always CA: Canada only
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

    /**
     * The {@code guid} argument, canonical, and only if that water body is Canadian. Anything else -- a
     * non-Canadian water body or an unknown id -- gets the same answer, so the tool cannot be used to probe
     * what lies outside Canada.
     */
    private String requireCanadianGuid(JsonNode args) {
        String guid = requireGuid(args);
        if (riverRepository.canadianIds(List.of(guid)).isEmpty()) {
            throw new InvalidDocumentException("No Canadian water body has id " + guid
                    + " (this server covers Canadian water bodies only)");
        }
        return guid;
    }

    /** {@code CA} when the country argument is absent or CA (any case); anything else is a caller error. */
    private static String requireCanada(String country) {
        if (country == null || country.trim().equalsIgnoreCase("CA")) return "CA";
        throw new InvalidDocumentException("Only Canada (CA) is available on this server");
    }

    /** The {@code guid} argument in canonical form; anything that is not a GUID never reaches SQL. */
    private static String requireGuid(JsonNode args) {
        String guid = optionalText(args, "guid");
        if (guid == null) {
            throw new InvalidDocumentException("guid is required");
        }
        return RiverController.normalizeGuid(guid);
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
