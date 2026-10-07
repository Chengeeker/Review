package com.sina.weibo;

import android.app.Application;
import android.content.Context;

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

    public native String calculateS(String value);
    public native String getIValue(String value);
    public native void init(String appKey);
    public native String newCalculateS(String value);
}
