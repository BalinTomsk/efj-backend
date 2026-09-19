package com.fishfind.docapi.repo;

import java.sql.Timestamp;

/**
 * Write-side companion to {@link NewsQueryRepository}/{@code newsStore}: the three operations
 * {@code fishfind-frontend}'s {@code Editor/AddNews.aspx} admin authoring page needs, backed by the
 * MySQL {@code news} table (see {@code envfish-db/mysql/script02_Proc.sql} ->
 * {@code sp_news_admin_draft_create}/{@code sp_news_admin_publish}/{@code sp_news_admin_photo_update}).
 *
 * <p>Kept as its own repository, not a method on {@link NewsQueryRepository} or {@code newsStore}:
 * it mutates the flat {@code news} row directly (title, author, paragraphs, photo slots, …), which is
 * a different shape from both the read queries and the generic JSON-document {@code DocumentStore}
 * CRUD (which is a separate, still-SQL-Server-backed surface -- see {@code NewsDocumentService}).
 */
public interface NewsAdminCommandRepository {

    /**
     * Purges every unpublished draft, then inserts one fresh draft row with the placeholder values
     * the page has always written on load ({@code title}/{@code Vantus}), and returns its id.
     *
     * @return the new draft's {@code news_id}
     */
    String createDraft();

    /**
     * Upserts an article's editable fields by id and marks it published — an unknown id creates the
     * row rather than doing nothing, mirroring {@code ButtonSubmitAddNews_Click}'s original
     * update-or-recover-by-insert behaviour for a draft that was purged out from under the form.
     *
     * @param request every editable field, including the id being saved
     * @return the id and whether this was a fresh {@code inserted} row or an {@code updated} one
     */
    PublishResult publish(NewsAdminPublishRequest request);

    /**
     * Updates one paragraph-photo slot (0, 1, or 2) on an existing article/draft. {@code author}/
     * {@code alt} of {@code null} leave that column's current value in place; the photo bytes are
     * always replaced.
     *
     * @param newsId the article's id
     * @param index  0, 1, or 2
     * @param photo  the new photo bytes
     * @param author photo credit, or {@code null} to leave unchanged
     * @param alt    photo alt text, or {@code null} to leave unchanged
     * @return whether the id exists at all, and whether a column was actually written
     */
    PhotoUpdateResult updatePhoto(String newsId, int index, byte[] photo, String author, String alt);

    /**
     * Every field {@code Editor/AddNews.aspx}'s Submit writes, plus the id being saved. A {@code null}
     * field is written as {@code NULL} — the draft row it is normally applied to already holds
     * {@code NULL} there, so this matches the original page's behaviour closely enough without
     * needing a separate partial-update path.
     */
    record NewsAdminPublishRequest(
            String newsId,
            String title,
            String author,
            String source,
            String sourceLink,
            String authorLink,
            Timestamp stamp,
            String videoLink,
            String paragraph0,
            String paragraph1,
            String paragraph2,
            String country,
            String lakeId,
            String fish1Id,
            String fish2Id,
            String fish3Id) {
    }

    /**
     * @param newsId the id that was saved (echoes the request)
     * @param action {@code "inserted"} for a brand-new row, {@code "updated"} for an existing one
     */
    record PublishResult(String newsId, String action) {
    }

    /**
     * @param found   whether {@code newsId} exists at all
     * @param updated whether a photo column was actually written (false when {@code found} but the
     *                slot index was outside 0..2)
     */
    record PhotoUpdateResult(boolean found, boolean updated) {
    }
}
