package com.review.compose

import android.graphics.*
import androidx.compose.ui.geometry.Rect
import androidx.compose.ui.geometry.Size
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.RuntimeEnvironment
import org.robolectric.annotation.Config
import org.robolectric.annotation.GraphicsMode

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [35])
@GraphicsMode(GraphicsMode.Mode.NATIVE)
class GlassGpuTest {
    private fun hostCanvas(bitmap: Bitmap): Canvas =
        Canvas(bitmap).also {
            // Host Skia can evaluate AGSL; this does not emulate Android HWUI scheduling.
            org.robolectric.util.ReflectionHelpers.callInstanceMethod<Unit>(
                it,
                "setHwFeaturesInSwModeEnabled",
                org.robolectric.util.ReflectionHelpers.ClassParameter.from(
                    Boolean::class.javaPrimitiveType,
                    true,
                ),
            )
        }

    @Test
    fun liveShaderKeepsOrientationTransparencyAndMovingLensCoordinates() {
        val optics = GlassOptics(RuntimeEnvironment.getApplication())
        val source = Bitmap.createBitmap(256, 86, Bitmap.Config.ARGB_8888)
        val canvas = Canvas(source)
        val paint = Paint()
        paint.color = Color.RED
        canvas.drawRect(0f, 0f, 256f, 43f, paint)
        paint.color = Color.BLUE
        canvas.drawRect(0f, 43f, 256f, 86f, paint)
        optics.shader.setInputShader(
            "background",
            BitmapShader(source, Shader.TileMode.CLAMP, Shader.TileMode.CLAMP),
        )
        val output = Bitmap.createBitmap(256, 86, Bitmap.Config.ARGB_8888)
        fun draw(shape: Rect, lens: Boolean = false) {
            output.eraseColor(Color.TRANSPARENT)
            optics.configure(Size(256f, 86f), shape, 1f, true, lens, if (lens) 1f else 0f, lens)
            val target = hostCanvas(output)
            target.drawRect(0f, 0f, 256f, 86f, Paint().apply { shader = optics.shader })
        }
        draw(Rect(20f, 15f, 236f, 71f))
        assertEquals(0, Color.alpha(output.getPixel(4, 43)))
        assertTrue(Color.red(output.getPixel(128, 30)) > 100)
        assertEquals(0, Color.blue(output.getPixel(128, 30)))
        assertTrue(Color.blue(output.getPixel(128, 55)) > 100)
        assertEquals(0, Color.red(output.getPixel(128, 55)))
        draw(Rect(24f, 19f, 94f, 67f), true)
        assertEquals(255, Color.alpha(output.getPixel(59, 43)))
        assertEquals(0, Color.alpha(output.getPixel(198, 43)))
        draw(Rect(162f, 19f, 232f, 67f), true)
        assertEquals(0, Color.alpha(output.getPixel(59, 43)))
        assertEquals(255, Color.alpha(output.getPixel(198, 43)))
        source.recycle()
        output.recycle()
    }

    @Test
    fun renderOriginalOpticsComparisonFrames() {
        val app = RuntimeEnvironment.getApplication()
        val optics = GlassOptics(app)
        val source = Bitmap.createBitmap(256, 86, Bitmap.Config.ARGB_8888)
        val pixels =
            IntArray(256 * 86) { i ->
                val x = i % 256
                val y = i / 256
                Color.rgb(x, y * 3, if ((x / 16 + y / 16) % 2 == 0) 220 else 40)
            }
        source.setPixels(pixels, 0, 256, 0, 0, 256, 86)
        optics.shader.setInputShader(
            "background",
            BitmapShader(source, Shader.TileMode.CLAMP, Shader.TileMode.CLAMP),
        )
        for (dark in listOf(false, true)) for (lens in listOf(false, true)) {
            val shape = if (lens) Rect(79.5f, 9.5f, 176.5f, 76.5f) else Rect(20f, 15f, 236f, 71f)
            optics.configure(Size(256f, 86f), shape, 1f, dark, lens, if (lens) 1f else 0f, lens)
            assertNotNull(optics.effect())
            val output = Bitmap.createBitmap(256, 86, Bitmap.Config.ARGB_8888)
            hostCanvas(output).drawRect(0f, 0f, 256f, 86f, Paint().apply { shader = optics.shader })
            output.getPixels(pixels, 0, 256, 0, 0, 256, 86)
            val bytes = ByteArray(pixels.size * 4)
            pixels.forEachIndexed { i, c ->
                bytes[4 * i] = Color.red(c).toByte()
                bytes[4 * i + 1] = Color.green(c).toByte()
                bytes[4 * i + 2] = Color.blue(c).toByte()
                bytes[4 * i + 3] = Color.alpha(c).toByte()
            }
            java.io.File("build/parity/agsl-$dark-$lens.rgba").apply {
                parentFile?.mkdirs()
                writeBytes(bytes)
            }
            output.recycle()
        }
        // Also construct the small gallery and detail paths, including their uniforms.
        for (kind in listOf(1, 3)) {
            optics.configure(
                Size(88f, 78f),
                Rect(20f, 15f, 68f, 63f),
                1f,
                true,
                kind = kind,
                touch = 1f,
            )
            assertNotNull(optics.effect())
        }
        source.recycle()
    }
}
