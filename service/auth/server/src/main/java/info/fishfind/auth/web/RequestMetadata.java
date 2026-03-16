package info.fishfind.auth.web;

public record RequestMetadata(
        String rawIp,
        String ip4,
        String ip6,
        String agent
) {
}
