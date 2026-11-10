package com.review.compose

import android.Manifest
import android.content.Context
import android.content.pm.PackageManager
import android.location.Location
import android.location.LocationManager
import androidx.core.content.ContextCompat
import org.json.JSONObject

fun hasLocationPermission(context: Context) = listOf(Manifest.permission.ACCESS_FINE_LOCATION, Manifest.permission.ACCESS_COARSE_LOCATION)
    .any { ContextCompat.checkSelfPermission(context, it) == PackageManager.PERMISSION_GRANTED }

fun lastPublishLocation(context: Context): Location? {
    if (!hasLocationPermission(context)) return null
    val manager = context.getSystemService(Context.LOCATION_SERVICE) as LocationManager
    return try {
        manager.getProviders(true).mapNotNull { manager.getLastKnownLocation(it) }
            .filter { it.latitude.isFinite() && it.longitude.isFinite() }.minByOrNull { if (it.hasAccuracy()) it.accuracy else Float.MAX_VALUE }
    } catch (_: SecurityException) { null }
}

fun normalizePlace(item: JSONObject): JSONObject = JSONObject(item.toString()).apply {
    put("poiid", item.optString("poiid").ifBlank { item.optString("id") })
    put("title", item.optString("title").ifBlank { item.optString("name") })
    put("long", item.optString("lon").ifBlank { item.optString("longitude") })
    put("lat", item.optString("lat").ifBlank { item.optString("latitude") })
    put("spot_type", item.optInt("spot_type", 0))
}

fun placeFields(place: JSONObject?): Map<String, String> = if (place == null || place.optString("poiid").isBlank()) emptyMap() else buildMap {
    put("poiid", place.optString("poiid")); put("poititle", place.optString("title"))
    listOf("pc_title", "long", "lat", "spot_type").forEach { key -> place.optString(key).takeIf(String::isNotBlank)?.let { put(key, it) } }
}

fun contentWithPlace(content: String, place: JSONObject?): String {
    if (place == null) return content.trim()
    val title = (if (place.optString("poiid").isNotBlank()) place.optString("pc_title") else place.optString("title")).trim()
    val text = content.trim()
    if (title.isBlank() || text.contains(title)) return text
    val marker = if (place.optString("poiid").isBlank()) "📍 $title" else title
    return if (text.isEmpty()) marker else "$text\n$marker"
}

fun nearbyPlaces(items: List<JSONObject>, location: Location?): List<JSONObject> {
    val places = items.map(::normalizePlace).filter { it.optString("title").isNotBlank() }
    places.forEach { place ->
        val supplied = place.optString("distance").toDoubleOrNull() ?: place.optString("distance_m").toDoubleOrNull()
        val latitude = place.optString("lat").toDoubleOrNull(); val longitude = place.optString("long").toDoubleOrNull()
        val distance = supplied?.takeIf { it.isFinite() && it >= 0 } ?: if (location != null && latitude != null && longitude != null && latitude in -90.0..90.0 && longitude in -180.0..180.0) {
            val result = FloatArray(1); Location.distanceBetween(location.latitude, location.longitude, latitude, longitude, result); result[0].toDouble()
        } else null
        if (distance != null) place.put("distance_m", distance)
    }
    return if (location == null) places else places.sortedBy { it.optDouble("distance_m", Double.POSITIVE_INFINITY) }
}

fun placeSubtitle(place: JSONObject): String {
    val detail = place.optString("client_show").ifBlank { place.optString("pc_title") }
    val distance = place.optDouble("distance_m", Double.NaN)
    if (!distance.isFinite()) return detail
    val label = if (distance < 1000) "距你 ${kotlin.math.round(distance).toInt()} 米" else "距你 ${String.format(java.util.Locale.ROOT, "%.1f", distance / 1000)} 公里"
    return if (detail.isBlank()) label else "$label · $detail"
}
