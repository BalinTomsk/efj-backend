package com.fishfind.weather.domain;

import static org.assertj.core.api.Assertions.assertThat;

import org.junit.jupiter.api.Test;

class StationRefTest {

    @Test
    void exposesAllComponents() {
        StationRef ref = new StationRef("MLI-1", 47.5, -122.3, "WA");

        assertThat(ref.mli()).isEqualTo("MLI-1");
        assertThat(ref.latitude()).isEqualTo(47.5);
        assertThat(ref.longitude()).isEqualTo(-122.3);
        assertThat(ref.state()).isEqualTo("WA");
    }

    @Test
    void valueEqualitySemantics() {
        StationRef a = new StationRef("MLI-1", 1.0, 2.0, "WA");
        StationRef b = new StationRef("MLI-1", 1.0, 2.0, "WA");

        assertThat(a).isEqualTo(b).hasSameHashCodeAs(b);
    }
}
