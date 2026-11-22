package com.fishfind.docapi.web;

import org.springframework.http.CacheControl;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RequestHeader;
import org.springframework.web.bind.annotation.RestController;

import java.util.LinkedHashMap;
import java.util.List;
import java.util.Locale;
import java.util.Map;

/**
 * {@code GET /api/v1/me} (1.42.0) — who cproxy says the caller is: {@code {role, userId, userType, userTypes}}.
 * <ul>
 *   <li>{@code role} — {@code guest | user | admin} ({@value ViewerRole#HEADER});</li>
 *   <li>{@code userId} — the account ({@value Caller#USER_HEADER}), {@code null} for a guest;</li>
 *   <li>{@code userType} — the account-type bitmask ({@value UserType#HEADER}: 1 registered, 2 paid, 4 scientist,
 *       8 editor, 16 ai_agent, 32 admin), {@code null} for a guest or while the type has not reached the mirror;</li>
 *   <li>{@code userTypes} — the same mask as codes, admin first ({@code []} when {@code userType} is null).</li>
 * </ul>
 * Headers only, no database read, never cached. The app (envfish-droid) uses it to refresh the account type it was
 * given at sign-in; it is also the end-to-end check that cproxy forwards the type.
 */
@RestController
public class MeController {

    /** @return the caller as cproxy stamped it */
    @GetMapping("/api/v1/me")
    public ResponseEntity<ApiResponse<Map<String, Object>>> me(
            @RequestHeader(value = ViewerRole.HEADER, required = false) String role,
            @RequestHeader(value = Caller.USER_HEADER, required = false) String user,
            @RequestHeader(value = UserType.HEADER, required = false) String type) {
        Caller caller = Caller.fromHeaders(role, user);
        Integer mask = caller.userId() == null ? null : UserType.maskFromHeader(type);
        Map<String, Object> body = new LinkedHashMap<>();
        body.put("role", caller.role().name().toLowerCase(Locale.ROOT));
        body.put("userId", caller.userId());
        body.put("userType", mask);
        body.put("userTypes", mask == null ? List.of() : UserType.codes(mask));
        return ResponseEntity.ok().cacheControl(CacheControl.noStore()).body(ApiResponse.ok(body));
    }
}
