package com.review.weiboauth;

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
        if (response == null) {
            response = new JSONObject();
        }
        JSONObject user = response.optJSONObject("user");
        JSONObject oauth = response.optJSONObject("oauth2.0");
        if (oauth == null) oauth = new JSONObject();

        String uid = first(
                response.optString("uid", null),
                user == null ? null : user.optString("idstr", null),
                user == null ? null : user.optString("id", null),
                extractUidFromCookie(response),
                previous == null ? null : previous.uid);

        String gsid = first(
                response.optString("gsid", null),
                previous == null ? null : previous.gsid);

        String sut = first(
                response.optString("sut", null),
                previous == null ? null : previous.sut);

        String cookie = extractCookie(response, previous);

        String accessToken = first(
                oauth.optString("access_token", null),
                response.optString("access_token", null),
                previous == null ? null : previous.accessToken);

        String expire = first(
                optStringOrNumber(response, "expire"),
                optStringOrNumber(oauth, "expires"),
                optStringOrNumber(oauth, "expires_in"),
                extractExpireFromCookie(response),
                previous == null ? null : previous.expire);

        String oauthIssuedAt = first(
                optStringOrNumber(oauth, "issued_at"),
                previous == null ? null : previous.oauthIssuedAt);

        String oauthExpires = first(
                optStringOrNumber(oauth, "expires"),
                optStringOrNumber(oauth, "expires_in"),
                previous == null ? null : previous.oauthExpires);

        return new WeiboSession(
                uid, gsid, sut, cookie, accessToken, expire,
                oauthIssuedAt, oauthExpires,
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
        return present(uid) && (present(cookie) || present(accessToken) || present(gsid));
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

    static String extractCookie(JSONObject response, WeiboSession previous) {
        Object rawCookie = response.opt("cookie");
        String extracted = null;

        if (rawCookie instanceof JSONObject) {
            extracted = parseCookieObject((JSONObject) rawCookie);
        } else if (rawCookie instanceof String) {
            String s = ((String) rawCookie).trim();
            if (!s.isEmpty() && !"null".equalsIgnoreCase(s)) {
                if (s.startsWith("{") && s.endsWith("}")) {
                    try {
                        extracted = parseCookieObject(new JSONObject(s));
                    } catch (Exception ignored) {}
                }
                if (extracted == null) {
                    extracted = s;
                }
            }
        }

        if (present(extracted)) {
            return extracted;
        }

        String sub = first(response.optString("sub", null), response.optString("SUB", null));
        String subp = first(response.optString("subp", null), response.optString("SUBP", null));
        if (present(sub)) {
            return "SUB=" + sub + (present(subp) ? "; SUBP=" + subp : "");
        }

        String gsid = response.optString("gsid", null);
        if (present(gsid) && gsid.startsWith("_2A")) {
            return "SUB=" + gsid;
        }

        return previous == null ? null : previous.cookie;
    }

    private static String parseCookieObject(JSONObject cookieObj) {
        if (cookieObj == null) return null;

        Object innerCookie = cookieObj.opt("cookie");
        if (innerCookie instanceof JSONObject) {
            String parsed = parseCookieMap((JSONObject) innerCookie);
            if (present(parsed)) return parsed;
        } else if (innerCookie instanceof String) {
            String s = ((String) innerCookie).trim();
            if (s.startsWith("{") && s.endsWith("}")) {
                try {
                    String parsed = parseCookieMap(new JSONObject(s));
                    if (present(parsed)) return parsed;
                } catch (Exception ignored) {}
            } else if (!s.isEmpty() && !"null".equalsIgnoreCase(s)) {
                return s;
            }
        }

        return parseCookieMap(cookieObj);
    }

    private static String parseCookieMap(JSONObject map) {
        if (map == null) return null;

        String[] priorityDomains = {".weibo.com", ".weibo.cn", "weibo.com", "weibo.cn", ".sina.com.cn", "sina.com.cn"};
        for (String domain : priorityDomains) {
            String val = map.optString(domain, null);
            if (present(val) && val.contains("SUB=")) {
                return val.replace("\n", "; ").trim();
            }
        }

        java.util.Iterator<String> keys = map.keys();
        while (keys.hasNext()) {
            String key = keys.next();
            if ("expire".equalsIgnoreCase(key) || "uid".equalsIgnoreCase(key)) continue;
            String val = map.optString(key, null);
            if (present(val) && val.contains("SUB=")) {
                return val.replace("\n", "; ").trim();
            }
        }

        String sub = first(map.optString("SUB", null), map.optString("sub", null));
        String subp = first(map.optString("SUBP", null), map.optString("subp", null));
        if (present(sub)) {
            return "SUB=" + sub + (present(subp) ? "; SUBP=" + subp : "");
        }

        for (String domain : priorityDomains) {
            String val = map.optString(domain, null);
            if (present(val)) {
                return val.replace("\n", "; ").trim();
            }
        }

        return null;
    }

    private static String extractUidFromCookie(JSONObject response) {
        Object rawCookie = response.opt("cookie");
        if (rawCookie instanceof JSONObject) {
            return optStringOrNumber((JSONObject) rawCookie, "uid");
        }
        return null;
    }

    private static String extractExpireFromCookie(JSONObject response) {
        Object rawCookie = response.opt("cookie");
        if (rawCookie instanceof JSONObject) {
            return optStringOrNumber((JSONObject) rawCookie, "expire");
        }
        return null;
    }

    private static String optStringOrNumber(JSONObject obj, String key) {
        if (obj == null) return null;
        Object val = obj.opt(key);
        if (val == null) return null;
        if (val instanceof Number) {
            long l = ((Number) val).longValue();
            return l != 0 ? String.valueOf(l) : null;
        }
        if (val instanceof String) {
            String s = ((String) val).trim();
            return (!s.isEmpty() && !"null".equalsIgnoreCase(s)) ? s : null;
        }
        return null;
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
