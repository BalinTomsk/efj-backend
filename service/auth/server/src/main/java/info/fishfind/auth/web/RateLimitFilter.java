package info.fishfind.auth.web;

import info.fishfind.auth.config.AppProperties;
import jakarta.servlet.FilterChain;
import jakarta.servlet.ServletException;
import jakarta.servlet.http.HttpServletRequest;
import jakarta.servlet.http.HttpServletResponse;
import org.springframework.http.MediaType;
import org.springframework.stereotype.Component;
import org.springframework.web.filter.OncePerRequestFilter;

import java.io.IOException;
import java.time.Instant;
import java.time.temporal.ChronoUnit;
import java.util.Map;
import java.util.concurrent.ConcurrentHashMap;
import java.util.concurrent.atomic.AtomicInteger;

@Component
public class RateLimitFilter extends OncePerRequestFilter {
    private final AppProperties appProperties;
    private final Map<String, WindowCounter> counters = new ConcurrentHashMap<>();

    /**
     * Creates the rate limiting filter using application rate limit settings.
     *
     * @param appProperties application properties
     */
    public RateLimitFilter(AppProperties appProperties) {
        this.appProperties = appProperties;
    }

    /**
     * Applies per-client request rate limiting based on the remote address.
     *
     * @param request incoming HTTP request
     * @param response outgoing HTTP response
     * @param filterChain remaining filter chain
     * @throws ServletException when the servlet pipeline fails
     * @throws IOException when response writing fails
     */
    @Override
    protected void doFilterInternal(HttpServletRequest request,
                                    HttpServletResponse response,
                                    FilterChain filterChain) throws ServletException, IOException {
        String key = request.getRemoteAddr() == null ? "unknown" : request.getRemoteAddr();
        Instant now = Instant.now();
        WindowCounter counter = counters.compute(key, (k, existing) -> {
            if (existing == null || now.isAfter(existing.windowEnd())) {
                return new WindowCounter(new AtomicInteger(1), now.plus(appProperties.rateLimit().windowMinutes(), ChronoUnit.MINUTES));
            }
            existing.counter().incrementAndGet();
            return existing;
        });

        if (counter.counter().get() > appProperties.rateLimit().maxRequests()) {
            response.setStatus(429);
            response.setContentType(MediaType.APPLICATION_JSON_VALUE);
            response.getWriter().write('{'+"\"error\":\"Too many requests\""+'}');
            return;
        }

        filterChain.doFilter(request, response);
    }

    private record WindowCounter(AtomicInteger counter, Instant windowEnd) {
    }
}
