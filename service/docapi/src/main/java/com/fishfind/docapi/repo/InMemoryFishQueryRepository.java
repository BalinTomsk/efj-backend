package com.fishfind.docapi.repo;

import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.node.ArrayNode;
import com.fasterxml.jackson.databind.node.JsonNodeFactory;
import com.fasterxml.jackson.databind.node.ObjectNode;
import com.fishfind.docapi.web.FishController.FishSearchPage;

import java.util.List;

/**
 * In-memory fish query repository (default, no-database profile).
 * Returns empty results so the service runs end-to-end with no DB.
 */
public class InMemoryFishQueryRepository implements FishQueryRepository {

    /** No database: no matches, so the search endpoint runs end-to-end returning an empty result. */
    @Override
    public FishSearchPage search(String query) {
        return new FishSearchPage(List.of(), 0, query);
    }

    /**
     * No database, so nothing resolves — but the <b>1:1 shape contract is still honoured</b>: every
     * requested code comes back in its own slot with a null {@code latin}, rather than an empty array.
     * A caller (or a test) can therefore exercise the response shape with no DB configured, and the
     * no-DB profile never looks like "this province has no codes" when it really means "no database".
     * With no code list there is nothing to echo, so the whole-province mode yields an empty array.
     */
    @Override
    public JsonNode codesToLatin(String country, String province, List<String> codes) {
        ArrayNode array = JsonNodeFactory.instance.arrayNode();
        if (codes != null) {
            for (String code : codes) {
                ObjectNode item = array.addObject();
                item.put("code", code);
                item.putNull("latin");
            }
        }
        return array;
    }

    /**
     * No database, so nothing resolves — but as with {@link #codesToLatin} each requested name keeps its
     * slot, echoed in {@code query} with null {@code name}/{@code latin}, preserving the ordering
     * guarantee the endpoint documents.
     */
    @Override
    public JsonNode namesToLatin(List<String> names) {
        ArrayNode array = JsonNodeFactory.instance.arrayNode();
        for (String name : names) {
            ObjectNode item = array.addObject();
            item.put("query", name);
            item.putNull("name");
            item.putNull("latin");
        }
        return array;
    }
}
