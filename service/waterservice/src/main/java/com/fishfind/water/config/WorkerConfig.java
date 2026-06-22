package com.fishfind.water.config;

import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.scheduling.concurrent.ThreadPoolTaskExecutor;
import org.springframework.scheduling.concurrent.ThreadPoolTaskScheduler;

import java.util.concurrent.Executor;

/**
 * Spring-managed thread pools that drive station processing.
 *
 * <p>Both pools are Spring beans, so the container shuts them down gracefully on context close
 * (waiting for an in-flight cycle to finish) instead of relying on hand-managed {@code Thread}s.
 */
@Configuration
public class WorkerConfig {

    /**
     * Single-threaded scheduler that fires the hourly station cycle.
     *
     * <p>A pool size of one means a cycle that overruns its hour simply delays the next trigger rather
     * than running two cycles concurrently — removing the previous tight-loop/overlap hazard.
     *
     * @return the cycle scheduler
     */
    @Bean
    public ThreadPoolTaskScheduler cycleScheduler() {
        ThreadPoolTaskScheduler scheduler = new ThreadPoolTaskScheduler();
        scheduler.setPoolSize(1);
        scheduler.setThreadNamePrefix("water-cycle-");
        scheduler.setWaitForTasksToCompleteOnShutdown(true);
        scheduler.setAwaitTerminationSeconds(60);
        return scheduler;
    }

    /**
     * Executor used to run the CA and US station passes in parallel within a single cycle.
     *
     * @return the country-pass executor
     */
    @Bean
    public Executor countryPassExecutor() {
        ThreadPoolTaskExecutor executor = new ThreadPoolTaskExecutor();
        executor.setCorePoolSize(2);
        executor.setMaxPoolSize(2);
        executor.setThreadNamePrefix("water-pass-");
        executor.setWaitForTasksToCompleteOnShutdown(true);
        executor.setAwaitTerminationSeconds(60);
        return executor;
    }
}
