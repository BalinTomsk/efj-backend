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
     * @param handler     arguments → result object; throws {@link InvalidDocumentException} or
     *                    {@link DocumentNotFoundException} for a caller mistake
     */
    public record Tool(String name, String title, String description, JsonNode inputSchema,
                       JsonNode annotations, Function<JsonNode, JsonNode> handler) {
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
                "Finds lakes, rivers and other water bodies in Canada and the US by part of a name, by "
                        + "CGNDB code, or by the MLI id of a linked hydrometric station. Every criterion "
                        + "given must match. Returns up to `limit` matches, exact name first, each with "
                        + "its `lakeId` GUID — pass that GUID to the other water-body tools.",
                """
                {"type":"object","properties":{
                  "name":{"type":"string","minLength":2,"maxLength":64,
                          "description":"Part of the English, alternative or French name"},
                  "cgndb":{"type":"string","maxLength":5,
                           "description":"Canadian Geographical Names Database code, e.g. FEFUL"},
                  "mli":{"type":"string","maxLength":64,
                         "description":"Id of a water station linked to the water body, e.g. 02HC024"},
                  "limit":{"type":"integer","minimum":1,"maximum":50,"default":20}
                },"additionalProperties":false}""",
                this::searchWaterBodies);

        add("get_water_body", "Water body details",
                "The description of one water body: names, type, description text, physical "
                        + "statistics (length, depth, area, volume), location (lat/lon, province/state, "
                        + "region), source and mouth, and the species recorded there.",
                guidSchema(), this::description);

        add("get_water_body_fish", "Fish species in a water body",
                "Every fish species recorded in one water body, listed once each: the entry with the "
                        + "highest probability (0-100) that the species is present, with its conservation "
                        + "status, last recorded catch and the source link for that entry.",
                guidSchema(), args -> uniqueSpecies(found(riverRepository.fish(requireGuid(args)), args)));

        add("get_water_body_links", "Water body source and mouth",
                "Where one water body starts (source) and where it drains (mouth): the linked water "
                        + "body or point for each end, with coordinates, elevation and location.",
                guidSchema(), this::links);

        add("get_water_body_regulations", "Water body fishing regulations",
                "The fishing regulations specific to one water body. Province/state-wide rules also "
                        + "apply; get them with get_region_regulations.",
                guidSchema(), args -> found(regulationRepository.lakeRegulation(requireGuid(args)), args));

        add("get_region_regulations", "Regional fishing regulations",
                "Fishing regulations for a whole country, or for one province/state. Country-wide "
                        + "rules and province rules are separate sets — the province set does not "
                        + "repeat the country rules.",
                """
                {"type":"object","properties":{
                  "country":{"type":"string","pattern":"^[A-Za-z]{2}$","description":"ISO-2 country code: CA or US"},
                  "state":{"type":"string","pattern":"^[A-Za-z]{2}$",
                           "description":"ISO-2 province/state code, e.g. ON or MN; omit for country-wide rules"}
                },"required":["country"],"additionalProperties":false}""",
                this::regionRegulations);

        add("search_fish", "Search fish species",
                "Finds fish species by common, alternative or Latin name, best match first, each with "
                        + "its `fishId` GUID.",
                """
                {"type":"object","properties":{
                  "query":{"type":"string","minLength":1,"maxLength":64,"description":"e.g. walleye, Sander vitreus"}
                },"required":["query"],"additionalProperties":false}""",
                this::searchFish);
    }

    /** The tools in publication order. */
    public List<Tool> tools() {
        return List.copyOf(tools.values());
    }

    /** The tool called {@code name}, or {@code null}. */
    public Tool find(String name) {
        return name == null ? null : tools.get(name);
    }

    private void add(String name, String title, String description, String inputSchema,
                     Function<JsonNode, JsonNode> handler) {
        tools.put(name, new Tool(name, title, description, json(inputSchema), json(READ_ONLY_ANNOTATIONS),
                handler.andThen(McpToolCatalog::stripPhotos)));
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
        String mli = optionalText(args, "mli");
        if (name == null && cgndb == null && mli == null) {
            throw new InvalidDocumentException("Give at least one of name, cgndb, mli");
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
        if (mli != null && mli.length() > RiverController.SEARCH_MAX_TERM) {
            throw new InvalidDocumentException("mli must not exceed " + RiverController.SEARCH_MAX_TERM + " characters");
        }
        int limit = limit(args);
        JsonNode items = riverRepository.search(name, null, cgndb, mli, limit);
        ObjectNode out = objectMapper.createObjectNode();
        out.set("items", items);
        out.put("total", items.size());
        out.put("limit", limit);
        return out;
    }

    private JsonNode description(JsonNode args) {
        return uniqueSpecies(found(riverRepository.description(requireGuid(args)), args));
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

    private JsonNode regionRegulations(JsonNode args) {
        String country = RegulationController.requireCode(optionalText(args, "country"), "country");
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

    // ---- argument helpers ----------------------------------------------------------------------

    /** A water-body document, or a not-found for the GUID the caller gave. */
    private static JsonNode found(JsonNode document, JsonNode args) {
        if (document == null) {
            throw new DocumentNotFoundException(DocumentType.WATERBODY, args.path("guid").asText());
        }
        return document;
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
