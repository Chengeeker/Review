package com.sina.deviceidjnisdk;

import android.content.Context;

public final class DeviceId {
    static {
        try {
            System.loadLibrary("weibosdkcore");
        } catch (Throwable ignored) {}
    }

    private static volatile DeviceId sInstance;
    private final Object mDeviceLock = new Object();
    private String mCachedId;
    private String mCachedImei;
    private String mCachedImsi;
    private String mCachedMac;

    public DeviceId() {}

    public DeviceId(Context context) {}

    public static DeviceId getInstance() {
        DeviceId instance = sInstance;
        if (instance == null) {
            synchronized (DeviceId.class) {
                instance = sInstance;
                if (instance == null) sInstance = instance = new DeviceId();
            }
        }
        return instance;
    }

    public static synchronized DeviceId getInstance(Context context) {
        if (sInstance == null) {
            sInstance = new DeviceId(context);
        }
        return sInstance;
    }

    public String getDeviceId() {
        return mCachedId != null ? mCachedId : "";
    }

    public String getDeviceId(Context context) {
        String empty = "";
        if (mCachedId != null && empty.equals(mCachedImei)
                && empty.equals(mCachedImsi) && empty.equals(mCachedMac)) return mCachedId;
        synchronized (mDeviceLock) {
            try {
                mCachedId = getDeviceIdNative(context, empty, empty, empty);
            } catch (Throwable ignored) {
                mCachedId = "";
            }
            mCachedImei = empty;
            mCachedImsi = empty;
            mCachedMac = empty;
            return mCachedId != null ? mCachedId : "";
        }
    }

    public String genCheckId(String str, String str2, String str3) {
        return (str == null ? "" : str) + (str2 == null ? "" : str2) + (str3 == null ? "" : str3);
    }

    public static String appendCheckId(Context context, String str, String str2, String str3) {
        return getInstance(context).genCheckId(str, str2, str3);
    }

    public static Boolean checkMyPermission(Context context, String permission) {
        if (context == null || permission == null) return false;
        try {
            return context.getPackageManager().checkPermission(permission, context.getPackageName()) == 0;
        } catch (Throwable ignored) {
            return false;
        }
    }

    private native String getDeviceIdNative(Context context, String imei, String imsi, String mac);
}
