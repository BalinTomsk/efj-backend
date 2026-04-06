package com.fishfind.water.service;

import com.fishfind.water.repo.WaterDataRepository;
import org.junit.jupiter.api.Test;
import org.mockito.InOrder;

import static org.mockito.Mockito.inOrder;
import static org.mockito.Mockito.mock;

class StationPostProcessingServiceTest {

    private final WaterDataRepository waterDataRepository = mock(WaterDataRepository.class);
    private final StationPostProcessingService service = new StationPostProcessingService(waterDataRepository);

    @Test
    void runAfterStationProcessingExecutesProceduresInOrder() {
        service.runAfterStationProcessing();

        InOrder inOrder = inOrder(waterDataRepository);
        inOrder.verify(waterDataRepository).cleanWeatherWaterData();
        inOrder.verify(waterDataRepository).pushSpeciesFromLakeToStation();
    }
}
