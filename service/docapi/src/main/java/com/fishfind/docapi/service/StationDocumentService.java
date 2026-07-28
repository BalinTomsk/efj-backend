package com.fishfind.docapi.service;

import com.fasterxml.jackson.databind.ObjectMapper;
import com.fishfind.docapi.domain.DocumentType;
import com.fishfind.docapi.repo.DocumentStore;
import org.springframework.beans.factory.annotation.Qualifier;
import org.springframework.stereotype.Service;

/** Water-station JSON-document service. */
@Service
public class StationDocumentService extends DocumentService {

    public StationDocumentService(@Qualifier("stationStore") DocumentStore store, ObjectMapper objectMapper) {
        super(store, objectMapper, DocumentType.STATION);
    }
}
