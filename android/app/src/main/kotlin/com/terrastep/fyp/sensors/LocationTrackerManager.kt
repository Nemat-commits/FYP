package com.terrastep.fyp.sensors

import android.annotation.SuppressLint
import android.content.Context
import android.location.Location
import android.os.Looper
import com.google.android.gms.location.*

class LocationTrackerManager(
    context: Context,
    private val onLocationFix: (Location) -> Unit
) {
    private val fusedClient: FusedLocationProviderClient =
        LocationServices.getFusedLocationProviderClient(context)

    private val locationCallback = object : LocationCallback() {
        override fun onLocationResult(result: LocationResult) {
            for (loc in result.locations) {
                onLocationFix(loc)
            }
        }
    }

    @SuppressLint("MissingPermission")
    fun startTracking() {
        val request = LocationRequest.Builder(Priority.PRIORITY_HIGH_ACCURACY, 2500L)
            .setMinUpdateIntervalMillis(1000L)
            .setMinUpdateDistanceMeters(1.5f)
            .setWaitForAccurateLocation(false)
            .build()

        fusedClient.requestLocationUpdates(
            request,
            locationCallback,
            Looper.getMainLooper()
        )
    }

    fun stopTracking() {
        fusedClient.removeLocationUpdates(locationCallback)
    }
}
