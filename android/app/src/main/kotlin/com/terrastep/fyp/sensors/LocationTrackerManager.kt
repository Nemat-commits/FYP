package com.terrastep.fyp.sensors

import android.Manifest
import android.annotation.SuppressLint
import android.content.Context
import android.content.pm.PackageManager
import android.location.Location
import android.location.LocationListener
import android.location.LocationManager
import android.os.Bundle
import android.os.Looper
import androidx.core.content.ContextCompat
import com.google.android.gms.location.*

/** Fused fixes plus a device GPS fallback; never silently swallow subscription failures. */
class LocationTrackerManager(
    private val context: Context,
    private val onStatus: (String) -> Unit,
    private val onLocationFix: (Location) -> Unit
) {
    private val fusedClient = LocationServices.getFusedLocationProviderClient(context)
    private val system = context.getSystemService(Context.LOCATION_SERVICE) as LocationManager
    private val listener = object : LocationListener {
        override fun onLocationChanged(location: Location) = onLocationFix(location)
        override fun onProviderEnabled(provider: String) { onStatus("WAITING") }
        override fun onProviderDisabled(provider: String) { reportAvailability() }
        @Deprecated("Legacy Android callback")
        override fun onStatusChanged(provider: String?, status: Int, extras: Bundle?) {}
    }
    private val callback = object : LocationCallback() {
        override fun onLocationResult(result: LocationResult) {
            result.locations.forEach(onLocationFix)
        }
        override fun onLocationAvailability(availability: LocationAvailability) {
            if (!availability.isLocationAvailable) reportAvailability()
        }
    }
    private fun reportAvailability() {
        val enabled = system.isProviderEnabled(LocationManager.GPS_PROVIDER) ||
            system.isProviderEnabled(LocationManager.NETWORK_PROVIDER)
        onStatus(if (enabled) "WAITING" else "DISABLED")
    }

    @SuppressLint("MissingPermission")
    fun startTracking() {
        if (ContextCompat.checkSelfPermission(context, Manifest.permission.ACCESS_FINE_LOCATION) != PackageManager.PERMISSION_GRANTED) {
            onStatus("PERMISSION_REQUIRED")
            return
        }
        stopTracking()
        reportAvailability()
        val request = LocationRequest.Builder(Priority.PRIORITY_HIGH_ACCURACY, 2500L)
            .setMinUpdateIntervalMillis(1000L)
            .setMinUpdateDistanceMeters(0f)
            .setWaitForAccurateLocation(false)
            .build()
        try {
            fusedClient.requestLocationUpdates(request, callback, Looper.getMainLooper())
                .addOnFailureListener { onStatus("GPS_FALLBACK") }
            // Do not depend exclusively on Google Play Services on physical devices.
            for (provider in listOf(LocationManager.GPS_PROVIDER, LocationManager.NETWORK_PROVIDER)) {
                if (system.allProviders.contains(provider)) {
                    system.requestLocationUpdates(provider, 2000L, 0f, listener, Looper.getMainLooper())
                }
            }
        } catch (_: SecurityException) {
            stopTracking()
            onStatus("PERMISSION_REQUIRED")
        } catch (_: Exception) {
            onStatus("UNAVAILABLE")
        }
    }

    fun stopTracking() {
        fusedClient.removeLocationUpdates(callback)
        system.removeUpdates(listener)
    }
}
