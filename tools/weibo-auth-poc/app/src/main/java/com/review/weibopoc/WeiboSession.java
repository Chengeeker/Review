package com.review.weibopoc;

import org.json.JSONObject;

final class WeiboSession {
    final String uid;
    final String gsid;
    final String sut;
    final String cookie;
    final String accessToken;
    final String expire;
    final String oauthIssuedAt;
    final String oauthExpires;
    final long createdAt;
    final long lastRefreshAt;

    private WeiboSession(String uid, String gsid, String sut, String cookie,
                         String accessToken, String expire, String oauthIssuedAt,
                         String oauthExpires, long createdAt, long lastRefreshAt) {
        this.uid = uid;
        this.gsid = gsid;
        this.sut = sut;
        this.cookie = cookie;
        this.accessToken = accessToken;
        this.expire = expire;
        this.oauthIssuedAt = oauthIssuedAt;
        this.oauthExpires = oauthExpires;
        this.createdAt = createdAt;
        this.lastRefreshAt = lastRefreshAt;
    }

    static WeiboSession parse(JSONObject response, WeiboSession previous, long now) {
        JSONObject user = response.optJSONObject("user");
        JSONObject oauth = response.optJSONObject("oauth2.0");
        if (oauth == null) oauth = new JSONObject();

        return new WeiboSession(
                first(response.optString("uid", null), user == null ? null : user.optString("idstr", null),
                        user == null ? null : user.optString("id", null), previous == null ? null : previous.uid),
                first(response.optString("gsid", null), previous == null ? null : previous.gsid),
                first(response.optString("sut", null), previous == null ? null : previous.sut),
                first(response.optString("cookie", null), previous == null ? null : previous.cookie),
                first(oauth.optString("access_token", null), response.optString("access_token", null),
                        previous == null ? null : previous.accessToken),
                first(response.optString("expire", null), previous == null ? null : previous.expire),
                first(oauth.optString("issued_at", null), previous == null ? null : previous.oauthIssuedAt),
                first(oauth.optString("expires", null), previous == null ? null : previous.oauthExpires),
                previous == null ? now : previous.createdAt,
                now);
    }

    static WeiboSession fromJson(JSONObject json) {
        return new WeiboSession(
                json.optString("uid", null), json.optString("gsid", null),
                json.optString("sut", null), json.optString("cookie", null),
                json.optString("accessToken", null), json.optString("expire", null),
                json.optString("oauthIssuedAt", null), json.optString("oauthExpires", null),
                json.optLong("createdAt", 0), json.optLong("lastRefreshAt", 0));
    }

    JSONObject toJson() {
        JSONObject json = new JSONObject();
        try {
            json.put("uid", uid);
            json.put("gsid", gsid);
            json.put("sut", sut);
            json.put("cookie", cookie);
            json.put("accessToken", accessToken);
            json.put("expire", expire);
            json.put("oauthIssuedAt", oauthIssuedAt);
            json.put("oauthExpires", oauthExpires);
            json.put("createdAt", createdAt);
            json.put("lastRefreshAt", lastRefreshAt);
        } catch (org.json.JSONException impossible) {
            throw new IllegalStateException(impossible);
        }
        return json;
    }

    boolean hasRequiredFields() {
        return present(uid) && present(gsid) && present(sut) && present(cookie)
                && present(accessToken) && present(expire);
    }

    String fieldPresence() {
        return "uid=" + present(uid) + ", gsid=" + present(gsid)
                + ", sut=" + present(sut) + ", cookie=" + present(cookie)
                + ", access_token=" + present(accessToken) + ", expire=" + present(expire);
    }

    boolean shouldRefresh(long now) {
        return lastRefreshAt > 0 && now - lastRefreshAt >= 21_000_000L;
    }

    WeiboSession withLastRefreshAt(long value) {
        return new WeiboSession(uid, gsid, sut, cookie, accessToken, expire,
                oauthIssuedAt, oauthExpires, createdAt, value);
    }

    private static boolean present(String value) {
        return value != null && !value.isEmpty() && !"null".equals(value);
    }

    private static String first(String... values) {
        for (String value : values) {
            if (present(value)) return value;
        }
        return null;
    }
}
