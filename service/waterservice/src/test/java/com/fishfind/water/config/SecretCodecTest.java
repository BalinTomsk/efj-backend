package com.fishfind.water.config;

import org.junit.jupiter.api.Test;

import javax.crypto.spec.SecretKeySpec;
import java.util.HexFormat;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertFalse;
import static org.junit.jupiter.api.Assertions.assertNull;
import static org.junit.jupiter.api.Assertions.assertThrows;
import static org.junit.jupiter.api.Assertions.assertTrue;

/**
 * Covers the {@code enc:v1:} value format.
 *
 * <p>The payloads below were produced by {@code efj-backend/secret/Protect-Env.ps1} under the fixed
 * key in {@link #KEY_HEX}, so these are genuine cross-language interop tests: if the PowerShell
 * encryptor and this Java decryptor ever drift on nonce placement, tag position, base64 alphabet, or
 * additional authenticated data, they fail. The values are invented, not real credentials.
 */
class SecretCodecTest {

    private static final String KEY_HEX = "000102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f";

    private static final String ENC_DB_URL =
            "enc:v1:GdbrPJpx_QeoN5-s7XAzyG0ROIL7IFPAOwmPVO5LgrSOs1KPkKoyYrtIhuIyVX_J8Xc"
                    + "VZY8VE6ybG0AN_q6iBSQK8Z0H3EGpPN0KXX9fVc6Szdb7wg";
    private static final String ENC_DB_USERNAME =
            "enc:v1:oNuX3o5NIC67K4HiN1M95YhWvh3S5AcORZLKOWSbzQ1NiQ";
    private static final String ENC_DB_PASSWORD =
            "enc:v1:6tiG1Z4iC24LMP6h7LN5x9s_OraeqDKDny_lHf9rAm94XKFNbu3pSaqv9A";

    private static SecretKeySpec key(String hex) {
        return new SecretKeySpec(HexFormat.of().parseHex(hex), "AES");
    }

    /** Flips a character in the middle of the payload, which always alters a full 6-bit group. */
    private static String tamper(String value) {
        String body = value.substring("enc:v1:".length());
        int index = body.length() / 2;
        char replacement = body.charAt(index) == 'A' ? 'B' : 'A';
        return "enc:v1:" + body.substring(0, index) + replacement + body.substring(index + 1);
    }

    @Test
    void decryptsPayloadsProducedByTheProtectEnvScript() {
        SecretKeySpec key = key(KEY_HEX);

        assertEquals("jdbc:sqlserver://db.example.net:1433;databaseName=envfish",
                SecretCodec.decryptWith(key, "DB_URL", ENC_DB_URL));
        assertEquals("ff_app", SecretCodec.decryptWith(key, "DB_USERNAME", ENC_DB_USERNAME));
        assertEquals("s3cr3t-p@ssw0rd", SecretCodec.decryptWith(key, "DB_PASSWORD", ENC_DB_PASSWORD));
    }

    @Test
    void returnsUnmarkedValuesUntouched() {
        // The backwards-compatibility guarantee: a fully-plaintext .env keeps working unchanged,
        // which is what lets the decrypt-capable images ship before the file is ever encrypted.
        assertEquals("3000", SecretCodec.decryptIfNeeded("PORT", "3000"));
        assertEquals("", SecretCodec.decryptIfNeeded("EMPTY", ""));
        assertNull(SecretCodec.decryptIfNeeded("MISSING", null));
    }

    @Test
    void detectsTheMarker() {
        assertTrue(SecretCodec.isEncrypted(ENC_DB_PASSWORD));
        assertFalse(SecretCodec.isEncrypted("3000"));
        assertFalse(SecretCodec.isEncrypted("enc:v2:something"));
        assertFalse(SecretCodec.isEncrypted(null));
    }

    @Test
    void refusesAValueMovedToADifferentVariable() {
        // The variable name is additional authenticated data, so a ciphertext cannot be relocated
        // from one key to another — e.g. copying the username over the password field.
        IllegalStateException thrown = assertThrows(IllegalStateException.class,
                () -> SecretCodec.decryptWith(key(KEY_HEX), "DB_PASSWORD", ENC_DB_USERNAME));

        assertTrue(thrown.getMessage().contains("DB_PASSWORD"));
    }

    @Test
    void refusesATamperedPayload() {
        assertThrows(IllegalStateException.class,
                () -> SecretCodec.decryptWith(key(KEY_HEX), "DB_PASSWORD", tamper(ENC_DB_PASSWORD)));
    }

    @Test
    void refusesTheWrongKey() {
        String otherKey = "1f1e1d1c1b1a191817161514131211100f0e0d0c0b0a09080706050403020100";

        assertThrows(IllegalStateException.class,
                () -> SecretCodec.decryptWith(key(otherKey), "DB_PASSWORD", ENC_DB_PASSWORD));
    }

    @Test
    void refusesAMalformedPayload() {
        IllegalStateException notBase64 = assertThrows(IllegalStateException.class,
                () -> SecretCodec.decryptWith(key(KEY_HEX), "DB_PASSWORD", "enc:v1:not base64!!"));
        assertTrue(notBase64.getMessage().contains("base64url"));

        IllegalStateException tooShort = assertThrows(IllegalStateException.class,
                () -> SecretCodec.decryptWith(key(KEY_HEX), "DB_PASSWORD", "enc:v1:AAAA"));
        assertTrue(tooShort.getMessage().contains("too short"));
    }

    @Test
    void neverExposesTheValueInAFailureMessage() {
        // Failure messages travel into logs and LogException rows; they must name the variable but
        // never echo the payload back.
        IllegalStateException thrown = assertThrows(IllegalStateException.class,
                () -> SecretCodec.decryptWith(key(KEY_HEX), "DB_PASSWORD", tamper(ENC_DB_PASSWORD)));

        assertFalse(thrown.getMessage().contains(ENC_DB_PASSWORD.substring(7, 30)));
    }
}
