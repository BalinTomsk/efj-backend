package com.fishfind.docapi.web;

import com.fishfind.docapi.service.InvalidDocumentException;
import org.junit.jupiter.api.Test;

import java.net.InetAddress;

import static org.junit.jupiter.api.Assertions.assertFalse;
import static org.junit.jupiter.api.Assertions.assertThrows;
import static org.junit.jupiter.api.Assertions.assertTrue;

class CatchPhotoFetcherTest {

    @Test
    void onlyPublicAddressesAreAllowed() throws Exception {
        for (String address : new String[] {"127.0.0.1", "10.1.2.3", "172.16.0.1", "192.168.1.1", "169.254.169.254",
                "100.64.0.1", "0.0.0.0", "224.0.0.1", "::1", "fd00::1", "fe80::1"}) {
            assertFalse(CatchPhotoFetcher.isPublic(InetAddress.getByName(address)), address);
        }
        for (String address : new String[] {"8.8.8.8", "104.16.1.1", "2606:4700::1111"}) {
            assertTrue(CatchPhotoFetcher.isPublic(InetAddress.getByName(address)), address);
        }
    }

    @Test
    void onlyPlainHttpsUrlsPass() {
        for (String url : new String[] {"http://8.8.8.8/a.jpg", "ftp://8.8.8.8/a.jpg", "https://8.8.8.8:8443/a.jpg",
                "https://user:pw@8.8.8.8/a.jpg", "https://127.0.0.1/a.jpg", "https://[::1]/a.jpg", "not a url",
                "https:///a.jpg"}) {
            assertThrows(InvalidDocumentException.class, () -> CatchPhotoFetcher.check(url), url);
        }
        CatchPhotoFetcher.check("https://8.8.8.8/a.jpg");
    }

    /** A 1x1 lossless WebP. */
    private static final String WEBP = "UklGRhoAAABXRUJQVlA4TA0AAAAvAAAAEAcQERGIiP4HAA==";

    @Test
    void aWebpBecomesAJpeg() {
        byte[] webp = java.util.Base64.getDecoder().decode(WEBP);
        assertTrue(CatchPhotoFetcher.isWebp(webp));
        byte[] jpeg = CatchPhotoFetcher.toJpeg(webp);
        assertTrue(CatchPhotoFetcher.isJpeg(jpeg));
    }

    @Test
    void aTransparentPngBecomesAJpeg() throws Exception {
        java.awt.image.BufferedImage img = new java.awt.image.BufferedImage(4, 3, java.awt.image.BufferedImage.TYPE_INT_ARGB);
        java.io.ByteArrayOutputStream png = new java.io.ByteArrayOutputStream();
        javax.imageio.ImageIO.write(img, "png", png);
        assertTrue(CatchPhotoFetcher.isPng(png.toByteArray()));
        byte[] jpeg = CatchPhotoFetcher.toJpeg(png.toByteArray());
        assertTrue(CatchPhotoFetcher.isJpeg(jpeg));
        java.awt.image.BufferedImage back = javax.imageio.ImageIO.read(new java.io.ByteArrayInputStream(jpeg));
        org.junit.jupiter.api.Assertions.assertEquals(4, back.getWidth());
    }

    @Test
    void garbageWithAWebpHeaderIsTheCallersError() {
        byte[] bad = "RIFF\0\0\0\0WEBPnot an image".getBytes(java.nio.charset.StandardCharsets.ISO_8859_1);
        assertThrows(InvalidDocumentException.class, () -> CatchPhotoFetcher.toJpeg(bad));
    }
}
