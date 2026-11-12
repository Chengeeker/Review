package com.review.weiboauth;

import android.content.Context;
import android.util.Log;

import java.util.LinkedHashMap;
import java.util.Map;

public final class WeiboAuthManager {
    private static final String TAG = "WeiboAuth";
    private final Context context;
    private final EncryptedSessionStore sessionStore;
    private WeiboSession pendingSession;
    private WeiboSession activeSession;
    private long readRetryAt;
    private String sessionReadError;
    private WeiboSession oauthVerifiedSession;
    private long oauthVerifiedUntil;
    private long oauthRenewRetryAt;
    private long oauthFeedRetryAt;

    public WeiboAuthManager(Context context) {
        this.context = context.getApplicationContext();
        this.sessionStore = new EncryptedSessionStore(this.context);
    }

    private synchronized WeiboSession getActiveSession() {
        if (activeSession != null) return activeSession;
        try {
            activeSession = sessionStore.load();
            sessionReadError = null;
        } catch (Throwable t) {
            sessionReadError = t.getMessage();
            Log.w(TAG, "Native encrypted session unavailable (" + t.getClass().getSimpleName() + ")");
        }
        return activeSession;
    }

    public synchronized String getSessionReadError() { return sessionReadError; }

    public synchronized boolean hasNativeSession() {
        WeiboSession session = getActiveSession();
        return session != null && session.gsid != null && !session.gsid.isEmpty();
    }

    public synchronized boolean hasNativeSessionFor(String uid) {
        WeiboSession session = getActiveSession();
        return session != null && uid.equals(session.uid) && session.hasNativeLoginProof();
    }

    public synchronized String requestApi(String endpoint, Map<String, String> params) throws Exception {
        WeiboSession session = getActiveSession();
        if (session == null || session.gsid == null || session.gsid.isEmpty()) {
            throw new WeiboApi.ApiFailure("session_missing", 401, "none", "未登录或缺少原生会话");
        }
        long now = android.os.SystemClock.elapsedRealtime();
        if (now < readRetryAt) {
            throw new WeiboApi.ApiFailure("native_read_rejected", 0, "-105", "");
        }
        try {
            return api().request(session, endpoint, params);
        } catch (WeiboApi.ApiFailure failure) {
            if ("native_read_rejected".equals(failure.category) && "-105".equals(failure.responseCode)) {
                readRetryAt = android.os.SystemClock.elapsedRealtime() + 60_000;
            }
            throw failure;
        }
    }

    public synchronized Map<String, Object> requestSmsCode(String phone, String area) throws Exception {
        WeiboApi.SmsCodeResult response = api().requestSmsCode(phone, area);
        Map<String, Object> result = new LinkedHashMap<>();
        result.put("sent", true);
        result.put("number", response.number);
        return result;
    }

    public synchronized Map<String, Object> loginWithSms(
            String phone, String area, String number, String smsCode) throws Exception {
        pendingSession = null;
        WeiboApi.ApiResult response = api().loginWithSms(phone, area, number, smsCode);
        pendingSession = response.session;
        return pendingLoginResult();
    }

    public synchronized Map<String, Object> loginWithPassword(String account, String password)
            throws Exception {
        pendingSession = null;
        WeiboApi.ApiResult response = api().loginWithPassword(account, password);
        pendingSession = response.session;
        return pendingLoginResult();
    }

    private Map<String, Object> pendingLoginResult() {
        Map<String, Object> result = new LinkedHashMap<>();
        result.put("uid", pendingSession.uid);
        result.put("cookie", pendingSession.cookie);
        result.put("desktopCookie", pendingSession.desktopCookie);
        result.put("mobileCookie", pendingSession.mobileCookie);
        result.put("nativeVerified", pendingSession.hasNativeLoginProof());
        return result;
    }

    public synchronized boolean verifyPendingNativeSession(String uid) throws Exception {
        if (pendingSession == null || !uid.equals(pendingSession.uid)
                || pendingSession.gsid == null || pendingSession.gsid.isEmpty()) return false;
        if (pendingSession.hasNativeLoginProof()) return true;
        WeiboSession verified = api().verifyNativeSession(pendingSession);
        if (verified == null || !verified.hasNativeLoginProof()) return false;
        pendingSession = verified;
        return true;
    }

    public synchronized boolean verifyActiveOAuthAccount(String uid) throws Exception {
        return withOAuthRenewal(uid, this::confirmOAuthAccount) == Boolean.TRUE;
    }

    private boolean confirmOAuthAccount(WeiboSession session) throws Exception {
        long now = android.os.SystemClock.elapsedRealtime();
        if (oauthVerifiedSession == session && now < oauthVerifiedUntil) return true;
        if (!session.hasOAuthToken()) return false;
        if (!matchesOAuthAccount(session.uid, api().readOAuth(session, "account/get_uid", java.util.Collections.emptyMap()))) return false;
        oauthVerifiedSession = session;
        oauthVerifiedUntil = now + 300_000;
        return true;
    }

    static boolean matchesOAuthAccount(String uid, org.json.JSONObject response) {
        String returned = response.optString("uid");
        return returned.matches("[1-9][0-9]*") && returned.equals(uid);
    }

    public synchronized String requestOAuthFollowing(String uid, Map<String, String> params) throws Exception {
        return withOAuthRenewal(uid, session -> {
            if (android.os.SystemClock.elapsedRealtime() < oauthFeedRetryAt) {
                throw new WeiboApi.ApiFailure("oauth_read_rejected", 403, "10014", "");
            }
            if (!confirmOAuthAccount(session)) return null;
            try {
                return api().readOAuth(session, "statuses/home_timeline", params).toString();
            } catch (WeiboApi.ApiFailure failure) {
                if ("10014".equals(failure.responseCode)) oauthFeedRetryAt = android.os.SystemClock.elapsedRealtime() + 300_000;
                throw failure;
            }
        });
    }

