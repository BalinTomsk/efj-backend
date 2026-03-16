package info.fishfind.auth.web;

import info.fishfind.auth.repository.UserRepository;
import jakarta.servlet.FilterChain;
import jakarta.servlet.ServletException;
import jakarta.servlet.http.HttpServletRequest;
import jakarta.servlet.http.HttpServletResponse;
import org.springframework.http.MediaType;
import org.springframework.stereotype.Component;
import org.springframework.web.filter.OncePerRequestFilter;

import java.io.IOException;

@Component
public class SuspendedNetworkFilter extends OncePerRequestFilter {
    private final UserRepository userRepository;
    private final RequestMetadataResolver requestMetadataResolver;

    public SuspendedNetworkFilter(UserRepository userRepository, RequestMetadataResolver requestMetadataResolver) {
        this.userRepository = userRepository;
        this.requestMetadataResolver = requestMetadataResolver;
    }

    @Override
    protected void doFilterInternal(HttpServletRequest request,
                                    HttpServletResponse response,
                                    FilterChain filterChain) throws ServletException, IOException {
        RequestMetadata metadata = requestMetadataResolver.resolve(request);
        if ((!metadata.ip4().isBlank() || !metadata.ip6().isBlank())
                && userRepository.findSuspendedByNetwork(metadata.ip4(), metadata.ip6()).isPresent()) {
            response.setStatus(404);
            response.setContentType(MediaType.APPLICATION_JSON_VALUE);
            response.getWriter().write("{\"error\":\"Endpoint not found\"}");
            return;
        }

        filterChain.doFilter(request, response);
    }
}
