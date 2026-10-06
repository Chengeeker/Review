package com.sina.weibo.security;

import android.content.Context;

public final class WeicoSecurityUtils {
    static {
        System.loadLibrary("wbgjb");
    }

    private WeicoSecurityUtils() {}

    public static String calculateS(Context context, String uid, String appKey, String client) {
        int appKeyVersion = 0;
        if (appKey.length() > 5) {
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
}
