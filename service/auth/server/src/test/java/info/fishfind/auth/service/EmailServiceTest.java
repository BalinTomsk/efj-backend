package info.fishfind.auth.service;

import info.fishfind.auth.config.AppProperties;
import jakarta.mail.BodyPart;
import jakarta.mail.Multipart;
import jakarta.mail.Session;
import jakarta.mail.internet.InternetAddress;
import jakarta.mail.internet.MimeMessage;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.springframework.mail.MailSendException;
import org.springframework.mail.javamail.JavaMailSender;

import java.util.Properties;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.mockito.Mockito.doThrow;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

class EmailServiceTest {

    private JavaMailSender mailSender;
    private EmailService emailService;

    @BeforeEach
    void setUp() {
        mailSender = mock(JavaMailSender.class);
        emailService = new EmailService(mailSender, appProperties());
    }

    @Test
    void sendActivationEmailBuildsAndSendsExpectedMessage() throws Exception {
        MimeMessage mimeMessage = new MimeMessage(Session.getInstance(new Properties()));
        when(mailSender.createMimeMessage()).thenReturn(mimeMessage);

        emailService.sendActivationEmail("alice@example.com", "alice", "token-123");

        assertThat(mimeMessage.getFrom()).containsExactly(new InternetAddress("noreply@example.com"));
        assertThat(mimeMessage.getAllRecipients()).containsExactly(new InternetAddress("alice@example.com"));
        assertThat(mimeMessage.getSubject()).isEqualTo("Activate your FishFind account");
        assertThat(extractText(mimeMessage.getContent()))
                .contains("Hello alice")
                .contains("<p>")
                .contains("https://fishfind.example/activate/token-123");
        verify(mailSender).send(mimeMessage);
    }

    @Test
    void sendActivationEmailWrapsMailSenderFailures() {
        MimeMessage mimeMessage = new MimeMessage(Session.getInstance(new Properties()));
        when(mailSender.createMimeMessage()).thenReturn(mimeMessage);
        doThrow(new MailSendException("smtp down")).when(mailSender).send(mimeMessage);

        assertThatThrownBy(() -> emailService.sendActivationEmail("alice@example.com", "alice", "token-123"))
                .isInstanceOfSatisfying(IllegalStateException.class, ex -> {
                    assertThat(ex.getMessage())
                            .isEqualTo("Account created in database, but sending activation email failed");
                    assertThat(ex.getCause()).isInstanceOf(MailSendException.class);
                });
    }

    private static AppProperties appProperties() {
        return new AppProperties(
                "https://fishfind.example",
                new AppProperties.Jwt("MDEyMzQ1Njc4OTAxMjM0NTY3ODkwMTIzNDU2Nzg5MDE=", 4),
                new AppProperties.Mail("noreply@example.com"),
                new AppProperties.RateLimit(100, 1)
        );
    }

    private static String extractText(Object content) throws Exception {
        if (content instanceof String text) {
            return text;
        }
        if (content instanceof Multipart multipart) {
            StringBuilder builder = new StringBuilder();
            for (int i = 0; i < multipart.getCount(); i++) {
                BodyPart bodyPart = multipart.getBodyPart(i);
                builder.append(extractText(bodyPart.getContent()));
            }
            return builder.toString();
        }
        return String.valueOf(content);
    }
}
