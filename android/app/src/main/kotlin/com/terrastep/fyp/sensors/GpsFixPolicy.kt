package com.terrastep.fyp.sensors

/** GPS movement alone is not walking: corroborate it with hardware steps. */
object GpsFixPolicy {
    fun isFresh(ageMs: Long): Boolean = ageMs in 0..15000

    fun acceptsMovement(distanceMeters: Double, deltaNanos: Long): Boolean {
        if (!distanceMeters.isFinite() || deltaNanos <= 0) return false
        val seconds = deltaNanos / 1_000_000_000.0
        return distanceMeters >= 1.2 && distanceMeters / seconds <= 6.5
    }

    fun acceptsWalking(
        distanceMeters: Double,
        deltaNanos: Long,
        accuracyMeters: Double,
        hasStepHardware: Boolean,
        newSteps: Int,
        measuredSpeed: Double?,
        speedAccuracy: Double?
    ): Boolean {
        if (!acceptsMovement(distanceMeters, deltaNanos)) return false
        if (!accuracyMeters.isFinite() || accuracyMeters < 0 || accuracyMeters > 25) return false
        // Accumulate short moves at the anchor until displacement clears a noise floor.
        val noiseFloor = maxOf(1.8, minOf(6.0, accuracyMeters * 0.5))
        if (distanceMeters < noiseFloor) return false
        if (hasStepHardware) {
            // Zero sensor steps means ZERO walking distance, regardless of GPS drift.
            // This is a plausibility gate, not a step-derived distance estimate.
            return newSteps > 0 && distanceMeters <= newSteps * 1.8 + 1.2
        }
        // Without a pedometer be deliberately conservative: require reliable Doppler speed
        // and displacement beyond the positional uncertainty, never infer it from jitter.
        return measuredSpeed != null && measuredSpeed in 0.8..3.5 &&
            speedAccuracy != null && speedAccuracy in 0.0..0.5 &&
            distanceMeters >= maxOf(3.0, accuracyMeters * 2)
    }
}
