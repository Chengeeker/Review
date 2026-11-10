package com.review.compose

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import coil.compose.AsyncImage
import org.json.JSONObject
import java.time.Instant
import java.time.ZoneId
import java.time.ZonedDateTime
import java.time.format.DateTimeFormatter
import java.util.Locale

private val chatApiTime = DateTimeFormatter.ofPattern("EEE MMM dd HH:mm:ss Z yyyy", Locale.ENGLISH)
internal fun chatTimestamp(raw: String): Instant? {
    val value = raw.trim()
    value.toLongOrNull()?.let {
        return runCatching { if (it in 1..9_999_999_999L) Instant.ofEpochSecond(it) else if (it > 0) Instant.ofEpochMilli(it) else null }.getOrNull()
    }
    return runCatching { Instant.parse(value) }.getOrNull()
        ?: runCatching { ZonedDateTime.parse(value, chatApiTime).toInstant() }.getOrNull()
}

internal fun showChatTime(current: String, older: String?): Boolean {
    if (current.isBlank() || current == "0") return false
    if (older == null) return true
    val time = chatTimestamp(current) ?: return false
    val before = chatTimestamp(older) ?: return true
    return time.isAfter(before.plusSeconds(300))
}

@Composable
internal fun ChatTimeDivider(raw: String) {
    val display = remember(raw) {
        val zone = ZoneId.systemDefault()
        val time = chatTimestamp(raw)?.atZone(zone)
        val now = ZonedDateTime.now(zone)
        time?.format(DateTimeFormatter.ofPattern(when {
            time.year != now.year -> "yyyy年M月d日 HH:mm"
            time.toLocalDate() != now.toLocalDate() -> "M月d日 HH:mm"
            else -> "HH:mm"
        })) ?: raw
    }
    Text(display, Modifier.fillMaxWidth().padding(top = 9.dp, bottom = 4.dp), fontSize = 11.sp,
        textAlign = TextAlign.Center, color = MaterialTheme.colorScheme.onSurfaceVariant)
}

