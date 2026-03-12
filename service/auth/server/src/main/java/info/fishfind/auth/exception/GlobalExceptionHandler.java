package info.fishfind.auth.exception;

import info.fishfind.auth.api.dto.AuthDtos;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.validation.FieldError;
import org.springframework.web.bind.MethodArgumentNotValidException;
import org.springframework.web.bind.annotation.ExceptionHandler;
import org.springframework.web.bind.annotation.RestControllerAdvice;

import java.util.stream.Collectors;

@RestControllerAdvice
public class GlobalExceptionHandler {

    /**
     * Converts domain-level API exceptions into JSON error responses.
     *
     * @param ex application exception
     * @return error response entity
     */
    @ExceptionHandler(ApiException.class)
    public ResponseEntity<AuthDtos.ErrorResponse> handleApiException(ApiException ex) {
        return ResponseEntity.status(ex.getStatus()).body(new AuthDtos.ErrorResponse(ex.getMessage()));
    }

    /**
     * Flattens validation errors into a single bad-request payload.
     *
     * @param ex validation exception raised by Spring
     * @return error response entity
     */
    @ExceptionHandler(MethodArgumentNotValidException.class)
    public ResponseEntity<AuthDtos.ErrorResponse> handleValidation(MethodArgumentNotValidException ex) {
        var message = ex.getBindingResult().getFieldErrors().stream()
                .map(FieldError::getDefaultMessage)
                .collect(Collectors.joining(", "));
        return ResponseEntity.badRequest().body(new AuthDtos.ErrorResponse(message));
    }

    /**
     * Returns a generic internal-server-error payload for unhandled exceptions.
     *
     * @param ex unexpected exception
     * @return error response entity
     */
    @ExceptionHandler(Exception.class)
    public ResponseEntity<AuthDtos.ErrorResponse> handleUnexpected(Exception ex) {
        return ResponseEntity.status(HttpStatus.INTERNAL_SERVER_ERROR)
                .body(new AuthDtos.ErrorResponse("Something went wrong!"));
    }
}
