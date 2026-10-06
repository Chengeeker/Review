package com.review.weiboauth;

import java.net.URLEncoder;
import java.nio.charset.StandardCharsets;
import java.util.Map;

final class RequestData {
    private RequestData() {}

    static String encode(Map<String, String> values) {
        StringBuilder encoded = new StringBuilder();
        for (Map.Entry<String, String> entry : values.entrySet()) {
            if (entry.getValue() == null) continue;
            if (encoded.length() != 0) encoded.append('&');
            encoded.append(formEncode(entry.getKey()));
            encoded.append('=');
            encoded.append(formEncode(entry.getValue()));
        }
        return encoded.toString();
    }

    static String addQuery(String url, Map<String, String> values) {
        StringBuilder query = new StringBuilder();
        for (Map.Entry<String, String> entry : values.entrySet()) {
            if (entry.getValue() == null) continue;
            if (query.length() != 0) query.append('&');
            query.append(percentEncode(entry.getKey())).append('=')
                    .append(percentEncode(entry.getValue()));
        }
        if (query.length() == 0) return url;
        return url + (url.contains("?") ? "&" : "?") + query;
    }

    private static String percentEncode(String value) {
        byte[] bytes = value.getBytes(StandardCharsets.UTF_8);
        StringBuilder encoded = new StringBuilder(bytes.length);
        final char[] hex = "0123456789ABCDEF".toCharArray();
        for (byte raw : bytes) {
            int valueByte = raw & 0xff;
            if ((valueByte >= 'a' && valueByte <= 'z') || (valueByte >= 'A' && valueByte <= 'Z')
                    || (valueByte >= '0' && valueByte <= '9') || valueByte == '-'
                    || valueByte == '_' || valueByte == '.' || valueByte == '~') {
                encoded.append((char) valueByte);
            } else {
                encoded.append('%').append(hex[valueByte >>> 4]).append(hex[valueByte & 0x0f]);
            }
        }
        return encoded.toString();
    }

    private static String formEncode(String value) {
        try {
            return URLEncoder.encode(value, "UTF-8");
        } catch (java.io.UnsupportedEncodingException impossible) {
            throw new AssertionError(impossible);
        }
    }
}
