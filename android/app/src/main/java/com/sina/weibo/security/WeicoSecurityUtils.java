package com.sina.weibo.security;

import android.content.Context;
import com.sina.deviceidjnisdk.DeviceId;
import java.nio.charset.StandardCharsets;
import java.security.MessageDigest;

public final class WeicoSecurityUtils {
    public static String sSeed;
    public static String sValue;

    static {
        System.loadLibrary("wbgjb");
    }

    private WeicoSecurityUtils() {}

    public static String aa4(String a, String b, String c) {
        return toSecurityValue(a, c, b);
    }

    public static String toSecurityValue(String p0, String p1, String p2) {
        StringBuilder sb = new StringBuilder();
        String hash1 = sha512(p1 + p0 + p2);
        String hash2 = sha512(p2);
        int index = 0;
        for (int i = 0; i <= 7; i++) {
            if (index >= hash2.length()) break;
            char c = hash2.charAt(index);
            int val = "0123456789abcdef".indexOf(c);
            if (val >= 0) index += val;
            if (index < hash1.length()) {
                sb.append(hash1.charAt(index));
            }
        }
        return sb.toString();
    }

    public static String sha512(String p0) {
        try {
            MessageDigest md = MessageDigest.getInstance("SHA-512");
            byte[] bytes = md.digest(p0.getBytes(StandardCharsets.UTF_8));
            return toHex(bytes);
        } catch (Exception e) {
            return "";
        }
    }

    public static String toHex(byte[] bytes) {
        StringBuilder sb = new StringBuilder();
        for (byte b : bytes) {
            String hex = Integer.toHexString(b & 0xff);
            if (hex.length() == 1) sb.append('0');
            sb.append(hex);
        }
        return sb.toString();
    }

    public static String aa2(String p0, String p1, String p2) {
        try {
            return DeviceId.getInstance().getDeviceId();
        } catch (Throwable t) {
            return "";
        }
    }

    public static String aa3(String p0) {
        try {
            MessageDigest md = MessageDigest.getInstance("MD5");
            byte[] digest = md.digest(p0.getBytes(StandardCharsets.UTF_8));
            StringBuilder hex = new StringBuilder();
            for (byte b : digest) {
                String h = Integer.toHexString(b & 0xff);
                if (h.length() == 1) hex.append('0');
                hex.append(h);
            }
            String s = hex.toString().toLowerCase();
            int[] indices = {1, 5, 2, 10, 17, 9, 25, 27};
            StringBuilder sb = new StringBuilder();
            for (int idx : indices) {
                if (idx < s.length()) sb.append(s.charAt(idx));
            }
            return sb.toString();
        } catch (Throwable t) {
            return "";
        }
    }

    public static String aaa(String p0) {
        return "";
    }

    public static byte charToByte(char c) {
        return (byte) "0123456789ABCDEF".indexOf(c);
    }

    public static byte[] hexString2Bytes(String s) {
        if (s == null || s.isEmpty() || s.length() % 2 != 0) return null;
        String upper = s.toUpperCase();
        int len = upper.length() / 2;
        byte[] result = new byte[len];
        char[] chars = upper.toCharArray();
        for (int i = 0; i < len; i++) {
            int pos = i * 2;
            result[i] = (byte) ((charToByte(chars[pos]) << 4) | charToByte(chars[pos + 1]));
        }
        return result;
    }

    public static String securityPsd(String p0, String p1) {
        return "";
    }

    public static String sinaPushParse(String p0) {
        try {
            byte[] bytes = hexString2Bytes(p0);
            if (bytes != null) return sinaPushDataParse(bytes);
        } catch (Throwable ignored) {}
        return "";
    }

    public static String calculateS(Context context, String uid, String appKey, String client) {
        int appKeyVersion = 0;
        if (appKey != null && appKey.length() > 5) {
            try {
                appKeyVersion = Integer.parseInt(appKey.substring(2, 5));
            } catch (Throwable ignored) {
                appKeyVersion = 0;
            }
        }
        String pin = WeiboPin(context);
        if (appKeyVersion > 0x32a) return generateS(context, uid, pin, appKey);
        throw new UnsupportedOperationException("Only the observed Share app-key branch is implemented");
    }

    public static native String WeiboPin(Context context);
    public static native String generateS(Context context, String uid, String pin, String appKey);
    public static native String generateDid(Context context, String p1, String p2, String p3);
    public static native String generateMfp(Context context);
    public static native String md5(Context context, String p1, String p2, String p3, String p4);
    public static native String securityPsd(Context context, String p1);
    public static native String sinaPushDataParse(byte[] p0);
}
