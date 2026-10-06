package com.review.weiboauth;

import android.content.ComponentName;
import android.content.Intent;
import android.content.IntentFilter;
import android.content.IntentSender;
import android.content.pm.*;
import android.content.res.Resources;
import android.content.res.XmlResourceParser;
import android.graphics.Rect;
import android.graphics.drawable.Drawable;
import android.os.Handler;
import android.os.UserHandle;

import java.util.List;

final class FakePackageManager extends PackageManager {
    private final PackageManager delegate;
    private final String packageName;
    private final PackageInfo fakeInfo;

    FakePackageManager(PackageManager delegate, String packageName, PackageInfo fakeInfo) {
        this.delegate = delegate;
        this.packageName = packageName;
        this.fakeInfo = fakeInfo;
    }

    @Override
    public PackageInfo getPackageInfo(String name, int flags) throws NameNotFoundException {
        if (packageName.equals(name)) {
            return fakeInfo;
        }
        return delegate != null ? delegate.getPackageInfo(name, flags) : null;
    }

    @Override
    public ApplicationInfo getApplicationInfo(String name, int flags) throws NameNotFoundException {
        if (packageName.equals(name)) {
            return fakeInfo.applicationInfo;
        }
        return delegate != null ? delegate.getApplicationInfo(name, flags) : null;
    }

    @Override
    public android.content.pm.PackageInfo getPackageInfo(android.content.pm.VersionedPackage arg0, int arg1) throws android.content.pm.PackageManager.NameNotFoundException {
        return delegate != null ? delegate.getPackageInfo(arg0, arg1) : null;
    }

    @Override
    public java.lang.String[] currentToCanonicalPackageNames(java.lang.String[] arg0) {
        return delegate != null ? delegate.currentToCanonicalPackageNames(arg0) : null;
    }

    @Override
    public java.lang.String[] canonicalToCurrentPackageNames(java.lang.String[] arg0) {
        return delegate != null ? delegate.canonicalToCurrentPackageNames(arg0) : null;
    }

    @Override
    public android.content.Intent getLaunchIntentForPackage(java.lang.String arg0) {
        return delegate != null ? delegate.getLaunchIntentForPackage(arg0) : null;
    }

    @Override
    public android.content.Intent getLeanbackLaunchIntentForPackage(java.lang.String arg0) {
        return delegate != null ? delegate.getLeanbackLaunchIntentForPackage(arg0) : null;
    }

    @Override
    public int[] getPackageGids(java.lang.String arg0) throws android.content.pm.PackageManager.NameNotFoundException {
        return delegate != null ? delegate.getPackageGids(arg0) : null;
    }

    @Override
    public int[] getPackageGids(java.lang.String arg0, int arg1) throws android.content.pm.PackageManager.NameNotFoundException {
        return delegate != null ? delegate.getPackageGids(arg0, arg1) : null;
    }

    @Override
    public int getPackageUid(java.lang.String arg0, int arg1) throws android.content.pm.PackageManager.NameNotFoundException {
        return delegate != null ? delegate.getPackageUid(arg0, arg1) : 0;
    }

    @Override
    public android.content.pm.PermissionInfo getPermissionInfo(java.lang.String arg0, int arg1) throws android.content.pm.PackageManager.NameNotFoundException {
        return delegate != null ? delegate.getPermissionInfo(arg0, arg1) : null;
    }

    @Override
    public java.util.List<android.content.pm.PermissionInfo> queryPermissionsByGroup(java.lang.String arg0, int arg1) throws android.content.pm.PackageManager.NameNotFoundException {
        return delegate != null ? delegate.queryPermissionsByGroup(arg0, arg1) : null;
    }

    @Override
    public android.content.pm.PermissionGroupInfo getPermissionGroupInfo(java.lang.String arg0, int arg1) throws android.content.pm.PackageManager.NameNotFoundException {
        return delegate != null ? delegate.getPermissionGroupInfo(arg0, arg1) : null;
    }

    @Override
    public java.util.List<android.content.pm.PermissionGroupInfo> getAllPermissionGroups(int arg0) {
        return delegate != null ? delegate.getAllPermissionGroups(arg0) : null;
    }

