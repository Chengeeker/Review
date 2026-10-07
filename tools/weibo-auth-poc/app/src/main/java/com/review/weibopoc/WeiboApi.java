package com.review.weibopoc;

import android.content.Context;
import android.net.ConnectivityManager;
import android.net.Network;
import android.net.NetworkCapabilities;
import android.os.Build;

import org.json.JSONObject;

import java.io.ByteArrayOutputStream;
import java.io.InputStream;
import java.net.HttpURLConnection;
import java.net.URL;
import java.nio.charset.StandardCharsets;
import java.util.LinkedHashMap;
import java.util.Locale;
import java.util.Map;
import java.util.UUID;

final class WeiboApi {
    private static final String API_ROOT = "https://api.weibo.cn/2/";
    private static final String REVIEW_CONFIG = "https://weibo.com/ajax/config/getconfig";
    private static final int TIMEOUT_MS = 20_000;
    private static final int MAX_RESPONSE_BYTES = 2 * 1024 * 1024;

    static final class ApiResult {
        final int httpCode;
        final String responseCode;
        final WeiboSession session;
        final boolean reviewApiAccepted;
        final boolean reviewUidMatches;

        ApiResult(int httpCode, String responseCode, WeiboSession session,
                  boolean reviewApiAccepted, boolean reviewUidMatches) {
            this.httpCode = httpCode;
            this.responseCode = responseCode;
            this.session = session;
            this.reviewApiAccepted = reviewApiAccepted;
            this.reviewUidMatches = reviewUidMatches;
        }
    }

    static final class ApiFailure extends Exception {
        final int httpCode;
        final String responseCode;
        final String category;

        ApiFailure(String category, int httpCode, String responseCode) {
            super(category);
            this.category = category;
            this.httpCode = httpCode;
            this.responseCode = responseCode;
        }
    }

    private final Context context;
    private final NativeRuntime nativeRuntime;

    WeiboApi(Context context, NativeRuntime nativeRuntime) {
        this.context = context.getApplicationContext();
        this.nativeRuntime = nativeRuntime;
    }

    ApiResult login(String account, String password, String captcha, String captchaCode) throws Exception {
        String passwordParam = NativeRuntime.password(password);
        String signature = nativeRuntime.loginSignature(account, password);
        password = null;

        Map<String, String> form = new LinkedHashMap<>();
        form.put("u", account);
        form.put("p", passwordParam);
        form.put("s", signature);
        if (!empty(captcha) && !empty(captchaCode)) {
            form.put("cpt", captcha);
            form.put("cptcode", captchaCode);
        }
        addCommonLoginForm(form);

        Map<String, String> query = new LinkedHashMap<>();
        query.put("getuser", "1");
        query.put("getoauth", "1");
        query.put("getcookie", "1");
        query.put("device_name", Build.MANUFACTURER + "-" + Build.MODEL);
        return sendSessionRequest("POST", "account/login", query, form, null);
    }

    ApiResult refresh(WeiboSession session) throws Exception {
        Map<String, String> query = new LinkedHashMap<>();
        query.put("c", "weicoabroad");
        query.put("s", nativeRuntime.oauthSignature(session.uid));
        query.put("i", nativeRuntime.oauthIValue());
        query.put("gsid", session.gsid);
        query.put("uid", session.uid);
        query.put("lang", "zh_CN");
        query.put("from", NativeRuntime.APP_KEY);
        return sendSessionRequest("GET", "account/getoauth", query, null, session);
    }

    ApiResult checkReviewApi(WeiboSession session) throws Exception {
        HttpURLConnection connection = open(REVIEW_CONFIG);
        int status;
        String body;
        try {
            connection.setRequestMethod("GET");
            connection.setRequestProperty("User-Agent", userAgent());
            connection.setRequestProperty("Cookie", session.cookie);
            String xsrf = cookieValue(session.cookie, "XSRF-TOKEN");
            if (!empty(xsrf)) connection.setRequestProperty("X-XSRF-TOKEN", xsrf);
            status = connection.getResponseCode();
            body = readBody(connection, status);
        } finally {
            connection.disconnect();
        }

        JSONObject json = parseJson(body);
        String responseCode = json == null ? "non_json" : responseCode(json);
        boolean accepted = json != null && desktopConfigShowsLoggedIn(json);
        String returnedUid = json == null ? "" : desktopUid(json);
        return new ApiResult(status, responseCode, null, accepted, session.uid.equals(returnedUid));
    }

