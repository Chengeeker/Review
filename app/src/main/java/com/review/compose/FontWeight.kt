package com.review.compose

import android.content.res.Configuration
import android.os.Build
import androidx.compose.runtime.*
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalConfiguration
import androidx.compose.ui.platform.LocalFontFamilyResolver
import androidx.compose.ui.text.font.*
import androidx.compose.material3.Typography

val LocalWeightAdjustment = staticCompositionLocalOf { 0 }
fun adjustedFontWeight(weight: FontWeight, delta: Int) = FontWeight((weight.weight + delta).coerceIn(100, 900))
@Composable fun reviewWeight(weight: FontWeight) = adjustedFontWeight(weight, LocalWeightAdjustment.current)
fun Typography.adjustWeight(delta: Int): Typography {
    fun androidx.compose.ui.text.TextStyle.adjust() = copy(fontWeight = adjustedFontWeight(fontWeight ?: FontWeight.Normal, delta))
    return copy(displayLarge = displayLarge.adjust(), displayMedium = displayMedium.adjust(), displaySmall = displaySmall.adjust(),
        headlineLarge = headlineLarge.adjust(), headlineMedium = headlineMedium.adjust(), headlineSmall = headlineSmall.adjust(),
        titleLarge = titleLarge.adjust(), titleMedium = titleMedium.adjust(), titleSmall = titleSmall.adjust(),
        bodyLarge = bodyLarge.adjust(), bodyMedium = bodyMedium.adjust(), bodySmall = bodySmall.adjust(),
        labelLarge = labelLarge.adjust(), labelMedium = labelMedium.adjust(), labelSmall = labelSmall.adjust())
}

@Composable
fun ReviewFontWeight(content: @Composable () -> Unit) {
    val model = LocalReview.current
    val enabled = model.bool("customWeight")
    val platformResolver = LocalFontFamilyResolver.current
    val context = LocalContext.current
    val configuration = LocalConfiguration.current
    val base = remember(context, configuration) {
        val neutral = Configuration(configuration).apply { if (Build.VERSION.SDK_INT >= 31) fontWeightAdjustment = 0 }
        createFontFamilyResolver(context.createConfigurationContext(neutral))
    }
    val delta = if (enabled) model.number("weight", 0f).toInt().coerceIn(-300, 300) else 0
    CompositionLocalProvider(LocalFontFamilyResolver provides if (enabled) base else platformResolver, LocalWeightAdjustment provides delta, content = content)
}