@Composable
internal fun ChatBubble(message: Message, group: Boolean, target: Contact?, sender: User? = null, room: ChatGroup? = null, gallery: (List<Media>, Int) -> Unit) {
    val model = LocalReview.current; val colors = MaterialTheme.colorScheme
    val raw = remember(message.raw) { JSONObject(message.raw) }
    val mine = message.sender == "me" || message.sender.isNotBlank() && message.sender == model.uid
    if (message.notice) {
        val text = message.text.ifBlank { raw.optString("status_tips") }
        if (text.isNotBlank()) ChatNotice(text)
        return
    }
    val images = remember(message.raw) { chatImages(raw) }
    val sticker = remember(message.raw) { chatSticker(raw) }
    val video = raw.optString("media_type") in setOf("10", "5") && chatAttachmentIds(raw).isNotEmpty()
    val link = remember(message.raw) { chatLink(raw) }
    val hasImages = images.isNotEmpty() || sticker != null
    val caption = chatCaption(message.text, hasImages, video, sticker?.shortUrl.orEmpty())
    val mediaOnly = (hasImages || video) && caption.isEmpty()
    val name = room?.names?.get(message.sender).orEmpty().ifBlank { message.name }.ifBlank { sender?.name.orEmpty() }
        .ifBlank { if (group) "群友 ${message.sender}" else target?.name.orEmpty() }
    val avatar = sender?.avatar.orEmpty().ifBlank { message.avatar }.ifBlank { if (group) "" else target?.avatar.orEmpty() }
    val verified = message.verified || sender?.isVerified == true
    val verifiedType = if (message.verified) message.verifiedType else sender?.verifiedType ?: -1
    Row(Modifier.fillMaxWidth().padding(vertical = 6.dp), horizontalArrangement = if (mine) Arrangement.End else Arrangement.Start, verticalAlignment = Alignment.Top) {
        if (!mine) {
            Avatar(name, avatar, Modifier.size(38.dp).semantics { contentDescription = "查看${name}的主页" }
                .reviewClickable(enabled = message.sender.isNotBlank()) {
                    model.openProfile(User(message.sender, name, avatar, isVerified = verified, verifiedType = verifiedType))
                }, verified = verified, verifiedType = verifiedType, shareWithProfile = true, crossfade = false)
            Spacer(Modifier.width(8.dp))
        }
        Column(Modifier.weight(1f, fill = false), horizontalAlignment = if (mine) Alignment.End else Alignment.Start) {
            if (group && !mine) Row(Modifier.padding(start = 4.dp, bottom = 3.dp), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(4.dp)) {
                Text(name, Modifier.weight(1f, fill = false), fontSize = 11.5.sp, color = colors.onSurfaceVariant,
                    fontWeight = reviewWeight(FontWeight.Medium), maxLines = 1, overflow = TextOverflow.Ellipsis)
                ChatMemberBadge(message.sender, room, raw)
            }
            Surface(color = if (mediaOnly) Color.Transparent else if (link != null) colors.surfaceContainerLow else if (mine) colors.primary else colors.surfaceContainerHighest.copy(alpha = .7f),
                contentColor = if (mine && link == null && !mediaOnly) colors.onPrimary else colors.onSurface, shape = RoundedCornerShape(topStart = 16.dp, topEnd = 16.dp, bottomStart = if (mine) 16.dp else 4.dp, bottomEnd = if (mine) 4.dp else 16.dp)) {
                Box(if (mediaOnly) Modifier.padding(4.dp) else Modifier.padding(horizontal = 14.dp, vertical = 10.dp)) {
                    ChatMessageBody(message, images, sticker, caption, gallery, primaryBubble = mine && link == null && !mediaOnly)
                }
            }
        }
        if (mine) { Spacer(Modifier.width(8.dp)); Avatar("我", model.me?.avatar.orEmpty().ifBlank { avatar }, Modifier.size(38.dp), shareWithProfile = true, crossfade = false) }
    }
    raw.optString("status_tips").takeIf(String::isNotBlank)?.let { ChatNotice(it) }
}

@Composable
private fun ChatNotice(text: String) {
    val colors = MaterialTheme.colorScheme
    Box(Modifier.fillMaxWidth().padding(vertical = 8.dp), contentAlignment = Alignment.Center) {
        Text(text, Modifier.background(colors.surfaceContainerHighest.copy(alpha = .6f), RoundedCornerShape(12.dp)).padding(horizontal = 12.dp, vertical = 4.dp),
            fontSize = 12.sp, color = colors.onSurfaceVariant, textAlign = TextAlign.Center)
    }
}

@Composable
private fun ChatMemberBadge(uid: String, room: ChatGroup?, raw: JSONObject) {
    val colors = MaterialTheme.colorScheme
    val owner = uid.isNotBlank() && uid == room?.owner
    val label = when {
        owner -> "群主"
        room != null && uid in room.admins -> "管理员"
        raw.optInt("faith_status") == 2 -> room?.fanLabel ?: "真爱粉"
        else -> ""
    }
    if (label.isNotEmpty()) {
        Text(label, Modifier.background(if (owner) colors.tertiaryContainer else colors.secondaryContainer, RoundedCornerShape(4.dp))
            .padding(horizontal = 4.dp, vertical = 1.dp), fontSize = 9.5.sp,
            color = if (owner) colors.onTertiaryContainer else colors.onSecondaryContainer, maxLines = 1)
    } else if (raw.optInt("faith_status") == 1) {
        val icon = secureImage(raw.optString("faith_icon"))
        if (icon.isNotEmpty()) AsyncImage(icon, "群成员粉丝标识", Modifier.size(48.dp, 14.dp), contentScale = ContentScale.Fit, alignment = Alignment.CenterStart)
    }
}
