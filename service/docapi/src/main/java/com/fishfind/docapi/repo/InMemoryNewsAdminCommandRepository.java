package com.fishfind.docapi.repo;

import java.util.UUID;
import java.util.concurrent.ConcurrentHashMap;
import java.util.Set;

/**
 * In-memory news-admin command repository (default, no-database profile). Behaves consistently
 * within one running process — a created draft can be published, and a photo update on a known id
 * reports {@code found:true} — so the endpoint runs end-to-end with no database, matching the other
 * in-memory command repositories.
 */
public class InMemoryNewsAdminCommandRepository implements NewsAdminCommandRepository {

    private final Set<String> knownIds = ConcurrentHashMap.newKeySet();

    @Override
    public String createDraft() {
        String id = UUID.randomUUID().toString();
        knownIds.add(id);
        return id;
    }

    @Override
    public PublishResult publish(NewsAdminPublishRequest request) {
        boolean isNew = knownIds.add(request.newsId());
        return new PublishResult(request.newsId(), isNew ? "inserted" : "updated");
    }

    @Override
    public PhotoUpdateResult updatePhoto(String newsId, int index, byte[] photo, String author, String alt) {
        boolean found = knownIds.contains(newsId);
        return new PhotoUpdateResult(found, found && index >= 0 && index <= 2);
    }
}