    @Override
    public android.content.pm.ActivityInfo getActivityInfo(android.content.ComponentName arg0, int arg1) throws android.content.pm.PackageManager.NameNotFoundException {
        return delegate != null ? delegate.getActivityInfo(arg0, arg1) : null;
    }

    @Override
    public android.content.pm.ActivityInfo getReceiverInfo(android.content.ComponentName arg0, int arg1) throws android.content.pm.PackageManager.NameNotFoundException {
        return delegate != null ? delegate.getReceiverInfo(arg0, arg1) : null;
    }

    @Override
    public android.content.pm.ServiceInfo getServiceInfo(android.content.ComponentName arg0, int arg1) throws android.content.pm.PackageManager.NameNotFoundException {
        return delegate != null ? delegate.getServiceInfo(arg0, arg1) : null;
    }

    @Override
    public android.content.pm.ProviderInfo getProviderInfo(android.content.ComponentName arg0, int arg1) throws android.content.pm.PackageManager.NameNotFoundException {
        return delegate != null ? delegate.getProviderInfo(arg0, arg1) : null;
    }

    @Override
    public java.util.List<android.content.pm.PackageInfo> getInstalledPackages(int arg0) {
        return delegate != null ? delegate.getInstalledPackages(arg0) : null;
    }

    @Override
    public java.util.List<android.content.pm.PackageInfo> getPackagesHoldingPermissions(java.lang.String[] arg0, int arg1) {
        return delegate != null ? delegate.getPackagesHoldingPermissions(arg0, arg1) : null;
    }

    @Override
    public int checkPermission(java.lang.String arg0, java.lang.String arg1) {
        return delegate != null ? delegate.checkPermission(arg0, arg1) : 0;
    }

    @Override
    public boolean isPermissionRevokedByPolicy(java.lang.String arg0, java.lang.String arg1) {
        return delegate != null && delegate.isPermissionRevokedByPolicy(arg0, arg1);
    }

    @Override
    public boolean addPermission(android.content.pm.PermissionInfo arg0) {
        return delegate != null && delegate.addPermission(arg0);
    }

    @Override
    public boolean addPermissionAsync(android.content.pm.PermissionInfo arg0) {
        return delegate != null && delegate.addPermissionAsync(arg0);
    }

    @Override
    public void removePermission(java.lang.String arg0) {
        if (delegate != null) delegate.removePermission(arg0);
    }

    @Override
    public int checkSignatures(java.lang.String arg0, java.lang.String arg1) {
        return delegate != null ? delegate.checkSignatures(arg0, arg1) : 0;
    }

    @Override
    public int checkSignatures(int arg0, int arg1) {
        return delegate != null ? delegate.checkSignatures(arg0, arg1) : 0;
    }

    @Override
    public java.lang.String[] getPackagesForUid(int arg0) {
        return delegate != null ? delegate.getPackagesForUid(arg0) : null;
    }

    @Override
    public java.lang.String getNameForUid(int arg0) {
        return delegate != null ? delegate.getNameForUid(arg0) : null;
    }

    @Override
    public java.util.List<android.content.pm.ApplicationInfo> getInstalledApplications(int arg0) {
        return delegate != null ? delegate.getInstalledApplications(arg0) : null;
    }

    @Override
    public boolean isInstantApp() {
        return delegate != null && delegate.isInstantApp();
    }

    @Override
    public boolean isInstantApp(java.lang.String arg0) {
        return delegate != null && delegate.isInstantApp(arg0);
    }

    @Override
    public int getInstantAppCookieMaxBytes() {
        return delegate != null ? delegate.getInstantAppCookieMaxBytes() : 0;
    }

    @Override
    public byte[] getInstantAppCookie() {
        return delegate != null ? delegate.getInstantAppCookie() : null;
    }

    @Override
    public void clearInstantAppCookie() {
        if (delegate != null) delegate.clearInstantAppCookie();
    }

    @Override
    public void updateInstantAppCookie(byte[] arg0) {
        if (delegate != null) delegate.updateInstantAppCookie(arg0);
    }

    @Override
    public java.lang.String[] getSystemSharedLibraryNames() {
        return delegate != null ? delegate.getSystemSharedLibraryNames() : null;
    }

