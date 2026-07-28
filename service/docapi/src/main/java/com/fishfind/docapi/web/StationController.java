package com.fishfind.docapi.web;

import com.fasterxml.jackson.databind.ObjectMapper;
import com.fishfind.docapi.service.StationDocumentService;
import org.springframework.http.MediaType;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

/** JSON-document endpoints for water stations under {@code /api/v1/station}. */
@RestController
@RequestMapping(value = "/api/v1/station", produces = MediaType.APPLICATION_JSON_VALUE)
public class StationController extends AbstractDocumentController {

    public StationController(StationDocumentService service, ObjectMapper objectMapper) {
        super(service, objectMapper);
    }
}
