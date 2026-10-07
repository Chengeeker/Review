package com.sina.weibo.utils;

import android.content.Context;

public final class NetCheckUtils {
    private NetCheckUtils() {}

    public static native String getParam(Context context, String pathWithQuery);
}
