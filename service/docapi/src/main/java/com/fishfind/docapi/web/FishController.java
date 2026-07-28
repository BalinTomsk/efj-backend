package com.fishfind.docapi.web;

import com.fasterxml.jackson.databind.ObjectMapper;
import com.fishfind.docapi.service.FishDocumentService;
import org.springframework.http.MediaType;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

/** JSON-document endpoints for fish species under {@code /api/v1/fish}. */
@RestController
@RequestMapping(value = "/api/v1/fish", produces = MediaType.APPLICATION_JSON_VALUE)
public class FishController extends AbstractDocumentController {

    public FishController(FishDocumentService service, ObjectMapper objectMapper) {
        super(service, objectMapper);
    }
}