    @Override
    public java.util.List<android.content.pm.SharedLibraryInfo> getSharedLibraries(int arg0) {
        return delegate != null ? delegate.getSharedLibraries(arg0) : null;
    }

    @Override
    public android.content.pm.ChangedPackages getChangedPackages(int arg0) {
        return delegate != null ? delegate.getChangedPackages(arg0) : null;
    }

    @Override
    public android.content.pm.FeatureInfo[] getSystemAvailableFeatures() {
        return delegate != null ? delegate.getSystemAvailableFeatures() : null;
    }

    @Override
    public boolean hasSystemFeature(java.lang.String arg0) {
        return delegate != null && delegate.hasSystemFeature(arg0);
    }

    @Override
    public boolean hasSystemFeature(java.lang.String arg0, int arg1) {
        return delegate != null && delegate.hasSystemFeature(arg0, arg1);
    }

    @Override
    public android.content.pm.ResolveInfo resolveActivity(android.content.Intent arg0, int arg1) {
        return delegate != null ? delegate.resolveActivity(arg0, arg1) : null;
    }

    @Override
    public java.util.List<android.content.pm.ResolveInfo> queryIntentActivities(android.content.Intent arg0, int arg1) {
        return delegate != null ? delegate.queryIntentActivities(arg0, arg1) : null;
    }

    @Override
    public java.util.List<android.content.pm.ResolveInfo> queryIntentActivityOptions(android.content.ComponentName arg0, android.content.Intent[] arg1, android.content.Intent arg2, int arg3) {
        return delegate != null ? delegate.queryIntentActivityOptions(arg0, arg1, arg2, arg3) : null;
    }

    @Override
    public java.util.List<android.content.pm.ResolveInfo> queryBroadcastReceivers(android.content.Intent arg0, int arg1) {
        return delegate != null ? delegate.queryBroadcastReceivers(arg0, arg1) : null;
    }

    @Override
    public android.content.pm.ResolveInfo resolveService(android.content.Intent arg0, int arg1) {
        return delegate != null ? delegate.resolveService(arg0, arg1) : null;
    }

    @Override
    public java.util.List<android.content.pm.ResolveInfo> queryIntentServices(android.content.Intent arg0, int arg1) {
        return delegate != null ? delegate.queryIntentServices(arg0, arg1) : null;
    }

    @Override
    public java.util.List<android.content.pm.ResolveInfo> queryIntentContentProviders(android.content.Intent arg0, int arg1) {
        return delegate != null ? delegate.queryIntentContentProviders(arg0, arg1) : null;
    }

    @Override
    public android.content.pm.ProviderInfo resolveContentProvider(java.lang.String arg0, int arg1) {
        return delegate != null ? delegate.resolveContentProvider(arg0, arg1) : null;
    }

    @Override
    public java.util.List<android.content.pm.ProviderInfo> queryContentProviders(java.lang.String arg0, int arg1, int arg2) {
        return delegate != null ? delegate.queryContentProviders(arg0, arg1, arg2) : null;
    }

    @Override
    public android.content.pm.InstrumentationInfo getInstrumentationInfo(android.content.ComponentName arg0, int arg1) throws android.content.pm.PackageManager.NameNotFoundException {
        return delegate != null ? delegate.getInstrumentationInfo(arg0, arg1) : null;
    }

    @Override
    public java.util.List<android.content.pm.InstrumentationInfo> queryInstrumentation(java.lang.String arg0, int arg1) {
        return delegate != null ? delegate.queryInstrumentation(arg0, arg1) : null;
    }

    @Override
    public android.graphics.drawable.Drawable getDrawable(java.lang.String arg0, int arg1, android.content.pm.ApplicationInfo arg2) {
        return delegate != null ? delegate.getDrawable(arg0, arg1, arg2) : null;
    }

    @Override
    public android.graphics.drawable.Drawable getActivityIcon(android.content.ComponentName arg0) throws android.content.pm.PackageManager.NameNotFoundException {
        return delegate != null ? delegate.getActivityIcon(arg0) : null;
    }

