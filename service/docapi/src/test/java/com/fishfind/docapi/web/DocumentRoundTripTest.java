package com.fishfind.docapi.web;

import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.autoconfigure.web.servlet.AutoConfigureMockMvc;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.http.MediaType;
import org.springframework.test.web.servlet.MockMvc;
import org.springframework.test.web.servlet.MvcResult;

import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.put;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

/**
 * End-to-end proof that the service works with the default in-memory backing and <strong>no
 * database</strong>: POST a document, read it back by the assigned id, update it, and read the update.
 * Exercises the full stack (controller → service → in-memory store) for each of the four entities.
 */
@SpringBootTest
@AutoConfigureMockMvc
class DocumentRoundTripTest {

    @Autowired
    private MockMvc mockMvc;

    @Test
    void newsRoundTripAddGetUpdate() throws Exception {
        // Add
        MvcResult created = mockMvc.perform(post("/api/v1/news")
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("{\"title\":\"Spring opener\"}"))
                .andExpect(status().isCreated())
                .andExpect(jsonPath("$.data.id").exists())
                .andReturn();

        String id = com.jayway.jsonpath.JsonPath.read(created.getResponse().getContentAsString(), "$.data.id");

        // Get back the stored document
        mockMvc.perform(get("/api/v1/news/" + id))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.data.title").value("Spring opener"));

        // Update
        mockMvc.perform(put("/api/v1/news/" + id)
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("{\"title\":\"Edited\"}"))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.data.id").value(id));

        // Read the update
        mockMvc.perform(get("/api/v1/news/" + id))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.data.title").value("Edited"));
    }

    @Test
    void unknownIdReturns404() throws Exception {
        mockMvc.perform(get("/api/v1/fish/does-not-exist"))
                .andExpect(status().isNotFound())
                .andExpect(jsonPath("$.error.code").value("not_found"));
    }

    @Test
    void newsQueryEndpointsWorkWithNoDatabase() throws Exception {
        // The latest-news list and the home page both run with the default in-memory backing (no DB),
        // returning well-formed but empty payloads.
        mockMvc.perform(get("/api/v1/news/list"))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.data.items").isArray())
                .andExpect(jsonPath("$.data.total").value(0))
                .andExpect(jsonPath("$.data.limit").value(25));

        mockMvc.perform(get("/api/v1/news/default"))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.data.items").isArray())
                .andExpect(jsonPath("$.data.items").isEmpty());
    }

    @Test
    void allFourEntitiesAcceptDocuments() throws Exception {
        for (String entity : new String[]{"news", "waterbody", "fish", "station"}) {
            mockMvc.perform(post("/api/v1/" + entity)
                            .contentType(MediaType.APPLICATION_JSON)
                            .content("{\"name\":\"" + entity + "\"}"))
                    .andExpect(status().isCreated())
                    .andExpect(jsonPath("$.data.id").exists());
        }
    }
}
