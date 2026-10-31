package com.fishfind.docapi.web;

import com.fasterxml.jackson.databind.ObjectMapper;
import com.fasterxml.jackson.databind.node.ObjectNode;
import com.fishfind.docapi.repo.CatchLog;
import com.fishfind.docapi.repo.CatchLogCommandRepository;
import com.fishfind.docapi.repo.FishQueryRepository;
import com.fishfind.docapi.service.InvalidDocumentException;
import com.fishfind.docapi.repo.RegulationQueryRepository;
import com.fishfind.docapi.repo.RiverQueryRepository;
import com.fishfind.docapi.repo.RiverSearchCriteria;
import org.junit.jupiter.api.Test;
import org.mockito.ArgumentCaptor;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.autoconfigure.web.servlet.WebMvcTest;
import org.springframework.boot.test.mock.mockito.MockBean;
import org.springframework.context.annotation.Import;
import org.springframework.http.MediaType;
import org.springframework.test.web.servlet.MockMvc;
import org.springframework.test.web.servlet.ResultActions;

import java.util.List;
import java.util.Set;

import static org.hamcrest.Matchers.containsString;
import static org.hamcrest.Matchers.hasSize;
import static org.hamcrest.Matchers.not;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.anyInt;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.ArgumentMatchers.anyString;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.verifyNoInteractions;
import static org.mockito.Mockito.when;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.delete;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.content;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.header;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

@WebMvcTest(McpController.class)
@Import(McpToolCatalog.class)
class McpControllerTest {

    private static final String GUID = "0d012b12-849c-20c3-8532-2f7a21cfcc58";

    @Autowired
    private MockMvc mockMvc;

    @Autowired
    private ObjectMapper objectMapper;

    @MockBean
    private RiverQueryRepository riverRepository;

    @MockBean
    private RegulationQueryRepository regulationRepository;

    @MockBean
    private FishQueryRepository fishRepository;

    @MockBean
    private CatchLogCommandRepository catchLogRepository;

    @MockBean
    private CatchPhotoFetcher photoFetcher;

    /** As cproxy sends it for an admin's key; the default, so the pre-1.21.0 tests still reach every tool. */
    private ResultActions rpc(String body) throws Exception {
        return rpcAs("admin", body);
    }

    /** {@code role} null = no X-Fish-Role header at all (read as GUEST). */
    private ResultActions rpcAs(String role, String body) throws Exception {
        var request = post("/api/v1/mcp")
                .contentType(MediaType.APPLICATION_JSON)
                .accept(MediaType.APPLICATION_JSON, MediaType.TEXT_EVENT_STREAM)
                .content(body);
        if (role != null) request = request.header("X-Fish-Role", role);
        return mockMvc.perform(request);
    }

    private ResultActions callAs(String role, String tool, String arguments) throws Exception {
        return rpcAs(role, "{\"jsonrpc\":\"2.0\",\"id\":7,\"method\":\"tools/call\",\"params\":{\"name\":\"" + tool
                + "\",\"arguments\":" + arguments + "}}");
    }

    private ResultActions call(String tool, String arguments) throws Exception {
        return rpc("{\"jsonrpc\":\"2.0\",\"id\":7,\"method\":\"tools/call\",\"params\":{\"name\":\"" + tool
                + "\",\"arguments\":" + arguments + "}}");
    }

    /** A name/key search as search_water_bodies builds it: no region, any type, name order, first page. */
    private static RiverSearchCriteria byKey(String name, String cgndb, String stateId, int limit) {
        return new RiverSearchCriteria(name, null, cgndb, stateId, null, null, null, null, "name", 0, limit);
    }

    /** What dbo.fn_river_search_json returns: {total, limit, offset, items}. */
    private com.fasterxml.jackson.databind.JsonNode page(int total, int limit, int offset, String items) throws Exception {
        return objectMapper.readTree("{\"total\":" + total + ",\"limit\":" + limit + ",\"offset\":" + offset
                + ",\"items\":" + items + "}");
    }

    @Test
    void initializeEchoesASupportedVersionAndAdvertisesToolsOnly() throws Exception {
        rpc("{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"initialize\",\"params\":{\"protocolVersion\":\"2025-06-18\","
                + "\"capabilities\":{},\"clientInfo\":{\"name\":\"test\",\"version\":\"1\"}}}")
                .andExpect(status().isOk())
                .andExpect(content().contentTypeCompatibleWith(MediaType.APPLICATION_JSON))
                .andExpect(header().doesNotExist("Mcp-Session-Id"))
                .andExpect(jsonPath("$.id").value(1))
                .andExpect(jsonPath("$.result.protocolVersion").value("2025-06-18"))
                .andExpect(jsonPath("$.result.capabilities.tools.listChanged").value(false))
                .andExpect(jsonPath("$.result.capabilities.resources").doesNotExist())
                .andExpect(jsonPath("$.result.serverInfo.name").value("fishfind-docapi"));
    }

    @Test
    void initializeWithAnUnknownVersionOffersTheNewest() throws Exception {
        rpc("{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"initialize\",\"params\":{\"protocolVersion\":\"1999-01-01\"}}")
                .andExpect(jsonPath("$.result.protocolVersion").value(McpController.PROTOCOL_VERSIONS.get(0)));
    }

    @Test
    void notificationsAreAcceptedWithNoBody() throws Exception {
        rpc("{\"jsonrpc\":\"2.0\",\"method\":\"notifications/initialized\"}")
                .andExpect(status().isAccepted())
                .andExpect(content().string(""));
    }

    @Test
    void pingAnswersAnEmptyResult() throws Exception {
        rpc("{\"jsonrpc\":\"2.0\",\"id\":\"p\",\"method\":\"ping\"}")
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.id").value("p"))
                .andExpect(jsonPath("$.result").isMap());
    }

    @Test
    void toolsListPublishesElevenReadsAndThreeCatchLogWritesToAnAdmin() throws Exception {
        mockMvc.perform(post("/api/v1/mcp").contentType(MediaType.APPLICATION_JSON)
                        .header("X-Fish-Role", "admin").header("X-Fish-User", "bb30165a-fd1a-4b54-b921-9334242c9bf6")
                        .content("{\"jsonrpc\":\"2.0\",\"id\":2,\"method\":\"tools/list\"}"))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.result.tools", hasSize(14)))
                .andExpect(jsonPath("$.result.tools[0].name").value("search_water_bodies"))
                .andExpect(jsonPath("$.result.tools[0].inputSchema.type").value("object"))
                .andExpect(jsonPath("$.result.tools[?(@.annotations.readOnlyHint != true)]", hasSize(3)))
                .andExpect(jsonPath("$.result.tools[11].name").value("add_catch_log"))
                .andExpect(jsonPath("$.result.tools[11].annotations.destructiveHint").value(false))
                .andExpect(jsonPath("$.result.tools[12].name").value("update_catch_log"))
                .andExpect(jsonPath("$.result.tools[12].annotations.idempotentHint").value(true))
                .andExpect(jsonPath("$.result.tools[12].inputSchema.properties.airTemp.type[1]").value("null"))
                .andExpect(jsonPath("$.result.tools[13].name").value("add_catch_log_photo"))
                .andExpect(jsonPath("$.result.tools[13].annotations.openWorldHint").value(true));
    }

    @Test
    void unknownMethodIsAJsonRpcError() throws Exception {
        rpc("{\"jsonrpc\":\"2.0\",\"id\":3,\"method\":\"resources/list\"}")
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.error.code").value(McpController.METHOD_NOT_FOUND));
    }

    @Test
    void unknownToolIsInvalidParams() throws Exception {
        call("drop_tables", "{}")
                .andExpect(jsonPath("$.error.code").value(McpController.INVALID_PARAMS));
    }

    @Test
    void malformedBodyIsAParseError() throws Exception {
        rpc("{not json")
                .andExpect(status().isBadRequest())
                .andExpect(jsonPath("$.error.code").value(McpController.PARSE_ERROR));
    }

