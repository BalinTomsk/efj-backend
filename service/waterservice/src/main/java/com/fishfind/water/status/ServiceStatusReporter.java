package com.fishfind.water.status;

import com.fasterxml.jackson.databind.ObjectMapper;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.boot.ApplicationArguments;
import org.springframework.boot.info.BuildProperties;
import org.springframework.context.SmartLifecycle;
import org.springframework.lang.Nullable;
import org.springframework.stereotype.Component;

import java.lang.management.ManagementFactory;
import java.net.InetAddress;
import java.net.URI;
import java.net.http.HttpClient;
import java.net.http.HttpRequest;
import java.net.http.HttpResponse;
import java.nio.charset.StandardCharsets;
import java.time.Duration;
import java.time.Instant;
import java.util.Base64;
import java.util.LinkedHashMap;
import java.util.Locale;
import java.util.Map;
import java.util.concurrent.Executors;
import java.util.concurrent.ScheduledExecutorService;
import java.util.concurrent.TimeUnit;

/**
 * Publishes this worker's status to {@code fishfind.servicestatus.events} through the RabbitMQ management HTTP API
 * (the platform's usual transport): {@code start} once, {@code heartbeat} every minute with the latest
 * {@link ServiceActivity}, {@code stop} on a clean shutdown. efcs-backend adminservice stores them in
 * dbo.ServiceStatus; the admin page shows it as dead once its heartbeats stop.
 *
 * <p>Runs only when {@code RABBITMQ_MANAGEMENT_URL}, {@code RABBITMQ_USERNAME} and {@code RABBITMQ_PASSWORD} are
 * all set (env or the dotenv file). {@code STATUS_MACHINE} names the host; inside Docker the host name is the
 * container id. Best-effort: a failed publish is logged once per outage and never retried in a loop.
 */
@Component
public class ServiceStatusReporter implements SmartLifecycle {

    public static final String MESSAGE_TYPE = "fishfind.service-status.v1";
    public static final String QUEUE = "fishfind.servicestatus.events";
    static final String SERVICE = "waterservice";

    private static final Logger log = LoggerFactory.getLogger(ServiceStatusReporter.class);
    private static final ObjectMapper JSON = new ObjectMapper();

    private final ServiceActivity activity;
    private final String version;
    private final String url;
    private final String authorization;
    private final String machine;
    private final long intervalSeconds;
    private final Instant processStart = Instant.ofEpochMilli(ManagementFactory.getRuntimeMXBean().getStartTime());
    private final HttpClient http = HttpClient.newBuilder().connectTimeout(Duration.ofSeconds(5)).build();

    private ScheduledExecutorService scheduler;
    private boolean console;
    private volatile boolean running;
    private volatile boolean warned;

    public ServiceStatusReporter(
            ServiceActivity activity,
            @Nullable BuildProperties buildProperties,
            @Value("${RABBITMQ_MANAGEMENT_URL:}") String url,
            @Value("${RABBITMQ_USERNAME:}") String username,
            @Value("${RABBITMQ_PASSWORD:}") String password,
            @Value("${STATUS_MACHINE:}") String machine,
            @Value("${STATUS_INTERVAL_SECONDS:60}") long intervalSeconds) {
        this.activity = activity;
        this.version = buildProperties == null ? "unknown" : buildProperties.getVersion();
        boolean configured = !url.isBlank() && !username.isBlank() && !password.isBlank();
        this.url = configured ? url.trim().replaceAll("/+$", "") + "/api/exchanges/%2F/amq.default/publish" : null;
        this.authorization = configured
                ? "Basic " + Base64.getEncoder().encodeToString(
                        (username.trim() + ":" + password.trim()).getBytes(StandardCharsets.UTF_8))
                : null;
        this.machine = (machine.isBlank() ? hostName() : machine.trim()).toLowerCase(Locale.ROOT);
        this.intervalSeconds = Math.max(10, intervalSeconds);
    }

    /** A {@code --console} one-shot run is not "the service": it must not show up as a restart on the page. */
    @Autowired(required = false)
    void setApplicationArguments(ApplicationArguments args) {
        this.console = args != null && args.containsOption("console");
    }

    public boolean enabled() {
        return url != null && !console;
    }

    @Override
    public void start() {
        running = true;
        if (!enabled()) {
            log.info("Service status reporting off ({}).", console ? "--console run" : "RABBITMQ_* not set");
            return;
        }
        log.info("Service status reporting on. queue={} machine={}", QUEUE, machine);
        scheduler = Executors.newSingleThreadScheduledExecutor(r -> {
            Thread t = new Thread(r, "service-status");
            t.setDaemon(true);
            return t;
        });
        scheduler.execute(() -> publish("start"));
        scheduler.scheduleWithFixedDelay(() -> publish("heartbeat"), intervalSeconds, intervalSeconds, TimeUnit.SECONDS);
    }

    @Override
    public void stop() {
        running = false;
        if (scheduler != null) {
            scheduler.shutdownNow();
            publish("stop");
        }
    }

    @Override
    public boolean isRunning() {
        return running;
    }

    /** Lowest phase stops last, so the stop goes out after the web server has drained. */
    @Override
    public int getPhase() {
        return Integer.MIN_VALUE + 1000;
    }

    String body(String event, Instant sent) {
        Map<String, Object> m = new LinkedHashMap<>();
        m.put("type", MESSAGE_TYPE);
        m.put("event", event);
        m.put("service", SERVICE);
        m.put("machine", machine);
        m.put("version", version);
        m.put("processStartUtc", processStart.toString());
        m.put("sentUtc", sent.toString());
        ServiceActivity.Last last = activity.last();
        m.put("lastActionUtc", last == null ? null : last.at().toString());
        m.put("lastAction", last == null ? null : last.action());
        return write(m);
    }

    private void publish(String event) {
        try {
            Map<String, Object> envelope = new LinkedHashMap<>();
            envelope.put("properties", Map.of("delivery_mode", 1, "content_type", "application/json"));
            envelope.put("routing_key", QUEUE);
            envelope.put("payload", body(event, Instant.now()));
            envelope.put("payload_encoding", "string");
            HttpRequest request = HttpRequest.newBuilder(URI.create(url))
                    .timeout(Duration.ofSeconds(5))
                    .header("Authorization", authorization)
                    .header("Content-Type", "application/json")
                    .POST(HttpRequest.BodyPublishers.ofString(write(envelope)))
                    .build();
            HttpResponse<Void> response = http.send(request, HttpResponse.BodyHandlers.discarding());
            if (response.statusCode() / 100 != 2) {
                throw new IllegalStateException("HTTP " + response.statusCode());
            }
            warned = false;
        } catch (InterruptedException e) {
            Thread.currentThread().interrupt();
        } catch (Exception e) {
            if (!warned) {
                log.warn("Service status not published. event={} queue={} error={}", event, QUEUE, e.toString());
                warned = true;
            }
        }
    }

    private static String write(Object value) {
        try {
            return JSON.writeValueAsString(value);
        } catch (Exception e) {
            throw new IllegalStateException(e);
        }
    }

    private static String hostName() {
        try {
            return InetAddress.getLocalHost().getHostName();
        } catch (Exception e) {
            return "unknown";
        }
    }
}
