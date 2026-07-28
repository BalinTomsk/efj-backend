package com.fishfind.docapi.domain;

/**
 * The four entity kinds whose JSON documents DocApi manages. Each value carries the URL-path segment
 * and the human-readable label used in log messages and error envelopes.
 *
 * <p>{@code WATERBODY} maps to the legacy {@code lake} entity in the database (water bodies are stored
 * in {@code dbo.lake}); the API surface uses the more descriptive "waterbody" name.
 */
public enum DocumentType {

    NEWS("news"),
    WATERBODY("waterbody"),
    FISH("fish"),
    STATION("station");

    private final String label;

    DocumentType(String label) {
        this.label = label;
    }

    /**
     * @return the lower-case label used in URL paths, logs, and error messages (e.g. {@code "news"})
     */
    public String label() {
        return label;
    }
}
