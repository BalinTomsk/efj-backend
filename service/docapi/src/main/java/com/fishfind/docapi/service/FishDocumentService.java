package com.fishfind.docapi.service;

import com.fasterxml.jackson.databind.ObjectMapper;
import com.fishfind.docapi.domain.DocumentType;
import com.fishfind.docapi.repo.DocumentStore;
import org.springframework.beans.factory.annotation.Qualifier;
import org.springframework.stereotype.Service;

/** Fish-species JSON-document service. */
@Service
public class FishDocumentService extends DocumentService {

    public FishDocumentService(@Qualifier("fishStore") DocumentStore store, ObjectMapper objectMapper) {
        super(store, objectMapper, DocumentType.FISH);
    }
}
