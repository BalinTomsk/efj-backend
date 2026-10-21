package com.fishfind.docapi.web;

import com.fasterxml.jackson.databind.ObjectMapper;
import com.fishfind.docapi.repo.FishQueryRepository;
import com.fishfind.docapi.service.FishDocumentService;
import org.junit.jupiter.api.Test;
import org.mockito.ArgumentCaptor;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.autoconfigure.web.servlet.WebMvcTest;
import org.springframework.boot.test.mock.mockito.MockBean;
import org.springframework.test.web.servlet.MockMvc;

import java.util.Collections;
import java.util.List;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

@WebMvcTest(FishController.class)
class FishControllerTest {

    @Autowired
    private MockMvc mockMvc;

    @Autowired
    private ObjectMapper objectMapper;

    @MockBean
    private FishDocumentService service;

    @MockBean
    private FishQueryRepository queryRepository;

    // ---- GET /{guid}: the species document (dbo.fn_fish_info_json, 1.28.0) ----

    private static final String WALLEYE = "2CFFB500-3E59-4120-9460-055856E9AC5C";

    @Test
    void getReturnsTheSpeciesDocumentForALowerCasedGuid() throws Exception {
        when(queryRepository.info(WALLEYE.toLowerCase())).thenReturn(objectMapper.readTree(
                "{\"fishId\":\"" + WALLEYE + "\",\"name\":\"Walleye\",\"zoology\":{\"maxLengthCm\":104.00}}"));

        mockMvc.perform(get("/api/v1/fish/" + WALLEYE))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.data.name").value("Walleye"))
                .andExpect(jsonPath("$.data.zoology.maxLengthCm").value(104.0))
                .andExpect(jsonPath("$.error").doesNotExist())
                .andExpect(jsonPath("$.meta.timestamp").exists());
        verify(service, never()).get(any());
    }

    @Test
    void getUnknownSpeciesReturns404WithErrorEnvelope() throws Exception {
        when(queryRepository.info(any())).thenReturn(null);

        mockMvc.perform(get("/api/v1/fish/" + WALLEYE))
                .andExpect(status().isNotFound())
                .andExpect(jsonPath("$.error.code").value("not_found"))
                .andExpect(jsonPath("$.data").doesNotExist());
    }

    @Test
    void getMalformedIdReturns400AndNeverQueries() throws Exception {
        mockMvc.perform(get("/api/v1/fish/walleye"))
                .andExpect(status().isBadRequest())
                .andExpect(jsonPath("$.error.code").value("invalid_document"));
        verify(queryRepository, never()).info(any());
        verify(service, never()).get(any());
    }

    // ---- species-catalogue search (delegated to FishQueryRepository) ----

    @Test
    void searchMapsRepositoryResultsIntoTheEnvelope() throws Exception {
        FishController.FishSearchItem item = new FishController.FishSearchItem(
                "f-id", "Bluegill", "Lepomis macrochirus", 0);
        when(queryRepository.search("rosefish"))
                .thenReturn(new FishController.FishSearchPage(List.of(item), 1, "rosefish"));

        mockMvc.perform(get("/api/v1/fish/search").param("q", "rosefish"))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.data.query").value("rosefish"))
                .andExpect(jsonPath("$.data.total").value(1))
                .andExpect(jsonPath("$.data.items[0].fishId").value("f-id"))
                .andExpect(jsonPath("$.data.items[0].name").value("Bluegill"))
                .andExpect(jsonPath("$.data.items[0].latin").value("Lepomis macrochirus"))
                .andExpect(jsonPath("$.data.items[0].rank").value(0));
    }

    @Test
    void searchTrimsTheTermBeforeQuerying() throws Exception {
        when(queryRepository.search("pike"))
                .thenReturn(new FishController.FishSearchPage(List.of(), 0, "pike"));

        mockMvc.perform(get("/api/v1/fish/search").param("q", "  pike  "))
                .andExpect(status().isOk());
        // verified via the stub: the controller must have passed the trimmed term
        verify(queryRepository).search("pike");
    }

    @Test
    void searchWithEmptyRepositoryReturnsEmptyPageEchoingTheQuery() throws Exception {
        when(queryRepository.search("nothing"))
                .thenReturn(new FishController.FishSearchPage(List.of(), 0, "nothing"));

        mockMvc.perform(get("/api/v1/fish/search").param("q", "nothing"))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.data.items").isArray())
                .andExpect(jsonPath("$.data.items").isEmpty())
                .andExpect(jsonPath("$.data.total").value(0))
                .andExpect(jsonPath("$.data.query").value("nothing"));
    }

