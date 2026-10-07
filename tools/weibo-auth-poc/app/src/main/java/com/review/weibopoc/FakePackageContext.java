package com.review.weibopoc;

import android.content.Context;
import android.content.ContextWrapper;
import android.content.pm.ApplicationInfo;
import android.content.pm.PackageInfo;
import android.content.pm.PackageManager;
import android.content.pm.Signature;

final class FakePackageContext extends ContextWrapper {
    private final String packageName;
    private final PackageInfo packageInfo;

    FakePackageContext(Context base, String packageName, byte[] signature) {
        super(base);
        this.packageName = packageName;
        this.packageInfo = new PackageInfo();
        this.packageInfo.packageName = packageName;
        this.packageInfo.signatures = new Signature[]{new Signature(signature)};
        this.packageInfo.applicationInfo = new ApplicationInfo(base.getApplicationInfo());
        this.packageInfo.applicationInfo.packageName = packageName;
    }

    @Override
    public String getPackageName() {
        return packageName;
    }

    @Override
    public Context getApplicationContext() {
        return this;
    }

    @Override
    public PackageManager getPackageManager() {
        return new FakePackageManager(getBaseContext().getPackageManager(), packageName, packageInfo);
    }

    @Override
    public ApplicationInfo getApplicationInfo() {
        return packageInfo.applicationInfo;
    }
}
