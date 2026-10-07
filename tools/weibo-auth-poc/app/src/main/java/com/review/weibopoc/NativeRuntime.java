package com.review.weibopoc;

import android.app.Instrumentation;
import android.content.Context;

import com.sina.deviceidjnisdk.DeviceId;
import com.sina.weibo.WeiboApplication;
import com.sina.weibo.security.SAUtils;
import com.sina.weibo.security.WeicoSecurityUtils;
import com.sina.weibo.utils.NetCheckUtils;

import java.io.ByteArrayOutputStream;
import java.io.InputStream;

final class NativeRuntime {
    static final String APP_KEY = "1299295010";
    private static NativeRuntime instance;

    final WeiboApplication application;
    final Context sinaContext;
    final Context weicoContext;

    private NativeRuntime(WeiboApplication application, Context sinaContext, Context weicoContext) {
        this.application = application;
        this.sinaContext = sinaContext;
        this.weicoContext = weicoContext;
    }

    static synchronized NativeRuntime get(Context context) throws Exception {
        if (instance != null) return instance;
        System.loadLibrary("SecShare");
        System.loadLibrary("wbutil");
        System.loadLibrary("wbgjb");
        System.loadLibrary("weibosdkcore");

        Context appContext = context.getApplicationContext();
        Context weico = fakeContext(appContext, "com.weico.international", "libbb.so");
        Context sina = fakeContext(appContext, "com.sina.weibo", "libshare.so");
        WeiboApplication app = (WeiboApplication) new Instrumentation().newApplication(
                context.getClassLoader(), WeiboApplication.class.getName(), sina);
        app.onCreate();
        app.init(APP_KEY);
        instance = new NativeRuntime(app, sina, weico);
        return instance;
    }

    static String password(String value) {
        return SAUtils.secP(value);
    }

    String loginSignature(String account, String password) {
        return application.newCalculateS(account + password);
    }

    String oauthSignature(String uid) {
        return WeicoSecurityUtils.calculateS(weicoContext, uid, APP_KEY, "weicoabroad");
    }

    String deviceId() {
        return DeviceId.getInstance().getDeviceId(sinaContext);
    }

    String oauthIValue() {
        String value = application.getIValue("000000000000000");
        return value == null || value.isEmpty() ? "000000000000000" : value;
    }

    String cum(String pathWithQuery) {
        return NetCheckUtils.getParam(application, pathWithQuery);
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
