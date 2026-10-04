package com.fishfind.docapi.web;

import com.fasterxml.jackson.databind.ObjectMapper;
import com.fishfind.docapi.repo.FishQueryRepository;
import com.fishfind.docapi.repo.RegulationQueryRepository;
import com.fishfind.docapi.repo.RiverQueryRepository;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.autoconfigure.web.servlet.WebMvcTest;
import org.springframework.boot.test.mock.mockito.MockBean;
import org.springframework.context.annotation.Import;
import org.springframework.http.MediaType;
import org.springframework.test.web.servlet.MockMvc;
import org.springframework.test.web.servlet.ResultActions;

import java.util.Collection;
import java.util.List;
import java.util.Locale;
import java.util.Set;
import java.util.stream.Collectors;

import static org.hamcrest.Matchers.containsString;
import static org.hamcrest.Matchers.hasSize;
import static org.hamcrest.Matchers.not;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.anyInt;
import static org.mockito.ArgumentMatchers.anyString;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.verifyNoInteractions;
import static org.mockito.Mockito.doReturn;
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

    /** Unless a test says otherwise every water body is Canadian, so the older tests keep their meaning. */
    @BeforeEach
    void everyWaterBodyIsCanadianByDefault() {
        when(riverRepository.canadianIds(any())).thenAnswer(inv -> ((Collection<String>) inv.getArgument(0))
                .stream().map(id -> id.toUpperCase(Locale.ROOT)).collect(Collectors.toSet()));
    }

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
    void toolsListPublishesEightReadOnlyTools() throws Exception {
        rpc("{\"jsonrpc\":\"2.0\",\"id\":2,\"method\":\"tools/list\"}")
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.result.tools", hasSize(8)))
                .andExpect(jsonPath("$.result.tools[0].name").value("search_water_bodies"))
                .andExpect(jsonPath("$.result.tools[0].inputSchema.type").value("object"))
                .andExpect(jsonPath("$.result.tools[?(@.annotations.readOnlyHint != true)]", hasSize(0)));
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
        when(riverRepository.search("Ottawa", null, "FEFUL", null, RiverController.SEARCH_MAX_LIMIT))
                .thenReturn(objectMapper.readTree("[{\"lakeId\":\"" + GUID + "\",\"lakeName\":\"Ottawa River\"}]"));

        call("search_water_bodies", "{\"name\":\" Ottawa \",\"cgndb\":\"feful\",\"limit\":500}")
                .andExpect(jsonPath("$.result.isError").value(false))
                .andExpect(jsonPath("$.result.structuredContent.total").value(1))
                .andExpect(jsonPath("$.result.structuredContent.limit").value(50))
                .andExpect(jsonPath("$.result.structuredContent.items[0].lakeName").value("Ottawa River"))
                .andExpect(jsonPath("$.result.content[0].type").value("text"))
                .andExpect(jsonPath("$.result.content[0].text", containsString("Ottawa River")));
    }

    @Test
    void searchWithNoCriterionIsAToolErrorAndNeverQueries() throws Exception {
        call("search_water_bodies", "{}")
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.result.isError").value(true))
                .andExpect(jsonPath("$.result.content[0].text", containsString("at least one")));
        verify(riverRepository, never()).search(any(), any(), any(), any(), anyInt());
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
        verify(fishRepository).waterBodies(WALLEYE.toLowerCase(), "CA", null, null, 100, 50);
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

    private static final Set<String> FISH_TOOLS = Set.of("get_water_body_fish", "search_fish", "find_water_bodies_by_fish");

    @Test
    void aGuestOrUserSeesFiveToolsAndNoFishTools() throws Exception {
        for (String role : new String[] {null, "guest", "user", "superuser"}) {
            rpcAs(role, "{\"jsonrpc\":\"2.0\",\"id\":2,\"method\":\"tools/list\"}")
                    .andExpect(jsonPath("$.result.tools", hasSize(5)))
                    .andExpect(jsonPath("$.result.tools[?(@.name == 'get_water_body_fish')]", hasSize(0)))
                    .andExpect(jsonPath("$.result.tools[?(@.name == 'search_fish')]", hasSize(0)))
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

    // ---- 1.21.0: Canadian water bodies only ----------------------------------------------------

    @Test
    void aNonCanadianWaterBodyIsAnsweredLikeAnUnknownOne() throws Exception {
        doReturn(Set.of()).when(riverRepository).canadianIds(any());

        for (String tool : List.of("get_water_body", "get_water_body_links", "get_water_body_regulations",
                "get_water_body_fish")) {
            callAs("admin", tool, "{\"guid\":\"" + GUID + "\"}")
                    .andExpect(jsonPath("$.result.isError").value(true))
                    .andExpect(jsonPath("$.result.content[0].text", containsString("Canadian")));
        }
        verify(riverRepository, never()).description(any());
        verify(riverRepository, never()).source(any());
        verify(riverRepository, never()).fish(any());
        verify(regulationRepository, never()).lakeRegulation(any());
    }

    @Test
    void searchKeepsOnlyCanadianMatchesAndThenAppliesTheLimit() throws Exception {
        String us = "11111111-1111-1111-1111-111111111111", on = "22222222-2222-2222-2222-222222222222",
               qc = "33333333-3333-3333-3333-333333333333";
        when(riverRepository.search("Red", null, null, null, RiverController.SEARCH_MAX_LIMIT))
                .thenReturn(objectMapper.readTree("[{\"lakeId\":\"" + us + "\",\"lakeName\":\"Red River US\"},"
                        + "{\"lakeId\":\"" + on + "\",\"lakeName\":\"Red River ON\"},"
                        + "{\"lakeId\":\"" + qc + "\",\"lakeName\":\"Red River QC\"}]"));
        doReturn(Set.of(on, qc)).when(riverRepository).canadianIds(any());

        callAs("user", "search_water_bodies", "{\"name\":\"Red\"}")
                .andExpect(jsonPath("$.result.structuredContent.total").value(2))
                .andExpect(jsonPath("$.result.structuredContent.items[0].lakeName").value("Red River ON"))
                .andExpect(jsonPath("$.result.content[0].text", not(containsString("Red River US"))));
        callAs("user", "search_water_bodies", "{\"name\":\"Red\",\"limit\":1}")
                .andExpect(jsonPath("$.result.structuredContent.items", hasSize(1)))
                .andExpect(jsonPath("$.result.structuredContent.items[0].lakeName").value("Red River ON"));
    }

    @Test
    void regulationsAndTheSpeciesToolAreCanadaOnly() throws Exception {
        callAs("user", "get_region_regulations", "{\"country\":\"US\",\"state\":\"MN\"}")
                .andExpect(jsonPath("$.result.isError").value(true))
                .andExpect(jsonPath("$.result.content[0].text", containsString("Canada")));
        callAs("admin", "find_water_bodies_by_fish", "{\"fishId\":\"" + WALLEYE + "\",\"country\":\"US\"}")
                .andExpect(jsonPath("$.result.isError").value(true));
        verify(regulationRepository, never()).region(anyString(), any());
        verify(fishRepository, never()).waterBodies(any(), any(), any(), any(), anyInt(), anyInt());
    }

    @Test
    void searchFishTrimsTheTerm() throws Exception {
        when(fishRepository.search("walleye")).thenReturn(new FishController.FishSearchPage(
                List.of(new FishController.FishSearchItem(GUID, "Walleye", "Sander vitreus", 0)), 1, "walleye"));

        call("search_fish", "{\"query\":\"  walleye \"}")
                .andExpect(jsonPath("$.result.structuredContent.items[0].latin").value("Sander vitreus"));
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
}
