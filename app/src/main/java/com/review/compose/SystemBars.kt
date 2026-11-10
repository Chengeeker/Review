package com.review.compose

import android.graphics.Color
import android.os.Build
import android.view.View
import android.view.Window
import android.view.WindowManager.LayoutParams
import androidx.core.view.WindowCompat

@Suppress("DEPRECATION")
internal fun applyReviewSystemBars(window: Window, view: View, dark: Boolean) {
    if (Build.VERSION.SDK_INT < 35) {
        window.clearFlags(LayoutParams.FLAG_TRANSLUCENT_STATUS)
        window.addFlags(LayoutParams.FLAG_DRAWS_SYSTEM_BAR_BACKGROUNDS)
        window.statusBarColor = Color.TRANSPARENT
    }
    if (Build.VERSION.SDK_INT < 35) window.navigationBarColor = Color.TRANSPARENT
    if (Build.VERSION.SDK_INT >= 29) {
        window.isStatusBarContrastEnforced = false
        window.isNavigationBarContrastEnforced = false
    }
    WindowCompat.getInsetsController(window, view).apply {
        isAppearanceLightStatusBars = !dark
        isAppearanceLightNavigationBars = !dark
    }
}
