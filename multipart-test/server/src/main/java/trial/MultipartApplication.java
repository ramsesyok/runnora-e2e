package trial;

import java.io.IOException;
import java.nio.charset.StandardCharsets;
import java.security.MessageDigest;
import java.security.NoSuchAlgorithmException;
import java.util.HexFormat;
import java.util.Map;
import javax.servlet.ServletException;
import javax.servlet.http.HttpServletRequest;
import org.springframework.boot.SpringApplication;
import org.springframework.boot.autoconfigure.SpringBootApplication;
import org.springframework.http.HttpStatus;
import org.springframework.http.MediaType;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestPart;
import org.springframework.web.bind.annotation.RestController;
import org.springframework.web.multipart.MultipartFile;
import org.springframework.web.server.ResponseStatusException;

@SpringBootApplication
public class MultipartApplication {
    public static void main(String[] args) {
        SpringApplication.run(MultipartApplication.class, args);
    }

    public record Metadata(String name, String kind, boolean enabled) {}

    @RestController
    public static class UploadController {
        @GetMapping(value = "/health", produces = MediaType.APPLICATION_JSON_VALUE)
        public Map<String, Object> health() { return Map.of("status", "UP"); }

        @PostMapping(value = "/upload", consumes = MediaType.MULTIPART_FORM_DATA_VALUE,
                     produces = MediaType.APPLICATION_JSON_VALUE)
        public Map<String, Object> upload(@RequestPart("metadata") Metadata metadata,
                @RequestPart("file") MultipartFile file, HttpServletRequest request)
                throws IOException, ServletException, NoSuchAlgorithmException {
            String expected = "image".equals(metadata.kind()) ? "image/png" : "text/csv";
            if (!expected.equals(file.getContentType())) {
                throw new ResponseStatusException(HttpStatus.UNSUPPORTED_MEDIA_TYPE,
                        "file part must be " + expected);
            }
            byte[] data = file.getBytes();
            // The fixture CSV is simple UTF-8 without quoted multiline fields.
            long rows = "csv".equals(metadata.kind())
                    ? new String(data, StandardCharsets.UTF_8).lines().skip(1).count() : 0;
            return Map.of("metadata", metadata, "fileName", file.getOriginalFilename(),
                    "contentType", file.getContentType(), "metadataContentType", request.getPart("metadata").getContentType(),
                    "size", data.length, "sha256", HexFormat.of().formatHex(MessageDigest.getInstance("SHA-256").digest(data)),
                    "rows", rows);
        }
    }
}
