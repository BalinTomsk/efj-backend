package com.fishfind.docapi.web;

import com.fasterxml.jackson.databind.ObjectMapper;
import com.fishfind.docapi.repo.FishQueryRepository;
import com.fishfind.docapi.service.FishDocumentService;
import com.fishfind.docapi.service.InvalidDocumentException;
import org.springframework.http.MediaType;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

import java.util.List;

/**
 * Fish endpoints under {@code /api/v1/fish}. Inherits the generic JSON-document CRUD
 * ({@code GET/POST/PUT /{id}}) from {@link AbstractDocumentController} and adds the species-catalogue
 * search query:
 *
 * <ul>
 *   <li>{@code GET /api/v1/fish/search} — relevance-ranked species search by name / Latin / synonym.</li>
 * </ul>
 *
 * <p>The query is delegated to {@link FishQueryRepository}, which handles DB access via
 * {@code dbo.SearchFishList} and provides an in-memory implementation for the no-database profile. The
 * literal {@code /search} path is matched ahead of the templated {@code /{id}} handler, so it never
 * collides with a document fetch.
 */
@RestController
@RequestMapping(value = "/api/v1/fish", produces = MediaType.APPLICATION_JSON_VALUE)
public class FishController extends AbstractDocumentController {

    /** Upper bound on the search term ({@code dbo.SearchFishList} takes a {@code varchar(64)}). */
    static final int MAX_TERM = 64;

    private final FishQueryRepository queryRepository;

    public FishController(FishDocumentService service, ObjectMapper objectMapper,
                          FishQueryRepository queryRepository) {
        super(service, objectMapper);
        this.queryRepository = queryRepository;
    }

    /**
     * Relevance-ranked search over the species catalogue: matches the term against a fish's primary
     * name, Latin name, and alternative/common names (so "rosefish" or "ling" resolves to the right
     * species even when it isn't the primary name), best match first. Backed by
     * {@code dbo.SearchFishList} — the same lookup the Editor {@code FishList.aspx} search box uses.
     *
     * <p>The literal {@code /search} path is matched ahead of the templated {@code /{id}} handler.
     *
     * @param q the search term (required, non-blank; trimmed and capped at {@value #MAX_TERM} chars)
     * @return the matching species list in the response envelope
     * @throws InvalidDocumentException if {@code q} is missing or blank (→ 400)
     */
    @GetMapping("/search")
    public ApiResponse<FishSearchPage> search(@RequestParam(required = false) String q) {
        if (q == null || q.isBlank()) {
            throw new InvalidDocumentException("q (search term) is required");
        }
        String term = q.trim();
        if (term.length() > MAX_TERM) {
            term = term.substring(0, MAX_TERM);
        }
        return ApiResponse.ok(queryRepository.search(term));
    }

    /**
     * One hit from {@code dbo.SearchFishList}: the fields needed to render a result row and link to the
     * species.
     *
     * @param fishId the species id (GUID)
     * @param name the primary common name
     * @param latin the Latin (scientific) name
     * @param rank the match rank — lower is a better match (0 = exact); rows are returned best-first
     */
    public record FishSearchItem(
            String fishId,
            String name,
            String latin,
            int rank) {
    }

    /**
     * The result of a fish search.
     *
     * @param items the matching species (best match first)
     * @param total the number of rows returned
     * @param query the (trimmed) term that was searched, echoed back
     */
    public record FishSearchPage(
            List<FishSearchItem> items,
            int total,
            String query) {
    }
}
