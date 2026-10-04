package com.fishfind.docapi.web;

import com.fasterxml.jackson.core.JsonProcessingException;
import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.fasterxml.jackson.databind.node.ArrayNode;
import com.fasterxml.jackson.databind.node.ObjectNode;
import com.fishfind.docapi.service.DocumentNotFoundException;
import com.fishfind.docapi.service.InvalidDocumentException;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.info.BuildProperties;
import org.springframework.http.HttpHeaders;
import org.springframework.http.HttpStatus;
import org.springframework.http.MediaType;
import org.springframework.http.ResponseEntity;
import org.springframework.lang.Nullable;
import org.springframework.web.bind.annotation.DeleteMapping;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestHeader;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

import java.util.List;

/**
 * A Model Context Protocol server at {@code /api/v1/mcp}: the water-body reads of
 * {@link McpToolCatalog}, offered to MCP clients (Claude Desktop, Claude Code) as tools.
 *
 * <p><strong>Streamable HTTP, stateless, JSON responses only.</strong> Every JSON-RPC request is a
 * {@code POST} answered with one {@code application/json} body; a notification or a client response
 * gets {@code 202} with no body. There is no session ({@code Mcp-Session-Id} is never issued) and no
 * server-sent-event stream, so {@code GET} and {@code DELETE} answer {@code 405} — which the spec
 * defines as "this server offers no stream". That is a requirement, not a simplification: cproxy
 * buffers each upstream response whole before relaying it, so a stream could never pass through it.
 *
 * <p>Hand-written rather than built on the MCP Java SDK: the protocol surface a tools-only stateless
 * server needs is four methods, and the SDK's Spring integration needs a newer Spring Boot than this
 * service runs, while the core SDK would add Reactor to a JVM on a one-vCPU droplet.
 *
 * <p><strong>Errors are never HTTP 5xx.</strong> A caller mistake or a database failure inside a tool
 * comes back as a tool result with {@code isError: true} — readable by the model, which can correct
 * its arguments — and a protocol mistake as a JSON-RPC error. Neither passes through
 * {@link ApiExceptionHandler}.
 *
 * <p><strong>Who may call it is cproxy's decision, not this controller's</strong>, the same trust model
 * as every other endpoint here: docapi is reachable only through cproxy. The one check made here is
 * the spec's DNS-rebinding guard — a request carrying an {@code Origin} header came from a browser,
 * and no browser is a legitimate caller, so it is refused.
 */
@RestController
@RequestMapping("/api/v1/mcp")
public class McpController {

    private static final Logger log = LoggerFactory.getLogger(McpController.class);

    /** Newest first; the first is offered when a client asks for one we do not speak. */
    static final List<String> PROTOCOL_VERSIONS = List.of("2025-11-25", "2025-06-18", "2025-03-26");

    static final String SERVER_NAME = "fishfind-docapi";

    static final String INSTRUCTIONS =
            "FishFind water-body data for CANADA: lakes, rivers and other Canadian water bodies, where "
                    + "they start and end, and fishing regulations. Start with search_water_bodies to get a "
                    + "water body's lakeId GUID, then pass it to the get_water_body* tools. Fish species "
                    + "information is available to administrators only. Read-only; no photos are provided.";

    // JSON-RPC 2.0 error codes.
    static final int PARSE_ERROR = -32700;
    static final int INVALID_REQUEST = -32600;
    static final int METHOD_NOT_FOUND = -32601;
    static final int INVALID_PARAMS = -32602;

    private final McpToolCatalog catalog;
    private final ObjectMapper objectMapper;
    private final String version;

    @Autowired
    public McpController(McpToolCatalog catalog, ObjectMapper objectMapper,
                         @Nullable BuildProperties buildProperties) {
        this.catalog = catalog;
        this.objectMapper = objectMapper;
        this.version = buildProperties == null ? "unknown" : buildProperties.getVersion();
    }

    @PostMapping
    public ResponseEntity<JsonNode> post(@RequestBody(required = false) String body,
                                         @RequestHeader(value = HttpHeaders.ORIGIN, required = false) String origin,
                                         @RequestHeader(value = "MCP-Protocol-Version", required = false) String protocolVersion,
                                         @RequestHeader(value = ViewerRole.HEADER, required = false) String roleHeader) {
        // Who is calling, as cproxy established it from the MCP key's owning account. Missing or unknown
        // reads as GUEST (fail closed): fish tools are then hidden.
        ViewerRole role = ViewerRole.fromHeader(roleHeader);
        if (origin != null) {
            return json(HttpStatus.FORBIDDEN, error(null, INVALID_REQUEST, "Browser origins are not accepted"));
        }
        if (protocolVersion != null && !PROTOCOL_VERSIONS.contains(protocolVersion.trim())) {
            return json(HttpStatus.BAD_REQUEST,
                    error(null, INVALID_REQUEST, "Unsupported MCP-Protocol-Version: " + protocolVersion));
        }
        JsonNode message;
        try {
            message = body == null || body.isBlank() ? null : objectMapper.readTree(body);
        } catch (JsonProcessingException ex) {
            message = null;
        }
        if (message == null) {
            return json(HttpStatus.BAD_REQUEST, error(null, PARSE_ERROR, "Body is not a JSON-RPC message"));
        }

        if (message.isArray()) {
            // Batches were allowed by protocol 2025-03-26 and dropped later; answering one costs nothing.
            if (message.isEmpty()) {
                return json(HttpStatus.BAD_REQUEST, error(null, INVALID_REQUEST, "Empty batch"));
            }
            ArrayNode replies = objectMapper.createArrayNode();
            for (JsonNode item : message) {
                JsonNode reply = handle(item, role);
                if (reply != null) replies.add(reply);
            }
            return replies.isEmpty() ? ResponseEntity.accepted().build() : json(HttpStatus.OK, replies);
        }
        JsonNode reply = handle(message, role);
        return reply == null ? ResponseEntity.accepted().build() : json(HttpStatus.OK, reply);
    }

