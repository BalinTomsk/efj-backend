package com.fishfind.docapi.repo;

import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.fasterxml.jackson.databind.node.ObjectNode;

import java.util.Base64;

/**
 * Default-profile (no database) {@link NewsWriteRepository}: writes into the in-memory
 * {@code newsStore}, so {@code GET /api/v1/news/{id}} reads back what {@code POST}/{@code PUT} wrote
 * and the service still runs end-to-end without a connection.
 *
 * <p>The stored document uses the snake_case field names {@code sp_news_doc_get} returns under the
 * {@code jdbc} profile, and mirrors {@code sp_news_doc_update}'s keep-rules: an update without a
 * stamp keeps the stored {@code date}, and one without slot-0 bytes keeps the stored {@code photo}.
 * A development backing -- nothing here is durable.
 */
public class InMemoryNewsWriteRepository implements NewsWriteRepository {

    private final DocumentStore store;
    private final ObjectMapper objectMapper;

    public InMemoryNewsWriteRepository(DocumentStore store, ObjectMapper objectMapper) {
        this.store = store;
        this.objectMapper = objectMapper;
    }

    @Override
    public String insert(NewsWrite write) {
        return store.addDocument(toDocument(write, null).toString());
    }

    @Override
    public boolean update(String id, NewsWrite write) {
        String existing = store.getDocument(id);
        if (existing == null) {
            return false;
        }
        store.updateDocument(id, toDocument(write, parse(existing)).toString());
        return true;
    }

    private ObjectNode toDocument(NewsWrite w, JsonNode previous) {
        ObjectNode doc = objectMapper.createObjectNode();
        doc.put("title", w.title());
        doc.put("author", w.author());
        doc.put("author_link", w.authorLink());
        doc.put("source", w.source());
        doc.put("source_link", w.sourceLink());
        doc.put("video_link", w.videoLink());
        doc.put("paragraph0", w.paragraph0());
        doc.put("paragraph1", w.paragraph1());
        doc.put("paragraph2", w.paragraph2());
        doc.put("country", w.country());
        doc.put("lake_id", w.lakeId());
        doc.put("fish1_id", w.fish1Id());
        doc.put("fish2_id", w.fish2Id());
        doc.put("fish3_id", w.fish3Id());
        doc.put("credit", w.photo0().author());
        doc.put("photo_alt", w.photo0().alt());

        if (w.stamp() != null) {
            doc.put("date", w.stamp().toLocalDateTime().toLocalDate().toString());
        } else if (previous != null && previous.hasNonNull("date")) {
            doc.set("date", previous.get("date"));
        } else {
            doc.put("date", java.time.LocalDate.now().toString());
        }

        if (w.photo0().bytes() != null) {
            doc.put("photo", Base64.getEncoder().encodeToString(w.photo0().bytes()));
        } else if (previous != null && previous.hasNonNull("photo")) {
            doc.set("photo", previous.get("photo"));
        } else {
            doc.putNull("photo");
        }
        return doc;
    }

    private JsonNode parse(String json) {
        try {
            return objectMapper.readTree(json);
        } catch (Exception ex) {
            return null;
        }
    }
}
