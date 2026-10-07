package com.review.weibopoc;

import android.content.IntentFilter;
import android.content.ComponentName;
import android.content.pm.*;

import java.util.List;

final class FakePackageManager extends android.test.mock.MockPackageManager {
    private final PackageManager delegate;
    private final String packageName;
    private final PackageInfo fakeInfo;

    FakePackageManager(PackageManager delegate, String packageName, PackageInfo fakeInfo) {
        this.delegate = delegate;
        this.packageName = packageName;
        this.fakeInfo = fakeInfo;
    }

    @Override public PackageInfo getPackageInfo(String name, int flags) throws NameNotFoundException {
        return name.equals(packageName) ? fakeInfo : delegate.getPackageInfo(name, flags);
    }

    @Override public ApplicationInfo getApplicationInfo(String name, int flags) throws NameNotFoundException {
        return name.equals(packageName) ? fakeInfo.applicationInfo : delegate.getApplicationInfo(name, flags);
    }

    @Override public PackageInstaller getPackageInstaller() {
        return delegate.getPackageInstaller();
    }

    @Override public boolean isSafeMode() {
        return delegate.isSafeMode();
    }

    @Override public int getApplicationEnabledSetting(String packageName) {
        return delegate.getApplicationEnabledSetting(packageName);
    }

    @Override public void setApplicationEnabledSetting(String packageName, int state, int flags) {
        delegate.setApplicationEnabledSetting(packageName, state, flags);
    }

    @Override public int getComponentEnabledSetting(ComponentName componentName) {
        return delegate.getComponentEnabledSetting(componentName);
    }

    @Override public void setComponentEnabledSetting(ComponentName componentName, int state, int flags) {
        delegate.setComponentEnabledSetting(componentName, state, flags);
    }

    @Override public int getPreferredActivities(List<IntentFilter> filters,
                                                List<ComponentName> activities, String packageName) {
        return delegate.getPreferredActivities(filters, activities, packageName);
    }

    @Override public void clearPackagePreferredActivities(String packageName) {
        delegate.clearPackagePreferredActivities(packageName);
    }

    @Override public void addPreferredActivity(IntentFilter filter, int match,
                                               ComponentName[] set, ComponentName activity) {
        delegate.addPreferredActivity(filter, match, set, activity);
    }

    @Override public List<PackageInfo> getPreferredPackages(int flags) {
        return delegate.getPreferredPackages(flags);
    }

    @Override public void removePackageFromPreferred(String packageName) {
        delegate.removePackageFromPreferred(packageName);
    }

    @Override public void addPackageToPreferred(String packageName) {
        delegate.addPackageToPreferred(packageName);
    }
}
