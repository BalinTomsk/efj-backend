package com.fishfind.docapi.repo;

import java.sql.Timestamp;

/**
 * One news write, already parsed and validated: what {@link NewsWriteRepository} persists for
 * {@code POST /api/v1/news}, {@code PUT /api/v1/news/{id}} and {@code POST /api/v1/news/import}.
 *
 * <p>Built only by {@code NewsWriteParser}, which has already turned every client error (blank
 * title, over-long field, bad country, bad base64) into a 400 -- so nothing reaching a repository
 * can fail validation inside the {@code sqlBreaker} and count against the database's health.
 *
 * <p>{@code stamp} {@code null} means "not supplied": now on insert, keep the stored stamp on update.
 * {@code lakeId}/{@code fishNId} are canonical lower-case GUIDs or {@code null} -- an invalid tag was
 * dropped by the parser, the {@code TRY_CONVERT} rule the SQL Server procedures applied.
 *
 * @param photo0 the paragraph-0 (lead) photo slot; never {@code null}, {@link Photo#NONE} when empty
 * @param photo1 slot 1; only an import fills it
 * @param photo2 slot 2; only an import fills it
 */
public record NewsWrite(
        String title,
        String author,
        String authorLink,
        String source,
        String sourceLink,
        String videoLink,
        String paragraph0,
        String paragraph1,
        String paragraph2,
        String country,
        Timestamp stamp,
        String lakeId,
        String fish1Id,
        String fish2Id,
        String fish3Id,
        Photo photo0,
        Photo photo1,
        Photo photo2) {

    public NewsWrite {
        photo0 = photo0 == null ? Photo.NONE : photo0;
        photo1 = photo1 == null ? Photo.NONE : photo1;
        photo2 = photo2 == null ? Photo.NONE : photo2;
    }

    /**
     * One paragraph-photo slot. Any component may be {@code null}; {@code bytes} {@code null} on an
     * update means "keep the stored photo".
     */
    public record Photo(byte[] bytes, String author, String alt) {

        public static final Photo NONE = new Photo(null, null, null);
    }
}
