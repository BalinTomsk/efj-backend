package com.fishfind.docapi.repo;

import com.fishfind.docapi.domain.DocumentType;

import java.util.concurrent.ConcurrentHashMap;
import java.util.concurrent.ConcurrentMap;
import java.util.concurrent.atomic.AtomicLong;

/**
 * Process-local, thread-safe {@link DocumentStore} used as the default backing so DocApi runs without
 * a database. Documents live only for the lifetime of the JVM and are lost on restart — this is a
 * development/demo backing, not durable storage.
 *
 * <p>Generated ids are prefixed with the entity label (e.g. {@code news-1}) so they read clearly and
 * never collide across entity types.
 */
public class InMemoryDocumentStore implements DocumentStore {

    private final ConcurrentMap<String, String> documents = new ConcurrentHashMap<>();
    private final AtomicLong sequence = new AtomicLong();
    private final DocumentType type;

    public InMemoryDocumentStore(DocumentType type) {
        this.type = type;
    }

    @Override
    public String getDocument(String id) {
        return documents.get(id);
    }

    @Override
    public String addDocument(String json) {
        String id = type.label() + "-" + sequence.incrementAndGet();
        documents.put(id, json);
        return id;
    }

    @Override
    public String updateDocument(String id, String json) {
        // PUT semantics: store the body under the given id whether or not it existed before.
        documents.put(id, json);
        return id;
    }
}
