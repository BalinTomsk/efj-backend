package com.fishfind.docapi.repo;

import com.fasterxml.jackson.databind.JsonNode;

import java.util.Base64;
import java.util.LinkedHashMap;
import java.util.Map;

/**
 * The AddNews editor's writes (draft / publish / photo): csnews-env {@code POST /api/v1/csnews/admin/draft},
 * {@code POST /admin/publish} and {@code PUT /admin/{id}/photo/{index}} ({@code sp_news_admin_*}), docapi 1.44.0.
 * Replaces {@code MySqlNewsAdminCommandRepository}. The index and the has_photo0 triggers that keep these
 * procedures fast and correct are now ensured by csnews-env at startup ({@code NewsSchemaBootstrap}).
 */
public class HttpNewsAdminCommandRepository implements NewsAdminCommandRepository {

    private final CsNewsClient csnews;

    public HttpNewsAdminCommandRepository(CsNewsClient csnews) {
        this.csnews = csnews;
    }

    @Override
    public String createDraft() {
        JsonNode data = csnews.send("POST", "/admin/draft", null);
        String id = data == null ? null : data.path("newsId").asText(null);
        if (id == null || id.isBlank()) {
            throw new CsNewsUnavailableException("csnews-env draft create returned no id", null);
        }
        return id;
    }

    @Override
    public PublishResult publish(NewsAdminPublishRequest r) {
        Map<String, Object> m = new LinkedHashMap<>();
        m.put("newsId", r.newsId());
        m.put("title", r.title());
        m.put("author", r.author());
        m.put("source", r.source());
        m.put("sourceLink", r.sourceLink());
        m.put("authorLink", r.authorLink());
        m.put("stamp", r.stamp() == null ? null : r.stamp().toLocalDateTime().format(HttpNewsWriteRepository.STAMP));
        m.put("videoLink", r.videoLink());
        m.put("paragraph0", r.paragraph0());
        m.put("paragraph1", r.paragraph1());
        m.put("paragraph2", r.paragraph2());
        m.put("country", r.country());
        m.put("lakeId", r.lakeId());
        m.put("fish1Id", r.fish1Id());
        m.put("fish2Id", r.fish2Id());
        m.put("fish3Id", r.fish3Id());
        JsonNode data = csnews.send("POST", "/admin/publish", m);
        if (data == null || data.isNull()) {
            throw new CsNewsUnavailableException("csnews-env publish returned no result", null);
        }
        return new PublishResult(data.path("newsId").asText(), data.path("action").asText());
    }

    @Override
    public PhotoUpdateResult updatePhoto(String newsId, int index, byte[] photo, String author, String alt) {
        Map<String, Object> m = new LinkedHashMap<>();
        m.put("data", Base64.getEncoder().encodeToString(photo));
        m.put("author", author);
        m.put("alt", alt);
        JsonNode data = csnews.send("PUT", "/admin/" + CsNewsClient.enc(newsId) + "/photo/" + index, m);
        if (data == null || data.isNull()) {
            return new PhotoUpdateResult(false, false);
        }
        return new PhotoUpdateResult(data.path("found").asBoolean(false), data.path("updated").asBoolean(false));
    }
}
