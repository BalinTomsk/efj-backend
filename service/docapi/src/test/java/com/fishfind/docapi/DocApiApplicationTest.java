package com.fishfind.docapi;

import org.junit.jupiter.api.Test;
import org.mockito.MockedStatic;
import org.springframework.boot.SpringApplication;

import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.mockStatic;
import static org.mockito.Mockito.times;

class DocApiApplicationTest {

    @Test
    void mainStartsSpringApplication() {
        try (MockedStatic<SpringApplication> springApplication = mockStatic(SpringApplication.class)) {
            springApplication.when(() -> SpringApplication.run(eq(DocApiApplication.class), eq(new String[]{})))
                    .thenReturn(mock(org.springframework.context.ConfigurableApplicationContext.class));

            DocApiApplication.main(new String[]{});

            springApplication.verify(
                    () -> SpringApplication.run(eq(DocApiApplication.class), eq(new String[]{})),
                    times(1)
            );
        }
    }
}
