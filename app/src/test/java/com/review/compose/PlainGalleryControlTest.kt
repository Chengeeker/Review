package com.review.compose

import android.graphics.Bitmap
import android.graphics.Canvas as AndroidCanvas
import android.view.ViewGroup
import androidx.activity.ComponentActivity
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.layout.*
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.mutableStateOf
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.rememberGraphicsLayer
import androidx.compose.ui.test.*
import androidx.compose.ui.test.junit4.createAndroidComposeRule
import androidx.compose.ui.unit.dp
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.rounded.ArrowBack
import androidx.compose.material.icons.rounded.Download
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.core.view.descendants
import androidx.compose.ui.input.key.Key
import androidx.compose.ui.semantics.SemanticsActions
import kotlin.math.abs
import org.junit.Assert.*
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.RuntimeEnvironment
import org.robolectric.annotation.Config
import org.robolectric.annotation.GraphicsMode

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [26, 35], qualifiers = "w412dp-h915dp-mdpi")
@GraphicsMode(GraphicsMode.Mode.NATIVE)
class PlainGalleryControlTest {
    val compose = createAndroidComposeRule<ComponentActivity>()
    private val register = org.junit.rules.TestRule { base, _ -> object : org.junit.runners.model.Statement() {
        override fun evaluate() {
            val context = androidx.test.core.app.ApplicationProvider.getApplicationContext<android.content.Context>()
            org.robolectric.Shadows.shadowOf(context.packageManager).addActivityIfNotPresent(
                android.content.ComponentName(context, ComponentActivity::class.java))
            runCatching { androidx.work.WorkManager.getInstance(context) }.onFailure {
                androidx.work.WorkManager.initialize(context, androidx.work.Configuration.Builder().build())
            }
            base.evaluate()
        }
    } }
    @get:Rule val rules: org.junit.rules.TestRule = org.junit.rules.RuleChain.outerRule(register).around(compose)

    @Test
    fun plainGalleryButtonsMatchRedNoteTintAndKeepTheirTouchTarget() {
        val model = androidx.lifecycle.ViewModelProvider(compose.activity)[ReviewModel::class.java]
        val enabled = mutableStateOf(true)
        var returned = 0
        var saved = 0
        val night = mutableStateOf(true)
        lateinit var inputMode: androidx.compose.ui.input.InputModeManager
        compose.setContent {
            inputMode = androidx.compose.ui.platform.LocalInputModeManager.current
            MaterialTheme(colorScheme = if (night.value) darkColorScheme() else lightColorScheme()) {
                Box(Modifier.size(112.dp, 48.dp)) {
                    Canvas(Modifier.fillMaxSize()) {
                        repeat(28) { stripe ->
                            drawRect(
                                if (stripe % 2 == 0) Color.Red else Color.Blue,
                                topLeft = Offset(stripe * 4f, 0f),
                                size = Size(4f, size.height),
                            )
                        }
                    }
                    CompositionLocalProvider(LocalReview provides model) {
                        Row(horizontalArrangement = Arrangement.spacedBy(16.dp)) {
                            GalleryGlassButton(Icons.Rounded.ArrowBack, "返回", enabled.value) { returned++ }
                            GalleryGlassButton(Icons.Rounded.Download, "保存图片", enabled.value) { saved++ }
                        }
                    }
                }
            }
        }
        fun sampleButton(label: String): List<Int> {
            val node = compose.onNodeWithContentDescription(label)
            val bounds = node.fetchSemanticsNode().boundsInRoot
            assertEquals(48f, bounds.width, .01f)
            assertEquals(48f, bounds.height, .01f)
            return compose.runOnUiThread {
                val view = compose.activity.findViewById<android.view.View>(android.R.id.content)
                val root = view as ViewGroup
                assertFalse(root.descendants.any { it is android.view.TextureView || it.javaClass.name.contains("AndroidViewsHandler") })
                val frame = Bitmap.createBitmap(view.width, view.height, Bitmap.Config.ARGB_8888)
                try {
                    view.draw(AndroidCanvas(frame))
                    (6..10).map { x -> frame.getPixel(bounds.left.toInt() + x, bounds.top.toInt() + 24) }
                } finally {
                    frame.recycle()
                }
            }
        }
        for (label in listOf("返回", "保存图片")) {
            val button = compose.onNodeWithContentDescription(label)
            val bounds = button.fetchSemanticsNode().boundsInRoot
            val resting = sampleButton(label)
            assertTrue("the plain control uses a translucent black fill", resting.all {
                val red = android.graphics.Color.red(it)
                val blue = android.graphics.Color.blue(it)
                (red in 140..165 && blue < 8) || (blue in 140..165 && red < 8)
            })
            fun brightness(pixels: List<Int>) = pixels.sumOf {
                android.graphics.Color.red(it) + android.graphics.Color.green(it) + android.graphics.Color.blue(it)
            }
            compose.mainClock.autoAdvance = false
            button.performTouchInput { down(center) }
            compose.waitForIdle()
            compose.mainClock.advanceTimeByFrame()
            compose.mainClock.advanceTimeBy(120)
            val pressed = sampleButton(label)
            assertTrue("pressed button reduces the black tint", brightness(pressed) > brightness(resting))
            assertEquals(bounds, button.fetchSemanticsNode().boundsInRoot)
            button.performTouchInput { up() }
            compose.waitForIdle()
            compose.mainClock.advanceTimeByFrame()
            compose.mainClock.advanceTimeBy(120)
            assertEquals("released button returns to its resting tint", brightness(resting), brightness(sampleButton(label)))
            compose.mainClock.autoAdvance = true
        }
        assertEquals(1, returned)
        assertEquals(1, saved)
        compose.runOnIdle { inputMode.requestInputMode(androidx.compose.ui.input.InputMode.Keyboard) }
        compose.onNodeWithContentDescription("返回").performSemanticsAction(SemanticsActions.RequestFocus) { it() }
        compose.onNodeWithContentDescription("返回").assertIsFocused()
        compose.onNodeWithContentDescription("返回").performKeyInput { pressKey(Key.Spacebar) }
        compose.runOnIdle { assertEquals(2, returned) }
        compose.runOnIdle {
            night.value = false
            enabled.value = false
        }
        compose.onNodeWithContentDescription("返回").assertIsNotEnabled().performTouchInput { click() }
        compose.onNodeWithContentDescription("保存图片").assertIsNotEnabled().performTouchInput { click() }
        assertEquals(5, sampleButton("返回").size)
        assertEquals(5, sampleButton("保存图片").size)
        compose.runOnIdle { assertEquals(2, returned) }
        assertEquals(1, saved)
    }
}