    @Test
    void aBrowserOriginIsRefused() throws Exception {
        mockMvc.perform(post("/api/v1/mcp").header("Origin", "https://evil.example")
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"ping\"}"))
                .andExpect(status().isForbidden());
    }

    @Test
    void anUnsupportedProtocolVersionHeaderIsRefused() throws Exception {
        mockMvc.perform(post("/api/v1/mcp").header("MCP-Protocol-Version", "1999-01-01")
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"ping\"}"))
                .andExpect(status().isBadRequest());
    }

    @Test
    void getAndDeleteOfferNoStreamAndNoSession() throws Exception {
        mockMvc.perform(get("/api/v1/mcp")).andExpect(status().isMethodNotAllowed())
                .andExpect(header().string("Allow", "POST"));
        mockMvc.perform(delete("/api/v1/mcp")).andExpect(status().isMethodNotAllowed());
    }

    @Test
    void aBatchIsAnsweredPerRequestAndSkipsNotifications() throws Exception {
        rpc("[{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"ping\"},{\"jsonrpc\":\"2.0\",\"method\":\"notifications/initialized\"}]")
                .andExpect(status().isOk())
                .andExpect(jsonPath("$", hasSize(1)))
                .andExpect(jsonPath("$[0].id").value(1));
    }

    @Test
    void searchPassesNormalizedCriteriaAndCapsTheLimit() throws Exception {
        when(riverRepository.search(byKey("Ottawa", "FEFUL", null, McpToolCatalog.SEARCH_MAX_LIMIT)))
                .thenReturn(page(1, 50, 0, "[{\"lakeId\":\"" + GUID + "\",\"lakeName\":\"Ottawa River\"}]"));

        call("search_water_bodies", "{\"name\":\" Ottawa \",\"cgndb\":\"feful\",\"limit\":500}")
                .andExpect(jsonPath("$.result.isError").value(false))
                .andExpect(jsonPath("$.result.structuredContent.total").value(1))
                .andExpect(jsonPath("$.result.structuredContent.limit").value(50))
                .andExpect(jsonPath("$.result.structuredContent.items[0].lakeName").value("Ottawa River"))
                .andExpect(jsonPath("$.result.content[0].type").value("text"))
                .andExpect(jsonPath("$.result.content[0].text", containsString("Ottawa River")));
    }

    @Test
    void searchByStateIdPassesItToTheRepository() throws Exception {
        when(riverRepository.search(byKey(null, null, "39325", McpToolCatalog.SEARCH_DEFAULT_LIMIT)))
                .thenReturn(page(1, 20, 0,
                        "[{\"lakeId\":\"" + GUID + "\",\"lakeName\":\"Fraser River\",\"stateId\":\"39325\"}]"));

        call("search_water_bodies", "{\"stateId\":\" 39325 \"}")
                .andExpect(jsonPath("$.result.isError").value(false))
                .andExpect(jsonPath("$.result.structuredContent.total").value(1))
                .andExpect(jsonPath("$.result.structuredContent.items[0].stateId").value("39325"));
    }

    @Test
    void searchByAGnisIdAsCgndbPassesItToTheRepository() throws Exception {
        when(riverRepository.search(byKey(null, "566885", null, McpToolCatalog.SEARCH_DEFAULT_LIMIT)))
                .thenReturn(page(1, 20, 0, "[{\"lakeId\":\"" + GUID + "\",\"lakeName\":\"Goodell Brook\"}]"));

        call("search_water_bodies", "{\"cgndb\":\"566885\"}")
                .andExpect(jsonPath("$.result.isError").value(false))
                .andExpect(jsonPath("$.result.structuredContent.items[0].lakeName").value("Goodell Brook"));
    }

    @Test
    void searchWithATooLongCgndbIsAToolError() throws Exception {
        call("search_water_bodies", "{\"cgndb\":\"12345678901\"}")
                .andExpect(jsonPath("$.result.isError").value(true))
                .andExpect(jsonPath("$.result.content[0].text", containsString("cgndb")));
        verify(riverRepository, never()).search(any());
    }

    @Test
    void searchWithAMalformedStateIdIsAToolError() throws Exception {
        call("search_water_bodies", "{\"stateId\":\"39 325\"}")
                .andExpect(jsonPath("$.result.isError").value(true))
                .andExpect(jsonPath("$.result.content[0].text", containsString("stateId")));
        verify(riverRepository, never()).search(any());
    }

    @Test
    void searchWithNoCriterionIsAToolErrorAndNeverQueries() throws Exception {
        call("search_water_bodies", "{}")
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.result.isError").value(true))
                .andExpect(jsonPath("$.result.content[0].text", containsString("at least one")));
        verify(riverRepository, never()).search(any());
    }

    @Test
    void rankingSearchPassesRegionTypesSortAndOffsetInOneCall() throws Exception {
        RiverSearchCriteria longestInMaine = new RiverSearchCriteria(null, null, null, null, null,
                null, "ME", 2 | 64, "length_desc", 5, 1);
        when(riverRepository.search(longestInMaine)).thenReturn(page(288, 1, 5,
                "[{\"lakeId\":\"" + GUID + "\",\"lakeName\":\"Kennebec River\",\"length\":270,\"lengthM\":268114}]"));

        call("search_water_bodies",
                "{\"state\":\" me \",\"types\":[\"river\",\"creek\"],\"sort\":\"LENGTH_DESC\",\"offset\":5,\"limit\":1}")
                .andExpect(jsonPath("$.result.isError").value(false))
                .andExpect(jsonPath("$.result.structuredContent.total").value(288))
                .andExpect(jsonPath("$.result.structuredContent.offset").value(5))
                .andExpect(jsonPath("$.result.structuredContent.items[0].length").value(270))
                .andExpect(jsonPath("$.result.structuredContent.items[0].lengthM").value(268114))
                .andExpect(jsonPath("$.result.structuredContent.query.state").value("ME"))
                .andExpect(jsonPath("$.result.structuredContent.query.locType").value(66))
                .andExpect(jsonPath("$.result.structuredContent.query.sort").value("length_desc"));
        verify(riverRepository).search(longestInMaine);
    }

    @Test
    void aCountryAloneIsASearchAndOffsetIsClampedAtZero() throws Exception {
        RiverSearchCriteria criteria = new RiverSearchCriteria(null, null, null, null, null,
                "US", null, 1, "area_desc", 0, McpToolCatalog.SEARCH_DEFAULT_LIMIT);
        when(riverRepository.search(criteria)).thenReturn(page(0, 20, 0, "[]"));

        call("search_water_bodies", "{\"country\":\"us\",\"types\":[\"lake\"],\"sort\":\"area_desc\",\"offset\":-3}")
                .andExpect(jsonPath("$.result.isError").value(false))
                .andExpect(jsonPath("$.result.structuredContent.total").value(0));
        verify(riverRepository).search(criteria);
    }

    @Test
    void typesOrSortAloneAreNotASearch() throws Exception {
        call("search_water_bodies", "{\"types\":[\"river\"],\"sort\":\"length_desc\"}")
                .andExpect(jsonPath("$.result.isError").value(true))
                .andExpect(jsonPath("$.result.content[0].text", containsString("at least one")));
        verify(riverRepository, never()).search(any());
    }

    @Test
    void aBadSortStateCountryOrTypeIsAToolErrorAndNeverQueries() throws Exception {
        call("search_water_bodies", "{\"state\":\"ME\",\"sort\":\"longest\"}")
                .andExpect(jsonPath("$.result.isError").value(true))
                .andExpect(jsonPath("$.result.content[0].text", containsString("length_desc")));
        call("search_water_bodies", "{\"state\":\"Maine\"}")
                .andExpect(jsonPath("$.result.isError").value(true))
                .andExpect(jsonPath("$.result.content[0].text", containsString("state")));
        call("search_water_bodies", "{\"country\":\"MX\"}")
                .andExpect(jsonPath("$.result.isError").value(true))
                .andExpect(jsonPath("$.result.content[0].text", containsString("country")));
        call("search_water_bodies", "{\"state\":\"ME\",\"types\":[\"ocean\"]}")
                .andExpect(jsonPath("$.result.isError").value(true))
                .andExpect(jsonPath("$.result.content[0].text", containsString("ocean")));
        verify(riverRepository, never()).search(any());
    }

    @Test
    void searchSchemaOffersRegionTypesSortAndOffset() throws Exception {
        rpc("{\"jsonrpc\":\"2.0\",\"id\":2,\"method\":\"tools/list\"}")
                .andExpect(jsonPath("$.result.tools[0].name").value("search_water_bodies"))
                .andExpect(jsonPath("$.result.tools[0].inputSchema.properties.country.enum", hasSize(4)))
                .andExpect(jsonPath("$.result.tools[0].inputSchema.properties.state.pattern").value("^[A-Za-z]{2}$"))
                .andExpect(jsonPath("$.result.tools[0].inputSchema.properties.types.items.enum",
                        hasSize(McpToolCatalog.WATER_BODY_TYPES.size())))
                .andExpect(jsonPath("$.result.tools[0].inputSchema.properties.sort.enum",
                        hasSize(RiverSearchCriteria.SORTS.size())))
                .andExpect(jsonPath("$.result.tools[0].inputSchema.properties.offset.minimum").value(0))
                .andExpect(jsonPath("$.result.tools[0].description", containsString("longest river in Maine")));
    }

    @Test
    void initializePointsRankingQuestionsAtOneSearch() throws Exception {
        rpc("{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"initialize\",\"params\":{\"protocolVersion\":\"2025-06-18\"}}")
                .andExpect(jsonPath("$.result.instructions", containsString("search_water_bodies ONCE")))
                .andExpect(jsonPath("$.result.instructions", containsString("sort")));
    }

    @Test
    void aMalformedGuidNeverReachesTheDatabase() throws Exception {
        call("get_water_body", "{\"guid\":\"'; drop table lake --\"}")
                .andExpect(jsonPath("$.result.isError").value(true))
                .andExpect(jsonPath("$.result.content[0].text", containsString("GUID")));
        verifyNoInteractions(riverRepository);
    }

    @Test
    void getWaterBodyNormalizesTheGuidAndReturnsNoPhotos() throws Exception {
        when(riverRepository.description(GUID)).thenReturn(objectMapper.readTree(
                "{\"guid\":\"" + GUID + "\",\"lakeName\":\"Lake X\",\"description\":\"Deep.\","
                        + "\"fish\":[{\"fishName\":\"Walleye\"}],"
                        + "\"images\":[{\"id\":1,\"author\":\"A\",\"pic\":\"QUJD\"}]}"));

        call("get_water_body", "{\"guid\":\"{" + GUID.replace("-", "").toUpperCase() + "}\"}")
                .andExpect(jsonPath("$.result.isError").value(false))
                .andExpect(jsonPath("$.result.structuredContent.lakeName").value("Lake X"))
                .andExpect(jsonPath("$.result.structuredContent.fish[0].fishName").value("Walleye"))
                .andExpect(jsonPath("$.result.structuredContent.images").doesNotExist())
                .andExpect(jsonPath("$.result.content[0].text", not(containsString("QUJD"))));
    }

    private static final String BROWN = "6DBF1306-DC10-421A-A29B-B260D540A0AE";
    private static final String RAINBOW = "B3A33573-8BC6-4803-B977-10F673AAD711";
    private static final String BROOK = "F124F917-D11F-4ED9-9B59-863D184CBFED";

    @Test
    void eachSpeciesIsReturnedOnceWithItsHighestProbabilityEntry() throws Exception {
        // The Humber River (ON) shape: lake_fish's key is (lake, fish, probability), so one species
        // can have an entry per probability level. The tool must return each species once.
        when(riverRepository.fish(GUID)).thenReturn(objectMapper.readTree("{\"guid\":\"" + GUID + "\",\"fish\":["
                + "{\"fishId\":\"" + BROOK + "\",\"fishName\":\"Trout, Brook\",\"probability\":100,\"link\":\"stocking\"},"
                + "{\"fishId\":\"" + BROWN + "\",\"fishName\":\"Trout, Brown\",\"probability\":90,\"link\":\"#southsaugeen\"},"
                + "{\"fishId\":\"" + BROWN + "\",\"fishName\":\"Trout, Brown\",\"probability\":100,\"link\":null},"
                + "{\"fishId\":\"" + RAINBOW + "\",\"fishName\":\"Trout, Rainbow\",\"probability\":0,\"link\":\"#beaver\"},"
                + "{\"fishId\":\"" + RAINBOW + "\",\"fishName\":\"Trout, Rainbow\",\"probability\":100,\"link\":null},"
                + "{\"fishId\":\"" + RAINBOW.toLowerCase() + "\",\"fishName\":\"Trout, Rainbow\",\"probability\":90,\"link\":\"#southsaugeen\"}"
                + "]}"));

        call("get_water_body_fish", "{\"guid\":\"" + GUID + "\"}")
                .andExpect(jsonPath("$.result.isError").value(false))
                .andExpect(jsonPath("$.result.structuredContent.fish", hasSize(3)))
                // name order kept; the highest-probability entry of each species wins
                .andExpect(jsonPath("$.result.structuredContent.fish[0].fishName").value("Trout, Brook"))
                .andExpect(jsonPath("$.result.structuredContent.fish[1].fishName").value("Trout, Brown"))
                .andExpect(jsonPath("$.result.structuredContent.fish[1].probability").value(100))
                .andExpect(jsonPath("$.result.structuredContent.fish[2].fishName").value("Trout, Rainbow"))
                .andExpect(jsonPath("$.result.structuredContent.fish[2].probability").value(100))
                .andExpect(jsonPath("$.result.content[0].text", not(containsString("#beaver"))))
                .andExpect(jsonPath("$.result.content[0].text", not(containsString("#southsaugeen"))));
    }

    @Test
    void aTieKeepsTheFirstEntryAndAMissingProbabilityRanksLowest() throws Exception {
        when(riverRepository.fish(GUID)).thenReturn(objectMapper.readTree("{\"fish\":["
                + "{\"fishId\":\"" + BROWN + "\",\"probability\":null,\"link\":\"none\"},"
                + "{\"fishId\":\"" + BROWN + "\",\"probability\":50,\"link\":\"first-50\"},"
                + "{\"fishId\":\"" + BROWN + "\",\"probability\":50,\"link\":\"second-50\"},"
                + "{\"fishName\":\"no id\"}"
                + "]}"));

        call("get_water_body_fish", "{\"guid\":\"" + GUID + "\"}")
                .andExpect(jsonPath("$.result.structuredContent.fish", hasSize(2)))
                .andExpect(jsonPath("$.result.structuredContent.fish[0].link").value("first-50"))
                .andExpect(jsonPath("$.result.structuredContent.fish[1].fishName").value("no id"));
    }

    @Test
    void theDescriptionListsEachSpeciesOnce() throws Exception {
        when(riverRepository.description(GUID)).thenReturn(objectMapper.readTree("{\"lakeName\":\"Humber River\",\"fish\":["
                + "{\"fishId\":\"" + BROWN + "\",\"fishName\":\"Trout, Brown\",\"status\":null},"
                + "{\"fishId\":\"" + BROWN + "\",\"fishName\":\"Trout, Brown\",\"status\":null},"
                + "{\"fishId\":\"" + RAINBOW + "\",\"fishName\":\"Trout, Rainbow\",\"status\":null}]}"));

        call("get_water_body", "{\"guid\":\"" + GUID + "\"}")
                .andExpect(jsonPath("$.result.structuredContent.fish", hasSize(2)))
                .andExpect(jsonPath("$.result.structuredContent.fish[1].fishName").value("Trout, Rainbow"));
    }

    @Test
    void anUnknownWaterBodyIsAToolError() throws Exception {
        when(riverRepository.fish(GUID)).thenReturn(null);

        call("get_water_body_fish", "{\"guid\":\"" + GUID + "\"}")
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.result.isError").value(true));
    }

    @Test
    void linksCombineSourceAndMouthWithoutTheirPictures() throws Exception {
        when(riverRepository.source(GUID)).thenReturn(objectMapper.readTree(
                "{\"lakeName\":\"R\",\"links\":[{\"pointName\":\"Spring\",\"pic\":\"QUJD\",\"Photo0\":\"x\"}]}"));
        when(riverRepository.mouth(GUID)).thenReturn(objectMapper.readTree(
                "{\"lakeName\":\"R\",\"links\":[{\"pointName\":\"Bay\",\"pic\":\"QUJD\"}]}"));

        call("get_water_body_links", "{\"guid\":\"" + GUID + "\"}")
                .andExpect(jsonPath("$.result.structuredContent.source.links[0].pointName").value("Spring"))
                .andExpect(jsonPath("$.result.structuredContent.source.links[0].pic").doesNotExist())
                .andExpect(jsonPath("$.result.structuredContent.source.links[0].Photo0").doesNotExist())
                .andExpect(jsonPath("$.result.structuredContent.mouth.links[0].pointName").value("Bay"))
                .andExpect(jsonPath("$.result.content[0].text", not(containsString("QUJD"))));
    }

    // ---- 1.22.0: get_water_body_tributaries ---------------------------------------------------

    private static final String TRIB_US = "11111111-1111-1111-1111-111111111111";
    private static final String TRIB_A = "22222222-2222-2222-2222-222222222222";
    private static final String TRIB_B = "33333333-3333-3333-3333-333333333333";

    private void humberWithThreeTributaries(int limit) throws Exception {
        int sqlTotal = 3;
        when(riverRepository.tributaries(GUID, limit)).thenReturn(objectMapper.readTree(
                "{\"guid\":\"" + GUID + "\",\"lakeName\":\"Humber River\",\"total\":" + sqlTotal + ",\"limit\":200,"
                        + "\"tributaries\":["
                        + "{\"lakeId\":\"" + TRIB_A.toUpperCase() + "\",\"lakeName\":\"East Humber River\",\"link\":\"mouth\"},"
                        + "{\"lakeId\":\"" + TRIB_US + "\",\"lakeName\":\"Over The Border Creek\",\"link\":\"mouth\"},"
                        + "{\"lakeId\":\"" + TRIB_B + "\",\"lakeName\":\"West Humber River\",\"link\":\"inflow\",\"pic\":\"QUJD\"}]}"));
    }

    @Test
    void tributariesIncludeUsWaterBodiesAndPassTheLimitThrough() throws Exception {
        humberWithThreeTributaries(McpToolCatalog.SEARCH_DEFAULT_LIMIT);

        callAs("user", "get_water_body_tributaries", "{\"guid\":\"" + GUID.toUpperCase() + "\"}")
                .andExpect(jsonPath("$.result.isError").value(false))
                .andExpect(jsonPath("$.result.structuredContent.lakeName").value("Humber River"))
                .andExpect(jsonPath("$.result.structuredContent.total").value(3))
                .andExpect(jsonPath("$.result.structuredContent.tributaries", hasSize(3)))
                .andExpect(jsonPath("$.result.structuredContent.tributaries[1].lakeName").value("Over The Border Creek"))
                .andExpect(jsonPath("$.result.content[0].text", not(containsString("QUJD"))));
        humberWithThreeTributaries(McpToolCatalog.SEARCH_MAX_LIMIT);
        call("get_water_body_tributaries", "{\"guid\":\"" + GUID + "\",\"limit\":500}")
                .andExpect(jsonPath("$.result.isError").value(false));
        verify(riverRepository).tributaries(GUID, McpToolCatalog.SEARCH_MAX_LIMIT);   // clamped to 50
    }

    // ---- 1.24.0: get_water_body_barriers ------------------------------------------------------

    @Test
    void barriersReturnTheWaterfallsAndDamsOfAWaterBody() throws Exception {
        when(riverRepository.barriers(GUID)).thenReturn(objectMapper.readTree(
                "{\"guid\":\"" + GUID + "\",\"lakeName\":\"Exploits River\","
                        + "\"waterfalls\":[{\"name\":\"Grand Falls\",\"type\":\"Falls\",\"lat\":48.93,\"lon\":-55.67}],"
                        + "\"dams\":[{\"name\":null,\"lat\":48.93,\"lon\":-55.70,\"linkMethod\":\"chn_polygon\"}]}"));

        callAs("user", "get_water_body_barriers", "{\"guid\":\"" + GUID.toUpperCase() + "\"}")
                .andExpect(jsonPath("$.result.isError").value(false))
                .andExpect(jsonPath("$.result.structuredContent.lakeName").value("Exploits River"))
                .andExpect(jsonPath("$.result.structuredContent.waterfalls", hasSize(1)))
                .andExpect(jsonPath("$.result.structuredContent.waterfalls[0].name").value("Grand Falls"))
                .andExpect(jsonPath("$.result.structuredContent.dams", hasSize(1)))
                .andExpect(jsonPath("$.result.structuredContent.dams[0].linkMethod").value("chn_polygon"));
    }

    @Test
    void barriersOfAnUnknownWaterBodyOrABadGuidAreToolErrors() throws Exception {
        when(riverRepository.barriers(GUID)).thenReturn(null);
        call("get_water_body_barriers", "{\"guid\":\"" + GUID + "\"}")
                .andExpect(jsonPath("$.result.isError").value(true));
        call("get_water_body_barriers", "{\"guid\":\"not-a-guid\"}")
                .andExpect(jsonPath("$.result.isError").value(true));
        verify(riverRepository).barriers(any());   // only the first call got that far
    }

    @Test
    void tributariesOfAnUnknownWaterBodyOrABadArgumentAreToolErrors() throws Exception {
        when(riverRepository.tributaries(GUID, McpToolCatalog.SEARCH_DEFAULT_LIMIT)).thenReturn(null);
        call("get_water_body_tributaries", "{\"guid\":\"" + GUID + "\"}")
                .andExpect(jsonPath("$.result.isError").value(true));

        call("get_water_body_tributaries", "{\"guid\":\"not-a-guid\"}")
                .andExpect(jsonPath("$.result.isError").value(true));
        call("get_water_body_tributaries", "{\"guid\":\"" + GUID + "\",\"limit\":\"many\"}")
                .andExpect(jsonPath("$.result.isError").value(true));
        verify(riverRepository).tributaries(any(), anyInt());   // only the first call got that far
    }

    @Test
    void regionRegulationsValidateTheCodes() throws Exception {
        when(regulationRepository.region("CA", "ON"))
                .thenReturn(objectMapper.readTree("{\"country\":\"CA\",\"state\":\"ON\",\"regulations\":[]}"));

        call("get_region_regulations", "{\"country\":\"ca\",\"state\":\"on\"}")
                .andExpect(jsonPath("$.result.isError").value(false))
                .andExpect(jsonPath("$.result.structuredContent.state").value("ON"));

        call("get_region_regulations", "{\"country\":\"Canada\"}")
                .andExpect(jsonPath("$.result.isError").value(true));
        verify(regulationRepository, never()).region(org.mockito.ArgumentMatchers.eq("CANADA"), any());
        verify(regulationRepository, org.mockito.Mockito.times(1)).region(anyString(), any());
    }

    private static final String WALLEYE = "2CFFB500-3E59-4120-9460-055856E9AC5C";

    @Test
    void waterBodiesByFishValidatesThenPassesNormalizedArguments() throws Exception {
        when(fishRepository.waterBodies(WALLEYE.toLowerCase(), "CA", "ON", 66, 50, 10)).thenReturn(objectMapper.readTree(
                "{\"total\":312,\"limit\":10,\"items\":[{\"lakeId\":\"" + GUID + "\",\"lakeName\":\"Speed River\","
                        + "\"locType\":2,\"state\":\"ON\",\"probability\":100}]}"));

        // braced upper-case GUID, lower-case codes, type names in any case: all normalized before SQL
        call("find_water_bodies_by_fish", "{\"fishId\":\"{" + WALLEYE + "}\",\"country\":\"ca\",\"state\":\"on\","
                + "\"types\":[\"River\",\"creek\"],\"min_probability\":50,\"limit\":10}")
                .andExpect(jsonPath("$.result.isError").value(false))
                .andExpect(jsonPath("$.result.structuredContent.total").value(312))
                .andExpect(jsonPath("$.result.structuredContent.items[0].lakeName").value("Speed River"))
                .andExpect(jsonPath("$.result.structuredContent.query.locType").value(66))
                .andExpect(jsonPath("$.result.structuredContent.query.state").value("ON"));
    }

    @Test
    void waterBodiesByFishDefaultsAndClamps() throws Exception {
        when(fishRepository.waterBodies(anyString(), any(), any(), any(), anyInt(), anyInt()))
                .thenReturn(objectMapper.readTree("{\"total\":0,\"limit\":50,\"items\":[]}"));

        call("find_water_bodies_by_fish", "{\"fishId\":\"" + WALLEYE + "\",\"min_probability\":500,\"limit\":999}")
                .andExpect(jsonPath("$.result.isError").value(false));
        verify(fishRepository).waterBodies(WALLEYE.toLowerCase(), null, null, null, 100, 50);   // no country = both
    }

    @Test
    void waterBodiesByFishRejectsBadArgumentsBeforeAnyQuery() throws Exception {
        call("find_water_bodies_by_fish", "{}")
                .andExpect(jsonPath("$.result.isError").value(true))
                .andExpect(jsonPath("$.result.content[0].text", containsString("search_fish")));
        call("find_water_bodies_by_fish", "{\"fishId\":\"walleye\"}")
                .andExpect(jsonPath("$.result.isError").value(true));
        call("find_water_bodies_by_fish", "{\"fishId\":\"" + WALLEYE + "\",\"types\":[\"ocean\"]}")
                .andExpect(jsonPath("$.result.isError").value(true))
                .andExpect(jsonPath("$.result.content[0].text", containsString("river")));
        call("find_water_bodies_by_fish", "{\"fishId\":\"" + WALLEYE + "\",\"state\":\"Ontario\"}")
                .andExpect(jsonPath("$.result.isError").value(true));
        call("find_water_bodies_by_fish", "{\"fishId\":\"" + WALLEYE + "\",\"limit\":\"lots\"}")
                .andExpect(jsonPath("$.result.isError").value(true));
        verify(fishRepository, never()).waterBodies(any(), any(), any(), any(), anyInt(), anyInt());
    }

    // ---- 1.21.0: fish information for admins only ---------------------------------------------

    private static final Set<String> FISH_TOOLS = Set.of("get_water_body_fish", "search_fish", "get_fish", "find_water_bodies_by_fish");

    @Test
    void aGuestOrUserSeesSevenToolsAndNoFishTools() throws Exception {
        for (String role : new String[] {null, "guest", "user", "superuser"}) {
            rpcAs(role, "{\"jsonrpc\":\"2.0\",\"id\":2,\"method\":\"tools/list\"}")
                    .andExpect(jsonPath("$.result.tools", hasSize(7)))
                    .andExpect(jsonPath("$.result.tools[?(@.name == 'get_water_body_fish')]", hasSize(0)))
                    .andExpect(jsonPath("$.result.tools[?(@.name == 'search_fish')]", hasSize(0)))
                    .andExpect(jsonPath("$.result.tools[?(@.name == 'get_fish')]", hasSize(0)))
                    .andExpect(jsonPath("$.result.tools[?(@.name == 'find_water_bodies_by_fish')]", hasSize(0)));
        }
    }

    @Test
    void aNonAdminCallingAFishToolGetsUnknownToolAndNothingIsQueried() throws Exception {
        for (String tool : FISH_TOOLS) {
            callAs("user", tool, "{\"guid\":\"" + GUID + "\",\"query\":\"walleye\",\"fishId\":\"" + WALLEYE + "\"}")
                    .andExpect(jsonPath("$.error.code").value(McpController.INVALID_PARAMS))
                    .andExpect(jsonPath("$.error.message", containsString("Unknown tool")));
        }
        verifyNoInteractions(fishRepository);
        verify(riverRepository, never()).fish(any());
    }

    @Test
    void getWaterBodyShowsSpeciesToAdminsOnly() throws Exception {
        // A fresh document per call, as the JDBC repository returns.
        when(riverRepository.description(GUID)).thenAnswer(inv -> objectMapper.readTree(
                "{\"lakeName\":\"Lake X\",\"fish\":[{\"fishId\":\"" + WALLEYE + "\",\"fishName\":\"Walleye\"}]}"));

        callAs("user", "get_water_body", "{\"guid\":\"" + GUID + "\"}")
                .andExpect(jsonPath("$.result.structuredContent.lakeName").value("Lake X"))
                .andExpect(jsonPath("$.result.structuredContent.fish").doesNotExist())
                .andExpect(jsonPath("$.result.content[0].text", not(containsString("Walleye"))));
        callAs(null, "get_water_body", "{\"guid\":\"" + GUID + "\"}")
                .andExpect(jsonPath("$.result.structuredContent.fish").doesNotExist());
        callAs("admin", "get_water_body", "{\"guid\":\"" + GUID + "\"}")
                .andExpect(jsonPath("$.result.structuredContent.fish[0].fishName").value("Walleye"));
    }

    @Test
    void getWaterBodyCarriesTheMouthRoadToEveryone() throws Exception {
        when(riverRepository.description(GUID)).thenAnswer(inv -> objectMapper.readTree(
                "{\"lakeName\":\"Wilton Creek\",\"mouthRoad\":\"Big Creek Road\"}"));

        callAs(null, "get_water_body", "{\"guid\":\"" + GUID + "\"}")
                .andExpect(jsonPath("$.result.structuredContent.mouthRoad").value("Big Creek Road"));
    }

    // ---- 1.25.0: Canada and the USA (the 1.21.0 Canada-only block is gone) -------------------

    @Test
    void aUsWaterBodyIsAnsweredLikeAnyOther() throws Exception {
        when(riverRepository.description(GUID)).thenReturn(objectMapper.readTree(
                "{\"lakeName\":\"Red River of the North\",\"country\":\"US\"}"));

        callAs("user", "get_water_body", "{\"guid\":\"" + GUID + "\"}")
                .andExpect(jsonPath("$.result.isError").value(false))
                .andExpect(jsonPath("$.result.structuredContent.lakeName").value("Red River of the North"));
    }

    @Test
    void searchReturnsUsMatchesToo() throws Exception {
        String us = "11111111-1111-1111-1111-111111111111", on = "22222222-2222-2222-2222-222222222222";
        when(riverRepository.search(byKey("Red", null, null, McpToolCatalog.SEARCH_DEFAULT_LIMIT)))
                .thenReturn(page(2, 20, 0, "[{\"lakeId\":\"" + us + "\",\"lakeName\":\"Red River US\"},"
                        + "{\"lakeId\":\"" + on + "\",\"lakeName\":\"Red River ON\"}]"));

        callAs("user", "search_water_bodies", "{\"name\":\"Red\"}")
                .andExpect(jsonPath("$.result.structuredContent.total").value(2))
                .andExpect(jsonPath("$.result.structuredContent.items[0].lakeName").value("Red River US"));
    }

    @Test
    void regulationsAndTheSpeciesToolTakeCaOrUs() throws Exception {
        when(regulationRepository.region("US", "MN"))
                .thenReturn(objectMapper.readTree("{\"country\":\"US\",\"state\":\"MN\",\"regulations\":[]}"));
        when(fishRepository.waterBodies(anyString(), any(), any(), any(), anyInt(), anyInt()))
                .thenReturn(objectMapper.readTree("{\"total\":0,\"limit\":20,\"items\":[]}"));

        callAs("user", "get_region_regulations", "{\"country\":\"us\",\"state\":\"mn\"}")
                .andExpect(jsonPath("$.result.isError").value(false))
                .andExpect(jsonPath("$.result.structuredContent.state").value("MN"));
        callAs("admin", "find_water_bodies_by_fish", "{\"fishId\":\"" + WALLEYE + "\",\"country\":\"us\"}")
                .andExpect(jsonPath("$.result.isError").value(false));
        verify(fishRepository).waterBodies(WALLEYE.toLowerCase(), "US", null, null, 0, 20);

        callAs("user", "get_region_regulations", "{\"country\":\"MX\"}")
                .andExpect(jsonPath("$.result.isError").value(true))
                .andExpect(jsonPath("$.result.content[0].text", containsString("CA or US")));
        callAs("user", "get_region_regulations", "{\"state\":\"ON\"}")
                .andExpect(jsonPath("$.result.isError").value(true));
        verify(regulationRepository, org.mockito.Mockito.times(1)).region(anyString(), any());
    }

    @Test
    void searchFishTrimsTheTerm() throws Exception {
        when(fishRepository.search("walleye")).thenReturn(new FishController.FishSearchPage(
                List.of(new FishController.FishSearchItem(GUID, "Walleye", "Sander vitreus", 0)), 1, "walleye"));

        call("search_fish", "{\"query\":\"  walleye \"}")
                .andExpect(jsonPath("$.result.structuredContent.items[0].latin").value("Sander vitreus"));
    }

    // ---- 1.27.0: get_fish ----------------------------------------------------------------------

    @Test
    void getFishReturnsTheSpeciesDocumentForANormalizedId() throws Exception {
        when(fishRepository.info(WALLEYE.toLowerCase())).thenReturn(objectMapper.readTree(
                "{\"fishId\":\"" + WALLEYE + "\",\"name\":\"Walleye\",\"moonSensitive\":true,"
                        + "\"zoology\":{\"maxLengthCm\":104.00},\"codes\":[{\"country\":\"CA\",\"state\":\"ON\",\"code\":\"334\"}]}"));

        call("get_fish", "{\"fishId\":\"{" + WALLEYE + "}\"}")
                .andExpect(jsonPath("$.result.isError").value(false))
                .andExpect(jsonPath("$.result.structuredContent.name").value("Walleye"))
                .andExpect(jsonPath("$.result.structuredContent.zoology.maxLengthCm").value(104.0))
                .andExpect(jsonPath("$.result.structuredContent.codes[0].code").value("334"));
    }

    @Test
    void getFishStripsAnyPictureTheDocumentCarries() throws Exception {
        when(fishRepository.info(WALLEYE.toLowerCase())).thenReturn(objectMapper.readTree(
                "{\"name\":\"Walleye\",\"img\":\"iVBORw0KGgo=\",\"image\":\"iVBORw0KGgo=\",\"zoology\":{\"photo\":\"x\",\"shape\":\"Elongate\"}}"));

        call("get_fish", "{\"fishId\":\"" + WALLEYE + "\"}")
                .andExpect(jsonPath("$.result.structuredContent.img").doesNotExist())
                .andExpect(jsonPath("$.result.structuredContent.image").doesNotExist())
                .andExpect(jsonPath("$.result.structuredContent.zoology.photo").doesNotExist())
                .andExpect(jsonPath("$.result.structuredContent.zoology.shape").value("Elongate"))
                .andExpect(jsonPath("$.result.content[0].text", not(containsString("iVBOR"))));
    }

    @Test
    void getFishForAnUnknownSpeciesIsAToolErrorNamingIt() throws Exception {
        when(fishRepository.info(anyString())).thenReturn(null);

        call("get_fish", "{\"fishId\":\"" + WALLEYE + "\"}")
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.result.isError").value(true))
                .andExpect(jsonPath("$.result.content[0].text", containsString(WALLEYE.toLowerCase())));
    }

    @Test
    void getFishRejectsAMissingOrMalformedIdBeforeAnyQuery() throws Exception {
        call("get_fish", "{}")
                .andExpect(jsonPath("$.result.isError").value(true))
                .andExpect(jsonPath("$.result.content[0].text", containsString("search_fish")));
        call("get_fish", "{\"fishId\":\"walleye\"}")
                .andExpect(jsonPath("$.result.isError").value(true));
        call("get_fish", "{\"fishId\":42}")
                .andExpect(jsonPath("$.result.isError").value(true));
        verify(fishRepository, never()).info(any());
    }

    @Test
    void aDatabaseFailureIsATemporaryToolErrorNotA500() throws Exception {
        when(riverRepository.description(GUID)).thenThrow(new RuntimeException("SQL river-description query failed"));

        call("get_water_body", "{\"guid\":\"" + GUID + "\"}")
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.result.isError").value(true))
                .andExpect(jsonPath("$.result.content[0].text", containsString("temporarily unavailable")))
                .andExpect(jsonPath("$.result.content[0].text", not(containsString("SQL"))));
    }

    // ---- catch-log writes (1.29.0) --------------------------------------------------------------

    /** One of the two admin accounts in application.yml docapi.mcp.write-users. */
    private static final String AUTHOR = "bb30165a-fd1a-4b54-b921-9334242c9bf6";
    /** An admin-role account that is not one of them. */
    private static final String OTHER_ADMIN = "0190bbbb-0000-7000-8000-000000000009";
    private static final String MEMO = "0190cccc-0000-7000-8000-000000000002";

    /** As cproxy 0.27.0 sends a self-service admin key: role and owning account. */
    private ResultActions write(String user, String tool, String arguments) throws Exception {
        var request = post("/api/v1/mcp")
                .contentType(MediaType.APPLICATION_JSON)
                .header("X-Fish-Role", "admin")
                .content("{\"jsonrpc\":\"2.0\",\"id\":9,\"method\":\"tools/call\",\"params\":{\"name\":\"" + tool
                        + "\",\"arguments\":" + arguments + "}}");
        if (user != null) request = request.header("X-Fish-User", user);
        return mockMvc.perform(request);
    }

    private ObjectNode storedLog() {
        ObjectNode stored = objectMapper.createObjectNode();
        stored.put("catchLogId", MEMO);
        stored.put("imageCount", 0);
        return stored;
    }

    @Test
    void addCatchLogStoresOnlyTheGivenFieldsUnderTheKeysAccount() throws Exception {
        when(catchLogRepository.add(any())).thenReturn(storedLog());
        when(catchLogRepository.stationWeather(any(), any())).thenReturn(CatchLog.Weather.NONE);

        write(AUTHOR.toUpperCase(), "add_catch_log", "{\"lakeId\":\"" + GUID.toUpperCase() + "\","
                + "\"species\":\"largemouth bass\",\"angler\":\"Jane Doe\",\"weight\":15.9,\"weightUnit\":\"LB\",\"catchDate\":\"2026-05-03\","
                + "\"method\":\"from the bank\",\"notes\":\"Age: 15\"}")
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.result.isError").value(false))
                .andExpect(jsonPath("$.result.structuredContent.catchLogId").value(MEMO))
                .andExpect(jsonPath("$.result.structuredContent.imageCount").value(0));

        ArgumentCaptor<CatchLog> saved = ArgumentCaptor.forClass(CatchLog.class);
        verify(catchLogRepository).add(saved.capture());
        CatchLog log = saved.getValue();
        org.junit.jupiter.api.Assertions.assertEquals(GUID, log.lakeId());
        org.junit.jupiter.api.Assertions.assertEquals(AUTHOR, log.userId());
        org.junit.jupiter.api.Assertions.assertEquals("lb", log.weightUnit());
        org.junit.jupiter.api.Assertions.assertEquals("Jane Doe", log.angler());
        org.junit.jupiter.api.Assertions.assertEquals(java.time.LocalDateTime.of(2026, 5, 3, 0, 0), log.catchDate());
        // Not stated = NULL, never a default.
        org.junit.jupiter.api.Assertions.assertNull(log.released());
        org.junit.jupiter.api.Assertions.assertNull(log.length());
        org.junit.jupiter.api.Assertions.assertNull(log.lengthUnit());
        org.junit.jupiter.api.Assertions.assertNull(log.lure());
        org.junit.jupiter.api.Assertions.assertNull(log.fishId());
        org.junit.jupiter.api.Assertions.assertFalse(log.isPrivate());
        org.junit.jupiter.api.Assertions.assertEquals('7', log.id().charAt(14));   // a version-7 id
    }

    @Test
    void theWritesAreHiddenFromNonAdminsAndNeedTheKeysAccount() throws Exception {
        callAs("user", "add_catch_log", "{\"lakeId\":\"" + GUID + "\"}")
                .andExpect(jsonPath("$.error.code").value(McpController.INVALID_PARAMS));
        // An operator key (no X-Fish-User), another admin account and a malformed id do not even see them.
        for (String user : new String[] {null, OTHER_ADMIN, "not-a-guid"}) {
            write(user, "add_catch_log", "{\"lakeId\":\"" + GUID + "\"}")
                    .andExpect(jsonPath("$.error.code").value(McpController.INVALID_PARAMS));
        }
        rpc("{\"jsonrpc\":\"2.0\",\"id\":2,\"method\":\"tools/list\"}")
                .andExpect(jsonPath("$.result.tools", hasSize(11)));
        // The list is the portal's two admins, whatever role cproxy reports for them.
        callAs("user", "add_catch_log", "{}").andExpect(jsonPath("$.error.code").value(McpController.INVALID_PARAMS));
        mockMvc.perform(post("/api/v1/mcp").contentType(MediaType.APPLICATION_JSON)
                        .header("X-Fish-Role", "user").header("X-Fish-User", AUTHOR)
                        .content("{\"jsonrpc\":\"2.0\",\"id\":2,\"method\":\"tools/list\"}"))
                .andExpect(jsonPath("$.result.tools", hasSize(10)))
                .andExpect(jsonPath("$.result.tools[?(@.name == 'add_catch_log')]", hasSize(1)))
                .andExpect(jsonPath("$.result.tools[?(@.name == 'get_fish')]", hasSize(0)));
        verifyNoInteractions(catchLogRepository, photoFetcher);
    }

    @Test
    void addCatchLogRefusesBadArgumentsBeforeAnyWrite() throws Exception {
        String lake = "\"lakeId\":\"" + GUID + "\"";
        for (String args : new String[] {
                "{}",
                "{\"lakeId\":\"Lake Erie\"}",
                "{" + lake + ",\"weight\":12}",                                  // weight without unit
                "{" + lake + ",\"weightUnit\":\"lb\"}",                          // unit without weight
                "{" + lake + ",\"weight\":12,\"weightUnit\":\"stone\"}",
                "{" + lake + ",\"length\":-3,\"lengthUnit\":\"in\"}",
                "{" + lake + ",\"weight\":\"12 lb\",\"weightUnit\":\"lb\"}",
                "{" + lake + ",\"catchDate\":\"May 3\"}",
                "{" + lake + ",\"catchDate\":\"2999-01-01\"}",
                "{" + lake + ",\"released\":\"yes\"}",
                "{" + lake + ",\"lat\":45.1}",
                "{" + lake + ",\"weather\":\"" + "x".repeat(65) + "\"}"}) {
            write(AUTHOR, "add_catch_log", args).andExpect(jsonPath("$.result.isError").value(true));
        }
        verify(catchLogRepository, never()).add(any());
    }

    @Test
    void addCatchLogChecksTheSpeciesAndTheWaterBody() throws Exception {
        String walleye = "0b1e7f00-0000-4000-8000-0000000000aa";
        when(catchLogRepository.fishExists(walleye)).thenReturn(false);
        write(AUTHOR, "add_catch_log", "{\"lakeId\":\"" + GUID + "\",\"fishId\":\"" + walleye + "\"}")
                .andExpect(jsonPath("$.result.isError").value(true))
                .andExpect(jsonPath("$.result.content[0].text", containsString("search_fish")));
        verify(catchLogRepository, never()).add(any());

        when(catchLogRepository.add(any())).thenReturn(null);   // no such water body
        write(AUTHOR, "add_catch_log", "{\"lakeId\":\"" + GUID + "\"}")
                .andExpect(jsonPath("$.result.isError").value(true))
                .andExpect(jsonPath("$.result.content[0].text", containsString(GUID)));
    }

    @Test
    void addCatchLogPhotoDownloadsTheJpegAndStoresItWithTheCredit() throws Exception {
        byte[] jpeg = {(byte) 0xff, (byte) 0xd8, (byte) 0xff, 0x01};
        when(catchLogRepository.photoCount(MEMO)).thenReturn(1);
        when(photoFetcher.fetch("https://8.8.8.8/bass.jpg")).thenReturn(jpeg);
        ObjectNode stored = storedLog();
        stored.put("imageCount", 2);
        when(catchLogRepository.addPhoto(eq(MEMO), eq(AUTHOR), eq(jpeg), eq(1), eq("Teen with the bass"), eq("Wired2Fish")))
                .thenReturn(stored);

        write(AUTHOR, "add_catch_log_photo", "{\"catchLogId\":\"" + MEMO + "\",\"imageUrl\":\"https://8.8.8.8/bass.jpg\","
                + "\"credit\":\"Wired2Fish\",\"caption\":\"Teen with the bass\"}")
                .andExpect(jsonPath("$.result.isError").value(false))
                .andExpect(jsonPath("$.result.structuredContent.imageCount").value(2));
    }

    @Test
    void addCatchLogPhotoRefusesAMissingCreditAFullLogAndAPrivateUrl() throws Exception {
        write(AUTHOR, "add_catch_log_photo", "{\"catchLogId\":\"" + MEMO + "\",\"imageUrl\":\"https://8.8.8.8/a.jpg\"}")
                .andExpect(jsonPath("$.result.isError").value(true))
                .andExpect(jsonPath("$.result.content[0].text", containsString("credit")));
        write(AUTHOR, "add_catch_log_photo", "{\"catchLogId\":\"" + MEMO + "\",\"imageUrl\":\"http://example.com/a.jpg\",\"credit\":\"X\"}")
                .andExpect(jsonPath("$.result.isError").value(true))
                .andExpect(jsonPath("$.result.content[0].text", containsString("https")));
        write(AUTHOR, "add_catch_log_photo", "{\"catchLogId\":\"" + MEMO + "\",\"imageUrl\":\"https://127.0.0.1/a.jpg\",\"credit\":\"X\"}")
                .andExpect(jsonPath("$.result.isError").value(true))
                .andExpect(jsonPath("$.result.content[0].text", containsString("public")));
        verifyNoInteractions(catchLogRepository);

        when(catchLogRepository.photoCount(MEMO)).thenReturn(3);
        write(AUTHOR, "add_catch_log_photo", "{\"catchLogId\":\"" + MEMO + "\",\"imageUrl\":\"https://8.8.8.8/a.jpg\",\"credit\":\"X\"}")
                .andExpect(jsonPath("$.result.isError").value(true))
                .andExpect(jsonPath("$.result.content[0].text", containsString("3 photos")));
        when(catchLogRepository.photoCount(MEMO)).thenReturn(-1);
        write(AUTHOR, "add_catch_log_photo", "{\"catchLogId\":\"" + MEMO + "\",\"imageUrl\":\"https://8.8.8.8/a.jpg\",\"credit\":\"X\"}")
                .andExpect(jsonPath("$.result.isError").value(true))
                .andExpect(jsonPath("$.result.content[0].text", containsString("No catch log")));
        verifyNoInteractions(photoFetcher);
        verify(catchLogRepository, never()).addPhoto(any(), any(), any(), anyInt(), any(), any());
    }

    @Test
    void aFailedDownloadIsAToolErrorTheModelCanRead() throws Exception {
        when(catchLogRepository.photoCount(MEMO)).thenReturn(0);
        when(photoFetcher.fetch(anyString())).thenThrow(new InvalidDocumentException("The image is not a JPEG"));
        write(AUTHOR, "add_catch_log_photo", "{\"catchLogId\":\"" + MEMO + "\",\"imageUrl\":\"https://8.8.8.8/a.webp\",\"credit\":\"X\"}")
                .andExpect(jsonPath("$.result.isError").value(true))
                .andExpect(jsonPath("$.result.content[0].text", containsString("not a JPEG")));
        verify(catchLogRepository, never()).addPhoto(any(), any(), any(), anyInt(), any(), any());
    }

    // ---- weather and corrections (1.30.0) -------------------------------------------------------

    private static final CatchLog.Weather STATION = new CatchLog.Weather(21.0, 1012.0, "Rain", "10d", 17.5);

    @Test
    void addCatchLogFillsOnlyTheOmittedWeatherFromTheStationAndSaysSo() throws Exception {
        when(catchLogRepository.add(any())).thenReturn(storedLog());
        when(catchLogRepository.stationWeather(GUID, java.time.LocalDate.of(2026, 10, 3))).thenReturn(STATION);

        write(AUTHOR, "add_catch_log", "{\"lakeId\":\"" + GUID + "\",\"catchDate\":\"2026-10-03T10:00\","
                + "\"airTemp\":14,\"weather\":\"clear\"}")
                .andExpect(jsonPath("$.result.isError").value(false))
                .andExpect(jsonPath("$.result.structuredContent.stationWeather", hasSize(2)))
                .andExpect(jsonPath("$.result.structuredContent.stationWeather[0]").value("waterTemp"))
                .andExpect(jsonPath("$.result.structuredContent.stationWeather[1]").value("pressure"));

        ArgumentCaptor<CatchLog> saved = ArgumentCaptor.forClass(CatchLog.class);
        verify(catchLogRepository).add(saved.capture());
        CatchLog.Weather w = saved.getValue().weather();
        org.junit.jupiter.api.Assertions.assertEquals(14.0, w.temp());       // given wins
        org.junit.jupiter.api.Assertions.assertEquals("clear", w.text());
        org.junit.jupiter.api.Assertions.assertEquals("01d", w.icon());      // a portal condition gets its icon
        org.junit.jupiter.api.Assertions.assertEquals(17.5, w.water());      // omitted: from the station
        org.junit.jupiter.api.Assertions.assertEquals(1012.0, w.pressure());
    }

    @Test
    void addCatchLogTakesNoStationWeatherWhenToldNotToOrWithoutADate() throws Exception {
        when(catchLogRepository.add(any())).thenReturn(storedLog());
        write(AUTHOR, "add_catch_log", "{\"lakeId\":\"" + GUID + "\",\"catchDate\":\"2026-10-03\","
                + "\"stationWeather\":false,\"weather\":\"Windy, 12 C\"}")
                .andExpect(jsonPath("$.result.structuredContent.stationWeather", hasSize(0)));
        write(AUTHOR, "add_catch_log", "{\"lakeId\":\"" + GUID + "\"}")
                .andExpect(jsonPath("$.result.isError").value(false));
        verify(catchLogRepository, never()).stationWeather(any(), any());

        ArgumentCaptor<CatchLog> saved = ArgumentCaptor.forClass(CatchLog.class);
        verify(catchLogRepository, org.mockito.Mockito.times(2)).add(saved.capture());
        org.junit.jupiter.api.Assertions.assertEquals("Windy, 12 C", saved.getAllValues().get(0).weather().text());
        org.junit.jupiter.api.Assertions.assertNull(saved.getAllValues().get(0).weather().icon());
        org.junit.jupiter.api.Assertions.assertTrue(saved.getAllValues().get(1).weather().isEmpty());
    }

    private static CatchLog stored(String author) {
        return new CatchLog(MEMO, GUID, author, null, "largemouth bass", "Luke Mulholland", "8 lb 10 oz bass",
                "Age: 14", null, null, "From the bank", null, "Trick Shad", java.time.LocalDateTime.of(2026, 10, 3, 0, 0),
                8.625, "lb", 23.5, "in", false, false, CatchLog.Weather.NONE);
    }

    @Test
    void updateCatchLogChangesOnlyTheGivenFieldsAndNullClears() throws Exception {
        when(catchLogRepository.find(MEMO)).thenReturn(stored(AUTHOR.toUpperCase()));
        when(catchLogRepository.add(any())).thenReturn(storedLog());

        write(AUTHOR, "update_catch_log", "{\"catchLogId\":\"" + MEMO + "\",\"airTemp\":14,"
                + "\"weather\":\"Clear\",\"lure\":null}")
                .andExpect(jsonPath("$.result.isError").value(false))
                .andExpect(jsonPath("$.result.structuredContent.catchLogId").value(MEMO));

        ArgumentCaptor<CatchLog> saved = ArgumentCaptor.forClass(CatchLog.class);
        verify(catchLogRepository).add(saved.capture());
        CatchLog log = saved.getValue();
        org.junit.jupiter.api.Assertions.assertEquals(MEMO, log.id());        // same log: an update
        org.junit.jupiter.api.Assertions.assertEquals(14.0, log.weather().temp());
        org.junit.jupiter.api.Assertions.assertEquals("01d", log.weather().icon());
        org.junit.jupiter.api.Assertions.assertNull(log.lure());
        org.junit.jupiter.api.Assertions.assertEquals(8.625, log.weight());
        org.junit.jupiter.api.Assertions.assertEquals("Luke Mulholland", log.angler());
        org.junit.jupiter.api.Assertions.assertEquals(Boolean.FALSE, log.released());
        verify(catchLogRepository, never()).stationWeather(any(), any());
        verify(catchLogRepository, never()).fishExists(any());
    }

    @Test
    void updateCatchLogRefusesAnotherAuthorsLogAMissingLogAndAnOrphanedUnit() throws Exception {
        when(catchLogRepository.find(MEMO)).thenReturn(stored(OTHER_ADMIN));
        write(AUTHOR, "update_catch_log", "{\"catchLogId\":\"" + MEMO + "\",\"airTemp\":14}")
                .andExpect(jsonPath("$.result.isError").value(true))
                .andExpect(jsonPath("$.result.content[0].text", containsString("not added by this key")));

        when(catchLogRepository.find(MEMO)).thenReturn(stored(AUTHOR));
        write(AUTHOR, "update_catch_log", "{\"catchLogId\":\"" + MEMO + "\",\"weight\":null}")
                .andExpect(jsonPath("$.result.isError").value(true))
                .andExpect(jsonPath("$.result.content[0].text", containsString("weightUnit given without weight")));

        when(catchLogRepository.find(MEMO)).thenReturn(null);
        write(AUTHOR, "update_catch_log", "{\"catchLogId\":\"" + MEMO + "\",\"airTemp\":14}")
                .andExpect(jsonPath("$.result.content[0].text", containsString("No catch log")));
        verify(catchLogRepository, never()).add(any());
    }
}
