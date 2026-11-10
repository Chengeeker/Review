package com.review.compose

import org.json.JSONObject

fun visibilityCode(value: Any?): Int? {
    if (value is Number) return value.toInt()
    val text = value?.toString()?.trim()?.lowercase().orEmpty()
    return text.toIntOrNull() ?: when (text) {
        "public", "公开" -> 0
        "fans", "粉丝", "仅粉丝可见" -> 10
        "friends", "好友", "好友圈", "好友圈可见", "仅好友可见" -> 6
        "private", "私密", "仅自己可见", "仅自己" -> 1
        "group", "群友", "群可见", "群友可见" -> 5
        else -> null
    }
}
fun postVisibility(data: JSONObject): Int? {
    listOf("visible_type", "visibleType", "visibility_type", "visibilityType", "privacy_type", "privacyType").forEach { visibilityCode(data.opt(it))?.let { return it } }
    when (val visible = data.opt("visible")) {
        is JSONObject -> listOf("type", "visible_type", "visibleType", "code", "value").forEach { visibilityCode(visible.opt(it))?.let { return it } }
        else -> visibilityCode(visible)?.let { return it }
    }
    return visibilityCode(data.opt("privacy")) ?: visibilityCode(data.optJSONObject("title")?.optString("text") ?: data.opt("title"))
}
fun visibilityLabel(type: Int?) = when (type) { 0 -> "公开"; 10 -> "仅粉丝可见"; 6 -> "好友圈可见"; 1 -> "仅自己可见"; 5 -> "群可见"; else -> null }
