package com.review.weiboauth;

import android.content.Context;
import android.util.Log;
import android.webkit.CookieManager;

import java.util.LinkedHashMap;
import java.util.Map;

public final class WeiboAuthManager {
    private static final String TAG = "WeiboAuth";
    private final Context context;
    private final EncryptedSessionStore sessionStore;
    private WeiboSession pendingSession;

    public WeiboAuthManager(Context context) {
        this.context = context.getApplicationContext();
        this.sessionStore = new EncryptedSessionStore(this.context);
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
        syncCookieManager(response.session.cookie);
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
        syncCookieManager(response.session.cookie);
        Map<String, Object> result = new LinkedHashMap<>();
        result.put("uid", response.session.uid);
        result.put("cookie", response.session.cookie);
        return result;
    }

    public synchronized boolean acceptPendingSession() throws Exception {
        if (pendingSession == null) return false;
        sessionStore.save(pendingSession);
        pendingSession = null;
        return true;
    }

    public synchronized void discardPendingSession() {
        pendingSession = null;
    }

    public synchronized Map<String, Object> restoreSession() throws Exception {
        WeiboSession session = sessionStore.load();
        if (session == null) return null;

        boolean refreshed = false;
        if (session.shouldRefresh(System.currentTimeMillis())) {
            session = api().refresh(session).session;
            sessionStore.save(session);
            refreshed = true;
        }

        syncCookieManager(session.cookie);

        Map<String, Object> result = new LinkedHashMap<>();
        result.put("uid", session.uid);
        result.put("cookie", session.cookie);
        result.put("refreshed", refreshed);
        return result;
    }

    public synchronized void logout() throws Exception {
        pendingSession = null;
        sessionStore.clear();
        clearCookieManager();
    }

    private void syncCookieManager(String cookie) {
        if (cookie == null || cookie.trim().isEmpty()) return;
        try {
            CookieManager cookieManager = CookieManager.getInstance();
            cookieManager.setAcceptCookie(true);
            String[] domains = {
                "https://weibo.com",
                "https://m.weibo.cn",
                "https://weibo.cn",
                "https://api.weibo.cn",
                "https://login.sina.com.cn",
                ".weibo.com",
                ".weibo.cn",
                ".sina.com.cn"
            };
            String[] pairs = cookie.split(";");
            for (String domain : domains) {
                for (String rawPair : pairs) {
                    String pair = rawPair.trim();
                    if (!pair.isEmpty()) {
                        cookieManager.setCookie(domain, pair);
                    }
                }
            }
            cookieManager.flush();
        } catch (Throwable t) {
            Log.w(TAG, "Failed to sync CookieManager (" + t.getClass().getSimpleName() + ")");
        }
    }

    private void clearCookieManager() {
        try {
            CookieManager cookieManager = CookieManager.getInstance();
            cookieManager.removeAllCookies(null);
            cookieManager.flush();
        } catch (Throwable t) {
            Log.w(TAG, "Failed to clear CookieManager (" + t.getClass().getSimpleName() + ")");
        }
    }

    private WeiboApi api() throws Exception {
        return new WeiboApi(context, NativeRuntime.get(context));
    }
}
