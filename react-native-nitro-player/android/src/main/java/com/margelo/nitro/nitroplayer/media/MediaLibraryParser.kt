package com.margelo.nitro.nitroplayer.media

import org.json.JSONArray
import org.json.JSONObject

/**
 * Parser for MediaLibrary JSON structure
 */
object MediaLibraryParser {
    fun fromJson(json: String): MediaLibrary {
        val jsonObject = JSONObject(json)

        val layoutType =
            when (jsonObject.optString("layoutType", "list").lowercase()) {
                "grid" -> LayoutType.GRID
                else -> LayoutType.LIST
            }

        val rootItems = parseMediaItems(jsonObject.optJSONArray("rootItems"))

        return MediaLibrary(
            layoutType = layoutType,
            rootItems = rootItems,
            appName = jsonObject.optString("appName").takeIf { it.isNotEmpty() },
            appIconUrl = jsonObject.optString("appIconUrl").takeIf { it.isNotEmpty() },
        )
    }

    private fun parseMediaItems(jsonArray: JSONArray?): List<MediaItem> {
        if (jsonArray == null) return emptyList()

        val items = mutableListOf<MediaItem>()

        for (i in 0 until jsonArray.length()) {
            val itemJson = jsonArray.optJSONObject(i) ?: continue
            items.add(parseMediaItem(itemJson))
        }

        return items
    }

    private fun parseMediaItem(jsonObject: JSONObject): MediaItem {
        val mediaTypeStr = jsonObject.optString("mediaType", "folder").lowercase()
        val mediaType =
            when (mediaTypeStr) {
                "audio" -> MediaType.AUDIO
                "playlist" -> MediaType.PLAYLIST
                else -> MediaType.FOLDER
            }

        val layoutTypeStr = jsonObject.optString("layoutType", "").lowercase()
        val layoutType =
            when (layoutTypeStr) {
                "grid" -> LayoutType.GRID
                "list" -> LayoutType.LIST
                else -> null
            }

        val children = parseMediaItems(jsonObject.optJSONArray("children"))

        return MediaItem(
            id = jsonObject.getString("id"),
            title = jsonObject.getString("title"),
            subtitle = jsonObject.optString("subtitle").takeIf { it.isNotEmpty() },
            iconUrl = jsonObject.optString("iconUrl").takeIf { it.isNotEmpty() },
            isPlayable = jsonObject.optBoolean("isPlayable", false),
            mediaType = mediaType,
            playlistId = jsonObject.optString("playlistId").takeIf { it.isNotEmpty() },
            children = children.takeIf { it.isNotEmpty() },
            layoutType = layoutType,
        )
    }
}
