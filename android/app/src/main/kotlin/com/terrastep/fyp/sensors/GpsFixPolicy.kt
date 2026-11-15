package com.terrastep.fyp.sensors

/** Shared recording gates; provider duplicates never inflate distance. */
object GpsFixPolicy {
    fun isFresh(ageMs: Long): Boolean = ageMs in 0..15000

    fun acceptsMovement(distanceMeters: Double, deltaNanos: Long): Boolean {
        if (!distanceMeters.isFinite() || deltaNanos <= 0) return false
        val seconds = deltaNanos / 1_000_000_000.0
        return distanceMeters >= 1.2 && distanceMeters / seconds <= 6.5
    }
}
