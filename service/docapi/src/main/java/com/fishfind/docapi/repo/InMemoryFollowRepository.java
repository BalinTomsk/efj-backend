package com.fishfind.docapi.repo;

import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.node.ArrayNode;
import com.fasterxml.jackson.databind.node.JsonNodeFactory;
import com.fasterxml.jackson.databind.node.ObjectNode;

import java.util.Set;
import java.util.concurrent.ConcurrentHashMap;

/** Follows in memory (default, no-database profile): any target exists, ids only, no names. */
public class InMemoryFollowRepository implements FollowRepository {

    private record Follow(String userId, int kind, String target) {}

    private final Set<Follow> follows = ConcurrentHashMap.newKeySet();

    @Override
    public JsonNode mine(String userId) {
        ObjectNode out = JsonNodeFactory.instance.objectNode();
        ArrayNode waters = out.putArray("waters");
        ArrayNode fish = out.putArray("fish");
        follows.stream().filter(f -> f.userId().equalsIgnoreCase(userId)).forEach(f -> {
            if (f.kind() == WATER) {
                waters.addObject().put("lakeId", f.target());
            } else {
                fish.addObject().put("fishId", f.target());
            }
        });
        return out;
    }

    @Override
    public int set(String userId, int kind, String targetId, boolean follow) {
        if (kind != WATER && kind != FISH) {
            return INVALID;
        }
        Follow f = new Follow(userId.toLowerCase(), kind, targetId.toLowerCase());
        if (!follow) {
            follows.remove(f);
            return NOT_FOLLOWED;
        }
        if (!follows.contains(f) && follows.stream().filter(x -> x.userId().equals(f.userId())).count() >= 500) {
            return TOO_MANY;
        }
        follows.add(f);
        return FOLLOWED;
    }
}