    /** No server-initiated stream is offered (see the class comment). */
    @GetMapping
    public ResponseEntity<Void> get() {
        return methodNotAllowed();
    }

    /** No session exists to terminate. */
    @DeleteMapping
    public ResponseEntity<Void> delete() {
        return methodNotAllowed();
    }

    /**
     * One JSON-RPC message → its response, or {@code null} for a notification or a client response
     * (both of which get no reply).
     */
    JsonNode handle(JsonNode message, ViewerRole role) {
        if (!message.isObject() || !"2.0".equals(message.path("jsonrpc").asText())) {
            return error(null, INVALID_REQUEST, "Not a JSON-RPC 2.0 message");
        }
        JsonNode method = message.get("method");
        JsonNode id = message.get("id");
        if (method == null) {
            return null;  // a response to a server request; this server never sends any
        }
        if (id == null || id.isNull()) {
            return null;  // a notification (notifications/initialized, notifications/cancelled, ...)
        }
        if (!method.isTextual()) {
            return error(id, INVALID_REQUEST, "method must be a string");
        }
        JsonNode params = message.path("params");
        return switch (method.asText()) {
            case "initialize" -> result(id, initialize(params));
            case "ping" -> result(id, objectMapper.createObjectNode());
            case "tools/list" -> result(id, toolsList(role));
            case "tools/call" -> callTool(id, params, role);
            default -> error(id, METHOD_NOT_FOUND, "Method not found: " + method.asText());
        };
    }

    private ObjectNode initialize(JsonNode params) {
        String requested = params.path("protocolVersion").asText("");
        ObjectNode out = objectMapper.createObjectNode();
        out.put("protocolVersion", PROTOCOL_VERSIONS.contains(requested) ? requested : PROTOCOL_VERSIONS.get(0));
        out.putObject("capabilities").putObject("tools").put("listChanged", false);
        out.putObject("serverInfo")
                .put("name", SERVER_NAME)
                .put("title", "FishFind water bodies")
                .put("version", version);
        out.put("instructions", INSTRUCTIONS);
        return out;
    }

    private ObjectNode toolsList(ViewerRole role) {
        ObjectNode out = objectMapper.createObjectNode();
        ArrayNode list = out.putArray("tools");
        for (McpToolCatalog.Tool tool : catalog.tools(role)) {
            ObjectNode t = list.addObject();
            t.put("name", tool.name());
            t.put("title", tool.title());
            t.put("description", tool.description());
            t.set("inputSchema", tool.inputSchema());
            t.set("annotations", tool.annotations());
        }
        return out;
    }

    private ObjectNode callTool(JsonNode id, JsonNode params, ViewerRole role) {
        // A tool the caller's role may not use is reported exactly like one that does not exist.
        McpToolCatalog.Tool tool = catalog.find(params.path("name").asText(null), role);
        if (tool == null) {
            return error(id, INVALID_PARAMS, "Unknown tool: " + params.path("name").asText(""));
        }
        JsonNode args = params.path("arguments");
        if (args.isMissingNode() || args.isNull()) {
            args = objectMapper.createObjectNode();
        } else if (!args.isObject()) {
            return error(id, INVALID_PARAMS, "arguments must be an object");
        }

        long started = System.nanoTime();
        ObjectNode out;
        String outcome;
        try {
            out = toolResult(tool.handler().apply(args, role));
            outcome = "ok";
        } catch (InvalidDocumentException | DocumentNotFoundException ex) {
            out = toolError(ex.getMessage());
            outcome = "rejected";
        } catch (RuntimeException ex) {
            // A database fault or an open breaker. Logged in full here; the model only learns it is
            // temporary, never the SQL behind it.
            log.warn("MCP tool {} failed", tool.name(), ex);
            out = toolError("The water-body database is temporarily unavailable; try again shortly.");
            outcome = "failed";
        }
        log.info("MCP tools/call {} -> {} ({}ms)", tool.name(), outcome, (System.nanoTime() - started) / 1_000_000);
        return result(id, out);
    }

    /** Text for every client, plus structured content for clients that read it. */
    private ObjectNode toolResult(JsonNode value) {
        ObjectNode out = objectMapper.createObjectNode();
        out.putArray("content").addObject().put("type", "text").put("text", value.toString());
        if (value.isObject()) {
            out.set("structuredContent", value);
        }
        out.put("isError", false);
        return out;
    }

    private ObjectNode toolError(String message) {
        ObjectNode out = objectMapper.createObjectNode();
        out.putArray("content").addObject().put("type", "text").put("text", message);
        out.put("isError", true);
        return out;
    }

    private ObjectNode result(JsonNode id, JsonNode result) {
        ObjectNode out = objectMapper.createObjectNode();
        out.put("jsonrpc", "2.0");
        out.set("id", id);
        out.set("result", result);
        return out;
    }

    private ObjectNode error(JsonNode id, int code, String message) {
        ObjectNode out = objectMapper.createObjectNode();
        out.put("jsonrpc", "2.0");
        out.set("id", id == null ? objectMapper.nullNode() : id);
        out.putObject("error").put("code", code).put("message", message);
        return out;
    }

    private static ResponseEntity<JsonNode> json(HttpStatus status, JsonNode body) {
        return ResponseEntity.status(status).contentType(MediaType.APPLICATION_JSON).body(body);
    }

    private static ResponseEntity<Void> methodNotAllowed() {
        return ResponseEntity.status(HttpStatus.METHOD_NOT_ALLOWED).header(HttpHeaders.ALLOW, "POST").build();
    }
}
