package com.sina.deviceidjnisdk;

import android.content.Context;

public final class DeviceId {
    static {
        System.loadLibrary("weibosdkcore");
    }

    private static volatile DeviceId sInstance;
    private final Object mDeviceLock = new Object();
    private String mCachedId;
    private String mCachedImei;
    private String mCachedImsi;
    private String mCachedMac;

    private DeviceId() {}

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

    public String getDeviceId(Context context) {
        String empty = "";
        if (mCachedId != null && empty.equals(mCachedImei)
                && empty.equals(mCachedImsi) && empty.equals(mCachedMac)) return mCachedId;
        synchronized (mDeviceLock) {
            mCachedId = getDeviceIdNative(context, empty, empty, empty);
            mCachedImei = empty;
            mCachedImsi = empty;
            mCachedMac = empty;
            return mCachedId;
        }
    }

    private native String getDeviceIdNative(Context context, String imei, String imsi, String mac);
}