    private ApiResult sendSessionRequest(String method, String endpoint, Map<String, String> query,
                                         Map<String, String> form, WeiboSession previous) throws Exception {
        query.put("aid", "7501641714");
        String noCumUrl = RequestData.addQuery(API_ROOT + endpoint, query);
        String pathWithQuery = new URL(noCumUrl).getFile();
        String cum = nativeRuntime.cum(pathWithQuery);
        query.put("cum", cum);
        String url = RequestData.addQuery(API_ROOT + endpoint, query);

        HttpURLConnection connection = open(url);
        int status;
        JSONObject json;
        try {
            connection.setRequestMethod(method);
            connection.setRequestProperty("User-Agent", userAgent());
            connection.setRequestProperty("X-Sessionid", UUID.randomUUID().toString());
            connection.setRequestProperty("Accept", "application/json");
            if (form != null) {
                connection.setDoOutput(true);
                connection.setRequestProperty("Content-Type", "application/x-www-form-urlencoded; charset=UTF-8");
                byte[] bytes = RequestData.encode(form).getBytes(StandardCharsets.UTF_8);
                try (java.io.OutputStream output = connection.getOutputStream()) {
                    output.write(bytes);
                }
            }
            status = connection.getResponseCode();
            json = parseJson(readBody(connection, status));
        } finally {
            connection.disconnect();
        }

        String responseCode = json == null ? "non_json" : responseCode(json);
        if (status < 200 || status >= 300 || json == null) {
            throw new ApiFailure("http_or_response_error", status, responseCode);
        }

        WeiboSession next = WeiboSession.parse(json, previous, System.currentTimeMillis());
        if (!next.hasRequiredFields()) {
            String category = containsCaptchaChallenge(json) ? "captcha_required" : "session_fields_missing";
            throw new ApiFailure(category, status, responseCode);
        }
        return new ApiResult(status, responseCode, next, false, false);
    }

    private void addCommonLoginForm(Map<String, String> form) {
        form.put("lang", "zh_CN");
        form.put("networktype", networkType());
        form.put("c", "android");
        form.put("from", "10B63950" + (isHarmonyOs() ? "60" : "10"));
        form.put("wm", "2468_1001");
        form.put("oldwm", oldWm());
        form.put("ua", Build.MANUFACTURER + "-" + Build.MODEL
                + "__weibo__11.6.3__android__android");
        form.put("v_p", "89");
        form.put("android_id", nativeRuntime.deviceId());
        form.put("wb_version", "5005");
        form.put("skin", "default");
        form.put("v_f", "2");
    }

    private String networkType() {
        ConnectivityManager manager = (ConnectivityManager) context.getSystemService(Context.CONNECTIVITY_SERVICE);
        Network active = manager == null ? null : manager.getActiveNetwork();
        NetworkCapabilities capabilities = active == null ? null : manager.getNetworkCapabilities(active);
        if (capabilities == null) return "N/A";
        if (capabilities.hasTransport(NetworkCapabilities.TRANSPORT_WIFI)) return "wifi";
        if (capabilities.hasTransport(NetworkCapabilities.TRANSPORT_CELLULAR)) return "mobile";
        return "unknown";
    }

    private static String oldWm() {
        String manufacturer = Build.MANUFACTURER.toUpperCase(Locale.ROOT);
        switch (manufacturer) {
            case "ONEPLUS": return "14038_0004";
            case "MEIZU": return "9848_0009";
            case "OPPO": return "9847_0002";
            case "VIVO": return "9856_0004";
            case "SMARTISAN": return "14010_0013";
            case "ZUK": return "20003_0002";
            case "SONY": return "9982_90002";
            case "XIAOMI": return "20005_0002";
            default: return "3333_1001";
        }
    }

