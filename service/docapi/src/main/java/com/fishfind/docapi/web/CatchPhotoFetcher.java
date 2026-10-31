package com.fishfind.docapi.web;

import com.fishfind.docapi.service.InvalidDocumentException;
import com.twelvemonkeys.imageio.plugins.webp.WebPImageReaderSpi;
import org.springframework.stereotype.Component;

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
import java.io.InputStream;
import java.net.Inet6Address;
import java.net.InetAddress;
import java.net.URI;
import java.net.URISyntaxException;
import java.net.UnknownHostException;
import java.net.http.HttpClient;
import java.net.http.HttpRequest;
import java.net.http.HttpResponse;
import java.time.Duration;
import java.util.Iterator;
import java.util.Locale;

/**
 * Downloads the photo for the MCP tool {@code add_catch_log_photo}, so the image never passes through the model.
 *
 * <p><strong>This is a server-side fetch of a URL a model chose</strong>, so it is fenced in: https only, port
 * 443, at most {@value #MAX_REDIRECTS} redirects (each one checked again), and every address the host resolves
 * to must be public — never loopback, private, link-local, CGNAT or multicast, which keeps it off the VPC and the
 * droplet itself. What remains is a DNS-rebinding window between the check and the connect; the tool is
 * admin-only, which is what makes that acceptable.
 *
 * <p><strong>Same rules as the portal's upload</strong> ({@code CatchMemoEdit.OnPostPhotoAsync}): at most
 * {@value #MAX_BYTES} bytes, stored as JPEG, because the catch log serves a stored photo only when it is a JPEG.
 * A JPEG (by its FF D8 FF signature, not the declared type) is stored as downloaded. Since 1.30.0 a WebP or PNG
 * (news sites often serve only WebP) is decoded and re-encoded as a JPEG at quality {@value #JPEG_QUALITY}, on
 * white where it is transparent; an image over {@value #MAX_PIXELS} pixels is refused before it is decoded.
 *
 * <p><strong>Time budget.</strong> cproxy gives a request 10 s; the download gets {@value #TIMEOUT_SECONDS} s
 * of it, leaving the rest for the SQL insert.
 */
@Component
public class CatchPhotoFetcher {

    static final int MAX_BYTES = 5_000_000;
    static final int MAX_REDIRECTS = 3;
    static final int TIMEOUT_SECONDS = 6;
    static final int MAX_PIXELS = 40_000_000;
    static final float JPEG_QUALITY = 0.9f;

    static {
        // Registered by hand: ImageIO's own plugin scan does not see a jar nested in the Spring Boot fat jar.
        IIORegistry.getDefaultInstance().registerServiceProvider(new WebPImageReaderSpi());
    }

    private final HttpClient client = HttpClient.newBuilder()
            .followRedirects(HttpClient.Redirect.NEVER)
            .connectTimeout(Duration.ofSeconds(3))
            .build();

    /**
     * The image at {@code url}.
     *
     * @throws InvalidDocumentException for every refusal or download failure: all of them are the caller's
     *                                  to correct (another URL), none is a database fault
     */
    public byte[] fetch(String url) {
        URI uri = check(url);
        for (int hop = 0; ; hop++) {
            HttpResponse<InputStream> response = get(uri);
            int status = response.statusCode();
            if (status >= 300 && status < 400) {
                close(response);
                String location = response.headers().firstValue("Location").orElse(null);
                if (location == null || hop >= MAX_REDIRECTS) {
                    throw new InvalidDocumentException("imageUrl redirects too often or without a target");
                }
                uri = check(uri.resolve(location).toString());
                continue;
            }
            if (status != 200) {
                close(response);
                throw new InvalidDocumentException("imageUrl answered HTTP " + status);
            }
            return jpeg(response);
        }
    }

