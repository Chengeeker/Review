package com.review.compose

import androidx.compose.runtime.*
import androidx.media3.common.C
import androidx.media3.common.Player
import androidx.media3.common.TrackSelectionOverride
import androidx.media3.common.Tracks

internal fun videoTrackChoices(tracks: Tracks): Map<String, TrackSelectionOverride> {
    val resolutions = sortedMapOf<Int, TrackSelectionOverride>(compareByDescending { it })
    for (group in tracks.groups) {
        if (group.type != C.TRACK_TYPE_VIDEO) continue
        for (index in 0 until group.length) {
            val format = group.getTrackFormat(index)
            val resolution = minOf(format.width, format.height)
            if (resolution > 0 && group.isTrackSupported(index) && resolution !in resolutions)
                resolutions[resolution] = TrackSelectionOverride(group.mediaTrackGroup, index)
        }
    }
    return if (resolutions.size < 2) emptyMap() else resolutions.mapKeys { "${it.key}P" }
}

@Composable
internal fun rememberVideoTrackChoices(player: Player): Map<String, TrackSelectionOverride> {
    var options by remember(player) { mutableStateOf(emptyMap<String, TrackSelectionOverride>()) }
    DisposableEffect(player) {
        val listener = object : Player.Listener {
            override fun onTracksChanged(tracks: Tracks) { options = videoTrackChoices(tracks) }
        }
        options = videoTrackChoices(player.currentTracks)
        player.addListener(listener)
        onDispose { player.removeListener(listener) }
    }
    return options
}

internal fun selectVideoTrack(player: Player, override: TrackSelectionOverride?) {
    player.trackSelectionParameters = player.trackSelectionParameters.buildUpon()
        .clearOverridesOfType(C.TRACK_TYPE_VIDEO)
        .apply { if (override != null) setOverrideForType(override) }
        .build()
}
