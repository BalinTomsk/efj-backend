package com.fishfind.docapi.service;

import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.fishfind.docapi.domain.DocumentType;
import com.fishfind.docapi.repo.DocumentStore;
import org.junit.jupiter.api.Test;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertThrows;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

class DocumentServiceTest {

    private final DocumentStore store = mock(DocumentStore.class);
    private final ObjectMapper objectMapper = new ObjectMapper();
    private final DocumentService service = new TestDocumentService(store, objectMapper);

    @Test
    void getParsesStoredJsonIntoATree() {
        when(store.getDocument("42")).thenReturn("{\"title\":\"Spring run\"}");

        JsonNode node = service.get("42");

        assertEquals("Spring run", node.get("title").asText());
    }

    @Test
    void getThrowsNotFoundWhenStoreReturnsNull() {
        when(store.getDocument("nope")).thenReturn(null);

        assertThrows(DocumentNotFoundException.class, () -> service.get("nope"));
    }

    @Test
    void getRejectsBlankId() {
        assertThrows(InvalidDocumentException.class, () -> service.get("  "));
    }

    @Test
    void addValidatesAndNormalizesBodyBeforeInserting() {
        when(store.addDocument(eq("{\"a\":1}"))).thenReturn("new-id");

        String id = service.add("  { \"a\" : 1 }  ");

        assertEquals("new-id", id);
        // Normalized (re-serialized) body, whitespace stripped, reaches the store.
        verify(store).addDocument("{\"a\":1}");
    }

    @Test
    void addRejectsBlankBody() {
        assertThrows(InvalidDocumentException.class, () -> service.add("   "));
    }

    @Test
    void addRejectsMalformedJson() {
        assertThrows(InvalidDocumentException.class, () -> service.add("{not json"));
    }

    @Test
    void updateFallsBackToSuppliedIdWhenStoreReturnsNothing() {
        when(store.updateDocument(eq("7"), eq("{\"x\":true}"))).thenReturn(null);

        String id = service.update("7", "{\"x\":true}");

        assertEquals("7", id);
    }

    /** Minimal concrete subclass to exercise the abstract base logic. */
    private static final class TestDocumentService extends DocumentService {
        private TestDocumentService(DocumentStore store, ObjectMapper objectMapper) {
            super(store, objectMapper, DocumentType.NEWS);
        }
    }
}
