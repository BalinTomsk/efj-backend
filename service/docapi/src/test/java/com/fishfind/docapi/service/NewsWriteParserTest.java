package com.fishfind.docapi.service;

import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.fishfind.docapi.repo.NewsWrite;
import org.junit.jupiter.api.Test;

import java.sql.Timestamp;
import java.util.Base64;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;

class NewsWriteParserTest {

    private static final ObjectMapper MAPPER = new ObjectMapper();
    private static final String G1 = "11111111-2222-3333-4444-555555555555";
    private static final String G2 = "aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee";
    private static final byte[] JPEG = {(byte) 0xFF, (byte) 0xD8, (byte) 0xFF, 0x10, 0x20, 0x30};

    private static JsonNode json(String s) throws Exception {
        return MAPPER.readTree(s);
    }

    // ---- article document (POST / PUT /api/v1/news) ---------------------------------------------

    @Test
    void documentMapsEverySnakeCaseField() throws Exception {
        String b64 = Base64.getEncoder().encodeToString(JPEG);
        NewsWrite w = NewsWriteParser.fromDocument(json("""
                {"title":"T","author":"A","author_link":"http://a","source":"S","source_link":"http://s",
                 "video_link":"http://v","paragraph0":"p0","paragraph1":"p1","paragraph2":"p2",
                 "country":"ca","date":"2026-09-15","lake_id":"%s","credit":"C","photo_alt":"Alt",
                 "photo":"%s","fishes":[{"id":"%s","name":"Pike"},{"id":"%s"}]}
                """.formatted(G1.toUpperCase(), b64, G1, G2)));

        assertThat(w.title()).isEqualTo("T");
        assertThat(w.author()).isEqualTo("A");
        assertThat(w.authorLink()).isEqualTo("http://a");
        assertThat(w.source()).isEqualTo("S");
        assertThat(w.sourceLink()).isEqualTo("http://s");
        assertThat(w.videoLink()).isEqualTo("http://v");
        assertThat(w.paragraph0()).isEqualTo("p0");
        assertThat(w.paragraph2()).isEqualTo("p2");
        assertThat(w.country()).isEqualTo("CA");
        assertThat(w.stamp()).isEqualTo(Timestamp.valueOf("2026-09-15 00:00:00"));
        assertThat(w.lakeId()).isEqualTo(G1);                 // lower-cased
        assertThat(w.fish1Id()).isEqualTo(G1);
        assertThat(w.fish2Id()).isEqualTo(G2);
        assertThat(w.fish3Id()).isNull();
        assertThat(w.photo0().bytes()).isEqualTo(JPEG);
        assertThat(w.photo0().author()).isEqualTo("C");
        assertThat(w.photo0().alt()).isEqualTo("Alt");
        assertThat(w.photo1()).isEqualTo(NewsWrite.Photo.NONE);
        assertThat(w.photo2()).isEqualTo(NewsWrite.Photo.NONE);
    }

    /**
     * GET /api/v1/news/{id} returns fish1_id..fish3_id, not a fishes array. A PUT is a full replace,
     * so without this fallback editing a GET body and PUTting it back would null all three species.
     */
    @Test
    void documentFallsBackToTheGetShapesFishColumnsWhenThereIsNoFishesArray() throws Exception {
        NewsWrite w = NewsWriteParser.fromDocument(json(
                "{\"title\":\"T\",\"fish1_id\":\"%s\",\"fish3_id\":\"%s\"}".formatted(G1, G2)));

        assertThat(w.fish1Id()).isEqualTo(G1);
        assertThat(w.fish2Id()).isNull();
        assertThat(w.fish3Id()).isEqualTo(G2);
    }

    @Test
    void aFishesArrayWinsAndAnEmptyOneClearsAllThree() throws Exception {
        NewsWrite w = NewsWriteParser.fromDocument(json(
                "{\"title\":\"T\",\"fishes\":[],\"fish1_id\":\"%s\"}".formatted(G1)));

        assertThat(w.fish1Id()).isNull();
        assertThat(w.fish2Id()).isNull();
        assertThat(w.fish3Id()).isNull();
    }

    /** Positional, as sp_news_doc_add's ROW_NUMBER() was: a bad entry empties its slot, it does not shift. */
    @Test
    void fishesArePositionalAndCappedAtThree() throws Exception {
        NewsWrite w = NewsWriteParser.fromDocument(json("""
                {"title":"T","fishes":[{"id":"not-a-guid"},{"id":"%s"},{"id":"%s"},{"id":"%s"}]}
                """.formatted(G1, G2, G1)));

        assertThat(w.fish1Id()).isNull();
        assertThat(w.fish2Id()).isEqualTo(G1);
        assertThat(w.fish3Id()).isEqualTo(G2);
    }

    /** TRY_CONVERT's rule, kept: an invalid tag is dropped rather than rejecting the whole article. */
    @Test
    void anInvalidLakeIdIsDroppedNotRejected() throws Exception {
        assertThat(NewsWriteParser.fromDocument(json("{\"title\":\"T\",\"lake_id\":\"lake-7\"}")).lakeId()).isNull();
    }

    /** MySQL's TO_BASE64 -- what GET returns -- wraps every 76 chars; that body must PUT straight back. */
    @Test
    void lineWrappedBase64IsAccepted() throws Exception {
        String b64 = Base64.getEncoder().encodeToString(new byte[120]);
        String wrapped = b64.substring(0, 76) + "\\n" + b64.substring(76);
        NewsWrite w = NewsWriteParser.fromDocument(json(
                "{\"title\":\"T\",\"photo\":\"" + wrapped + "\"}"));

        assertThat(w.photo0().bytes()).hasSize(120);
    }

