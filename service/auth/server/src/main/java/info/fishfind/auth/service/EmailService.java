package info.fishfind.auth.service;

import info.fishfind.auth.config.AppProperties;
import jakarta.mail.MessagingException;
import jakarta.mail.internet.MimeMessage;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.mail.MailException;
import org.springframework.mail.javamail.JavaMailSender;
import org.springframework.mail.javamail.MimeMessageHelper;
import org.springframework.stereotype.Service;

@Service
public class EmailService {

    private static final Logger log = LoggerFactory.getLogger(EmailService.class);

    private final JavaMailSender mailSender;
    private final AppProperties appProperties;

    /**
     * Creates the email service used for transactional auth emails.
     *
     * @param mailSender JavaMail sender
     * @param appProperties application properties
     */
    public EmailService(JavaMailSender mailSender, AppProperties appProperties) {
        this.mailSender = mailSender;
        this.appProperties = appProperties;
    }

    /**
     * Sends the account activation email to a newly registered user.
     *
     * @param email recipient email address
     * @param username recipient username
     * @param activationToken account activation token
     */
    public void sendActivationEmail(String email, String username, String activationToken) {
        String activationUrl = appProperties.frontendBaseUrl() + "/activate/" + activationToken;

        try {
            MimeMessage message = mailSender.createMimeMessage();
            MimeMessageHelper helper = new MimeMessageHelper(message, true, "UTF-8");

            helper.setFrom(appProperties.mail().from());
            helper.setTo(email);
            helper.setSubject("Activate your FishFind account");
            helper.setText("""
                    <p>Hello %s,</p>
                    <p>Your FishFind account has been created.</p>
                    <p>Please activate your account by clicking the link below:</p>
                    <p><a href="%s">%s</a></p>
                    """.formatted(username, activationUrl, activationUrl), true);

            mailSender.send(message);
        } catch (MessagingException | MailException ex) {
            log.error("Failed to send activation email to {}", email, ex);
            throw new IllegalStateException(
                    "Account created in database, but sending activation email failed", ex
            );
        }
    }
}
