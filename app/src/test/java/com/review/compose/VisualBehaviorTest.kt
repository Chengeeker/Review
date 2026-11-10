package com.review.compose

import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.RuntimeEnvironment
import org.robolectric.annotation.Config
import org.robolectric.annotation.GraphicsMode
import android.graphics.Bitmap
import android.graphics.BitmapShader
import android.graphics.Canvas
import android.graphics.Paint
import android.graphics.Shader
import androidx.compose.ui.geometry.Rect
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.luminance

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [35])
@GraphicsMode(GraphicsMode.Mode.NATIVE)
class VisualBehaviorTest {
    @Test fun copiedGlassShadersCompileOnTheAndroidRenderer() {
        val context = RuntimeEnvironment.getApplication()
        assertNotNull(glassShader(context))

    }
    private fun renderGlass(dark: Boolean, indicator: Boolean, patterned: Boolean = false, pressed: Float = 0f, plainButton: Boolean = false): Bitmap {
        val source = Bitmap.createBitmap(300, 180, Bitmap.Config.ARGB_8888)
        source.eraseColor(if (dark) android.graphics.Color.BLACK else android.graphics.Color.WHITE)
        if (patterned) Canvas(source).apply {
            for (x in 0 until 300 step 16) drawRect(x.toFloat(), 0f, x + 8f, 180f, Paint().apply { color = android.graphics.Color.BLACK })
        }
        val shader = glassShader(RuntimeEnvironment.getApplication())
        configureGlass(shader, Size(300f, 180f), Rect(30f, 30f, 270f, 150f), 3f,
            if (indicator) { if (dark) Color(0x26FFFFFF) else Color(0x18000000) }
            else if (dark) Color(0x66000000) else Color(0xF0FFFFFF), dark, indicator, pressed, 1f,
            if (dark) Color.Black else Color.White, plainButton = plainButton)
        shader.setInputShader("background", BitmapShader(source, Shader.TileMode.CLAMP, Shader.TileMode.CLAMP))
        val node = android.graphics.RenderNode("glass-test").apply { setPosition(0, 0, 300, 180) }
        node.beginRecording().drawRect(0f, 0f, 300f, 180f, Paint().apply { this.shader = shader })
        node.endRecording()
        val hardware = android.graphics.HardwareRenderer::class.java.getDeclaredMethod("createHardwareBitmap", android.graphics.RenderNode::class.java, Int::class.javaPrimitiveType, Int::class.javaPrimitiveType)
            .invoke(null, node, 300, 180) as Bitmap
        return hardware.copy(Bitmap.Config.ARGB_8888, false).also { hardware.recycle(); source.recycle(); node.discardDisplayList() }
    }
    @Test fun glassPixelsPreserveDarkTintAndHaveTransparentCorners() {
        val plain = renderGlass(false, false, plainButton = true)
        assertEquals(android.graphics.Color.WHITE, plain.getPixel(150, 90))
        assertEquals(0, android.graphics.Color.alpha(plain.getPixel(0, 0)))
        plain.recycle()
        for (dark in listOf(false, true)) for (indicator in listOf(false, true)) {
            val bitmap = renderGlass(dark, indicator)
            val center = bitmap.getPixel(150, 90)
            assertEquals(255, android.graphics.Color.alpha(center))
            val expected = if (dark) { if (indicator) 38 else 0 } else if (indicator) 231 else 255
            assertTrue("dark=$dark indicator=$indicator center=$center", kotlin.math.abs(android.graphics.Color.red(center) - expected) <= 2)
            assertEquals(0, android.graphics.Color.alpha(bitmap.getPixel(30, 30)))
            bitmap.recycle()
        }
    }
    @Test fun activeLensActuallyRefractsTheSampledContent() {
        val resting = renderGlass(false, true, patterned = true)
        val pressed = renderGlass(false, true, patterned = true, pressed = 1f)
        var changed = 0
        for (y in 65..115) for (x in 80..220) {
            if (kotlin.math.abs(android.graphics.Color.red(resting.getPixel(x, y)) - android.graphics.Color.red(pressed.getPixel(x, y))) > 20) changed++
        }
        assertTrue("Pinch must move backdrop pixels, not just tint the pill: $changed", changed > 100)
        java.io.File("build/reports/screenshots/glass-lens-pixels.png").apply { parentFile?.mkdirs() }.outputStream().use { pressed.compress(Bitmap.CompressFormat.PNG, 100, it) }
        resting.recycle(); pressed.recycle()
    }
    @Test fun allPalettesKeepReadableTextOnDarkAndPureBlackSurfaces() {
        val dynamicLight = reviewDynamicSurfaces(ReviewPalettes[0].first, false, 0xFF904A46.toInt(), 0xFFFFFBFA.toInt())
        assertEquals(Color(0xFFFFFBFA), dynamicLight.surface)
        assertTrue(dynamicLight.surfaceContainerLow.luminance() < dynamicLight.surface.luminance())
        val dynamicDark = reviewDynamicSurfaces(ReviewPalettes[0].second, true, 0xFFFFB3AE.toInt(), 0xFF191112.toInt())
        assertTrue(dynamicDark.surfaceContainerLow.luminance() > dynamicDark.surface.luminance())
        assertEquals("#5 1080x2400 @ 120Hz", refreshRateTitles(1260, 2800)[5])
        assertEquals("#1 1260x2800 @ 120Hz", refreshRateTitles(0, 0)[1])
        for ((light, dark) in ReviewPalettes) for (pureBlack in listOf(false, true)) {
            for ((scheme, night) in listOf(light to false, dark to true)) {
                val c = reviewColors(scheme, night, pureBlack)
                fun contrast(a: Color, b: Color): Float = (maxOf(a.luminance(), b.luminance()) + .05f) / (minOf(a.luminance(), b.luminance()) + .05f)
                for (surface in listOf(c.background, c.surface, c.surfaceContainerLowest, c.surfaceContainer, c.surfaceContainerHigh, c.surfaceContainerHighest)) {
                    assertTrue(contrast(c.onSurface, surface) >= 4.5f)
                    assertTrue(contrast(c.onSurfaceVariant, surface) >= 4.5f)
                }
                assertTrue(contrast(c.onPrimaryContainer, c.primaryContainer) >= 4.5f)
                assertTrue(contrast(c.onPrimary, c.primary) >= 4.5f)
                if (night && pureBlack) {
                    assertEquals(Color.Black, c.surface)
                    assertEquals(Color(0xFF222222), c.surfaceContainerHighest)
                }
            }
        }
    }
    @Test fun glassCommitsOnlyOnValidRelease() {
        assertArrayEquals(floatArrayOf(1f, 1f, .5f, .5f, 0f, 0f), glassButtonStretch(androidx.compose.ui.geometry.Offset.Zero), .001f)
        val stretch = glassButtonStretch(androidx.compose.ui.geometry.Offset(500f, 0f))
        assertTrue(stretch[0] in 1f..1.3f && stretch[1] in .85f..1f)
        assertEquals(0f, stretch[2], .001f)
        assertArrayEquals(floatArrayOf(1f, 1f), jellyScale(Float.NaN, 1f), .001f)
        assertArrayEquals(floatArrayOf(1f, 1f), jellyScale(1000f, 0f), .001f)
        assertArrayEquals(jellyScale(-1000f, 1f), jellyScale(1000f, 1f), .001f)
        assertEquals(.72f, jellyScale(1000f, 1f)[0], .001f)
        assertEquals(0, glassReleaseTarget(0, 0, 0f, false, false, false, false))
        assertNull(glassReleaseTarget(0, 0, 0f, true, false, false, false))
        assertNull(glassReleaseTarget(0, 2, 0f, false, true, false, true))
        assertNull(glassReleaseTarget(0, 2, 0f, false, false, true, false))
        assertEquals(2, glassReleaseTarget(0, 2, 500f, false, true, false, false))
        assertEquals(1, glassReleaseTarget(0, 2, 1200f, false, true, false, false))
        assertEquals(1, glassReleaseTarget(2, 0, -1200f, false, true, false, false))
    }
    @Test fun blurPreservesOpaqueUniformColorAndClampsEdges() {
        val pixels = IntArray(25) { 0xff284c90.toInt() }
        blurPixels(pixels, 5, 5, 7)
        assertTrue(pixels.all { it == 0xff284c90.toInt() })
        val impulse = IntArray(25) { 0xff000000.toInt() }.apply { this[12] = -1 }
        blurPixels(impulse, 5, 5, 1)
        assertTrue(impulse.all { it ushr 24 == 255 })
        assertTrue((impulse[12] and 255) in 1..254)
        assertEquals(impulse[0], impulse[24])
    }
    @Test fun visibilityMetadataAndFollowedTopicPrivacyArePreserved() {
        assertEquals("仅粉丝可见", visibilityLabel(postVisibility(JSONObject("""{"visible":{"type":10}}"""))))
        assertEquals(6, postVisibility(JSONObject("""{"title":{"text":"好友圈可见"}}""")))
        assertNull(postVisibility(JSONObject()))
        assertThrows(java.io.IOException::class.java) { followedTopicsPage(JSONObject("""{"ok":1,"data":{"msg":"仅自己可见"}}"""), 1) }
        assertThrows(java.io.IOException::class.java) { followedTopicsPage(JSONObject("""{"ok":1}"""), 1) }
        assertTrue(followedTopicsPage(JSONObject("""{"ok":1,"data":{"list":[]}}"""), 1).items.isEmpty())
        val page = followedTopicsPage(JSONObject("""{"data":{"max_page":2,"list":[{"oid":"1022:100808abc","topic_name":"测试"}]}}"""), 1)
        assertEquals("100808abc", page.items.single().id); assertEquals("2", page.next)
    }
}
