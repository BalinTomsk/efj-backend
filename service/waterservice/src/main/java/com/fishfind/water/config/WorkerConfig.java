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
     * Scheduler that fires the CA and US station cycles, one cron task per country.
     *
     * <p>Two threads, one per country task, so a slow CA pass cannot hold back the US one. A cron task is
     * only rescheduled once its run has finished, so a cycle that overruns its hour delays that country's
     * next trigger instead of running two of its cycles concurrently.
     *
     * @return the cycle scheduler
     */
    @Bean
    public ThreadPoolTaskScheduler cycleScheduler() {
        ThreadPoolTaskScheduler scheduler = new ThreadPoolTaskScheduler();
        scheduler.setPoolSize(2);
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
