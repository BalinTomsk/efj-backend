package com.fishfind.docapi.web;

import com.fasterxml.jackson.databind.ObjectMapper;
import com.fishfind.docapi.repo.FishQueryRepository;
import com.fishfind.docapi.repo.RegulationQueryRepository;
import com.fishfind.docapi.repo.RiverQueryRepository;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.autoconfigure.web.servlet.WebMvcTest;
import org.springframework.boot.test.mock.mockito.MockBean;
import org.springframework.context.annotation.Import;
import org.springframework.http.MediaType;
import org.springframework.test.web.servlet.MockMvc;
import org.springframework.test.web.servlet.ResultActions;

import java.util.List;

import static org.hamcrest.Matchers.containsString;
import static org.hamcrest.Matchers.hasSize;
import static org.hamcrest.Matchers.not;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.anyInt;
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

    private ResultActions rpc(String body) throws Exception {
        return mockMvc.perform(post("/api/v1/mcp")
                .contentType(MediaType.APPLICATION_JSON)
                .accept(MediaType.APPLICATION_JSON, MediaType.TEXT_EVENT_STREAM)
                .content(body));
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
    void toolsListPublishesSevenReadOnlyTools() throws Exception {
        rpc("{\"jsonrpc\":\"2.0\",\"id\":2,\"method\":\"tools/list\"}")
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.result.tools", hasSize(7)))
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
        when(riverRepository.search("Ottawa", null, "FEFUL", null, 50))
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
