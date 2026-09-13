package com.klochkov.workingwithmaps.tracking

import org.junit.Assert.*
import org.junit.Test

class GpsFilterTest {
    private val filter = GpsFilter()
    private fun fix(lon: Double = 0.0, time: Long = 0, accuracy: Double = 5.0) =
        GpsFix(0.0, lon, accuracy, 0.0, time)
    @Test fun accuracyBoundaryAndMalformedFixes() {
        assertTrue(filter.accepts(fix(accuracy=50.0), null))
        assertFalse(filter.accepts(fix(accuracy=50.01), null))
        assertFalse(filter.accepts(fix(accuracy=Double.NaN), null))
        assertFalse(filter.accepts(fix(lon=181.0), null))
    }
    @Test fun movementAndCalculatedSpeedMatchDartPolicy() {
        assertFalse(filter.accepts(fix(0.00001, 10000), fix()))
        assertTrue(filter.accepts(fix(0.0001, 2000), fix()))
        assertFalse(filter.accepts(fix(0.01, 1000), fix()))
        assertFalse(filter.accepts(fix(0.0001, 0), fix()))
        assertFalse(filter.accepts(fix(0.0001, -1000), fix()))
    }
}
