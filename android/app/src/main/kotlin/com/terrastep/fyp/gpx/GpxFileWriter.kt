package com.terrastep.fyp.gpx

import android.content.ContentValues
import android.content.Context
import android.os.Build
import android.os.Environment
import android.provider.MediaStore
import android.util.Xml
import com.terrastep.fyp.db.TrackPointEntity
import com.terrastep.fyp.db.WalkSessionEntity
import java.io.File
import java.io.FileOutputStream
import java.text.SimpleDateFormat
import java.util.*

object GpxFileWriter {
    private val isoFormat = SimpleDateFormat("yyyy-MM-dd'T'HH:mm:ss.SSS'Z'", Locale.US).apply {
        timeZone = TimeZone.getTimeZone("UTC")
    }
    private val fileTimestampFormat = SimpleDateFormat("yyyyMMdd_HHmmss", Locale.US)

    @Synchronized
    fun writeSessionGpx(
        context: Context,
        session: WalkSessionEntity,
        points: List<TrackPointEntity>
    ): File {
        val gpxDir = File(context.getExternalFilesDir(null) ?: context.filesDir, "gpx")
        if (!gpxDir.exists()) gpxDir.mkdirs()

        val shortId = session.sessionId.take(8)
        val ts = fileTimestampFormat.format(Date(session.startTimeUtcMs))
        val outFile = File(gpxDir, "terrastep_${ts}_${shortId}.gpx")

        FileOutputStream(outFile).use { fos ->
            val serializer = Xml.newSerializer()
            serializer.setOutput(fos, "UTF-8")
            serializer.startDocument("UTF-8", true)
            serializer.setFeature("http://xmlpull.org/v1/doc/features.html#indent-output", true)

            serializer.startTag(null, "gpx")
            serializer.attribute(null, "version", "1.1")
            serializer.attribute(null, "creator", "Terrastep FYP 30% Milestone Build")
            serializer.attribute(null, "xmlns", "http://www.topografix.com/GPX/1/1")
            serializer.attribute(null, "xmlns:xsi", "http://www.w3.org/2001/XMLSchema-instance")
            serializer.attribute(null, "xmlns:terrastep", "https://terrastep.fyp/schema/gpx/v1")
            serializer.attribute(
                null,
                "xsi:schemaLocation",
                "http://www.topografix.com/GPX/1/1 http://www.topografix.com/GPX/1/1/gpx.xsd"
            )

            // <metadata>
            serializer.startTag(null, "metadata")
            serializer.startTag(null, "name")
            serializer.text(session.title)
            serializer.endTag(null, "name")

            serializer.startTag(null, "desc")
            val distKm = String.format(Locale.US, "%.2f", session.totalDistanceMeters / 1000.0)
            serializer.text("Steps: ${session.totalSteps} | Distance: ${distKm} km | Points: ${points.size}")
            serializer.endTag(null, "desc")

            serializer.startTag(null, "time")
            serializer.text(isoFormat.format(Date(session.startTimeUtcMs)))
            serializer.endTag(null, "time")

            if (points.isNotEmpty()) {
                val minLat = points.minOf { it.latitude }
                val maxLat = points.maxOf { it.latitude }
                val minLon = points.minOf { it.longitude }
                val maxLon = points.maxOf { it.longitude }
                serializer.startTag(null, "bounds")
                serializer.attribute(null, "minlat", String.format(Locale.US, "%.7f", minLat))
                serializer.attribute(null, "minlon", String.format(Locale.US, "%.7f", minLon))
                serializer.attribute(null, "maxlat", String.format(Locale.US, "%.7f", maxLat))
                serializer.attribute(null, "maxlon", String.format(Locale.US, "%.7f", maxLon))
                serializer.endTag(null, "bounds")
            }
            serializer.endTag(null, "metadata")

            // Waypoints for START and FINISH
            if (points.isNotEmpty()) {
                val first = points.first()
                writeWaypoint(serializer, first.latitude, first.longitude, first.altitudeMeters, first.timestampUtcMs, "START")
                if (points.size > 1) {
                    val last = points.last()
                    writeWaypoint(serializer, last.latitude, last.longitude, last.altitudeMeters, last.timestampUtcMs, "FINISH")
                }
            }

            // <trk>
            serializer.startTag(null, "trk")
            serializer.startTag(null, "name")
            serializer.text(session.title)
            serializer.endTag(null, "name")

            val groupedBySegment = points.groupBy { it.segmentIndex }.toSortedMap()
            for ((_, segPoints) in groupedBySegment) {
                serializer.startTag(null, "trkseg")
                for (pt in segPoints) {
                    serializer.startTag(null, "trkpt")
                    serializer.attribute(null, "lat", String.format(Locale.US, "%.7f", pt.latitude))
                    serializer.attribute(null, "lon", String.format(Locale.US, "%.7f", pt.longitude))

                    serializer.startTag(null, "ele")
                    serializer.text(String.format(Locale.US, "%.1f", pt.altitudeMeters))
                    serializer.endTag(null, "ele")

                    serializer.startTag(null, "time")
                    serializer.text(isoFormat.format(Date(pt.timestampUtcMs)))
                    serializer.endTag(null, "time")

                    serializer.startTag(null, "extensions")
                    serializer.startTag(null, "terrastep:accuracy_m")
                    serializer.text(String.format(Locale.US, "%.1f", pt.horizontalAccuracyMeters))
                    serializer.endTag(null, "terrastep:accuracy_m")
                    serializer.startTag(null, "terrastep:steps")
                    serializer.text(pt.cumulativeSessionSteps.toString())
                    serializer.endTag(null, "terrastep:steps")

                    serializer.startTag(null, "terrastep:speed_mps")
                    serializer.text(String.format(Locale.US, "%.2f", pt.speedMetersPerSec))
                    serializer.endTag(null, "terrastep:speed_mps")

                    serializer.endTag(null, "extensions")

                    serializer.endTag(null, "trkpt")
                }
                serializer.endTag(null, "trkseg")
            }

            serializer.endTag(null, "trk")
            serializer.endTag(null, "gpx")
            serializer.endDocument()
            serializer.flush()
        }
        return outFile
    }

