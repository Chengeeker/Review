package com.review.compose

import android.content.Context
import android.graphics.Bitmap
import android.graphics.SurfaceTexture
import android.opengl.*
import android.os.Handler
import android.os.HandlerThread
import android.view.TextureView
import java.nio.ByteBuffer
import java.nio.ByteOrder

// The original two-pass shaders use top-down pixels; only GL framebuffer reads flip Y.
internal class GlassView(context: Context) :
    TextureView(context), TextureView.SurfaceTextureListener {
    private val thread = HandlerThread("ReviewGlass").apply { start() }
    private val worker = Handler(thread.looper)
    private var display = EGL14.EGL_NO_DISPLAY
    private var eglContext = EGL14.EGL_NO_CONTEXT
    private var surface = EGL14.EGL_NO_SURFACE
    private var target: SurfaceTexture? = null
    private var programs = IntArray(0)
    private val textures = IntArray(8)
    private val buffers = IntArray(5)
    private var vertexBuffer = 0
    @Volatile
    var surfaceGeneration = 0
        private set

    private var bufferWidth = 0
    private var bufferHeight = 0
    private var frostDirty = true
    private var frostDark = false
    @Volatile private var closed = false
    @Volatile
    var ready = false
        private set

    var failure: ((String) -> Unit)? = null
    private val vertices =
        ByteBuffer.allocateDirect(32).order(ByteOrder.nativeOrder()).asFloatBuffer().apply {
            put(floatArrayOf(-1f, -1f, 1f, -1f, -1f, 1f, 1f, 1f))
            position(0)
        }

    init {
        isOpaque = false
        surfaceTextureListener = this
    }

    override fun onSurfaceTextureAvailable(target: SurfaceTexture, width: Int, height: Int) {
        worker.post {
            if (closed) {
                target.release()
                return@post
            }
            try {
                this.target = target
                display = EGL14.eglGetDisplay(EGL14.EGL_DEFAULT_DISPLAY)
                check(EGL14.eglInitialize(display, IntArray(2), 0, IntArray(2), 1))
                val configs = arrayOfNulls<EGLConfig>(1)
                val count = IntArray(1)
                check(
                    EGL14.eglChooseConfig(
                        display,
                        intArrayOf(
                            EGL14.EGL_RENDERABLE_TYPE,
                            0x40,
                            EGL14.EGL_SURFACE_TYPE,
                            EGL14.EGL_WINDOW_BIT,
                            EGL14.EGL_RED_SIZE,
                            8,
                            EGL14.EGL_GREEN_SIZE,
                            8,
                            EGL14.EGL_BLUE_SIZE,
                            8,
                            EGL14.EGL_ALPHA_SIZE,
                            8,
                            EGL14.EGL_NONE,
                        ),
                        0,
                        configs,
                        0,
                        1,
                        count,
                        0,
                    ) && count[0] > 0
                )
                eglContext =
                    EGL14.eglCreateContext(
                        display,
                        configs[0],
                        EGL14.EGL_NO_CONTEXT,
                        intArrayOf(EGL14.EGL_CONTEXT_CLIENT_VERSION, 3, EGL14.EGL_NONE),
                        0,
                    )
                surface =
                    EGL14.eglCreateWindowSurface(
                        display,
                        configs[0],
                        target,
                        intArrayOf(EGL14.EGL_NONE),
                        0,
                    )
                check(EGL14.eglMakeCurrent(display, surface, surface, eglContext))
                programs =
                    listOf(
                            "liquid_glass_geometry_blended",
                            "liquid_glass_render",
                            "compose",
                            "gallery_button",
                        )
                        .map { name ->
                            program(
                                context.assets.open("glass/$name.frag").bufferedReader().use {
                                    it.readText()
                                }
                            )
                        }
                        .toIntArray()
                val vbo = IntArray(1)
                GLES30.glGenBuffers(1, vbo, 0)
                vertexBuffer = vbo[0]
                GLES30.glBindBuffer(GLES30.GL_ARRAY_BUFFER, vertexBuffer)
                GLES30.glBufferData(GLES30.GL_ARRAY_BUFFER, 32, vertices, GLES30.GL_STATIC_DRAW)
                GLES30.glGenTextures(textures.size, textures, 0)
                GLES30.glGenFramebuffers(buffers.size, buffers, 0)
                textures.forEach { texture ->
                    GLES30.glBindTexture(GLES30.GL_TEXTURE_2D, texture)
                    GLES30.glTexParameteri(
                        GLES30.GL_TEXTURE_2D,
                        GLES30.GL_TEXTURE_MIN_FILTER,
                        GLES30.GL_LINEAR,
                    )
                    GLES30.glTexParameteri(
                        GLES30.GL_TEXTURE_2D,
                        GLES30.GL_TEXTURE_MAG_FILTER,
                        GLES30.GL_LINEAR,
                    )
                    GLES30.glTexParameteri(
                        GLES30.GL_TEXTURE_2D,
                        GLES30.GL_TEXTURE_WRAP_S,
                        GLES30.GL_CLAMP_TO_EDGE,
                    )
                    GLES30.glTexParameteri(
                        GLES30.GL_TEXTURE_2D,
                        GLES30.GL_TEXTURE_WRAP_T,
                        GLES30.GL_CLAMP_TO_EDGE,
                    )
                }
                surfaceGeneration++
                ready = true
            } catch (e: Exception) {
                post { failure?.invoke(e.message ?: "玻璃渲染初始化失败") }
            }
        }
    }

    private fun program(fragment: String): Int {
        val vertex =
            """#version 300 es
            layout(location=0) in vec2 point;
            uniform vec2 size;
            out vec2 vPosition;
            void main(){gl_Position=vec4(point,0.0,1.0);vPosition=vec2((point.x+1.0)*0.5,(1.0-point.y)*0.5)*size;}
        """
                .trimIndent()
        fun shader(type: Int, source: String): Int {
            val id = GLES30.glCreateShader(type)
            GLES30.glShaderSource(id, source)
            GLES30.glCompileShader(id)
            val status = IntArray(1)
            GLES30.glGetShaderiv(id, GLES30.GL_COMPILE_STATUS, status, 0)
            if (status[0] == 0) {
                val log = GLES30.glGetShaderInfoLog(id)
                GLES30.glDeleteShader(id)
                error(log)
            }
            return id
        }
        val v = shader(GLES30.GL_VERTEX_SHADER, vertex)
        val f =
            try {
                shader(GLES30.GL_FRAGMENT_SHADER, fragment)
            } catch (e: Exception) {
                GLES30.glDeleteShader(v)
                throw e
            }
        val p = GLES30.glCreateProgram()
        GLES30.glAttachShader(p, v)
        GLES30.glAttachShader(p, f)
        GLES30.glLinkProgram(p)
        GLES30.glDeleteShader(v)
        GLES30.glDeleteShader(f)
        val status = IntArray(1)
        GLES30.glGetProgramiv(p, GLES30.GL_LINK_STATUS, status, 0)
        check(status[0] != 0) { GLES30.glGetProgramInfoLog(p) }
        return p
    }

    private fun uniform(p: Int, name: String, vararg values: Float) {
        val location = GLES30.glGetUniformLocation(p, name)
        when (values.size) {
            1 -> GLES30.glUniform1f(location, values[0])
            2 -> GLES30.glUniform2fv(location, 1, values, 0)
            3 -> GLES30.glUniform3fv(location, 1, values, 0)
            4 -> GLES30.glUniform4fv(location, 1, values, 0)
        }
    }

    private fun sampler(p: Int, name: String, unit: Int, texture: Int) {
        GLES30.glActiveTexture(GLES30.GL_TEXTURE0 + unit)
        GLES30.glBindTexture(GLES30.GL_TEXTURE_2D, texture)
        GLES30.glUniform1i(GLES30.glGetUniformLocation(p, name), unit)
    }

    private fun draw(p: Int, w: Int, h: Int) {
        uniform(p, "size", w.toFloat(), h.toFloat())
        GLES30.glEnableVertexAttribArray(0)
        GLES30.glVertexAttribPointer(0, 2, GLES30.GL_FLOAT, false, 0, 0)
        GLES30.glDrawArrays(GLES30.GL_TRIANGLE_STRIP, 0, 4)
    }

    fun render(
        background: Bitmap?,
        labels: Bitmap?,
        selected: Float,
        pressed: Float,
        dark: Boolean,
        density: Float,
        kind: Int = 0,
        lensVelocity: Float = 0f,
        selectedLabels: Bitmap? = null,
        generation: Int = surfaceGeneration,
        outputSize: androidx.compose.ui.unit.IntSize? = null,
        touch: Float = 0f,
        complete: (Boolean) -> Unit,
    ) {
        if (closed) {
            background?.recycle()
            labels?.recycle()
            selectedLabels?.recycle()
            complete(false)
            return
        }
        worker.post {
            var presented = false
            try {
                if (!ready || generation != surfaceGeneration) return@post
                // The legacy header is already downsampled. Blur at its sampled resolution
                // and only upscale during the final draw to the TextureView.
                val w =
                    if (kind == 4) background?.width ?: bufferWidth
                    else outputSize?.width ?: background?.width ?: bufferWidth
                val h =
                    if (kind == 4) background?.height ?: bufferHeight
                    else outputSize?.height ?: background?.height ?: bufferHeight
                if (w == 0 || h == 0) return@post
                val wf = w.toFloat()
                val hf = h.toFloat()
                val scale = density / 3f
                GLES30.glViewport(0, 0, w, h)
                GLES30.glActiveTexture(GLES30.GL_TEXTURE0)
                fun upload(bitmap: Bitmap?, index: Int) {
                    if (bitmap == null) return
                    GLES30.glBindTexture(GLES30.GL_TEXTURE_2D, textures[index])
                    GLUtils.texImage2D(GLES30.GL_TEXTURE_2D, 0, bitmap, 0)
                }
                upload(background, 0)
                if (background != null || frostDark != dark) frostDirty = true
                frostDark = dark
                upload(labels, 1)
                upload(selectedLabels, 6)
                if (bufferWidth != w || bufferHeight != h) {
                    frostDirty = true
                    for (i in 0 until if (kind == 0) 5 else 4) {
                        val texture = textures[if (i == 4) 7 else i + 2]
                        GLES30.glBindTexture(GLES30.GL_TEXTURE_2D, texture)
                        GLES30.glTexImage2D(
                            GLES30.GL_TEXTURE_2D,
                            0,
                            GLES30.GL_RGBA,
                            w,
                            h,
                            0,
                            GLES30.GL_RGBA,
                            GLES30.GL_UNSIGNED_BYTE,
                            null,
                        )
                        GLES30.glBindFramebuffer(GLES30.GL_FRAMEBUFFER, buffers[i])
                        GLES30.glFramebufferTexture2D(
                            GLES30.GL_FRAMEBUFFER,
                            GLES30.GL_COLOR_ATTACHMENT0,
                            GLES30.GL_TEXTURE_2D,
                            texture,
                            0,
                        )
                        check(
                            GLES30.glCheckFramebufferStatus(GLES30.GL_FRAMEBUFFER) ==
                                GLES30.GL_FRAMEBUFFER_COMPLETE
                        )
                    }
                    bufferWidth = w
                    bufferHeight = h
                }
                val barWidth = wf - 40 * density
                val barHeight = if (kind == 0) 56 * density else hf - 30 * density
                val tab = (barWidth - 8 * density) / 3f
                val cx = 20 * density + 4 * density + tab * (selected + .5f)
                val jelly = jellyScale(lensVelocity, pressed)
                val lensWidth = (tab * (1 + .06f * pressed) + 24 * density * pressed) * jelly[0]
                val lensHeight =
                    ((barHeight - 8 * density) * (1 + .06f * pressed) + 16 * density * pressed) *
                        jelly[1]
                fun composite(
                    target: Int,
                    texture: Int,
                    flip: Boolean,
                    blur: Float = 0f,
                    indicator: Boolean = false,
                    vertical: Boolean = false,
                    labelPass: Boolean = false,
                    pillBlur: Float = 0f,
                ) {
                    GLES30.glBindFramebuffer(GLES30.GL_FRAMEBUFFER, target)
                    val p = programs[2]
                    GLES30.glUseProgram(p)
                    sampler(p, "source", 0, texture)
                    uniform(p, "flip", if (flip) 1f else 0f)
                    uniform(p, "blur", blur)
                    uniform(p, "denseBlur", if (kind == 4) 1f else 0f)
                    uniform(p, "blurDirection", if (vertical) 0f else 1f, if (vertical) 1f else 0f)
                    uniform(p, "indicator", if (indicator) 1f - pressed else 0f)
                    uniform(p, "pill", cx, hf / 2, lensWidth, lensHeight)
                    uniform(p, "labelPass", if (labelPass) 1f else 0f)
                    uniform(p, "pillBlur", pillBlur)
                    if (pillBlur > 0f) sampler(p, "pillBackdrop", 3, textures[7])
                    if (labelPass) sampler(p, "selectedLabels", 2, textures[6])
                    uniform(p, "dark", if (dark) 1f else 0f)
                    draw(p, w, h)
                }
                GLES30.glDisable(GLES30.GL_BLEND)
                val sigma =
                    if (kind == 4) 20 * density * w / (outputSize?.width ?: w)
                    else (if (kind == 1) 2f else if (kind == 2) 2.5f else 1.5f) * density
                composite(buffers[3], textures[0], false, sigma)
                composite(buffers[1], textures[5], true, sigma, vertical = true)
                if (kind == 4) {
                    GLES30.glViewport(0, 0, outputSize?.width ?: w, outputSize?.height ?: h)
                    composite(0, textures[3], true)
                    check(GLES30.glGetError() == GLES30.GL_NO_ERROR)
                    check(EGL14.eglSwapBuffers(display, surface))
                    presented = true
                    return@post
                }
                GLES30.glBindFramebuffer(GLES30.GL_FRAMEBUFFER, buffers[2])
                GLES30.glClearColor(0f, 0f, 0f, 0f)
                GLES30.glClear(GLES30.GL_COLOR_BUFFER_BIT)
                fun glass(lens: Boolean) {
                    val fade = if (lens) pressed.coerceIn(.001f, 1f) else 1f
                    val thickness = (if (lens) 20f * fade else if (kind == 1) 32f else 10f) * scale
                    val ri = if (lens) 1f + .18f * fade else if (kind == 1) 1.24f else 1.16f
                    val ca = if (lens) .025f * fade else if (kind == 1) .025f else .008f
                    GLES30.glBindFramebuffer(GLES30.GL_FRAMEBUFFER, buffers[0])
                    GLES30.glDisable(GLES30.GL_BLEND)
                    val g = programs[0]
                    GLES30.glUseProgram(g)
                    uniform(g, "uSize", wf, hf)
                    uniform(g, "uOpticalProps", ri, ca, thickness, 0f)
                    uniform(g, "uShapeSettings", 1f, density)
                    uniform(g, "uNativeEdge", if (!dark && lens) 1f else 0f)
                    val shape = FloatArray(112)
                    shape[0] = 3f
                    shape[1] = if (lens) cx else wf / 2
                    shape[2] = hf / 2
                    shape[3] = if (lens) lensWidth else barWidth
                    shape[4] = if (lens) lensHeight else barHeight
                    shape[5] = 9999f
                    shape[6] = 9999f
                    GLES30.glUniform1fv(GLES30.glGetUniformLocation(g, "uShapeData"), 112, shape, 0)
                    draw(g, w, h)
                    GLES30.glBindFramebuffer(GLES30.GL_FRAMEBUFFER, if (lens) 0 else buffers[2])
                    GLES30.glEnable(GLES30.GL_BLEND)
                    GLES30.glBlendFunc(GLES30.GL_ONE, GLES30.GL_ONE_MINUS_SRC_ALPHA)
                    val p = programs[1]
                    GLES30.glUseProgram(p)
                    uniform(p, "uLayerFade", if (lens) 1f - pressed else 0f)
                    uniform(p, "uSize", wf, hf)
                    uniform(
                        p,
                        "uGeometryOffset",
                        (if (lens) cx else wf / 2) - (if (lens) lensWidth else barWidth) / 2,
                        (hf - (if (lens) lensHeight else barHeight)) / 2,
                    )
                    uniform(
                        p,
                        "uGeometrySize",
                        if (lens) lensWidth else barWidth,
                        if (lens) lensHeight else barHeight,
                    )
                    val rgb =
                        if (lens) {
                            if (dark) 1f else 0f
                        } else {
                            if (kind == 1 || dark) 0f else 1f
                        }
                    uniform(
                        p,
                        "uGlassColor",
                        rgb,
                        rgb,
                        rgb,
                        (if (lens) {
                            if (dark) 38f / 255 else 24f / 255
                        } else {
                            if (kind == 1 || dark) .4f else 240f / 255
                        }) * fade,
                    )
                    uniform(p, "uOpticalProps", ri, ca, thickness, 1f)
                    uniform(
                        p,
                        "uLightConfig",
                        (if (lens) 2f else .25f) * fade,
                        0f,
                        if (lens || kind == 1) 1.5f else 1f,
                    )
                    uniform(p, "uLightDirection", -.7071068f, .7071068f)
                    uniform(p, "uWhiten", 0f)
                    uniform(p, "uWhitenGated", 1f)
                    uniform(
                        p,
                        "uPinchStrength",
                        if (lens) .7f * (1 - (1 - fade) * (1 - fade)) else 0f,
                    )
                    uniform(p, "uBackgroundFallback", 0f, 0f, 0f, 0f)
                    uniform(p, "uCaptureOffset", 0f, 0f)
                    uniform(p, "uEdgeConfig", 0f, fade, scale, 0f)
                    uniform(p, "uPlatformViewMode", 0f)
                    uniform(p, "uBodyMode", 1f)
                    uniform(p, "uTouchPosition", if (kind == 1) wf / 2 else cx, hf / 2)
                    uniform(p, "uTouchIntensity", (if (kind == 1) touch else pressed) * .125f)
                    uniform(
                        p,
                        "uRimConfig",
                        if (lens && !dark) .12f * fade else 0f,
                        (if (kind == 1) 0f
                        else if (dark) {
                            if (lens || kind == 3) 0f else .12f
                        } else if (lens) .35f else 1f) * fade,
                        .2f,
                    )
                    uniform(p, "uLensModel", 0f)
                    uniform(p, "uFrost", 0f, 0f, 0f, 1f)
                    uniform(p, "uBodyShade", 0f)
                    uniform(p, "uBackgroundFlip", 1f)
                    sampler(p, "uBackgroundTexture", 0, textures[if (lens) 5 else 3])
                    sampler(p, "uGeometryTexture", 1, textures[2])
                    draw(p, w, h)
                }
                if (kind == 2) {
                    GLES30.glBindFramebuffer(GLES30.GL_FRAMEBUFFER, buffers[2])
                    val p = programs[3]
                    GLES30.glUseProgram(p)
                    val diameter = 44 * density
                    val x = (wf - diameter) / 2
                    val y = (hf - diameter) / 2
                    GLES30.glViewport(x.toInt(), y.toInt(), diameter.toInt(), diameter.toInt())
                    uniform(p, "u_size", diameter, diameter)
                    uniform(p, "u_origin", x, y)
                    uniform(p, "u_capture", wf, hf)
                    uniform(p, "u_density", density)
                    sampler(p, "u_texture_input", 0, textures[3])
                    GLES30.glEnable(GLES30.GL_BLEND)
                    GLES30.glBlendFunc(GLES30.GL_ONE, GLES30.GL_ONE_MINUS_SRC_ALPHA)
                    draw(p, diameter.toInt(), diameter.toInt())
                    GLES30.glViewport(0, 0, w, h)
                } else glass(false)
                GLES30.glDisable(GLES30.GL_BLEND)
                if (kind == 0) {
                    val innerBlur = 6 * density
                    if (frostDirty) {
                        composite(buffers[1], textures[0], false)
                        GLES30.glEnable(GLES30.GL_BLEND)
                        GLES30.glBlendFunc(GLES30.GL_ONE, GLES30.GL_ONE_MINUS_SRC_ALPHA)
                        composite(buffers[1], textures[4], true)
                        GLES30.glDisable(GLES30.GL_BLEND)
                        composite(buffers[4], textures[3], true, blur = innerBlur)
                        frostDirty = false
                    }
                    composite(buffers[0], textures[4], true, indicator = true, pillBlur = innerBlur)
                    GLES30.glEnable(GLES30.GL_BLEND)
                    GLES30.glBlendFunc(GLES30.GL_ONE, GLES30.GL_ONE_MINUS_SRC_ALPHA)
                    composite(buffers[0], textures[1], false, labelPass = true)
                    GLES30.glDisable(GLES30.GL_BLEND)
                    composite(0, textures[2], true)
                    if (pressed > .001f) {
                        // The scene is a lens input only. The window keeps transparent margins.
                        composite(buffers[3], textures[0], false)
                        GLES30.glEnable(GLES30.GL_BLEND)
                        composite(buffers[3], textures[2], true)
                        glass(true)
                    }
                } else {
                    composite(0, textures[4], true)
                }
                check(GLES30.glGetError() == GLES30.GL_NO_ERROR)
                check(EGL14.eglSwapBuffers(display, surface))
                presented = true
            } catch (e: Exception) {
                post { failure?.invoke(e.message ?: "玻璃渲染失败") }
            } finally {
                background?.recycle()
                labels?.recycle()
                selectedLabels?.recycle()
                post { complete(presented) }
            }
        }
    }

    override fun onSurfaceTextureSizeChanged(target: SurfaceTexture, width: Int, height: Int) {}

    override fun onSurfaceTextureUpdated(target: SurfaceTexture) {}

    override fun onSurfaceTextureDestroyed(target: SurfaceTexture): Boolean {
        worker.post { releaseSurface(target) }
        return false
    }

    private fun releaseSurface(owned: SurfaceTexture?) {
        ready = false
        if (display != EGL14.EGL_NO_DISPLAY) {
            programs.forEach(GLES30::glDeleteProgram)
            if (vertexBuffer != 0) GLES30.glDeleteBuffers(1, intArrayOf(vertexBuffer), 0)
            vertexBuffer = 0
            GLES30.glDeleteTextures(textures.size, textures, 0)
            GLES30.glDeleteFramebuffers(buffers.size, buffers, 0)
            EGL14.eglMakeCurrent(
                display,
                EGL14.EGL_NO_SURFACE,
                EGL14.EGL_NO_SURFACE,
                EGL14.EGL_NO_CONTEXT,
            )
            if (surface != EGL14.EGL_NO_SURFACE) EGL14.eglDestroySurface(display, surface)
            if (eglContext != EGL14.EGL_NO_CONTEXT) EGL14.eglDestroyContext(display, eglContext)
            EGL14.eglTerminate(display)
        }
        owned?.release()
        target = null
        display = EGL14.EGL_NO_DISPLAY
        surface = EGL14.EGL_NO_SURFACE
        eglContext = EGL14.EGL_NO_CONTEXT
        bufferWidth = 0
        bufferHeight = 0
        programs = IntArray(0)
    }

    fun close() {
        if (closed) return
        closed = true
        worker.post {
            releaseSurface(target)
            thread.quitSafely()
        }
    }
}
