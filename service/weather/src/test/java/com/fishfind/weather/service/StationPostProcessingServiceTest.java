package com.fishfind.weather.service;

import com.fishfind.weather.repo.WeatherDataRepository;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.InOrder;
import org.mockito.InjectMocks;
import org.mockito.Mock;
import org.mockito.Mockito;
import org.mockito.junit.jupiter.MockitoExtension;

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
}