    @Test
    void searchWithBlankTermReturns400() throws Exception {
        mockMvc.perform(get("/api/v1/fish/search").param("q", "   "))
                .andExpect(status().isBadRequest())
                .andExpect(jsonPath("$.error.code").value("invalid_document"));
    }

    @Test
    void searchWithMissingTermReturns400() throws Exception {
        mockMvc.perform(get("/api/v1/fish/search"))
                .andExpect(status().isBadRequest())
                .andExpect(jsonPath("$.error.code").value("invalid_document"));
    }

    // ---- code -> latin lookup (?province= & ?codes=) ----
    //
    // These use .param(...) rather than a query string baked into the path: MockMvc does not
    // URL-decode an embedded query string, whereas .param supplies the already-decoded value the
    // servlet container hands the controller. Several values below (braces, quotes, commas) are
    // exactly the characters that would otherwise arrive percent-encoded and never be parsed.

    /** Captures the code list the controller parsed out of the given raw {@code codes} value(s). */
    private List<String> capturedCodes(String... codes) throws Exception {
        ArgumentCaptor<List<String>> captor = captorOfList();
        when(queryRepository.codesToLatin(any(), any(), any())).thenReturn(objectMapper.createArrayNode());

        mockMvc.perform(get("/api/v1/fish").param("province", "AB").param("codes", codes))
                .andExpect(status().isOk());

        verify(queryRepository).codesToLatin(any(), any(), captor.capture());
        return captor.getValue();
    }

    @Test
    void codesLookupReturnsTheArrayNestedInTheEnvelope() throws Exception {
        when(queryRepository.codesToLatin(null, "AB", List.of("BURB", "WALL")))
                .thenReturn(objectMapper.readTree(
                        "[{\"code\":\"BURB\",\"latin\":\"Lota lota\"},"
                        + "{\"code\":\"WALL\",\"latin\":\"Stizostedion vitreum\"}]"));

        mockMvc.perform(get("/api/v1/fish").param("province", "AB").param("codes", "BURB,WALL"))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.data[0].code").value("BURB"))
                .andExpect(jsonPath("$.data[0].latin").value("Lota lota"))
                .andExpect(jsonPath("$.data[1].code").value("WALL"))
                .andExpect(jsonPath("$.data[1].latin").value("Stizostedion vitreum"))
                .andExpect(jsonPath("$.error").doesNotExist())
                .andExpect(jsonPath("$.meta.timestamp").exists());
    }

    /**
     * The literal the endpoint is documented with — braces and quotes around the list. Both are
     * structural and must not survive into the codes themselves.
     */
    @Test
    void codesAcceptTheBraceAndQuoteLiteral() throws Exception {
        assertThat(capturedCodes("{\"BURB\", \"WALL\"}")).containsExactly("BURB", "WALL");
    }

    @Test
    void codesAcceptABracketWrappedListAndSemicolons() throws Exception {
        assertThat(capturedCodes("[BURB;WALL]")).containsExactly("BURB", "WALL");
    }

    /**
     * A repeated parameter is the unambiguous form: each value is one entry verbatim, with no comma
     * splitting. This is what lets an entry that itself contains a comma be passed unquoted.
     */
    @Test
    void repeatedCodesParameterIsNotCommaSplit() throws Exception {
        assertThat(capturedCodes("BURB", "WALL")).containsExactly("BURB", "WALL");
    }

    @Test
    void blankCodeEntriesAreDropped() throws Exception {
        assertThat(capturedCodes("BURB,,  ,WALL")).containsExactly("BURB", "WALL");
    }

    @Test
    void provinceAndCountryArePassedThroughTrimmed() throws Exception {
        when(queryRepository.codesToLatin("US", "AB", List.of("BURB")))
                .thenReturn(objectMapper.createArrayNode());

        mockMvc.perform(get("/api/v1/fish")
                        .param("province", "  AB ").param("country", " US ").param("codes", "BURB"))
                .andExpect(status().isOk());
        verify(queryRepository).codesToLatin("US", "AB", List.of("BURB"));
    }

    /** No codes at all means "publish the whole province" — the repository is called with a null list. */
    @Test
    void provinceWithoutCodesRequestsTheWholeProvince() throws Exception {
        when(queryRepository.codesToLatin(null, "AB", null)).thenReturn(objectMapper.createArrayNode());

        mockMvc.perform(get("/api/v1/fish").param("province", "AB"))
                .andExpect(status().isOk());
        verify(queryRepository).codesToLatin(null, "AB", null);
    }

