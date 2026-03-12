package info.fishfind.auth.exception;

import org.springframework.http.HttpStatus;

public class ApiException extends RuntimeException {
    private final HttpStatus status;

    /**
     * Creates an API exception carrying an HTTP status for the response layer.
     *
     * @param status HTTP status to return
     * @param message error message payload
     */
    public ApiException(HttpStatus status, String message) {
        super(message);
        this.status = status;
    }

    /**
     * Returns the HTTP status associated with this exception.
     *
     * @return response status
     */
    public HttpStatus getStatus() {
        return status;
    }
}
