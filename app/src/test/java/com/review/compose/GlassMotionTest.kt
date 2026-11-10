package com.review.compose

import androidx.activity.ComponentActivity
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.runtime.*
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.layout.positionInRoot
import androidx.compose.ui.test.*
import androidx.compose.ui.test.junit4.createAndroidComposeRule
import androidx.compose.ui.unit.dp
import org.junit.*
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.RuntimeEnvironment
import org.robolectric.annotation.Config
import org.robolectric.annotation.GraphicsMode

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [35], qualifiers = "w412dp-h915dp-mdpi")
@GraphicsMode(GraphicsMode.Mode.NATIVE)
class GlassMotionTest {
    @get:Rule val compose = createAndroidComposeRule<ComponentActivity>()

    @Test
    fun releasingWaterBeginsContractionImmediatelyAndFadesToRest() {
        val touching = mutableStateOf(true)
        var pressure = 0f
        compose.mainClock.autoAdvance = false
        compose.setContent {
            val value = navigationGlassMotion(1, touching.value, true, 1f, longPressed = true)
            SideEffect { pressure = value.second }
        }
        compose.runOnIdle { Assert.assertEquals(1f, pressure, .001f) }
        compose.runOnUiThread { touching.value = false }
        repeat(6) {
            compose.mainClock.advanceTimeByFrame()
            compose.waitForIdle()
        }
        var previous =
            compose.runOnIdle {
                Assert.assertTrue(
                    "release must not hold full pressure for 250 ms (pressure=$pressure)",
                    pressure in .001f..0.999f,
                )
                pressure
            }
        repeat(4) {
            compose.mainClock.advanceTimeBy(32)
            compose.runOnIdle {
                Assert.assertTrue(pressure <= previous)
                previous = pressure
            }
        }
        compose.mainClock.advanceTimeBy(80)
        compose.runOnIdle { Assert.assertEquals(0f, pressure, .001f) }
        Assert.assertArrayEquals(floatArrayOf(1f, 1f), jellyScale(100f, 0f), .001f)
    }

    @Test
    fun onlyLongPressActivatesWaterWhileTapsAndQuickDragsMovePlate() {
        val selected = mutableIntStateOf(0)
        val dragging = mutableStateOf(false)
        val longPressed = mutableStateOf(false)
        var lens = 0f
        var press = 0f
        compose.mainClock.autoAdvance = false
        compose.setContent {
            val value =
                navigationGlassMotion(
                    selected.intValue,
                    dragging.value,
                    dragging.value,
                    2f,
                    longPressed.value,
                )
            SideEffect {
                lens = value.first
                press = value.second
            }
        }
        compose.runOnUiThread { selected.intValue = 2 }
        repeat(12) {
            compose.mainClock.advanceTimeBy(16)
            compose.runOnIdle { Assert.assertEquals(0f, press, 0f) }
        }
        compose.runOnIdle { Assert.assertTrue(lens > 0f) }
        compose.runOnUiThread { selected.intValue = 1 }
        compose.mainClock.advanceTimeBy(64)
        compose.runOnIdle { Assert.assertEquals(0f, press, 0f) }
        compose.runOnUiThread { dragging.value = true }
        repeat(10) {
            compose.mainClock.advanceTimeByFrame()
            compose.runOnIdle { Assert.assertEquals(0f, press, 0f) }
        }
        compose.runOnIdle { Assert.assertTrue(lens > 1.5f) }
        compose.runOnUiThread { longPressed.value = true }
        repeat(10) {
            compose.mainClock.advanceTimeByFrame()
            compose.waitForIdle()
        }
        compose.runOnIdle { Assert.assertTrue("long press pressure=$press", press > .1f) }
        compose.runOnUiThread {
            dragging.value = false
            longPressed.value = false
        }
        repeat(20) {
            compose.mainClock.advanceTimeByFrame()
            compose.waitForIdle()
        }
        compose.runOnIdle { Assert.assertEquals(0f, press, .001f) }
    }


}