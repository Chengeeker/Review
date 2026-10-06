package com.sina.weibo.utils;

import android.content.Context;

public final class NetCheckUtils {
    static {
        try {
            System.loadLibrary("wbutil");
        } catch (Throwable ignored) {}
    }

    private NetCheckUtils() {}

    public static native String getParam(Context context, String pathWithQuery);
}
