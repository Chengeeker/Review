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

    public WeiboAuthManager(Context context) {
        this.context = context.getApplicationContext();
        this.sessionStore = new EncryptedSessionStore(this.context);
    }

    private synchronized WeiboSession getActiveSession() {
        if (activeSession != null) return activeSession;
        try {
            activeSession = sessionStore.load();
        } catch (Throwable t) {
            Log.w(TAG, "Failed to load active session", t);
        }
        return activeSession;
    }

    public synchronized boolean hasNativeSession() {
        WeiboSession session = getActiveSession();
        return session != null && session.gsid != null && !session.gsid.isEmpty();
    }

    public synchronized String requestApi(String endpoint, Map<String, String> params) throws Exception {
        WeiboSession session = getActiveSession();
        if (session == null || session.gsid == null || session.gsid.isEmpty()) {
            throw new WeiboApi.ApiFailure("session_missing", 401, "none", "未登录或缺少原生会话");
        }
        return api().request(session, endpoint, params);
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
        Map<String, Object> result = new LinkedHashMap<>();
        result.put("uid", response.session.uid);
        result.put("cookie", response.session.cookie);
        return result;
    }

    public synchronized Map<String, Object> loginWithPassword(String account, String password)
            throws Exception {
        pendingSession = null;
        WeiboApi.ApiResult response = api().loginWithPassword(account, password);
        pendingSession = response.session;
        Map<String, Object> result = new LinkedHashMap<>();
        result.put("uid", response.session.uid);
        result.put("cookie", response.session.cookie);
        return result;
    }

    public synchronized boolean acceptPendingSession() throws Exception {
        if (pendingSession == null) return false;
        sessionStore.save(pendingSession);
        activeSession = pendingSession;
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
            result.put("refreshed", false);
            return result;
        } catch (Throwable t) {
            Log.w(TAG, "Unexpected error in restoreSession (" + t.getClass().getSimpleName() + ")", t);
            return null;
        }
    }

    public synchronized void logout() throws Exception {
        activeSession = null;
        pendingSession = null;
        sessionStore.clear();
    }

    private WeiboApi api() throws Exception {
        return new WeiboApi(context, NativeRuntime.get(context));
    }
}