    @Override
    public android.graphics.drawable.Drawable getActivityIcon(android.content.Intent arg0) throws android.content.pm.PackageManager.NameNotFoundException {
        return delegate != null ? delegate.getActivityIcon(arg0) : null;
    }

    @Override
    public android.graphics.drawable.Drawable getActivityBanner(android.content.ComponentName arg0) throws android.content.pm.PackageManager.NameNotFoundException {
        return delegate != null ? delegate.getActivityBanner(arg0) : null;
    }

    @Override
    public android.graphics.drawable.Drawable getActivityBanner(android.content.Intent arg0) throws android.content.pm.PackageManager.NameNotFoundException {
        return delegate != null ? delegate.getActivityBanner(arg0) : null;
    }

    @Override
    public android.graphics.drawable.Drawable getDefaultActivityIcon() {
        return delegate != null ? delegate.getDefaultActivityIcon() : null;
    }

    @Override
    public android.graphics.drawable.Drawable getApplicationIcon(android.content.pm.ApplicationInfo arg0) {
        return delegate != null ? delegate.getApplicationIcon(arg0) : null;
    }

    @Override
    public android.graphics.drawable.Drawable getApplicationIcon(java.lang.String arg0) throws android.content.pm.PackageManager.NameNotFoundException {
        return delegate != null ? delegate.getApplicationIcon(arg0) : null;
    }

    @Override
    public android.graphics.drawable.Drawable getApplicationBanner(android.content.pm.ApplicationInfo arg0) {
        return delegate != null ? delegate.getApplicationBanner(arg0) : null;
    }

    @Override
    public android.graphics.drawable.Drawable getApplicationBanner(java.lang.String arg0) throws android.content.pm.PackageManager.NameNotFoundException {
        return delegate != null ? delegate.getApplicationBanner(arg0) : null;
    }

    @Override
    public android.graphics.drawable.Drawable getActivityLogo(android.content.ComponentName arg0) throws android.content.pm.PackageManager.NameNotFoundException {
        return delegate != null ? delegate.getActivityLogo(arg0) : null;
    }

    @Override
    public android.graphics.drawable.Drawable getActivityLogo(android.content.Intent arg0) throws android.content.pm.PackageManager.NameNotFoundException {
        return delegate != null ? delegate.getActivityLogo(arg0) : null;
    }

    @Override
    public android.graphics.drawable.Drawable getApplicationLogo(android.content.pm.ApplicationInfo arg0) {
        return delegate != null ? delegate.getApplicationLogo(arg0) : null;
    }

    @Override
    public android.graphics.drawable.Drawable getApplicationLogo(java.lang.String arg0) throws android.content.pm.PackageManager.NameNotFoundException {
        return delegate != null ? delegate.getApplicationLogo(arg0) : null;
    }

    @Override
    public android.graphics.drawable.Drawable getUserBadgedIcon(android.graphics.drawable.Drawable arg0, android.os.UserHandle arg1) {
        return delegate != null ? delegate.getUserBadgedIcon(arg0, arg1) : null;
    }

    @Override
    public android.graphics.drawable.Drawable getUserBadgedDrawableForDensity(android.graphics.drawable.Drawable arg0, android.os.UserHandle arg1, android.graphics.Rect arg2, int arg3) {
        return delegate != null ? delegate.getUserBadgedDrawableForDensity(arg0, arg1, arg2, arg3) : null;
    }

    @Override
    public java.lang.CharSequence getUserBadgedLabel(java.lang.CharSequence arg0, android.os.UserHandle arg1) {
        return delegate != null ? delegate.getUserBadgedLabel(arg0, arg1) : null;
    }

    @Override
    public java.lang.CharSequence getText(java.lang.String arg0, int arg1, android.content.pm.ApplicationInfo arg2) {
        return delegate != null ? delegate.getText(arg0, arg1, arg2) : null;
    }

    @Override
    public android.content.res.XmlResourceParser getXml(java.lang.String arg0, int arg1, android.content.pm.ApplicationInfo arg2) {
        return delegate != null ? delegate.getXml(arg0, arg1, arg2) : null;
    }

    @Override
    public java.lang.CharSequence getApplicationLabel(android.content.pm.ApplicationInfo arg0) {
        return delegate != null ? delegate.getApplicationLabel(arg0) : null;
    }

