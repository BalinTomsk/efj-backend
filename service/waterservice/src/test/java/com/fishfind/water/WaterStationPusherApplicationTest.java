package com.fishfind.water;

import org.junit.jupiter.api.Test;
import org.mockito.MockedStatic;
import org.springframework.boot.SpringApplication;

import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.mockStatic;
import static org.mockito.Mockito.times;

class WaterStationPusherApplicationTest {

    @Test
    void mainStartsSpringApplication() {
        try (MockedStatic<SpringApplication> springApplication = mockStatic(SpringApplication.class)) {
            springApplication.when(() -> SpringApplication.run(eq(WaterStationPusherApplication.class), eq(new String[]{"--console"})))
                    .thenReturn(mock(org.springframework.context.ConfigurableApplicationContext.class));

            WaterStationPusherApplication.main(new String[]{"--console"});

            springApplication.verify(
                    () -> SpringApplication.run(eq(WaterStationPusherApplication.class), eq(new String[]{"--console"})),
                    times(1)
            );
        }
    }
}
