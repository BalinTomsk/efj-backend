package com.fishfind.docapi.service;

import com.fasterxml.jackson.databind.ObjectMapper;
import com.fishfind.docapi.domain.DocumentType;
import com.fishfind.docapi.repo.DocumentStore;
import org.springframework.beans.factory.annotation.Qualifier;
import org.springframework.stereotype.Service;

/** Water-body JSON-document service. */
@Service
public class WaterbodyDocumentService extends DocumentService {

    public WaterbodyDocumentService(@Qualifier("waterbodyStore") DocumentStore store, ObjectMapper objectMapper) {
        super(store, objectMapper, DocumentType.WATERBODY);
    }
}
