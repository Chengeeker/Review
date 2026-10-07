package com.sina.weibo.security;

public final class SAUtils {
    static {
        System.loadLibrary("SecShare");
    }

    private SAUtils() {}

    public static native String secP(String password);
}