    private fun writeWaypoint(
        serializer: org.xmlpull.v1.XmlSerializer,
        lat: Double,
        lon: Double,
        ele: Double,
        timeMs: Long,
        label: String
    ) {
        serializer.startTag(null, "wpt")
        serializer.attribute(null, "lat", String.format(Locale.US, "%.7f", lat))
        serializer.attribute(null, "lon", String.format(Locale.US, "%.7f", lon))
        serializer.startTag(null, "ele")
        serializer.text(String.format(Locale.US, "%.1f", ele))
        serializer.endTag(null, "ele")
        serializer.startTag(null, "time")
        serializer.text(isoFormat.format(Date(timeMs)))
        serializer.endTag(null, "time")
        serializer.startTag(null, "name")
        serializer.text(label)
        serializer.endTag(null, "name")
        serializer.endTag(null, "wpt")
    }

    fun copyToPublicDownloads(context: Context, sourceFile: File): String {
        val fileName = sourceFile.name
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            val values = ContentValues().apply {
                put(MediaStore.Downloads.DISPLAY_NAME, fileName)
                put(MediaStore.Downloads.MIME_TYPE, "application/gpx+xml")
                put(MediaStore.Downloads.RELATIVE_PATH, Environment.DIRECTORY_DOWNLOADS + "/Terrastep")
            }
            val resolver = context.contentResolver
            val uri = resolver.insert(MediaStore.Downloads.EXTERNAL_CONTENT_URI, values)
                ?: throw IllegalStateException("Failed to create MediaStore Downloads entry")
            resolver.openOutputStream(uri)?.use { out ->
                sourceFile.inputStream().use { input -> input.copyTo(out) }
            }
            return "Downloads/Terrastep/$fileName"
        } else {
            val dir = File(Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_DOWNLOADS), "Terrastep")
            if (!dir.exists()) dir.mkdirs()
            val dest = File(dir, fileName)
            sourceFile.copyTo(dest, overwrite = true)
            return dest.absolutePath
        }
    }
}
