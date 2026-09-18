package com.fishfind.docapi.service;

import com.fasterxml.jackson.core.JsonProcessingException;
import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.fishfind.docapi.domain.DocumentType;
import com.fishfind.docapi.repo.DocumentStore;
import com.fishfind.docapi.repo.NewsCaches;
import com.fishfind.docapi.repo.NewsQueryRepository;
import com.fishfind.docapi.repo.NewsWrite;
import com.fishfind.docapi.repo.NewsWriteRepository;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Qualifier;
import org.springframework.stereotype.Service;

/**
 * News-article JSON-document service -- and, since docapi 1.16.0, the single place every news write
 * goes through: {@code POST /api/v1/news}, {@code PUT /api/v1/news/{id}} and
 * {@code POST /api/v1/news/import}.
 *
 * <p>Reads are inherited unchanged ({@code GET /{id}} from the {@code newsStore}, MySQL-backed).
 * Writes do not go through the {@link DocumentStore} at all: the body is parsed and validated by
 * {@link NewsWriteParser} -- every client error a 400 before any database call -- and persisted by
 * {@link NewsWriteRepository} (MySQL {@code sp_news_doc_insert}/{@code sp_news_doc_update}). After a
 * successful write both news caches are cleared, so the new or edited article shows on the next read
 * instead of after the midnight eviction.
 */
@Service
public class NewsDocumentService extends DocumentService {

    private static final Logger log = LoggerFactory.getLogger(NewsDocumentService.class);

    private final DocumentStore store;
    private final ObjectMapper objectMapper;
    private final NewsWriteRepository writeRepository;
    private final NewsQueryRepository queryRepository;

    public NewsDocumentService(@Qualifier("newsStore") DocumentStore store, ObjectMapper objectMapper,
                               NewsWriteRepository writeRepository, NewsQueryRepository queryRepository) {
        super(store, objectMapper, DocumentType.NEWS);
        this.store = store;
        this.objectMapper = objectMapper;
        this.writeRepository = writeRepository;
        this.queryRepository = queryRepository;
    }

    /**
     * Creates a published article from the snake_case article document (the shape
     * {@code GET /api/v1/news/{id}} returns).
     *
     * @return the new article id
     * @throws InvalidDocumentException if the body is not a JSON object or fails validation (→ 400)
     */
    @Override
    public String add(String rawBody) {
        NewsWrite write = NewsWriteParser.fromDocument(requireObject(rawBody));
        String id = writeRepository.insert(write);
        NewsCaches.evictAll(queryRepository, store);
        log.info("Added news article (id={})", id);
        return id;
    }

    /**
     * Replaces an article from the snake_case article document. A full replace: a field absent from
     * the body is cleared -- except the date (kept when absent), the lead photo's bytes (kept when
     * absent) and whether the article is published (never changed here).
     *
     * @return the id
     * @throws InvalidDocumentException  if the id is blank, or the body is not a JSON object or fails
     *                                   validation (→ 400)
     * @throws DocumentNotFoundException if no article exists for the id (→ 404) -- nothing is written
     */
    @Override
    public String update(String id, String rawBody) {
        if (id == null || id.isBlank()) {
            throw new InvalidDocumentException("Document id must not be blank");
        }
        NewsWrite write = NewsWriteParser.fromDocument(requireObject(rawBody));
        String trimmed = id.trim();
        if (!writeRepository.update(trimmed, write)) {
            throw new DocumentNotFoundException(DocumentType.NEWS, trimmed);
        }
        NewsCaches.evictAll(queryRepository, store);
        log.info("Updated news article (id={})", trimmed);
        return trimmed;
    }

    /**
     * Creates a published article from the camelCase interchange document
     * ({@code GET /api/v1/news/export/{id}}'s shape), all three photo slots included.
     *
     * @return the new article id
     * @throws InvalidDocumentException if the body is not a JSON object or fails validation (→ 400)
     */
    public String importInterchange(String rawBody) {
        NewsWrite write = NewsWriteParser.fromInterchange(requireObject(rawBody));
        String id = writeRepository.insert(write);
        NewsCaches.evictAll(queryRepository, store);
        log.info("Imported news article (id={})", id);
        return id;
    }

    private JsonNode requireObject(String rawBody) {
        if (rawBody == null || rawBody.isBlank()) {
            throw new InvalidDocumentException("Request body must be a non-empty JSON document");
        }
        JsonNode node;
        try {
            node = objectMapper.readTree(rawBody);
        } catch (JsonProcessingException ex) {
            throw new InvalidDocumentException("Request body is not well-formed JSON: " + ex.getOriginalMessage(), ex);
        }
        if (node == null || !node.isObject()) {
            throw new InvalidDocumentException("Request body must be a JSON object");
        }
        return node;
    }
}
