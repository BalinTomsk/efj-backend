package com.fishfind.docapi.status;

import jakarta.servlet.FilterChain;
import jakarta.servlet.ServletException;
import jakarta.servlet.http.HttpServletRequest;
import jakarta.servlet.http.HttpServletResponse;
import org.springframework.web.filter.OncePerRequestFilter;
import org.springframework.web.servlet.HandlerMapping;

import java.io.IOException;

/**
 * Records every {@code /api/} request in {@link ServiceActivity} as method + matched route pattern. The pattern
 * keeps ids, names and query strings off the admin page; an unmatched path is not recorded.
 *
 * <p>Registered by {@link ServiceStatusConfig}, not as a {@code @Component}: {@code @WebMvcTest} slices pick up
 * every servlet filter bean, and would then need {@link ServiceActivity} too.
 */
public class ServiceActivityFilter extends OncePerRequestFilter {

    private final ServiceActivity activity;

    public ServiceActivityFilter(ServiceActivity activity) {
        this.activity = activity;
    }

    @Override
    protected boolean shouldNotFilter(HttpServletRequest request) {
        return !request.getRequestURI().startsWith("/api/");
    }

    @Override
    protected void doFilterInternal(HttpServletRequest request, HttpServletResponse response, FilterChain chain)
            throws ServletException, IOException {
        try {
            chain.doFilter(request, response);
        } finally {
            Object pattern = request.getAttribute(HandlerMapping.BEST_MATCHING_PATTERN_ATTRIBUTE);
            if (pattern != null) {
                activity.record(request.getMethod() + " " + pattern);
            }
        }
    }
}