    @Test
    void invalidBase64IsA400NotSilentGarbage() {
        assertThatThrownBy(() -> NewsWriteParser.fromDocument(json("{\"title\":\"T\",\"photo\":\"@@not base64@@\"}")))
                .isInstanceOf(InvalidDocumentException.class)
                .hasMessageContaining("\"photo\" is not valid base64");
    }

    @Test
    void anUnparseableDateIsTreatedAsAbsent() throws Exception {
        assertThat(NewsWriteParser.fromDocument(json("{\"title\":\"T\",\"date\":\"yesterday\"}")).stamp()).isNull();
        assertThat(NewsWriteParser.fromDocument(json("{\"title\":\"T\",\"date\":\"2026-09-15T08:30:00\"}")).stamp())
                .isEqualTo(Timestamp.valueOf("2026-09-15 08:30:00"));
    }

    // ---- validation: every client error is a 400, before any database call ---------------------

    @Test
    void aMissingOrBlankTitleIsA400() {
        assertThatThrownBy(() -> NewsWriteParser.fromDocument(json("{\"author\":\"A\"}")))
                .isInstanceOf(InvalidDocumentException.class).hasMessageContaining("\"title\" is required");
        assertThatThrownBy(() -> NewsWriteParser.fromInterchange(json("{\"title\":\"   \"}")))
                .isInstanceOf(InvalidDocumentException.class).hasMessageContaining("\"title\" is required");
    }

    @Test
    void anOverLongFieldIsA400NamingTheFieldAndLimit() {
        String title = "x".repeat(NewsWriteParser.TITLE_MAX + 1);
        assertThatThrownBy(() -> NewsWriteParser.fromDocument(json("{\"title\":\"" + title + "\"}")))
                .isInstanceOf(InvalidDocumentException.class)
                .hasMessageContaining("\"title\" is longer than its 128-character limit");

        String credit = "c".repeat(NewsWriteParser.PHOTO_AUTHOR_MAX + 1);
        assertThatThrownBy(() -> NewsWriteParser.fromDocument(json("{\"title\":\"T\",\"credit\":\"" + credit + "\"}")))
                .isInstanceOf(InvalidDocumentException.class)
                .hasMessageContaining("\"credit\" is longer than its 64-character limit");
    }

    /** MySQL counts characters, not UTF-16 units: 128 emoji are a legal title. */
    @Test
    void lengthIsCountedInCodePoints() throws Exception {
        String emoji = "🐟".repeat(NewsWriteParser.TITLE_MAX);  // 128 fish, 256 chars
        assertThat(NewsWriteParser.fromDocument(json("{\"title\":\"" + emoji + "\"}")).title()).isEqualTo(emoji);
    }

    @Test
    void aCountryThatIsNotTwoLettersIsA400() {
        assertThatThrownBy(() -> NewsWriteParser.fromDocument(json("{\"title\":\"T\",\"country\":\"CAN\"}")))
                .isInstanceOf(InvalidDocumentException.class)
                .hasMessageContaining("two-letter country code");
    }

    @Test
    void aNonObjectBodyOrStructuredStringFieldIsA400() {
        assertThatThrownBy(() -> NewsWriteParser.fromDocument(json("[1,2]")))
                .isInstanceOf(InvalidDocumentException.class).hasMessageContaining("JSON object");
        assertThatThrownBy(() -> NewsWriteParser.fromDocument(json("{\"title\":{\"x\":1}}")))
                .isInstanceOf(InvalidDocumentException.class).hasMessageContaining("\"title\" must be a string");
        assertThatThrownBy(() -> NewsWriteParser.fromDocument(json("{\"title\":\"T\",\"fishes\":\"pike\"}")))
                .isInstanceOf(InvalidDocumentException.class).hasMessageContaining("\"fishes\" must be an array");
    }

    // ---- interchange document (POST /api/v1/news/import) ----------------------------------------

    @Test
    void interchangeMapsCamelCaseFieldsAndAllThreePhotoSlots() throws Exception {
        String b64 = Base64.getEncoder().encodeToString(JPEG);
        NewsWrite w = NewsWriteParser.fromInterchange(json("""
                {"title":"T","authorLink":"http://a","sourceLink":"http://s","videoLink":"http://v",
                 "country":"US","date":"2026-01-02","lakeId":"%s","fish1Id":"%s","fish2Id":null,"fish3Id":"%s",
                 "photo0":"%s","photoAuthor0":"A0","photoAlt0":"L0",
                 "photo1":null,"photoAuthor1":"A1","photoAlt1":null,
                 "photo2":"%s","photoAuthor2":null,"photoAlt2":"L2"}
                """.formatted(G1, G1, G2, b64, b64)));

        assertThat(w.authorLink()).isEqualTo("http://a");
        assertThat(w.sourceLink()).isEqualTo("http://s");
        assertThat(w.videoLink()).isEqualTo("http://v");
        assertThat(w.stamp()).isEqualTo(Timestamp.valueOf("2026-01-02 00:00:00"));
        assertThat(w.lakeId()).isEqualTo(G1);
        assertThat(w.fish1Id()).isEqualTo(G1);
        assertThat(w.fish2Id()).isNull();
        assertThat(w.fish3Id()).isEqualTo(G2);
        assertThat(w.photo0().bytes()).isEqualTo(JPEG);
        assertThat(w.photo0().author()).isEqualTo("A0");
        assertThat(w.photo0().alt()).isEqualTo("L0");
        assertThat(w.photo1().bytes()).isNull();
        assertThat(w.photo1().author()).isEqualTo("A1");
        assertThat(w.photo2().bytes()).isEqualTo(JPEG);
        assertThat(w.photo2().alt()).isEqualTo("L2");
    }
}
