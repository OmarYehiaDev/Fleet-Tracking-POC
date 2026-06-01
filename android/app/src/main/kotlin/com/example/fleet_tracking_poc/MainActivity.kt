package com.example.fleet_tracking_poc

import android.database.Cursor
import android.net.Uri
import android.provider.DocumentsContract
import android.provider.MediaStore
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {

  private val CHANNEL = "com.fleet_tracking_poc/file_utils"

  override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
    super.configureFlutterEngine(flutterEngine)

    MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler {
      call,
      result ->
      when (call.method) {
        "getFilesFromUri" -> {
          val uriString = call.argument<String>("uri")
          val extensions = call.argument<List<String>>("extensions") ?: emptyList()
          if (uriString == null) {
            result.error("INVALID_ARG", "uri is null", null)
            return@setMethodCallHandler
          }
          try {
            val files = getFilesFromUri(uriString, extensions)
            result.success(files)
          } catch (e: Exception) {
            result.error("ERROR", e.message, null)
          }
        }
        else -> result.notImplemented()
      }
    }
  }

  private fun getFilesFromUri(uriString: String, extensions: List<String>): List<String> {
    // If it's already a real file path, scan it directly
    if (uriString.startsWith("/")) {
      return getFilesFromRealPath(uriString, extensions)
    }

    val treeUri = Uri.parse(uriString)
    val docUri =
      DocumentsContract.buildChildDocumentsUriUsingTree(
        treeUri,
        DocumentsContract.getTreeDocumentId(treeUri),
      )
    return queryChildren(docUri, treeUri, extensions)
  }

  private fun getFilesFromRealPath(path: String, extensions: List<String>): List<String> {
    val dir = java.io.File(path)
    android.util.Log.d(
      "FileUtils",
      "realPath=$path exists=${dir.exists()} isDir=${dir.isDirectory}",
    )
    if (!dir.exists() || !dir.isDirectory) return emptyList()
    val files =
      dir
        .walkTopDown()
        .filter { it.isFile }
        .filter { file ->
          val ext = file.extension.lowercase()
          extensions.isEmpty() || extensions.contains(ext)
        }
        .map { it.absolutePath }
        .toList()
    android.util.Log.d("FileUtils", "found ${files.size} files: $files")
    return files
  }

  private fun queryChildren(docUri: Uri, treeUri: Uri, extensions: List<String>): List<String> {
    val results = mutableListOf<String>()
    val cursor: Cursor? =
      contentResolver.query(
        docUri,
        arrayOf(
          DocumentsContract.Document.COLUMN_DOCUMENT_ID,
          DocumentsContract.Document.COLUMN_MIME_TYPE,
          DocumentsContract.Document.COLUMN_DISPLAY_NAME,
        ),
        null,
        null,
        null,
      )

    cursor?.use {
      while (it.moveToNext()) {
        val docId = it.getString(0)
        val mimeType = it.getString(1)
        val name = it.getString(2)

        if (mimeType == DocumentsContract.Document.MIME_TYPE_DIR) {
          // Recurse into subdirectory
          val childUri = DocumentsContract.buildChildDocumentsUriUsingTree(treeUri, docId)
          results.addAll(queryChildren(childUri, treeUri, extensions))
        } else {
          val ext = name.substringAfterLast('.', "").lowercase()
          if (extensions.isEmpty() || extensions.contains(ext)) {
            // Resolve to real file path via MediaStore
            val fileDocUri = DocumentsContract.buildDocumentUriUsingTree(treeUri, docId)
            val realPath = getRealPathFromUri(fileDocUri, name)
            if (realPath != null) results.add(realPath)
          }
        }
      }
    }
    return results
  }

  private fun getRealPathFromUri(uri: Uri, displayName: String): String? {
    // Try MediaStore first
    val videoUri = MediaStore.Video.Media.EXTERNAL_CONTENT_URI
    val projection = arrayOf(MediaStore.Video.Media.DATA)
    val selection = "${MediaStore.Video.Media.DISPLAY_NAME} = ?"
    val cursor = contentResolver.query(videoUri, projection, selection, arrayOf(displayName), null)
    cursor?.use {
      if (it.moveToFirst()) {
        val path = it.getString(it.getColumnIndexOrThrow(MediaStore.Video.Media.DATA))
        if (!path.isNullOrBlank()) return path
      }
    }
    // Fallback: copy to cache and return cache path
    return try {
      val inputStream = contentResolver.openInputStream(uri) ?: return null
      val cacheFile = java.io.File(cacheDir, displayName)
      cacheFile.outputStream().use { out -> inputStream.copyTo(out) }
      cacheFile.absolutePath
    } catch (e: Exception) {
      null
    }
  }
}
