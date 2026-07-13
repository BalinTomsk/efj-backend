package com.fishfind.weather.service;

import java.time.format.DateTimeFormatter;
import java.util.List;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.mail.MailException;
import org.springframework.mail.SimpleMailMessage;
import org.springframework.mail.javamail.JavaMailSender;
import org.springframework.scheduling.annotation.Scheduled;
import org.springframework.stereotype.Service;

/**
 * Emails a weekly digest of the daily "cycle completed" summaries recorded by
 * {@link CycleReportRecorder}, plus any crash/unclean-restart incidents recorded by
 * {@link ServiceLifecycleTracker}. Fires on {@code weather.report.cron} (default: every
 * Friday at 08:00 server-local time). A missing recipient skips the send; so does having
 * nothing to report (no cycles AND no incidents) — but incidents alone are enough to send,
 * since a crash-loop that never completes a cycle must not go unreported. A mail-send
 * failure is logged, not propagated.
 */
@Service
public class WeeklyReportMailService {
    private static final Logger log = LoggerFactory.getLogger(WeeklyReportMailService.class);
    private static final DateTimeFormatter DATE_FORMAT = DateTimeFormatter.ISO_LOCAL_DATE;
    private static final DateTimeFormatter TIMESTAMP_FORMAT = DateTimeFormatter.ofPattern("yyyy-MM-dd HH:mm:ss");

    private final JavaMailSender mailSender;
    private final CycleReportRecorder recorder;
    private final ServiceLifecycleTracker lifecycleTracker;

    @Value("${weather.report.to:}")
    private String to;

    @Value("${weather.report.from:}")
    private String from;

    @Value("${spring.mail.username:}")
    private String smtpUsername;

    public WeeklyReportMailService(JavaMailSender mailSender, CycleReportRecorder recorder,
                                    ServiceLifecycleTracker lifecycleTracker) {
        this.mailSender = mailSender;
        this.recorder = recorder;
        this.lifecycleTracker = lifecycleTracker;
    }

    @Scheduled(cron = "${weather.report.cron:0 0 8 * * FRI}")
    public void sendWeeklyReport() {
        if (to == null || to.isBlank()) {
            log.info("weather.report.to not configured; skipping weekly report email.");
            return;
        }

        List<CycleReportEntry> entries = recorder.recentEntries();
        List<IncidentEntry> incidents = lifecycleTracker.recentIncidents();
        if (entries.isEmpty() && incidents.isEmpty()) {
            log.info("No cycle data or incidents recorded since last report; skipping weekly report email.");
            return;
        }

        SimpleMailMessage message = new SimpleMailMessage();
        message.setTo(to);
        String effectiveFrom = (from != null && !from.isBlank()) ? from : smtpUsername;
        if (effectiveFrom != null && !effectiveFrom.isBlank()) {
            message.setFrom(effectiveFrom);
        }
        message.setSubject("Weather Service Weekly Report");
        message.setText(buildReportBody(entries, incidents));

        try {
            mailSender.send(message);
            log.info("Weekly report email sent. to={} days={} incidents={}", to, entries.size(), incidents.size());
        } catch (MailException ex) {
            log.error("Failed to send weekly report email. to={}", to, ex);
        }
    }

    static String buildReportBody(List<CycleReportEntry> entries, List<IncidentEntry> incidents) {
        StringBuilder body = new StringBuilder("Weather service - cycle summary for the past ")
                .append(entries.size())
                .append(entries.size() == 1 ? " day" : " days")
                .append(":\n\n");

        for (CycleReportEntry entry : entries) {
            body.append(entry.date().format(DATE_FORMAT)).append(": ")
                    .append("processed=").append(entry.successfulStations())
                    .append(" failed=").append(entry.failedStations())
                    .append(" lastProcessedStation=").append(displayStation(entry.lastProcessedStation()))
                    .append(" lastFailedStation=").append(displayStation(entry.lastFailedStation()))
                    .append('\n');
        }

        body.append("\nService reliability this week: ");
        if (incidents.isEmpty()) {
            body.append("no crashes or unexpected restarts detected.\n");
        } else {
            body.append(incidents.size())
                    .append(incidents.size() == 1 ? " crash detected\n" : " crashes detected\n");
            for (IncidentEntry incident : incidents) {
                body.append(incident.detectedAt().format(TIMESTAMP_FORMAT)).append(": down from ")
                        .append(incident.downtimeStart().format(TIMESTAMP_FORMAT)).append(" to ")
                        .append(incident.downtimeEnd().format(TIMESTAMP_FORMAT)).append(" - ")
                        .append(incident.description())
                        .append('\n');
            }
        }

        return body.toString();
    }

    private static String displayStation(String station) {
        return station == null || station.isBlank() ? "<none>" : station;
    }
}
