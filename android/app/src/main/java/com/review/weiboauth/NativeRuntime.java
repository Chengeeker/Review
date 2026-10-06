package com.review.weiboauth;

import android.app.Instrumentation;
import android.content.Context;

import com.hengye.share.module.other.SAUtils;
import com.sina.deviceidjnisdk.DeviceId;
import com.sina.weibo.WeiboApplication;
import com.sina.weibo.security.WeicoSecurityUtils;
import com.sina.weibo.utils.NetCheckUtils;

import java.io.ByteArrayOutputStream;
import java.io.InputStream;

final class NativeRuntime {
    static final String APP_KEY = "1299295010";
    private static NativeRuntime instance;

    final WeiboApplication application;
    final Context weicoContext;

    private NativeRuntime(WeiboApplication application, Context weicoContext) {
        this.application = application;
        this.weicoContext = weicoContext;
    }

    static synchronized NativeRuntime get(Context context) throws Exception {
        if (instance != null) return instance;

        Context appContext = context.getApplicationContext();
        Context weico = fakeContext(appContext, "com.weico.international", "libbb.so");
        Context sina = fakeContext(appContext, "com.sina.weibo", "libshare.so");
        WeiboApplication app = (WeiboApplication) new Instrumentation().newApplication(
                context.getClassLoader(), WeiboApplication.class.getName(), sina);
        app.onCreate();
        app.init(APP_KEY);
        instance = new NativeRuntime(app, weico);
        return instance;
    }

    String oauthSignature(String uid) {
        return WeicoSecurityUtils.calculateS(weicoContext, uid, APP_KEY, "weicoabroad");
    }

    String deviceId() {
        try {
            return DeviceId.getInstance().getDeviceId(application);
        } catch (Throwable ignored) {
            return "";
        }
    }

    String oauthIValue() {
        try {
            String value = application.getIValue("000000000000000");
            return value == null || value.isEmpty() ? "000000000000000" : value;
        } catch (Throwable ignored) {
            return "000000000000000";
        }
    }

    String passwordParam(String password) {
        String value = SAUtils.secP(password);
        if (value == null || value.isEmpty()) throw new IllegalStateException("native_auth_failed");
        return value;
    }

    String passwordSignature(String account, String password) {
        String value = application.newCalculateS(account + password);
        if (value == null || value.isEmpty()) throw new IllegalStateException("native_auth_failed");
        return value;
    }

    String cum(String pathWithQuery) {
        try {
            return NetCheckUtils.getParam(application, pathWithQuery);
        } catch (Throwable ignored) {
            return null;
        }
    }

    private static Context fakeContext(Context base, String packageName, String assetName) throws Exception {
        try (InputStream input = base.getAssets().open(assetName);
             ByteArrayOutputStream output = new ByteArrayOutputStream()) {
            byte[] buffer = new byte[1024];
            int count;
            while ((count = input.read(buffer)) != -1) output.write(buffer, 0, count);
            return new FakePackageContext(base, packageName, output.toByteArray());
        }
    }
}
