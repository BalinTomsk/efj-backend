package com.fishfind.weather.service;

import com.fishfind.weather.repo.WeatherDataRepository;
import java.util.concurrent.CountDownLatch;
import java.util.concurrent.TimeUnit;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.InOrder;
import org.mockito.InjectMocks;
import org.mockito.Mock;
import org.mockito.Mockito;
import org.mockito.junit.jupiter.MockitoExtension;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.Mockito.times;

@ExtendWith(MockitoExtension.class)
class StationPostProcessingServiceTest {

    @Mock
    private WeatherDataRepository weatherDataRepository;

    @InjectMocks
    private StationPostProcessingService service;

    @Test
    void runsProceduresInLegacyOrder() {
        service.runAfterStationProcessing();

        InOrder inOrder = Mockito.inOrder(weatherDataRepository);
        inOrder.verify(weatherDataRepository).pushSpeciesFromLakeToStation();
        inOrder.verify(weatherDataRepository).totalUpdateProbability();
        inOrder.verify(weatherDataRepository).cleanOldWeatherData();
        inOrder.verifyNoMoreInteractions();
    }

    @Test
    void serializesConcurrentRuns() throws Exception {
        CountDownLatch firstRunEntered = new CountDownLatch(1);
        CountDownLatch releaseFirstRun = new CountDownLatch(1);
        Mockito.doAnswer(invocation -> {
            firstRunEntered.countDown();
            assertThat(releaseFirstRun.await(2, TimeUnit.SECONDS)).isTrue();
            return null;
        }).doNothing().when(weatherDataRepository).pushSpeciesFromLakeToStation();

        Thread first = new Thread(service::runAfterStationProcessing);
        Thread second = new Thread(service::runAfterStationProcessing);

        first.start();
        assertThat(firstRunEntered.await(2, TimeUnit.SECONDS)).isTrue();
        second.start();

        Thread.sleep(100);
        Mockito.verify(weatherDataRepository, times(1)).pushSpeciesFromLakeToStation();

        releaseFirstRun.countDown();
        first.join(2_000);
        second.join(2_000);

        assertThat(first.isAlive()).isFalse();
        assertThat(second.isAlive()).isFalse();
        Mockito.verify(weatherDataRepository, times(2)).pushSpeciesFromLakeToStation();
    }
}
