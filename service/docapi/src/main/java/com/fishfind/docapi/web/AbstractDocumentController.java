package com.fishfind.docapi.web;

import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.fasterxml.jackson.databind.node.ObjectNode;
import com.fishfind.docapi.service.DocumentService;
import org.springframework.http.HttpStatus;
import org.springframework.http.MediaType;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.PutMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.ResponseStatus;

/**
 * Shared REST surface for the four entity document controllers. Each concrete subclass only supplies its
 * {@code @RequestMapping} base path and the matching {@link DocumentService}; all three verbs live here:
 *
 * <ul>
 *   <li>{@code GET  /api/v1/&lt;entity&gt;/{id}} — return the stored JSON document</li>
 *   <li>{@code POST /api/v1/&lt;entity&gt;}      — add a new document (JSON body)</li>
 *   <li>{@code PUT  /api/v1/&lt;entity&gt;/{id}}  — update an existing document (JSON body)</li>
 * </ul>
 *
 * <p>All responses use the {@link ApiResponse} envelope. The request body is consumed as a raw JSON string
 * so the service layer controls parsing/validation rather than binding to a fixed DTO — each entity's
 * document shape is defined by its stored procedures, not by this generic layer.
 */
public abstract class AbstractDocumentController {

    private final DocumentService service;
    private final ObjectMapper objectMapper;

    protected AbstractDocumentController(DocumentService service, ObjectMapper objectMapper) {
        this.service = service;
        this.objectMapper = objectMapper;
    }

    /**
     * Returns the stored JSON document for the id.
     *
     * @param id the entity id
     * @return the document nested as real JSON inside the response envelope
     */
    @GetMapping("/{id}")
    public ApiResponse<JsonNode> get(@PathVariable String id) {
        return ApiResponse.ok(service.get(id));
    }

    /**
     * Adds a new document.
     *
     * @param body the JSON document body
     * @return an envelope carrying {@code { "id": <newId> }}
     */
    @PostMapping(consumes = MediaType.APPLICATION_JSON_VALUE)
    @ResponseStatus(HttpStatus.CREATED)
    public ApiResponse<JsonNode> add(@RequestBody(required = false) String body) {
        String newId = service.add(body);
        return ApiResponse.ok(idNode(newId));
    }

    /**
     * Updates an existing document.
     *
     * @param id the entity id to update
     * @param body the JSON document body
     * @return an envelope carrying {@code { "id": <id> }}
     */
    @PutMapping(value = "/{id}", consumes = MediaType.APPLICATION_JSON_VALUE)
    public ApiResponse<JsonNode> update(@PathVariable String id, @RequestBody(required = false) String body) {
        String updatedId = service.update(id, body);
        return ApiResponse.ok(idNode(updatedId));
    }

    private JsonNode idNode(String id) {
        ObjectNode node = objectMapper.createObjectNode();
        node.put("id", id);
        return node;
    }
}
