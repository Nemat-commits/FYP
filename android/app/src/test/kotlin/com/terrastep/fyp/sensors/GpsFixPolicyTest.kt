package com.terrastep.fyp.sensors

import org.junit.Assert.*
import org.junit.Test

class GpsFixPolicyTest {
    @Test fun staleAndFutureFixesAreRejected() {
        assertTrue(GpsFixPolicy.isFresh(0))
        assertTrue(GpsFixPolicy.isFresh(15000))
        assertFalse(GpsFixPolicy.isFresh(15001))
        assertFalse(GpsFixPolicy.isFresh(-1))
    }
    @Test fun ordinaryWalkingAddsDistance() {
        assertTrue(GpsFixPolicy.acceptsMovement(3.0, 2_500_000_000))
    }
    @Test fun jitterTeleportsAndProviderDuplicatesDoNotAddDistance() {
        assertFalse(GpsFixPolicy.acceptsMovement(0.5, 2_000_000_000))
        assertFalse(GpsFixPolicy.acceptsMovement(50.0, 2_000_000_000))
        assertFalse(GpsFixPolicy.acceptsMovement(2.0, 0))
        assertFalse(GpsFixPolicy.acceptsMovement(2.0, -1))
        assertFalse(GpsFixPolicy.acceptsMovement(Double.NaN, 2_000_000_000))
    }
}
