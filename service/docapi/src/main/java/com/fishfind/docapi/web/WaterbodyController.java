package com.fishfind.docapi.web;

import com.fasterxml.jackson.databind.ObjectMapper;
import com.fishfind.docapi.service.WaterbodyDocumentService;
import org.springframework.http.MediaType;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

/** JSON-document endpoints for water bodies under {@code /api/v1/waterbody}. */
@RestController
@RequestMapping(value = "/api/v1/waterbody", produces = MediaType.APPLICATION_JSON_VALUE)
public class WaterbodyController extends AbstractDocumentController {

    public WaterbodyController(WaterbodyDocumentService service, ObjectMapper objectMapper) {
        super(service, objectMapper);
    }
}