    /** A URL this fetcher may open, or a refusal saying why not. */
    static URI check(String url) {
        URI uri;
        try {
            uri = new URI(url);
        } catch (URISyntaxException ex) {
            throw new InvalidDocumentException("imageUrl is not a valid URL");
        }
        if (!"https".equalsIgnoreCase(uri.getScheme()) || uri.getHost() == null) {
            throw new InvalidDocumentException("imageUrl must be an https URL");
        }
        if (uri.getPort() != -1 && uri.getPort() != 443) {
            throw new InvalidDocumentException("imageUrl must use the standard https port");
        }
        if (uri.getUserInfo() != null) {
            throw new InvalidDocumentException("imageUrl must not carry credentials");
        }
        InetAddress[] addresses;
        try {
            addresses = InetAddress.getAllByName(uri.getHost());
        } catch (UnknownHostException ex) {
            throw new InvalidDocumentException("imageUrl host " + uri.getHost() + " does not resolve");
        }
        for (InetAddress address : addresses) {
            if (!isPublic(address)) {
                throw new InvalidDocumentException("imageUrl must point at a public internet host");
            }
        }
        return uri;
    }

    static boolean isPublic(InetAddress a) {
        if (a.isAnyLocalAddress() || a.isLoopbackAddress() || a.isLinkLocalAddress() || a.isSiteLocalAddress()
                || a.isMulticastAddress()) {
            return false;
        }
        byte[] b = a.getAddress();
        if (a instanceof Inet6Address) {
            return (b[0] & 0xfe) != 0xfc;                                   // fc00::/7 unique local
        }
        int first = b[0] & 0xff;
        int second = b[1] & 0xff;
        return first != 0                                                    // 0.0.0.0/8
                && !(first == 100 && second >= 64 && second <= 127)          // 100.64.0.0/10 CGNAT
                && !(first == 192 && second == 0 && (b[2] & 0xff) == 0)      // 192.0.0.0/24
                && !(first == 198 && (second == 18 || second == 19))         // 198.18.0.0/15
                && first < 240;                                              // 240.0.0.0/4 reserved
    }

    private HttpResponse<InputStream> get(URI uri) {
        HttpRequest request = HttpRequest.newBuilder(uri)
                .timeout(Duration.ofSeconds(TIMEOUT_SECONDS))
                .header("User-Agent", "FishFind-docapi (catch log photo)")
                .header("Accept", "image/jpeg,image/webp,image/png;q=0.9,image/*;q=0.8")
                .GET()
                .build();
        try {
            return client.send(request, HttpResponse.BodyHandlers.ofInputStream());
        } catch (IOException ex) {
            throw new InvalidDocumentException("imageUrl could not be downloaded: " + describe(ex));
        } catch (InterruptedException ex) {
            Thread.currentThread().interrupt();
            throw new InvalidDocumentException("imageUrl download was interrupted");
        }
    }

    private static byte[] jpeg(HttpResponse<InputStream> response) {
        byte[] bytes;
        try (InputStream in = response.body()) {
            bytes = in.readNBytes(MAX_BYTES + 1);
        } catch (IOException ex) {
            throw new InvalidDocumentException("imageUrl could not be downloaded: " + describe(ex));
        }
        if (bytes.length > MAX_BYTES) {
            throw new InvalidDocumentException("The image is larger than " + MAX_BYTES / 1_000_000 + " MB");
        }
        if (isJpeg(bytes)) {
            return bytes;
        }
        if (isWebp(bytes) || isPng(bytes)) {
            return toJpeg(bytes);
        }
        String type = response.headers().firstValue("Content-Type").orElse("unknown").toLowerCase(Locale.ROOT);
        throw new InvalidDocumentException("The image is not a JPEG, WebP or PNG (Content-Type " + type + ")");
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

    private static void close(HttpResponse<InputStream> response) {
        try {
            response.body().close();
        } catch (IOException ignored) {
            // nothing more to read from a response that is being discarded
        }
    }

    private static String describe(IOException ex) {
        return ex.getMessage() == null ? ex.getClass().getSimpleName() : ex.getMessage();
    }
}
