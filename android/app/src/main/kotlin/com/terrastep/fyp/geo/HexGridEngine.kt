package com.terrastep.fyp.geo

import kotlin.math.*

object HexGridEngine {
    private const val ORIGIN_LAT = 34.1688
    private const val ORIGIN_LON = 73.2215
    private const val HEX_RADIUS_METERS = 195.0 // Resolution-9 hex circumradius (~0.105 km2 area)
    private const val METERS_PER_DEG_LAT = 111132.92

    private fun metersPerDegLon(latDeg: Double): Double =
        111412.84 * cos(Math.toRadians(latDeg))

    fun latLonToHexId(lat: Double, lon: Double): String {
        val dy = (lat - ORIGIN_LAT) * METERS_PER_DEG_LAT
        val dx = (lon - ORIGIN_LON) * metersPerDegLon(ORIGIN_LAT)

        val qFrac = (sqrt(3.0) / 3.0 * dx - 1.0 / 3.0 * dy) / HEX_RADIUS_METERS
        val rFrac = (2.0 / 3.0 * dy) / HEX_RADIUS_METERS
        val (q, r) = axialRound(qFrac, rFrac)
        return "h3r9_${q}_${r}"
    }

    fun hexIdToBoundaryLatLon(hexId: String): List<Pair<Double, Double>> {
        val parts = hexId.split("_")
        if (parts.size != 3) return emptyList()
        val q = parts[1].toIntOrNull() ?: return emptyList()
        val r = parts[2].toIntOrNull() ?: return emptyList()

        val centerX = HEX_RADIUS_METERS * sqrt(3.0) * (q + r / 2.0)
        val centerY = HEX_RADIUS_METERS * (3.0 / 2.0) * r

        val centerLat = ORIGIN_LAT + (centerY / METERS_PER_DEG_LAT)
        val lonScale = metersPerDegLon(centerLat)

        val vertices = mutableListOf<Pair<Double, Double>>()
        for (i in 0 until 6) {
            val angleRad = Math.toRadians(60.0 * i - 30.0)
            val vx = centerX + HEX_RADIUS_METERS * cos(angleRad)
            val vy = centerY + HEX_RADIUS_METERS * sin(angleRad)
            val vLat = ORIGIN_LAT + (vy / METERS_PER_DEG_LAT)
            val vLon = ORIGIN_LON + (vx / lonScale)
            vertices.add(Pair(vLat, vLon))
        }
        // Close ring for GeoJSON Polygon compliance
        vertices.add(vertices.first())
        return vertices
    }

    private fun axialRound(q: Double, r: Double): Pair<Int, Int> {
        val s = -q - r
        var rq = q.roundToInt()
        var rr = r.roundToInt()
        val rs = s.roundToInt()

        val qDiff = abs(rq - q)
        val rDiff = abs(rr - r)
        val sDiff = abs(rs - s)

        if (qDiff > rDiff && qDiff > sDiff) {
            rq = -rr - rs
        } else if (rDiff > sDiff) {
            rr = -rq - rs
        }
        return Pair(rq, rr)
    }
}
