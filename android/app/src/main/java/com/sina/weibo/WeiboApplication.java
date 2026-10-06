package com.sina.weibo;

import android.app.Application;
import android.content.Context;
import java.io.File;

public final class WeiboApplication extends Application {
    private static volatile WeiboApplication context;

    static {
        System.loadLibrary("wbutil");
    }

    @Override
    protected void attachBaseContext(Context base) {
        super.attachBaseContext(base);
        context = this;
    }

    public static Context getContext() {
        return context;
    }

    // wbutil registers this full native table in JNI_OnLoad before individual calls are made.
    public native String calculateS(String value);
    public native String generateCheckToken(String value, String suffix);
    public native String getDecryptionString(String value);
    public native com.sina.weibo.net.e getNetInstance(Context context, String name);
    public native com.sina.weibo.net.e getNetInstanceFromHotFix(
            Context context, String name, File file, String first, String second, String third);
    public native String getIValue(String value);
    public native void init(String appKey);
    public native String newCalculateS(String value);
}
