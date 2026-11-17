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

    @Test fun sittingFor47SecondsNeverAccumulates142Metres() {
        var distance = 0.0
        repeat(47) {
            val jitter = 142.0 / 47
            if (GpsFixPolicy.acceptsWalking(jitter, 1_000_000_000, 2.8, true, 0, 1.2, 0.1)) {
                distance += jitter
            }
        }
        assertEquals(0.0, distance, 0.0)
    }

    @Test fun stoppingAfterWalkingStillRejectsDrift() {
        assertTrue(GpsFixPolicy.acceptsWalking(4.0, 3_000_000_000, 3.0, true, 5, 1.2, 0.2))
        // Even if GPS still reports plausible walking speed, no NEW steps means no distance.
        assertFalse(GpsFixPolicy.acceptsWalking(4.0, 3_000_000_000, 3.0, true, 0, 1.2, 0.2))
    }

    @Test fun stepsDoNotPermitArbitraryGpsJumpsOrNoise() {
        assertFalse(GpsFixPolicy.acceptsWalking(14.0, 4_000_000_000, 3.0, true, 2, 1.2, 0.2))
        assertFalse(GpsFixPolicy.acceptsWalking(2.0, 3_000_000_000, 10.0, true, 4, 1.2, 0.2))
        assertFalse(GpsFixPolicy.acceptsWalking(4.0, 3_000_000_000, Double.NaN, true, 5, 1.2, 0.2))
    }

    @Test fun sensorlessPhonesRequireReliableSpeedAndClearDisplacement() {
        assertFalse(GpsFixPolicy.acceptsWalking(8.0, 5_000_000_000, 3.0, false, 0, null, null))
        assertFalse(GpsFixPolicy.acceptsWalking(8.0, 5_000_000_000, 3.0, false, 0, 0.0, 0.1))
        assertFalse(GpsFixPolicy.acceptsWalking(8.0, 5_000_000_000, 3.0, false, 0, 1.2, 2.0))
        assertTrue(GpsFixPolicy.acceptsWalking(8.0, 5_000_000_000, 3.0, false, 0, 1.2, 0.2))
    }
}
