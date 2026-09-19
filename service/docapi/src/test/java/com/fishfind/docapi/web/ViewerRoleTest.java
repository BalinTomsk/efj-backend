package com.fishfind.docapi.web;

import org.junit.jupiter.api.Test;

import static org.assertj.core.api.Assertions.assertThat;

class ViewerRoleTest {

    @Test
    void namesTheThreeRolesCaseInsensitivelyAndTrimmed() {
        assertThat(ViewerRole.fromHeader("admin")).isEqualTo(ViewerRole.ADMIN);
        assertThat(ViewerRole.fromHeader("ADMIN")).isEqualTo(ViewerRole.ADMIN);
        assertThat(ViewerRole.fromHeader("  User ")).isEqualTo(ViewerRole.USER);
        assertThat(ViewerRole.fromHeader("guest")).isEqualTo(ViewerRole.GUEST);
    }

    @Test
    void everythingElseIsTheMostRestrictedRole() {
        assertThat(ViewerRole.fromHeader(null)).isEqualTo(ViewerRole.GUEST);
        assertThat(ViewerRole.fromHeader("")).isEqualTo(ViewerRole.GUEST);
        assertThat(ViewerRole.fromHeader("   ")).isEqualTo(ViewerRole.GUEST);
        assertThat(ViewerRole.fromHeader("root")).isEqualTo(ViewerRole.GUEST);
        assertThat(ViewerRole.fromHeader("admin,user")).isEqualTo(ViewerRole.GUEST);
    }

    @Test
    void theHeaderNameIsTheOneCproxyStamps() {
        assertThat(ViewerRole.HEADER).isEqualTo("X-Fish-Role");
    }
}