    /**
     * A regional code has no meaning without its jurisdiction — dbo.fish_code is keyed on
     * country+state+code, and the same code names different species in different provinces. So this is
     * a 400 rather than a guess or an empty result.
     */
    @Test
    void codesWithoutProvinceReturns400() throws Exception {
        mockMvc.perform(get("/api/v1/fish").param("codes", "BURB"))
                .andExpect(status().isBadRequest())
                .andExpect(jsonPath("$.error.code").value("invalid_document"));
    }

    @Test
    void noLookupParameterAtAllReturns400() throws Exception {
        mockMvc.perform(get("/api/v1/fish"))
                .andExpect(status().isBadRequest())
                .andExpect(jsonPath("$.error.code").value("invalid_document"));
    }

    @Test
    void codeBatchOverTheLimitReturns400() throws Exception {
        String tooMany = String.join(",", Collections.nCopies(FishController.MAX_BATCH + 1, "BURB"));

        mockMvc.perform(get("/api/v1/fish").param("province", "AB").param("codes", tooMany))
                .andExpect(status().isBadRequest())
                .andExpect(jsonPath("$.error.code").value("invalid_document"));
    }

    // ---- name -> latin lookup (?fishes=) ----

    @Test
    void fishesLookupEchoesTheQueryAndReturnsLatinNames() throws Exception {
        when(queryRepository.namesToLatin(List.of("Walley", "Burbot")))
                .thenReturn(objectMapper.readTree(
                        "[{\"query\":\"Walley\",\"name\":\"Walleye\",\"latin\":\"Stizostedion vitreum\"},"
                        + "{\"query\":\"Burbot\",\"name\":\"Burbot\",\"latin\":\"Lota lota\"}]"));

        mockMvc.perform(get("/api/v1/fish").param("fishes", "{\"Walley\", \"Burbot\"}"))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.data[0].query").value("Walley"))
                .andExpect(jsonPath("$.data[0].name").value("Walleye"))
                .andExpect(jsonPath("$.data[0].latin").value("Stizostedion vitreum"))
                .andExpect(jsonPath("$.data[1].query").value("Burbot"));
    }

    /**
     * 762 of the 1041 species names contain a comma, so a quoted entry must survive the split intact —
     * otherwise most of the catalogue is unreachable by name.
     */
    @Test
    void aQuotedNameKeepsItsComma() throws Exception {
        ArgumentCaptor<List<String>> captor = captorOfList();
        when(queryRepository.namesToLatin(any())).thenReturn(objectMapper.createArrayNode());

        mockMvc.perform(get("/api/v1/fish").param("fishes", "\"Bass, Guadalupe\",Burbot"))
                .andExpect(status().isOk());

        verify(queryRepository).namesToLatin(captor.capture());
        assertThat(captor.getValue()).containsExactly("Bass, Guadalupe", "Burbot");
    }

    /** A repeated parameter passes each name verbatim, commas and all, with no quoting needed. */
    @Test
    void repeatedFishesParameterKeepsCommasInNames() throws Exception {
        ArgumentCaptor<List<String>> captor = captorOfList();
        when(queryRepository.namesToLatin(any())).thenReturn(objectMapper.createArrayNode());

        mockMvc.perform(get("/api/v1/fish").param("fishes", "Bass, Guadalupe", "Burbot"))
                .andExpect(status().isOk());

        verify(queryRepository).namesToLatin(captor.capture());
        assertThat(captor.getValue()).containsExactly("Bass, Guadalupe", "Burbot");
    }

    /** fishes is its own mode: it wins outright, and province/codes are not consulted. */
    @Test
    void fishesTakesPrecedenceOverTheCodeLookup() throws Exception {
        when(queryRepository.namesToLatin(List.of("Burbot"))).thenReturn(objectMapper.createArrayNode());

        mockMvc.perform(get("/api/v1/fish").param("fishes", "Burbot").param("province", "AB"))
                .andExpect(status().isOk());

        verify(queryRepository).namesToLatin(List.of("Burbot"));
        verify(queryRepository, never()).codesToLatin(any(), any(), any());
    }

    @Test
    void fishBatchOverTheLimitReturns400() throws Exception {
        String tooMany = String.join(",", Collections.nCopies(FishController.MAX_BATCH + 1, "Burbot"));

        mockMvc.perform(get("/api/v1/fish").param("fishes", tooMany))
                .andExpect(status().isBadRequest())
                .andExpect(jsonPath("$.error.code").value("invalid_document"));
    }

    @SuppressWarnings("unchecked")
    private static ArgumentCaptor<List<String>> captorOfList() {
        return ArgumentCaptor.forClass(List.class);
    }
}
