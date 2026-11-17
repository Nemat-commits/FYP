package com.terrastep.fyp.sensors

import android.Manifest
import android.annotation.SuppressLint
import android.content.Context
import android.content.pm.PackageManager
import android.location.Location
import android.location.LocationListener
import android.location.LocationManager
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.os.SystemClock
import androidx.core.content.ContextCompat
import com.google.android.gms.location.*

/** Exactly one feed is delivered: fused first, device GPS only if fused fails/stalls. */
class LocationTrackerManager(
    private val context: Context,
    private val onStatus: (String) -> Unit,
    private val onLocationFix: (Location) -> Unit
) {
    private val fusedClient = LocationServices.getFusedLocationProviderClient(context)
    private val system = context.getSystemService(Context.LOCATION_SERVICE) as LocationManager
    private val handler = Handler(Looper.getMainLooper())
    private var feed = "STOPPED"
    private var generation = 0
    private var lastFixMs = 0L
    private val listener = object : LocationListener {
        override fun onLocationChanged(location: Location) {
            if (feed == "GPS") onLocationFix(location)
        }
        override fun onProviderEnabled(provider: String) { onStatus("WAITING") }
        override fun onProviderDisabled(provider: String) { onStatus("DISABLED") }
        @Deprecated("Legacy Android callback")
        override fun onStatusChanged(provider: String?, status: Int, extras: Bundle?) {}
    }
    private val callback = object : LocationCallback() {
        override fun onLocationResult(result: LocationResult) {
            if (feed != "FUSED") return
            for (location in result.locations) {
                if (SystemClock.elapsedRealtimeNanos() - location.elapsedRealtimeNanos in 0..15_000_000_000L) {
                    lastFixMs = SystemClock.elapsedRealtime()
                    onLocationFix(location)
                }
            }
        }
    }
    private val watchdog = object : Runnable {
        override fun run() {
            if (feed != "FUSED") return
            if (SystemClock.elapsedRealtime() - lastFixMs >= 12000L) activateGps()
            else handler.postDelayed(this, 3000L)
        }
    }

    @SuppressLint("MissingPermission")
    private fun activateGps() {
        if (feed != "FUSED") return
        feed = "GPS"
        fusedClient.removeLocationUpdates(callback)
        try {
            if (!system.allProviders.contains(LocationManager.GPS_PROVIDER)) {
                onStatus("UNAVAILABLE")
                return
            }
            onStatus(if (system.isProviderEnabled(LocationManager.GPS_PROVIDER)) "GPS_FALLBACK" else "DISABLED")
            system.requestLocationUpdates(LocationManager.GPS_PROVIDER, 2000L, 0f, listener, Looper.getMainLooper())
        } catch (_: SecurityException) { onStatus("PERMISSION_REQUIRED") }
          catch (_: Exception) { onStatus("UNAVAILABLE") }
    }

    @SuppressLint("MissingPermission")
    fun startTracking() {
        if (ContextCompat.checkSelfPermission(context, Manifest.permission.ACCESS_FINE_LOCATION) != PackageManager.PERMISSION_GRANTED) {
            onStatus("PERMISSION_REQUIRED")
            return
        }
        if (feed != "STOPPED") return
        generation += 1
        val requestGeneration = generation
        feed = "FUSED"
        lastFixMs = SystemClock.elapsedRealtime()
        onStatus(if (system.isProviderEnabled(LocationManager.GPS_PROVIDER) || system.isProviderEnabled(LocationManager.NETWORK_PROVIDER)) "WAITING" else "DISABLED")
        val request = LocationRequest.Builder(Priority.PRIORITY_HIGH_ACCURACY, 2500L)
            .setMinUpdateIntervalMillis(1000L)
            .setMinUpdateDistanceMeters(0f)
            .setWaitForAccurateLocation(false)
            .build()
        try {
            fusedClient.requestLocationUpdates(request, callback, Looper.getMainLooper())
                .addOnFailureListener { if (generation == requestGeneration) activateGps() }
            handler.postDelayed(watchdog, 12000L)
        } catch (_: SecurityException) {
            stopTracking()
            onStatus("PERMISSION_REQUIRED")
        } catch (_: Exception) { activateGps() }
    }

    fun stopTracking() {
        generation += 1
        feed = "STOPPED"
        handler.removeCallbacks(watchdog)
        fusedClient.removeLocationUpdates(callback)
        system.removeUpdates(listener)
    }
}
