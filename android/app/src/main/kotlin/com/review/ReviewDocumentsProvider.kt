package com.review

import android.content.Context
import android.content.res.AssetFileDescriptor
import android.database.Cursor
import android.database.MatrixCursor
import android.graphics.Point
import android.os.CancellationSignal
import android.os.Handler
import android.os.ParcelFileDescriptor
import android.provider.DocumentsContract
import android.provider.DocumentsContract.Document
import android.provider.DocumentsContract.Root
import android.provider.DocumentsProvider
import android.webkit.MimeTypeMap
import java.io.File
import java.io.FileNotFoundException

/**
 * Review DocumentsProvider
 * 完整实现 Android Storage Access Framework (SAF) 协议
 * 支持在 MT 管理器、系统文件选择器等应用中直接通过「添加本地存储」挂载并全权读写 Review 应用私有数据与备份目录
 */
class ReviewDocumentsProvider : DocumentsProvider() {

    companion object {
        private val DEFAULT_ROOT_PROJECTION = arrayOf(
            Root.COLUMN_ROOT_ID,
            Root.COLUMN_FLAGS,
            Root.COLUMN_TITLE,
            Root.COLUMN_SUMMARY,
            Root.COLUMN_DOCUMENT_ID,
            Root.COLUMN_MIME_TYPES,
            Root.COLUMN_ICON
        )

        private val DEFAULT_DOCUMENT_PROJECTION = arrayOf(
            Document.COLUMN_DOCUMENT_ID,
            Document.COLUMN_MIME_TYPE,
            Document.COLUMN_DISPLAY_NAME,
            Document.COLUMN_LAST_MODIFIED,
            Document.COLUMN_FLAGS,
            Document.COLUMN_SIZE
        )
    }

    override fun onCreate(): Boolean {
        return true
    }

    override fun queryRoots(projection: Array<out String>?): Cursor {
        val proj = projection ?: DEFAULT_ROOT_PROJECTION
        val result = MatrixCursor(proj)
        val ctx = context ?: return result

        // 应用私有内部存储根目录 (/data/data/com.review or /data/user/0/com.review)
        val dataDir = File(ctx.applicationInfo.dataDir)
        val targetDir = if (dataDir.exists()) dataDir else (ctx.filesDir?.parentFile ?: ctx.filesDir)

        if (targetDir != null && targetDir.exists()) {
            val appIcon = if (ctx.applicationInfo.icon != 0) ctx.applicationInfo.icon else R.mipmap.ic_launcher
            val row = result.newRow()
            for (col in proj) {
                when (col) {
                    Root.COLUMN_ROOT_ID -> row.add(col, "review_root")
                    Root.COLUMN_FLAGS -> row.add(
                        col,
                        Root.FLAG_SUPPORTS_CREATE or Root.FLAG_SUPPORTS_IS_CHILD or Root.FLAG_LOCAL_ONLY
                    )
                    Root.COLUMN_TITLE -> row.add(col, "Review")
                    Root.COLUMN_SUMMARY -> row.add(col, ctx.packageName)
                    Root.COLUMN_DOCUMENT_ID -> row.add(col, targetDir.absolutePath)
                    Root.COLUMN_MIME_TYPES -> row.add(col, "*/*")
                    Root.COLUMN_ICON -> row.add(col, appIcon)
                    Root.COLUMN_AVAILABLE_BYTES -> row.add(col, null)
                    else -> row.add(col, null)
                }
            }
        }

        return result
    }

    override fun queryDocument(documentId: String, projection: Array<out String>?): Cursor {
        val result = MatrixCursor(projection ?: DEFAULT_DOCUMENT_PROJECTION)
        val file = File(documentId)
        if (!file.exists()) {
            throw FileNotFoundException("File not found: $documentId")
        }
        includeFile(result, file)
        return result
    }

    override fun queryChildDocuments(
        parentDocumentId: String,
        projection: Array<out String>?,
        sortOrder: String?
    ): Cursor {
        val result = MatrixCursor(projection ?: DEFAULT_DOCUMENT_PROJECTION)
        val parent = File(parentDocumentId)
        if (!parent.exists()) {
            throw FileNotFoundException("Parent file not found: $parentDocumentId")
        }

        val children = parent.listFiles() ?: emptyArray()
        for (child in children) {
            includeFile(result, child)
        }
        return result
    }

    override fun openDocument(
        documentId: String,
        mode: String,
        signal: CancellationSignal?
    ): ParcelFileDescriptor {
        val file = File(documentId)
        if (!file.exists()) {
            throw FileNotFoundException("File not found: $documentId")
        }
        val accessMode = ParcelFileDescriptor.parseMode(mode)
        return ParcelFileDescriptor.open(file, accessMode)
    }

    override fun createDocument(
        parentDocumentId: String,
        mimeType: String,
        displayName: String
    ): String {
        val parent = File(parentDocumentId)
        if (!parent.exists()) {
            throw FileNotFoundException("Parent file not found: $parentDocumentId")
        }

        val newFile = File(parent, displayName)
        if (Document.MIME_TYPE_DIR == mimeType) {
            if (!newFile.mkdirs()) {
                throw FileNotFoundException("Failed to create directory: ${newFile.absolutePath}")
            }
        } else {
            if (!newFile.createNewFile()) {
                throw FileNotFoundException("Failed to create file: ${newFile.absolutePath}")
            }
        }
        return newFile.absolutePath
    }

    override fun deleteDocument(documentId: String) {
        val file = File(documentId)
        if (!file.deleteRecursively()) {
            throw FileNotFoundException("Failed to delete file: $documentId")
        }
    }

    override fun renameDocument(documentId: String, displayName: String): String {
        val file = File(documentId)
        if (!file.exists()) {
            throw FileNotFoundException("File not found: $documentId")
        }
        val parent = file.parentFile ?: throw FileNotFoundException("Cannot rename root")
        val target = File(parent, displayName)
        if (!file.renameTo(target)) {
            throw FileNotFoundException("Failed to rename file to: ${target.absolutePath}")
        }
        return target.absolutePath
    }

    override fun isChildDocument(parentDocumentId: String, documentId: String): Boolean {
        return documentId.startsWith(parentDocumentId)
    }

    private fun includeFile(result: MatrixCursor, file: File) {
        var flags = 0
        if (file.isDirectory) {
            if (file.canWrite()) {
                flags = flags or Document.FLAG_DIR_SUPPORTS_CREATE
            }
        } else if (file.canWrite()) {
            flags = flags or Document.FLAG_SUPPORTS_WRITE
            flags = flags or Document.FLAG_SUPPORTS_DELETE
            flags = flags or Document.FLAG_SUPPORTS_RENAME
        }

        val mimeType = if (file.isDirectory) {
            Document.MIME_TYPE_DIR
        } else {
            getTypeForFile(file)
        }

        result.newRow().apply {
            add(Document.COLUMN_DOCUMENT_ID, file.absolutePath)
            add(Document.COLUMN_DISPLAY_NAME, file.name)
            add(Document.COLUMN_SIZE, file.length())
            add(Document.COLUMN_MIME_TYPE, mimeType)
            add(Document.COLUMN_LAST_MODIFIED, file.lastModified())
            add(Document.COLUMN_FLAGS, flags)
            add(Document.COLUMN_ICON, null)
        }
    }

    private fun getTypeForFile(file: File): String {
        val ext = file.extension.lowercase()
        return MimeTypeMap.getSingleton().getMimeTypeFromExtension(ext) ?: "application/octet-stream"
    }
}
