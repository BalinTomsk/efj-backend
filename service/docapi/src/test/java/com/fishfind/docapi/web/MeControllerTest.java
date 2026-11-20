package com.fishfind.docapi.web;

import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.autoconfigure.web.servlet.WebMvcTest;
import org.springframework.test.web.servlet.MockMvc;

import static org.assertj.core.api.Assertions.assertThat;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.header;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

@WebMvcTest(MeController.class)
class MeControllerTest {

    private static final String ME = "0190aaaa-0000-7000-8000-000000000001";

    @Autowired
    private MockMvc mockMvc;

    @Test
    void aSignedInCallerGetsRoleIdAndTheDecodedMask() throws Exception {
        mockMvc.perform(get("/api/v1/me").header("X-Fish-Role", "user").header("X-Fish-User", ME)
                        .header("X-Fish-User-Type", "6"))
                .andExpect(status().isOk())
                .andExpect(header().string("Cache-Control", "no-store"))
                .andExpect(jsonPath("$.data.role").value("user"))
                .andExpect(jsonPath("$.data.userId").value(ME))
                .andExpect(jsonPath("$.data.userType").value(6))
                .andExpect(jsonPath("$.data.userTypes[0]").value("paid"))
                .andExpect(jsonPath("$.data.userTypes[1]").value("scientist"))
                .andExpect(jsonPath("$.data.userTypes.length()").value(2));
    }

    @Test
    void anAdminMaskListsAdminFirst() throws Exception {
        mockMvc.perform(get("/api/v1/me").header("X-Fish-Role", "admin").header("X-Fish-User", ME)
                        .header("X-Fish-User-Type", "47"))
                .andExpect(jsonPath("$.data.role").value("admin"))
                .andExpect(jsonPath("$.data.userTypes[0]").value("admin"))
                .andExpect(jsonPath("$.data.userTypes.length()").value(5));
    }

    @Test
    void aGuestHasNoAccountAndNoTypeEvenIfOneIsSent() throws Exception {
        mockMvc.perform(get("/api/v1/me").header("X-Fish-User-Type", "47"))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.data.role").value("guest"))
                .andExpect(jsonPath("$.data.userId").doesNotExist())
                .andExpect(jsonPath("$.data.userType").doesNotExist())
                .andExpect(jsonPath("$.data.userTypes").isEmpty());
    }

    @Test
    void anUnreadableMaskIsNull() throws Exception {
        for (String bad : new String[] {"editor", "0", "64", "-1", " "}) {
            mockMvc.perform(get("/api/v1/me").header("X-Fish-Role", "user").header("X-Fish-User", ME)
                            .header("X-Fish-User-Type", bad))
                    .andExpect(jsonPath("$.data.userType").doesNotExist())
                    .andExpect(jsonPath("$.data.userTypes").isEmpty());
        }
    }

    @Test
    void theBitsMatchTheDatabase() {
        int sum = 0;
        for (UserType type : UserType.values()) {
            assertThat(Integer.bitCount(type.bit())).isEqualTo(1);
            sum += type.bit();
        }
        assertThat(sum).isEqualTo(UserType.KNOWN);
        assertThat(UserType.codes(12)).containsExactly("scientist", "editor");
        assertThat(UserType.codes(16)).containsExactly("ai_agent");
    }
}
