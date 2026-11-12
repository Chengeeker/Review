package com.review.compose

import android.content.Context
import android.util.AtomicFile
import java.io.File
import java.io.IOException
import java.security.InvalidKeyException
import java.security.UnrecoverableKeyException
import java.util.UUID
import javax.crypto.AEADBadTagException

internal enum class SecretFailureKind { MISSING_KEY, UNUSABLE_KEY, AUTHENTICATION, FORMAT, IO }
internal class SecretReadFailure(val kind: SecretFailureKind) : IOException(when(kind) {
    SecretFailureKind.MISSING_KEY -> "本机加密密钥不存在，原资料已保留；请从原手机的应用内备份恢复"
    SecretFailureKind.UNUSABLE_KEY -> "本机加密密钥暂不可用，原资料已保留，请重试"
    SecretFailureKind.AUTHENTICATION -> "密文认证失败，可能是密钥不匹配或文件损坏；原资料已保留"
    SecretFailureKind.FORMAT -> "本机加密资料格式损坏或版本不支持，原文件已保留"
    SecretFailureKind.IO -> "本机资料读取失败，原文件已保留，请检查存储后重试"
}) {
    val recoverable get() = kind in setOf(SecretFailureKind.MISSING_KEY, SecretFailureKind.UNUSABLE_KEY, SecretFailureKind.AUTHENTICATION)
}

internal inline fun <T> readEncrypted(block: () -> T): T = try { block() }
catch(e: SecretReadFailure) { throw e }
catch(_: AEADBadTagException) { throw SecretReadFailure(SecretFailureKind.AUTHENTICATION) }
catch(_: InvalidKeyException) { throw SecretReadFailure(SecretFailureKind.UNUSABLE_KEY) }
catch(_: UnrecoverableKeyException) { throw SecretReadFailure(SecretFailureKind.UNUSABLE_KEY) }
catch(_: IllegalArgumentException) { throw SecretReadFailure(SecretFailureKind.FORMAT) }
catch(_: org.json.JSONException) { throw SecretReadFailure(SecretFailureKind.FORMAT) }
catch(_: IOException) { throw SecretReadFailure(SecretFailureKind.IO) }

internal fun archiveEncryptedFile(context: Context, source: File) {
    require(source.canonicalPath.startsWith(File(context.applicationInfo.dataDir).canonicalPath + File.separator))
    check(source.length() in 1..(32L * 1024 * 1024)) { "原加密文件无法归档，已停止恢复" }
    val bytes = source.readBytes()
    val directory = File(context.noBackupFilesDir, "account-recovery")
    check(directory.isDirectory || directory.mkdirs()) { "无法保留原加密资料，已停止恢复" }
    val archive = AtomicFile(File(directory, "encrypted-${UUID.randomUUID()}.bin"))
    val stream = archive.startWrite()
    try { stream.write(bytes); archive.finishWrite(stream) }
    catch(e: Exception) { archive.failWrite(stream); throw e }
    check(archive.readFully().contentEquals(bytes) && source.readBytes().contentEquals(bytes)) { "原加密资料归档校验失败，已停止恢复" }
}
