package com.fishfind.docapi.web;

import com.fishfind.docapi.service.InvalidDocumentException;
import com.twelvemonkeys.imageio.plugins.webp.WebPImageReaderSpi;

import javax.imageio.IIOImage;
import javax.imageio.ImageIO;
import javax.imageio.ImageReadParam;
import javax.imageio.ImageReader;
import javax.imageio.ImageWriteParam;
import javax.imageio.ImageWriter;
import javax.imageio.spi.IIORegistry;
import javax.imageio.stream.ImageInputStream;
import javax.imageio.stream.ImageOutputStream;
import java.awt.Color;
import java.awt.Graphics2D;
import java.awt.image.BufferedImage;
import java.io.ByteArrayInputStream;
import java.io.ByteArrayOutputStream;
import java.io.IOException;
import java.util.Iterator;

/**
 * Catch-log photo bytes: the format checks and the WebP/PNG to JPEG conversion behind
 * {@code POST /api/v1/catch/{id}/photo}.
 *
 * <p><strong>Same rules as the portal's upload</strong> ({@code CatchMemoEdit.OnPostPhotoAsync}): at most
 * {@value #MAX_BYTES} bytes, stored as JPEG, because the catch log serves a stored photo only when it is a JPEG.
 * A JPEG (by its FF D8 FF signature, not the declared type) is stored as sent. A WebP or PNG (news sites often
 * serve only WebP) is decoded and re-encoded as a JPEG at quality {@value #JPEG_QUALITY}, on white where it is
 * transparent; an image over {@value #MAX_PIXELS} pixels is refused before it is decoded.
 *
 * <p>Until 1.43.0 this class also downloaded the image for the MCP tool {@code add_catch_log_photo}. The MCP
 * server moved to its own service (mcp-env, on the cproxy droplet), which now downloads the image itself and
 * posts the bytes here, so docapi makes no outbound fetch of a URL a model chose.
 */
final class CatchPhotoImage {

    static final int MAX_BYTES = 5_000_000;
    static final int MAX_PIXELS = 40_000_000;
    static final float JPEG_QUALITY = 0.9f;

    static {
        // Registered by hand: ImageIO's own plugin scan does not see a jar nested in the Spring Boot fat jar.
        IIORegistry.getDefaultInstance().registerServiceProvider(new WebPImageReaderSpi());
    }

    private CatchPhotoImage() {
    }

    /** The image as a JPEG: a JPEG as it is, a WebP or PNG converted; anything else is the caller's error. */
    static byte[] asJpeg(byte[] image) {
        if (isJpeg(image)) return image;
        if (isWebp(image) || isPng(image)) return toJpeg(image);
        throw new InvalidDocumentException("The photo must be a JPEG, WebP or PNG");
    }

    static boolean isJpeg(byte[] b) {
        return b.length >= 3 && (b[0] & 0xff) == 0xff && (b[1] & 0xff) == 0xd8 && (b[2] & 0xff) == 0xff;
    }

    static boolean isPng(byte[] b) {
        return b.length >= 8 && (b[0] & 0xff) == 0x89 && b[1] == 'P' && b[2] == 'N' && b[3] == 'G';
    }

    static boolean isWebp(byte[] b) {
        return b.length >= 12 && b[0] == 'R' && b[1] == 'I' && b[2] == 'F' && b[3] == 'F'
                && b[8] == 'W' && b[9] == 'E' && b[10] == 'B' && b[11] == 'P';
    }

    /** A WebP or PNG re-encoded as a JPEG; any decode failure is the caller's (another URL), never a fault. */
    static byte[] toJpeg(byte[] image) {
        BufferedImage decoded;
        try (ImageInputStream in = ImageIO.createImageInputStream(new ByteArrayInputStream(image))) {
            Iterator<ImageReader> readers = ImageIO.getImageReaders(in);
            if (!readers.hasNext()) {
                throw new InvalidDocumentException("The image format cannot be read");
            }
            ImageReader reader = readers.next();
            try {
                reader.setInput(in, true, true);
                long pixels = (long) reader.getWidth(0) * reader.getHeight(0);
                if (pixels > MAX_PIXELS) {
                    throw new InvalidDocumentException("The image is larger than " + MAX_PIXELS / 1_000_000
                            + " megapixels");
                }
                ImageReadParam param = reader.getDefaultReadParam();
                decoded = reader.read(0, param);
            } finally {
                reader.dispose();
            }
        } catch (IOException | RuntimeException ex) {
            if (ex instanceof InvalidDocumentException invalid) throw invalid;
            throw new InvalidDocumentException("The image could not be decoded: " + ex.getMessage());
        }
        BufferedImage rgb = new BufferedImage(decoded.getWidth(), decoded.getHeight(), BufferedImage.TYPE_INT_RGB);
        Graphics2D g = rgb.createGraphics();
        try {
            g.drawImage(decoded, 0, 0, Color.WHITE, null);
        } finally {
            g.dispose();
        }
        ByteArrayOutputStream out = new ByteArrayOutputStream();
        ImageWriter writer = ImageIO.getImageWritersByFormatName("jpeg").next();
        try (ImageOutputStream ios = ImageIO.createImageOutputStream(out)) {
            writer.setOutput(ios);
            ImageWriteParam param = writer.getDefaultWriteParam();
            param.setCompressionMode(ImageWriteParam.MODE_EXPLICIT);
            param.setCompressionQuality(JPEG_QUALITY);
            writer.write(null, new IIOImage(rgb, null, null), param);
        } catch (IOException ex) {
            throw new IllegalStateException("JPEG encoding failed", ex);
        } finally {
            writer.dispose();
        }
        byte[] jpeg = out.toByteArray();
        if (jpeg.length > MAX_BYTES) {
            throw new InvalidDocumentException("The image is larger than " + MAX_BYTES / 1_000_000 + " MB as a JPEG");
        }
        return jpeg;
    }
}
