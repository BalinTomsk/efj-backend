package com.fishfind.weather.service;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.Mockito.doThrow;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.verifyNoInteractions;
import static org.mockito.Mockito.when;

import java.time.LocalDate;
import java.time.LocalDateTime;
import java.util.List;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.mockito.ArgumentCaptor;
import org.mockito.Mockito;
import org.springframework.mail.MailSendException;
import org.springframework.mail.SimpleMailMessage;
import org.springframework.mail.javamail.JavaMailSender;
import org.springframework.test.util.ReflectionTestUtils;

class WeeklyReportMailServiceTest {

    private JavaMailSender mailSender;
    private CycleReportRecorder recorder;
    private ServiceLifecycleTracker lifecycleTracker;
    private WeeklyReportMailService service;

    @BeforeEach
    void setUp() {
        mailSender = Mockito.mock(JavaMailSender.class);
        recorder = new CycleReportRecorder();
        lifecycleTracker = Mockito.mock(ServiceLifecycleTracker.class);
        when(lifecycleTracker.recentIncidents()).thenReturn(List.of());
        service = new WeeklyReportMailService(mailSender, recorder, lifecycleTracker);
        ReflectionTestUtils.setField(service, "to", "ops@example.com");
        ReflectionTestUtils.setField(service, "from", "weather@example.com");
        ReflectionTestUtils.setField(service, "smtpUsername", "");
    }

    @Test
    void skipsWhenRecipientNotConfigured() {
        ReflectionTestUtils.setField(service, "to", "");
        recorder.record(new CycleReportEntry(LocalDate.of(2026, 7, 10), 5, 1, "MLI-1", "MLI-2"));

        service.sendWeeklyReport();

        verifyNoInteractions(mailSender);
    }

    @Test
    void skipsWhenNoCyclesAndNoIncidentsRecorded() {
        service.sendWeeklyReport();

        verifyNoInteractions(mailSender);
    }

    @Test
    void sendsWhenOnlyIncidentsExistAndNoCyclesCompleted() {
        // A crash-loop that never completes a single cycle must still be reported.
        when(lifecycleTracker.recentIncidents()).thenReturn(List.of(
                new IncidentEntry(
                        LocalDateTime.of(2026, 7, 10, 9, 0),
                        LocalDateTime.of(2026, 7, 10, 8, 45),
                        LocalDateTime.of(2026, 7, 10, 9, 0),
                        "ERROR: out of memory")));

        service.sendWeeklyReport();

        verify(mailSender).send(any(SimpleMailMessage.class));
    }

    @Test
    void sendsOneEmailCoveringEveryRecordedDay() {
        recorder.record(new CycleReportEntry(LocalDate.of(2026, 7, 6), 5, 0, "MLI-1", null));
        recorder.record(new CycleReportEntry(LocalDate.of(2026, 7, 7), 3, 2, "MLI-3", "MLI-4"));

        service.sendWeeklyReport();

        ArgumentCaptor<SimpleMailMessage> captor = ArgumentCaptor.forClass(SimpleMailMessage.class);
        verify(mailSender).send(captor.capture());
        SimpleMailMessage sent = captor.getValue();
        assertThat(sent.getTo()).containsExactly("ops@example.com");
        assertThat(sent.getFrom()).isEqualTo("weather@example.com");
        assertThat(sent.getSubject()).contains("Weekly Report");
        assertThat(sent.getText())
                .contains("2026-07-06")
                .contains("processed=5")
                .contains("2026-07-07")
                .contains("failed=2")
                .contains("lastFailedStation=MLI-4")
                .contains("no crashes or unexpected restarts detected");
    }

    @Test
    void includesIncidentDetailsInBody() {
        recorder.record(new CycleReportEntry(LocalDate.of(2026, 7, 10), 1, 0, "MLI-1", null));
        when(lifecycleTracker.recentIncidents()).thenReturn(List.of(
                new IncidentEntry(
                        LocalDateTime.of(2026, 7, 8, 3, 0),
                        LocalDateTime.of(2026, 7, 7, 23, 45),
                        LocalDateTime.of(2026, 7, 8, 3, 0),
                        "ERROR: Weather worker loop failed")));

        service.sendWeeklyReport();

        ArgumentCaptor<SimpleMailMessage> captor = ArgumentCaptor.forClass(SimpleMailMessage.class);
        verify(mailSender).send(captor.capture());
        assertThat(captor.getValue().getText())
                .contains("1 crash detected")
                .contains("2026-07-07 23:45:00")
                .contains("2026-07-08 03:00:00")
                .contains("ERROR: Weather worker loop failed");
    }

    @Test
    void fallsBackToSmtpUsernameWhenFromNotConfigured() {
        ReflectionTestUtils.setField(service, "from", "");
        ReflectionTestUtils.setField(service, "smtpUsername", "smtp-account@example.com");
        recorder.record(new CycleReportEntry(LocalDate.of(2026, 7, 10), 1, 0, "MLI-1", null));

        service.sendWeeklyReport();

        ArgumentCaptor<SimpleMailMessage> captor = ArgumentCaptor.forClass(SimpleMailMessage.class);
        verify(mailSender).send(captor.capture());
        assertThat(captor.getValue().getFrom()).isEqualTo("smtp-account@example.com");
    }

    @Test
    void doesNotPropagateMailSendFailure() {
        recorder.record(new CycleReportEntry(LocalDate.of(2026, 7, 10), 1, 0, "MLI-1", null));
        doThrow(new MailSendException("boom")).when(mailSender).send(any(SimpleMailMessage.class));

        service.sendWeeklyReport(); // must not throw
    }

    @Test
    void buildReportBodyFormatsMissingStationsAsNone() {
        String body = WeeklyReportMailService.buildReportBody(
                List.of(new CycleReportEntry(LocalDate.of(2026, 7, 10), 0, 0, null, null)),
                List.of());

        assertThat(body).contains("lastProcessedStation=<none>").contains("lastFailedStation=<none>");
    }
}
