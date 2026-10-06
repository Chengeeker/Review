package com.review.weiboauth;

import android.content.Context;
import android.net.ConnectivityManager;
import android.net.Network;
import android.net.NetworkCapabilities;
import android.os.Build;
import android.provider.Settings;

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

public final class WeiboApi {
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

    public static final class ApiFailure extends Exception {
        public final int httpCode;
        public final String responseCode;
        public final String category;
        public final String serverMsg;

        public ApiFailure(String category, int httpCode, String responseCode, String serverMsg) {
            super(serverMsg != null && !serverMsg.isEmpty() ? serverMsg : category);
            this.category = category;
            this.httpCode = httpCode;
            this.responseCode = responseCode;
            this.serverMsg = serverMsg;
        }

        public ApiFailure(String category, int httpCode, String responseCode) {
            this(category, httpCode, responseCode, null);
        }
    }

    static final class SmsCodeResult {
        final String number;

        SmsCodeResult(String number) {
            this.number = number;
        }
    }

    private static final class JsonResponse {
        final int httpCode;
        final JSONObject json;

        JsonResponse(int httpCode, JSONObject json) {
            this.httpCode = httpCode;
            this.json = json;
        }
    }

    private final Context context;
    private final NativeRuntime nativeRuntime;

    WeiboApi(Context context, NativeRuntime nativeRuntime) {
        this.context = context.getApplicationContext();
        this.nativeRuntime = nativeRuntime;
    }

    SmsCodeResult requestSmsCode(String phone, String area) throws Exception {
        Map<String, String> query = commonLoginQuery();
        query.put("phone", phone);
        String effectiveArea = ("86".equals(area) || "0086".equals(area)) ? "" : (area == null ? "" : area);
        query.put("area", effectiveArea);
        query.put("getuser", "1");
        query.put("getoauth", "1");
        query.put("getcookie", "1");

        Map<String, String> form = new LinkedHashMap<>();
        form.put("pwd", "");
        form.put("flag", "1");
        form.put("phone", phone);

        JsonResponse response = sendJsonRequest("POST", "account/login_sendcode", query, form);
        JSONObject json = response.json;
        if (!truthy(json.opt("sendsms"))) {
            String msg = json.optString("msg", "");
            if (empty(msg)) msg = json.optString("errmsg", "");
            if (empty(msg)) msg = json.optString("error", "");
            throw new ApiFailure("sms_send_rejected", response.httpCode, responseCode(json), msg);
        }
        String number = json.optString("number", "");
        if (empty(number)) {
            String msg = json.optString("msg", "");
            if (empty(msg)) msg = json.optString("errmsg", "");
            throw new ApiFailure("sms_challenge_missing", response.httpCode, responseCode(json), msg);
        }
        return new SmsCodeResult(number);
    }

    ApiResult loginWithSms(String phone, String area, String number, String smsCode) throws Exception {
        Map<String, String> query = commonLoginQuery();
        query.put("i", nativeRuntime.oauthIValue());
        query.put("phone", phone);
        query.put("number", number);
        String effectiveArea = ("86".equals(area) || "0086".equals(area)) ? "" : (area == null ? "" : area);
        query.put("code", effectiveArea);
        query.put("smscode", smsCode);

        Map<String, String> form = new LinkedHashMap<>();
        form.put("getuser", "1");
        form.put("getoauth", "1");
        form.put("getcookie", "1");
        form.put("device_name", deviceName());
        return sendSessionRequest("POST", "account/login", query, form, null);
    }

    ApiResult loginWithPassword(String account, String password) throws Exception {
        Map<String, String> query = commonLoginQuery();
        query.put("i", nativeRuntime.oauthIValue());
        query.put("s", nativeRuntime.passwordSignature(account, password));
        query.put("u", account);
        query.put("p", nativeRuntime.passwordParam(password));

        Map<String, String> form = new LinkedHashMap<>();
        form.put("getuser", "1");
        form.put("getoauth", "1");
        form.put("getcookie", "1");
        form.put("device_name", deviceName());
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
        JsonResponse response = sendJsonRequest(method, endpoint, query, form);
        JSONObject json = response.json;
        String responseCode = responseCode(json);
        WeiboSession next = WeiboSession.parse(json, previous, System.currentTimeMillis());
        if (!next.hasRequiredFields()) {
            android.util.Log.w("WeiboAuth", "Session fields missing! Fields: " + next.fieldPresence()
                    + ", responseCode=" + responseCode);
            String category = containsCaptchaChallenge(json) ? "captcha_required" : "session_fields_missing";
            String msg = json.optString("msg", "");
            if (empty(msg)) msg = json.optString("errmsg", "");
            if (empty(msg)) msg = json.optString("error", "");
            throw new ApiFailure(category, response.httpCode, responseCode, msg);
        }
        return new ApiResult(response.httpCode, responseCode, next, false, false);
    }

    private JsonResponse sendJsonRequest(String method, String endpoint, Map<String, String> query,
                                         Map<String, String> form) throws Exception {
        String noCumUrl = RequestData.addQuery(API_ROOT + endpoint, query);
        String pathWithQuery = new URL(noCumUrl).getFile();
        String cum = nativeRuntime.cum(pathWithQuery);
        if (cum != null && !cum.isEmpty()) {
            query.put("cum", cum);
        }
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

        android.util.Log.i("WeiboAuth", method + " " + endpoint + " status=" + status);

        String responseCode = json == null ? "non_json" : responseCode(json);
        if (status < 200 || status >= 300 || json == null) {
            String msg = json != null ? json.optString("msg", "") : "";
            if (empty(msg) && json != null) msg = json.optString("errmsg", "");
            if (empty(msg) && json != null) msg = json.optString("error", "");
            throw new ApiFailure("http_or_response_error", status, responseCode, msg);
        }
        return new JsonResponse(status, json);
    }

    private Map<String, String> commonLoginQuery() {
        Map<String, String> query = new LinkedHashMap<>();
        query.put("c", "android");
        query.put("from", "10B63950" + (isHarmonyOs() ? "60" : "10"));
        query.put("lang", "zh_CN");
        query.put("networktype", networkType());
        query.put("wm", "2468_1001");
        query.put("oldwm", oldWm());
        query.put("ua", Build.MANUFACTURER + "-" + Build.MODEL
                + "__weibo__11.6.3__android__android" + Build.VERSION.RELEASE);
        query.put("v_p", "89");
        query.put("android_id", androidId());
        query.put("wb_version", "5005");
        query.put("skin", "default");
        query.put("v_f", "2");
        return query;
    }

    private String androidId() {
        try {
            String aid = Settings.Secure.getString(context.getContentResolver(), Settings.Secure.ANDROID_ID);
            return aid == null ? "" : aid;
        } catch (Throwable ignored) {
            return "";
        }
    }

    private static String deviceName() {
        return Build.MANUFACTURER + "-" + Build.MODEL;
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

    private static boolean truthy(Object value) {
        if (value instanceof Boolean) return (Boolean) value;
        if (value instanceof Number) return ((Number) value).intValue() != 0;
        String text = value == null ? "" : value.toString();
        return "1".equals(text) || "true".equalsIgnoreCase(text) || "yes".equalsIgnoreCase(text);
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
