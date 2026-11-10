package com.review.compose

import org.junit.Assert.*
import org.junit.Test

class CacheTest {
    @Test fun neverEvictsRecentFilesOrVideoAsImageCache() {
        assertFalse(evictImageCache(59_999, Long.MAX_VALUE, true))
        assertFalse(evictImageCache(-1, Long.MAX_VALUE, true))
        assertTrue(evictImageCache(60_000, 1, true))
        assertFalse(evictImageCache(60_000, 1, false))
        assertTrue(evictImageCache(61L * 86400_000, 1, false))
    }
    @Test fun preservesOriginalThresholdsAndFormatting() {
        assertEquals(listOf(0, 50, 100, 200, 500, 1024, 2048), cacheThresholds)
        assertEquals("1.00 MB", cacheSizeLabel(1048576))
        assertEquals("2 GB", cacheThresholdLabel(2048))
    }
}