    private interface OAuthRead<T> {
        T read(WeiboSession session) throws Exception;
    }

    private <T> T withOAuthRenewal(String uid, OAuthRead<T> operation) throws Exception {
        WeiboSession session = getActiveSession();
        if (session == null || !uid.equals(session.uid)) return null;
        try {
            return operation.read(session);
        } catch (WeiboApi.ApiFailure failure) {
            boolean expired = "21327".equals(failure.responseCode);
            if (expired || failure.httpCode == 401 || "21332".equals(failure.responseCode)) oauthVerifiedSession = null;
            if (!expired) throw failure;
            WeiboSession renewed = renewOAuth(session);
            if (renewed == null) throw failure;
            return operation.read(renewed);
        }
    }

    private WeiboSession renewOAuth(WeiboSession session) {
        long now = android.os.SystemClock.elapsedRealtime();
        if (now < oauthRenewRetryAt || session.gsid == null || session.gsid.isEmpty()) return null;
        oauthRenewRetryAt = now + 60_000;
        try {
            WeiboSession candidate = session.withRenewedOAuth(api().requestNativeOAuth(session), System.currentTimeMillis());
            if (candidate == null || !confirmOAuthAccount(candidate)) {
                Log.i(TAG, "OAuth renewal did not return a verifiable replacement");
                return null;
            }
            sessionStore.save(candidate);
            activeSession = candidate;
            oauthFeedRetryAt = 0;
            return candidate;
        } catch (Exception failure) {
            Log.i(TAG, "OAuth renewal unsuccessful: " + failure.getClass().getSimpleName());
            return null;
        }
    }

    public synchronized boolean acceptPendingSession() throws Exception {
        if (pendingSession == null) return false;
        sessionStore.save(pendingSession, true);
        sessionReadError = null;
        activeSession = pendingSession;
        oauthVerifiedSession = null;
        oauthRenewRetryAt = 0;
        oauthFeedRetryAt = 0;
        readRetryAt = 0;
        pendingSession = null;
        return true;
    }

    public synchronized void discardPendingSession() {
        pendingSession = null;
    }

    public synchronized Map<String, Object> restoreSession() {
        try {
            WeiboSession session = getActiveSession();
            if (session == null) return null;

            Map<String, Object> result = new LinkedHashMap<>();
            result.put("uid", session.uid);
            result.put("cookie", session.cookie);
            result.put("desktopCookie", session.desktopCookie);
            result.put("mobileCookie", session.mobileCookie);
            result.put("refreshed", false);
            return result;
        } catch (Throwable t) {
            Log.w(TAG, "Unexpected error in restoreSession (" + t.getClass().getSimpleName() + ")", t);
            return null;
        }
    }

    public synchronized void logout() throws Exception {
        activeSession = null;
        oauthVerifiedSession = null;
        oauthRenewRetryAt = 0;
        oauthFeedRetryAt = 0;
        readRetryAt = 0;
        pendingSession = null;
        sessionStore.clear();
        sessionReadError = null;
    }

    public synchronized String exportBackupSession(String uid) {
        WeiboSession session = getActiveSession();
        if (sessionReadError != null) throw new IllegalStateException(sessionReadError);
        if (session == null) return null;
        if (!session.uid.equals(uid)) throw new IllegalArgumentException("备份账号与原生会话不一致");
        return session.toJson().toString();
    }

    public synchronized boolean preserveBeforeLogin() throws Exception {
        return sessionStore.preserveBeforeReplacement(true);
    }

    public synchronized String encryptedBackupSnapshot() { return sessionStore.encryptedSnapshot(); }
    public synchronized void restoreEncryptedBackupSnapshot(String value) throws Exception {
        sessionStore.restoreEncryptedSnapshot(value); activeSession = null; oauthVerifiedSession = null; pendingSession = null;
    }

    public String verifyBackupSession(String json, String uid) throws Exception {
        WeiboSession candidate = WeiboSession.fromJson(new org.json.JSONObject(json));
        if (!candidate.hasRequiredFields() || !candidate.uid.equals(uid)) throw new IllegalArgumentException("无效的备份原生会话");
        WeiboSession verified = api().verifyNativeSession(candidate);
        if (verified == null || !verified.hasRequiredFields() || !verified.uid.equals(uid)) throw new IllegalArgumentException("备份账号校验不匹配");
        return verified.toJson().toString();
    }

    public synchronized boolean restoreBackupSession(String json, String uid) throws Exception {
        if (json == null) {
            sessionStore.preserveBeforeReplacement(true);
            logout();
            return true;
        }
        WeiboSession session = WeiboSession.fromJson(new org.json.JSONObject(json));
        if (!session.hasRequiredFields() || !session.uid.equals(uid)) {
            throw new IllegalArgumentException("无效的备份原生会话");
        }
        sessionStore.save(session, true);
        sessionReadError = null;
        activeSession = session;
        oauthVerifiedSession = null;
        oauthRenewRetryAt = 0;
        oauthFeedRetryAt = 0;
        readRetryAt = 0;
        pendingSession = null;
        return true;
    }

    private WeiboApi api() throws Exception {
        return new WeiboApi(context, NativeRuntime.get(context));
    }
}
