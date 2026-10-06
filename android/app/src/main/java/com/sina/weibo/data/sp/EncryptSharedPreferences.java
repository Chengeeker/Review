package com.sina.weibo.data.sp;

import android.content.Context;

/** Native methods registered by wbutil during JNI_OnLoad. */
public final class EncryptSharedPreferences {
    private EncryptSharedPreferences() {}

    public static native byte[] loadSpFile(Context context, String name);

    public static native void saveSpFile(Context context, String name, byte[] value);
}
