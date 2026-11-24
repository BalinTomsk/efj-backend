package com.fishfind.docapi.repo;

import com.fasterxml.jackson.databind.JsonNode;

import java.time.format.DateTimeFormatter;
import java.util.Base64;
import java.util.LinkedHashMap;
import java.util.Map;

/**
 * {@code POST /api/v1/news}, {@code PUT /api/v1/news/{id}} and {@code POST /api/v1/news/import}: csnews-env
 * {@code POST /api/v1/csnews/doc} and {@code PUT /api/v1/csnews/doc/{id}} ({@code sp_news_doc_insert} /
 * {@code sp_news_doc_update}), docapi 1.44.0. Replaces {@code MySqlNewsWriteRepository}.
 *
 * <p>{@code NewsWriteParser} has validated the write, so csnews-env sees only clean values. Photos travel as
 * base64; the stamp as a zone-less wall clock {@code yyyy-MM-dd'T'HH:mm:ss.SSS} -- the same value the JDBC
 * driver used to bind.
 */
public class HttpNewsWriteRepository implements NewsWriteRepository {

    static final DateTimeFormatter STAMP = DateTimeFormatter.ofPattern("yyyy-MM-dd'T'HH:mm:ss.SSS");

    private final CsNewsClient csnews;

    public HttpNewsWriteRepository(CsNewsClient csnews) {
        this.csnews = csnews;
    }

    @Override
    public String insert(NewsWrite write) {
        JsonNode data = csnews.send("POST", "/doc", body(write, true));
        String id = data == null ? null : data.path("newsId").asText(null);
        if (id == null || id.isBlank()) {
            throw new CsNewsUnavailableException("csnews-env insert returned no id", null);
        }
        return id;
    }

    @Override
    public boolean update(String id, NewsWrite write) {
        JsonNode data = csnews.send("PUT", "/doc/" + CsNewsClient.enc(id), body(write, false));
        return data != null && data.path("found").asBoolean(false);
    }

    /** The csnews-env {@code NewsWrite} body. Slots 1 and 2 only on insert: {@code sp_news_doc_update} takes slot 0 only. */
    static Map<String, Object> body(NewsWrite w, boolean allSlots) {
        Map<String, Object> m = new LinkedHashMap<>();
        m.put("title", w.title());
        m.put("author", w.author());
        m.put("authorLink", w.authorLink());
        m.put("source", w.source());
        m.put("sourceLink", w.sourceLink());
        m.put("videoLink", w.videoLink());
        m.put("paragraph0", w.paragraph0());
        m.put("paragraph1", w.paragraph1());
        m.put("paragraph2", w.paragraph2());
        m.put("country", w.country());
        m.put("stamp", w.stamp() == null ? null : w.stamp().toLocalDateTime().format(STAMP));
        m.put("lakeId", w.lakeId());
        m.put("fish1Id", w.fish1Id());
        m.put("fish2Id", w.fish2Id());
        m.put("fish3Id", w.fish3Id());
        m.put("photo0", photo(w.photo0()));
        if (allSlots) {
            m.put("photo1", photo(w.photo1()));
            m.put("photo2", photo(w.photo2()));
        }
        return m;
    }

    static Map<String, Object> photo(NewsWrite.Photo p) {
        Map<String, Object> m = new LinkedHashMap<>();
        m.put("data", p.bytes() == null ? null : Base64.getEncoder().encodeToString(p.bytes()));
        m.put("author", p.author());
        m.put("alt", p.alt());
        return m;
    }
}
