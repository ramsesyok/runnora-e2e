package trial;

import java.io.IOException;
import java.nio.charset.StandardCharsets;
import java.security.MessageDigest;
import java.util.HexFormat;
import java.util.Map;
import java.util.concurrent.atomic.AtomicInteger;
import javax.servlet.FilterChain;
import javax.servlet.ServletException;
import javax.servlet.http.HttpServletRequest;
import javax.servlet.http.HttpServletResponse;
import org.springframework.boot.SpringApplication;
import org.springframework.boot.autoconfigure.SpringBootApplication;
import org.springframework.context.annotation.Bean;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RestController;
import org.springframework.web.multipart.MultipartFile;
import org.springframework.web.filter.OncePerRequestFilter;
import trial.generated.api.MultipartUploadApi;
import trial.generated.model.Metadata1;
import trial.generated.model.Metadata2;
import trial.generated.model.UploadSummary;

@SpringBootApplication
public class GeneratedMultipartApplication {
    private static final AtomicInteger receivedUploads = new AtomicInteger();

    public static void main(String[] args) {
        SpringApplication.run(GeneratedMultipartApplication.class, args);
    }

    @Bean
    public OncePerRequestFilter countRequests() {
        return new OncePerRequestFilter() {
            @Override
            protected void doFilterInternal(HttpServletRequest request, HttpServletResponse response, FilterChain chain)
                    throws ServletException, IOException {
                if ("POST".equals(request.getMethod()) && "/generated/upload".equals(request.getRequestURI())) {
                    receivedUploads.incrementAndGet();
                }
                chain.doFilter(request, response);
            }
        };
    }

    @RestController
    public static class UploadController implements MultipartUploadApi {
        private final HttpServletRequest request;
        private final AtomicInteger handledUploads = new AtomicInteger();

        public UploadController(HttpServletRequest request) { this.request = request; }

        @GetMapping(value = "/health", produces = "application/json")
        public Map<String, Object> health() {
            return Map.of("status", "UP", "handledUploads", handledUploads.get(), "receivedUploads", receivedUploads.get());
        }

        // RequestMapping/RequestPart and the DTOs come only from generated code.
        @Override
        public ResponseEntity<UploadSummary> uploadMultipart(Metadata1 metadata1, Metadata2 metadata2, MultipartFile csv) {
            handledUploads.incrementAndGet();
            try {
                byte[] data = csv.getBytes();
                UploadSummary summary = new UploadSummary()
                    .metadata1(metadata1).metadata2(metadata2)
                    .fileName(csv.getOriginalFilename()).csvContentType(csv.getContentType())
                    .metadata1ContentType(request.getPart("metadata1").getContentType())
                    .metadata2ContentType(request.getPart("metadata2").getContentType())
                    .size((long) data.length)
                    .sha256(HexFormat.of().formatHex(MessageDigest.getInstance("SHA-256").digest(data)))
                    .rows(new String(data, StandardCharsets.UTF_8).lines().skip(1).count());
                return ResponseEntity.ok(summary);
            } catch (Exception ex) {
                throw new IllegalStateException("Failed to inspect uploaded parts", ex);
            }
        }
    }
}