    @Override
    public android.content.res.Resources getResourcesForActivity(android.content.ComponentName arg0) throws android.content.pm.PackageManager.NameNotFoundException {
        return delegate != null ? delegate.getResourcesForActivity(arg0) : null;
    }

    @Override
    public android.content.res.Resources getResourcesForApplication(android.content.pm.ApplicationInfo arg0) throws android.content.pm.PackageManager.NameNotFoundException {
        return delegate != null ? delegate.getResourcesForApplication(arg0) : null;
    }

    @Override
    public android.content.res.Resources getResourcesForApplication(java.lang.String arg0) throws android.content.pm.PackageManager.NameNotFoundException {
        return delegate != null ? delegate.getResourcesForApplication(arg0) : null;
    }

    @Override
    public void verifyPendingInstall(int arg0, int arg1) {
        if (delegate != null) delegate.verifyPendingInstall(arg0, arg1);
    }

    @Override
    public void extendVerificationTimeout(int arg0, int arg1, long arg2) {
        if (delegate != null) delegate.extendVerificationTimeout(arg0, arg1, arg2);
    }

    @Override
    public void setInstallerPackageName(java.lang.String arg0, java.lang.String arg1) {
        if (delegate != null) delegate.setInstallerPackageName(arg0, arg1);
    }

    @Override
    public java.lang.String getInstallerPackageName(java.lang.String arg0) {
        return delegate != null ? delegate.getInstallerPackageName(arg0) : null;
    }

    @Override
    public void addPackageToPreferred(java.lang.String arg0) {
        if (delegate != null) delegate.addPackageToPreferred(arg0);
    }

    @Override
    public void removePackageFromPreferred(java.lang.String arg0) {
        if (delegate != null) delegate.removePackageFromPreferred(arg0);
    }

    @Override
    public java.util.List<android.content.pm.PackageInfo> getPreferredPackages(int arg0) {
        return delegate != null ? delegate.getPreferredPackages(arg0) : null;
    }

    @Override
    public void addPreferredActivity(android.content.IntentFilter arg0, int arg1, android.content.ComponentName[] arg2, android.content.ComponentName arg3) {
        if (delegate != null) delegate.addPreferredActivity(arg0, arg1, arg2, arg3);
    }

    @Override
    public void clearPackagePreferredActivities(java.lang.String arg0) {
        if (delegate != null) delegate.clearPackagePreferredActivities(arg0);
    }

    @Override
    public int getPreferredActivities(java.util.List<android.content.IntentFilter> arg0, java.util.List<android.content.ComponentName> arg1, java.lang.String arg2) {
        return delegate != null ? delegate.getPreferredActivities(arg0, arg1, arg2) : 0;
    }

    @Override
    public void setComponentEnabledSetting(android.content.ComponentName arg0, int arg1, int arg2) {
        if (delegate != null) delegate.setComponentEnabledSetting(arg0, arg1, arg2);
    }

    @Override
    public int getComponentEnabledSetting(android.content.ComponentName arg0) {
        return delegate != null ? delegate.getComponentEnabledSetting(arg0) : 0;
    }

    @Override
    public void setApplicationEnabledSetting(java.lang.String arg0, int arg1, int arg2) {
        if (delegate != null) delegate.setApplicationEnabledSetting(arg0, arg1, arg2);
    }

    @Override
    public int getApplicationEnabledSetting(java.lang.String arg0) {
        return delegate != null ? delegate.getApplicationEnabledSetting(arg0) : 0;
    }

    @Override
    public boolean isSafeMode() {
        return delegate != null && delegate.isSafeMode();
    }

    @Override
    public void setApplicationCategoryHint(java.lang.String arg0, int arg1) {
        if (delegate != null) delegate.setApplicationCategoryHint(arg0, arg1);
    }

    @Override
    public android.content.pm.PackageInstaller getPackageInstaller() {
        return delegate != null ? delegate.getPackageInstaller() : null;
    }

    @Override
    public boolean canRequestPackageInstalls() {
        return delegate != null && delegate.canRequestPackageInstalls();
    }
}
