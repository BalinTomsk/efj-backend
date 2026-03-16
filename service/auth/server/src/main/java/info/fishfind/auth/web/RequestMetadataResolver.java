package info.fishfind.auth.web;

import jakarta.servlet.http.HttpServletRequest;
import org.springframework.stereotype.Component;

@Component
public class RequestMetadataResolver {

    /**
     * Extracts the normalized client IP information and user agent from the request.
     *
     * @param request current HTTP request
     * @return normalized request metadata
     */
    public RequestMetadata resolve(HttpServletRequest request) {
        String rawIp = firstNonBlank(
                firstForwardedIp(request.getHeader("X-Forwarded-For")),
                request.getHeader("X-Real-IP"),
                request.getRemoteAddr(),
                "unknown"
        ).trim();
        String agent = firstNonBlank(request.getHeader("User-Agent"), "").trim();

        if (rawIp.isBlank() || "unknown".equals(rawIp)) {
            return new RequestMetadata("unknown", "", "", agent);
        }

        String mappedIpv4 = rawIp.startsWith("::ffff:") ? rawIp.substring(7) : "";
        if (isIpv4(mappedIpv4)) {
            return new RequestMetadata(mappedIpv4, mappedIpv4, rawIp.toLowerCase(), agent);
        }

        if (isIpv4(rawIp)) {
            return new RequestMetadata(rawIp, rawIp, "", agent);
        }

        if (isIpv6(rawIp)) {
            String normalized = rawIp.toLowerCase();
            return new RequestMetadata(normalized, "", normalized, agent);
        }

        return new RequestMetadata(rawIp, "", "", agent);
    }

    private String firstForwardedIp(String header) {
        if (header == null || header.isBlank()) {
            return "";
        }
        return header.split(",")[0].trim();
    }

    private String firstNonBlank(String... values) {
        for (String value : values) {
            if (value != null && !value.isBlank()) {
                return value;
            }
        }
        return "";
    }

    private boolean isIpv4(String value) {
        return value != null && value.matches("^(25[0-5]|2[0-4]\\d|1\\d\\d|[1-9]?\\d)(\\.(25[0-5]|2[0-4]\\d|1\\d\\d|[1-9]?\\d)){3}$");
    }

    private boolean isIpv6(String value) {
        return value != null && value.contains(":");
    }
}