    private static boolean isHarmonyOs() {
        try {
            Class.forName("com.huawei.system.BuildEx");
            return true;
        } catch (ClassNotFoundException ignored) {
            return false;
        }
    }

    private static String userAgent() {
        return Build.MODEL + "_" + Build.VERSION.RELEASE + "_weibo_11.6.3_android";
    }

    private static HttpURLConnection open(String url) throws Exception {
        HttpURLConnection connection = (HttpURLConnection) new URL(url).openConnection();
        connection.setConnectTimeout(TIMEOUT_MS);
        connection.setReadTimeout(TIMEOUT_MS);
        connection.setInstanceFollowRedirects(true);
        return connection;
    }

    private static String readBody(HttpURLConnection connection, int status) throws Exception {
        InputStream stream = status >= 400 ? connection.getErrorStream() : connection.getInputStream();
        if (stream == null) return "";
        try (InputStream input = stream; ByteArrayOutputStream output = new ByteArrayOutputStream()) {
            byte[] buffer = new byte[8192];
            int count;
            while ((count = input.read(buffer)) != -1) {
                if (output.size() + count > MAX_RESPONSE_BYTES) throw new IllegalStateException("response too large");
                output.write(buffer, 0, count);
            }
            return output.toString(StandardCharsets.UTF_8.name());
        }
    }

    private static JSONObject parseJson(String value) {
        try {
            return new JSONObject(value);
        } catch (Exception ignored) {
            return null;
        }
    }

    private static String responseCode(JSONObject json) {
        String code = json.optString("retcode", null);
        if (empty(code)) code = json.optString("errno", null);
        return empty(code) ? "none" : code;
    }

    private static boolean containsCaptchaChallenge(JSONObject json) {
        return json.has("cpt") || json.has("captcha") || json.has("captcha_url")
                || json.has("captcha_image") || "CAPTCHA_REQUIRED".equals(responseCode(json));
    }

    private static boolean desktopConfigShowsLoggedIn(JSONObject body) {
        if (body.optInt("ok", 0) == -100 || body.optString("url", "").toLowerCase(Locale.ROOT).contains("login")) {
            return false;
        }
        JSONObject data = body.optJSONObject("data");
        JSONObject user = data == null ? null : data.optJSONObject("user");
        if (user == null) user = body.optJSONObject("user");
        boolean flagPresent = (data != null && (data.has("islogin") || data.has("login")))
                || body.has("islogin") || body.has("login");
        boolean loggedIn = truthy(data == null ? null : data.opt("islogin"))
                || truthy(data == null ? null : data.opt("login"))
                || truthy(body.opt("islogin")) || truthy(body.opt("login"))
                || (!flagPresent && user != null);
        return loggedIn && !desktopUid(body).isEmpty();
    }

    private static String desktopUid(JSONObject body) {
        JSONObject data = body.optJSONObject("data");
        JSONObject user = data == null ? null : data.optJSONObject("user");
        if (user == null) user = body.optJSONObject("user");
        if (data != null) {
            String value = first(data.optString("uid", null), data.optString("id", null), data.optString("idstr", null));
            if (!empty(value) && !"0".equals(value)) return value;
        }
        return first(user == null ? null : user.optString("id", null),
                user == null ? null : user.optString("idstr", null),
                user == null ? null : user.optString("uid", null), body.optString("uid", null));
    }

    private static boolean truthy(Object value) {
        if (value instanceof Boolean) return (Boolean) value;
        if (value instanceof Number) return ((Number) value).intValue() != 0;
        String text = value == null ? "" : value.toString();
        return "1".equals(text) || "true".equalsIgnoreCase(text) || "yes".equalsIgnoreCase(text);
    }

    private static String cookieValue(String cookie, String name) {
        for (String part : cookie.split(";")) {
            String[] pair = part.trim().split("=", 2);
            if (pair.length == 2 && name.equals(pair[0])) return pair[1];
        }
        return null;
    }

    private static String first(String... values) {
        for (String value : values) if (!empty(value) && !"null".equals(value)) return value;
        return "";
    }

    private static boolean empty(String value) {
        return value == null || value.isEmpty();
    }
}
