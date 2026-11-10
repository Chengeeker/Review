@file:OptIn(coil.annotation.ExperimentalCoilApi::class)
package com.review.compose

import android.content.Context
import coil.imageLoader
import coil.disk.DiskCache
import okio.ByteString.Companion.encodeUtf8
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import java.io.File

class ManagedImageCache(private val cache: DiskCache) : DiskCache by cache {
    override fun openEditor(key: String): DiskCache.Editor? = cache.openEditor(key)?.also {
        runCatching { File(cache.directory.toFile(), "${key.encodeUtf8().sha256().hex()}.key").writeText(key) }
    }
    override fun remove(key: String): Boolean = cache.remove(key).also { removed -> if (removed) File(cache.directory.toFile(), "${key.encodeUtf8().sha256().hex()}.key").delete() }
}

val cacheThresholds = listOf(0, 50, 100, 200, 500, 1024, 2048)
fun cacheThresholdLabel(value: Int) = when { value == 0 -> "不限制（关闭自动清理）"; value >= 1024 -> "${value / 1024} GB"; else -> "$value MB" }
fun cacheSizeLabel(bytes: Long): String {
    if (bytes <= 0) return "0 B"
    var size = bytes.toDouble(); var unit = 0
    while (size >= 1024 && unit < 4) { size /= 1024; unit++ }
    return String.format(java.util.Locale.ROOT, if (unit == 0) "%.0f %s" else "%.2f %s", size, listOf("B", "KB", "MB", "GB", "TB")[unit])
}
private fun imageCacheFiles(context: Context): List<File> = listOf("images", "originals").flatMap { name ->
    val directory = File(context.cacheDir, name).canonicalFile
    if (directory.parentFile != context.cacheDir.canonicalFile) emptyList()
    else directory.listFiles().orEmpty().filter { it.isFile && it.canonicalFile.parentFile == directory && it.name.matches(Regex("[a-f0-9]{64}(?:\\.[01])?")) }
}
suspend fun imageCacheSize(context: Context): Long = withContext(Dispatchers.IO) { imageCacheFiles(context).sumOf(File::length) }
suspend fun maintainImageCache(context: Context, threshold: Int = 0, clear: Boolean = false): Long = withContext(Dispatchers.IO) {
    val now = System.currentTimeMillis()
    val files = imageCacheFiles(context)
    var remaining = files.sumOf(File::length)
    val clearAll = clear || (threshold > 0 && remaining >= threshold * 1048576L)
    var deleted = 0L
    val coilKeys = mutableSetOf<String>()
    files.sortedBy(File::lastModified).forEach { file ->
        val age = now - file.lastModified()
        if (!evictImageCache(age, remaining, clearAll)) return@forEach
        val size = file.length()
        if (file.parentFile.name == "images") {
            // DiskCache owns its journal and active snapshots; never unlink those files directly.
            val hash = file.name.substringBefore('.')
            val index = File(file.parentFile, "$hash.key")
            val key = if (index.isFile && index.length() <= 16384) index.readText() else ""
            val siblings = files.filter { it.parentFile == file.parentFile && it.name.substringBefore('.') == hash }
            val removedBytes = siblings.sumOf(File::length)
            if (key.isNotBlank() && siblings.all { now - it.lastModified() >= 60_000 } && coilKeys.add(hash) && context.imageLoader.diskCache?.remove(key) == true) {
                deleted += removedBytes; remaining -= removedBytes
            }
        } else if (file.delete()) { deleted += size; remaining -= size }
    }
    File(context.cacheDir, "images").listFiles().orEmpty().filter { it.name.matches(Regex("[a-f0-9]{64}\\.key")) && now - it.lastModified() >= 60_000 }.forEach { index ->
        val base = index.name.removeSuffix(".key")
        if (!File(index.parentFile, "$base.0").exists() && !File(index.parentFile, "$base.1").exists() && !File(index.parentFile, "$base.0.tmp").exists()) index.delete()
    }
    deleted
}
fun evictImageCache(ageMs: Long, totalBytes: Long, clear: Boolean) = ageMs >= 60_000 && (clear || ageMs > 60L * 86400_000 || totalBytes > 512L * 1048576)
