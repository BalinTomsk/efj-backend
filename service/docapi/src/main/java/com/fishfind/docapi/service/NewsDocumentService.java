package com.fishfind.docapi.service;

import com.fasterxml.jackson.databind.ObjectMapper;
import com.fishfind.docapi.domain.DocumentType;
import com.fishfind.docapi.repo.DocumentStore;
import org.springframework.beans.factory.annotation.Qualifier;
import org.springframework.stereotype.Service;

/** News-article JSON-document service. */
@Service
public class NewsDocumentService extends DocumentService {

    public NewsDocumentService(@Qualifier("newsStore") DocumentStore store, ObjectMapper objectMapper) {
        super(store, objectMapper, DocumentType.NEWS);
    }
}
