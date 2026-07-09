package app.danxe.mobile

import android.app.Activity
import android.content.Intent
import android.net.Uri
import android.os.Bundle
import android.os.Environment
import android.provider.OpenableColumns
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import org.json.JSONArray
import org.json.JSONObject
import java.io.File
import java.io.FileOutputStream
import java.text.Normalizer
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale
import java.util.UUID
import java.util.zip.ZipInputStream

class MainActivity : FlutterActivity() {
    private val channelName = "danxe/host"
    private val viewerEventsName = "danxe/viewer_events"
    private val importRequestCode = 7301
    private var pendingImportResult: MethodChannel.Result? = null
    private var pendingKind: String = "other"
    private lateinit var viewerEvents: MethodChannel

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        viewerEvents = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, viewerEventsName)
        flutterEngine.platformViewsController.registry.registerViewFactory(
            "danxe/mmd_view",
            MmdWebViewFactory(viewerEvents, libraryRoot()),
        )
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "getLibraryRoot" -> result.success(libraryRoot().absolutePath)
                    "scanLibrary" -> result.success(scanLibrary().toString())
                    "importAsset" -> startImport(call, result)
                    "deleteAsset" -> deleteAsset(call, result)
                    "renameAsset" -> renameAsset(call, result)
                    "rescanAsset" -> rescanAsset(call, result)
                    "viewerLoadScene" -> viewerLoadScene(call, result)
                    "viewerClear" -> viewerCommand("clear", result)
                    "viewerPlay" -> viewerCommand("play", result)
                    "viewerPause" -> viewerCommand("pause", result)
                    "viewerSeek" -> viewerCommand("seek", result, JSONObject().put("second", call.argument<Double>("second") ?: 0.0))
                    "viewerSetSpeed" -> viewerCommand("setSpeed", result, JSONObject().put("speed", call.argument<Double>("speed") ?: 1.0))
                    "viewerSetCamera" -> viewerSetCamera(call, result)
                    "viewerSetCameraPreset" -> viewerSetCameraPreset(call, result)
                    "viewerExport" -> viewerExport(call, result)
                    else -> result.notImplemented()
                }
            }
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        libraryRoot().mkdirs()
        ensureDownloadExportRoot()
    }

    @Deprecated("Used for FlutterActivity compatibility without adding ActivityX dependencies.")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode != importRequestCode) return

        val result = pendingImportResult ?: return
        pendingImportResult = null
        if (resultCode != Activity.RESULT_OK || data == null) {
            result.success(null)
            return
        }

        try {
            val metadata = JSONArray()
            selectedUris(data).forEach { uri ->
                metadata.put(importUri(pendingKind, uri))
            }
            result.success(metadata.toString())
        } catch (error: Exception) {
            result.error("IMPORT_FAILED", error.message, null)
        }
    }

    private fun startImport(call: MethodCall, result: MethodChannel.Result) {
        if (pendingImportResult != null) {
            result.error("IMPORT_BUSY", "Another import picker is already open.", null)
            return
        }
        pendingKind = call.argument<String>("kind") ?: "other"
        pendingImportResult = result
        val intent = Intent(Intent.ACTION_OPEN_DOCUMENT).apply {
            addCategory(Intent.CATEGORY_OPENABLE)
            type = mimeTypeForKind(pendingKind)
            putExtra(Intent.EXTRA_MIME_TYPES, mimeAlternatesForKind(pendingKind))
            putExtra(Intent.EXTRA_ALLOW_MULTIPLE, true)
        }
        startActivityForResult(intent, importRequestCode)
    }

    private fun deleteAsset(call: MethodCall, result: MethodChannel.Result) {
        val kind = call.argument<String>("kind") ?: "other"
        val id = call.argument<String>("id") ?: ""
        val target = File(File(libraryRoot(), kind), id)
        val rootPath = libraryRoot().canonicalPath
        if (target.canonicalPath.startsWith(rootPath) && target.exists()) {
            target.deleteRecursively()
        }
        result.success(null)
    }

    private fun renameAsset(call: MethodCall, result: MethodChannel.Result) {
        try {
            val assetDir = assetDirectory(call)
            requireInsideLibrary(assetDir)
            require(assetDir.exists()) { "Asset does not exist." }

            val manifest = readManifest(assetDir)
            val kind = manifest.optString("kind", call.argument<String>("kind") ?: "other")
            val id = manifest.optString("id", call.argument<String>("id") ?: assetDir.name)
            val nextName = call.argument<String>("name")?.trim().orEmpty()
            require(nextName.isNotEmpty()) { "Asset name cannot be empty." }

            val metadata = scanAssetDirectory(
                assetDir = assetDir,
                kind = kind,
                id = id,
                displayName = nextName,
                sourceFile = sourceFileFor(assetDir, manifest),
                sourceDisplayName = manifest.optString("sourceName", ""),
                pathAliases = manifest.optJSONObject("pathAliases") ?: JSONObject(),
            )
            File(assetDir, "asset.json").writeText(metadata.toString(2))
            result.success(metadata.toString())
        } catch (error: Exception) {
            result.error("RENAME_FAILED", error.message, null)
        }
    }

    private fun rescanAsset(call: MethodCall, result: MethodChannel.Result) {
        try {
            val assetDir = assetDirectory(call)
            requireInsideLibrary(assetDir)
            require(assetDir.exists()) { "Asset does not exist." }

            val manifest = readManifest(assetDir)
            val metadata = scanAssetDirectory(
                assetDir = assetDir,
                kind = manifest.optString("kind", call.argument<String>("kind") ?: "other"),
                id = manifest.optString("id", call.argument<String>("id") ?: assetDir.name),
                displayName = manifest.optString("name", assetDir.name),
                sourceFile = sourceFileFor(assetDir, manifest),
                sourceDisplayName = manifest.optString("sourceName", ""),
                pathAliases = manifest.optJSONObject("pathAliases") ?: JSONObject(),
            )
            File(assetDir, "asset.json").writeText(metadata.toString(2))
            result.success(metadata.toString())
        } catch (error: Exception) {
            result.error("RESCAN_FAILED", error.message, null)
        }
    }

    private fun viewerLoadScene(call: MethodCall, result: MethodChannel.Result) {
        val sceneText = call.argument<String>("scene") ?: "{}"
        val view = MmdViewRegistry.current
        if (view == null) {
            result.error("VIEWER_UNAVAILABLE", "The MMD renderer view is not mounted.", null)
            return
        }
        view.loadScene(JSONObject(sceneText))
        result.success(null)
    }

    private fun viewerCommand(name: String, result: MethodChannel.Result, payload: JSONObject = JSONObject()) {
        val view = MmdViewRegistry.current
        if (view == null) {
            result.error("VIEWER_UNAVAILABLE", "The MMD renderer view is not mounted.", null)
            return
        }
        view.command(name, payload)
        result.success(null)
    }

    private fun viewerSetCamera(call: MethodCall, result: MethodChannel.Result) {
        val payload = JSONObject()
            .put("yaw", call.argument<Double>("yaw") ?: 18.0)
            .put("pitch", call.argument<Double>("pitch") ?: -8.0)
            .put("distance", call.argument<Double>("distance") ?: 5.4)
        viewerCommand("setCamera", result, payload)
    }

    private fun viewerSetCameraPreset(call: MethodCall, result: MethodChannel.Result) {
        val payload = JSONObject()
            .put("preset", call.argument<String>("preset") ?: "fullFront")
        viewerCommand("setCameraPreset", result, payload)
    }

    private fun viewerExport(call: MethodCall, result: MethodChannel.Result) {
        val view = MmdViewRegistry.current
        if (view == null) {
            result.error("VIEWER_UNAVAILABLE", "The MMD renderer view is not mounted.", null)
            return
        }
        if (MmdViewRegistry.pendingExportResult != null) {
            result.error("EXPORT_BUSY", "A video export is already running.", null)
            return
        }
        val payload = JSONObject(call.argument<String>("settings") ?: "{}")
        MmdViewRegistry.pendingExportResult = result
        view.command("exportVideo", payload)
    }

    private fun importUri(kind: String, uri: Uri): JSONObject {
        val displayName = queryDisplayName(uri)
        val id = SimpleDateFormat("yyyyMMdd_HHmmss", Locale.US).format(Date()) +
            "_" + UUID.randomUUID().toString().substring(0, 8)
        val assetDir = File(File(libraryRoot(), kind), id)
        val sourceDir = File(assetDir, "source")
        sourceDir.mkdirs()
        val sourceFile = File(sourceDir, sourceFileName(kind, displayName))
        contentResolver.openInputStream(uri).use { input ->
            requireNotNull(input) { "Unable to open selected file." }
            FileOutputStream(sourceFile).use { output -> input.copyTo(output) }
        }
        val aliases = JSONObject()
        if (sourceFile.extension.lowercase(Locale.US) == "zip") {
            mergeAliases(aliases, extractZip(sourceFile, assetDir))
        }
        val metadata = scanAssetDirectory(
            assetDir = assetDir,
            kind = kind,
            id = id,
            displayName = displayName,
            sourceFile = sourceFile,
            sourceDisplayName = displayName,
            pathAliases = aliases,
        )
        File(assetDir, "asset.json").writeText(metadata.toString(2))
        return metadata
    }

    private fun selectedUris(data: Intent): List<Uri> {
        val uris = mutableListOf<Uri>()
        val clipData = data.clipData
        if (clipData != null) {
            for (index in 0 until clipData.itemCount) {
                clipData.getItemAt(index).uri?.let { uri ->
                    if (!uris.contains(uri)) uris.add(uri)
                }
            }
        }
        data.data?.let { uri ->
            if (!uris.contains(uri)) uris.add(uri)
        }
        return uris
    }

    private fun scanLibrary(): JSONArray {
        val items = JSONArray()
        val root = libraryRoot()
        if (!root.exists()) return items
        root.listFiles()?.filter { it.isDirectory }?.forEach { kindDir ->
            kindDir.listFiles()?.filter { it.isDirectory }?.forEach { assetDir ->
                val manifest = File(assetDir, "asset.json")
                if (manifest.exists()) {
                    items.put(JSONObject(manifest.readText()))
                } else {
                    val source = assetDir.walkTopDown().firstOrNull { it.isFile }
                    items.put(
                        scanAssetDirectory(
                            assetDir = assetDir,
                            kind = kindDir.name,
                            id = assetDir.name,
                            displayName = assetDir.name,
                            sourceFile = source ?: assetDir,
                        ),
                    )
                }
            }
        }
        return items
    }

    private fun scanAssetDirectory(
        assetDir: File,
        kind: String,
        id: String,
        displayName: String,
        sourceFile: File,
        sourceDisplayName: String = sourceFile.name,
        pathAliases: JSONObject = JSONObject(),
    ): JSONObject {
        val pmx = JSONArray()
        val motions = JSONArray()
        val textures = JSONArray()
        val audio = JSONArray()
        var fileCount = 0
        var totalBytes = 0L
        assetDir.walkTopDown().filter { it.isFile && it.name != "asset.json" }.forEach { file ->
            fileCount += 1
            totalBytes += file.length()
            val rel = relativePath(assetDir, file)
            when (file.extension.lowercase(Locale.US)) {
                "pmx", "pmd" -> pmx.put(rel)
                "vmd", "vpd", "vpdpose" -> motions.put(rel)
                "png", "jpg", "jpeg", "bmp", "tga", "dds", "spa", "sph" -> textures.put(rel)
                "wav", "mp3", "m4a", "aac", "flac", "ogg" -> audio.put(rel)
            }
        }
        return JSONObject()
            .put("id", id)
            .put("kind", kind)
            .put("name", displayName)
            .put("path", assetDir.absolutePath)
            .put("sourcePath", sourceFile.absolutePath)
            .put("sourceName", sourceDisplayName.ifBlank { sourceFile.name })
            .put("fileCount", fileCount)
            .put("totalBytes", totalBytes)
            .put("pmxCandidates", pmx)
            .put("motionCandidates", motions)
            .put("textureCandidates", textures)
            .put("audioCandidates", audio)
            .put("pathAliases", pathAliases)
    }

    private fun extractZip(zipFile: File, targetDir: File): JSONObject {
        val canonicalTarget = targetDir.canonicalFile
        val aliases = JSONObject()
        val usedPaths = mutableSetOf<String>()
        targetDir.walkTopDown()
            .filter { it.isFile }
            .forEach { file -> usedPaths.add(relativePath(targetDir, file)) }
        ZipInputStream(zipFile.inputStream().buffered()).use { zip ->
            var entry = zip.nextEntry
            while (entry != null) {
                val originalPath = normalizeZipPath(entry.name)
                if (originalPath.isEmpty()) {
                    zip.closeEntry()
                    entry = zip.nextEntry
                    continue
                }
                val safePath = safeRelativePath(originalPath, usedPaths, !entry.isDirectory)
                val outFile = File(targetDir, safePath).canonicalFile
                if (!outFile.path.startsWith(canonicalTarget.path + File.separator)) {
                    throw IllegalArgumentException("Blocked unsafe zip entry: ${entry.name}")
                }
                if (entry.isDirectory) {
                    outFile.mkdirs()
                } else {
                    outFile.parentFile?.mkdirs()
                    FileOutputStream(outFile).use { output -> zip.copyTo(output) }
                    if (safePath != originalPath) {
                        addPathAliases(aliases, originalPath, safePath)
                    }
                }
                zip.closeEntry()
                entry = zip.nextEntry
            }
        }
        return aliases
    }

    private fun queryDisplayName(uri: Uri): String {
        contentResolver.query(uri, arrayOf(OpenableColumns.DISPLAY_NAME), null, null, null).use { cursor ->
            if (cursor != null && cursor.moveToFirst()) {
                val index = cursor.getColumnIndex(OpenableColumns.DISPLAY_NAME)
                if (index >= 0) {
                    val name = cursor.getString(index)
                    if (!name.isNullOrBlank()) return name
                }
            }
        }
        return uri.lastPathSegment?.substringAfterLast('/') ?: "asset.bin"
    }

    private fun libraryRoot(): File = File(filesDir, "danxe_library")

    private fun ensureDownloadExportRoot(): File {
        val root = File(
            Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_DOWNLOADS),
            "danxe",
        )
        try {
            root.mkdirs()
        } catch (_: Exception) {
        }
        return root
    }

    private fun assetDirectory(call: MethodCall): File {
        val kind = call.argument<String>("kind") ?: "other"
        val id = call.argument<String>("id") ?: ""
        return File(File(libraryRoot(), kind), id)
    }

    private fun requireInsideLibrary(file: File) {
        val rootPath = libraryRoot().canonicalPath
        val targetPath = file.canonicalPath
        require(targetPath.startsWith(rootPath + File.separator)) { "Blocked unsafe asset path." }
    }

    private fun readManifest(assetDir: File): JSONObject {
        val manifest = File(assetDir, "asset.json")
        return if (manifest.exists()) JSONObject(manifest.readText()) else JSONObject()
    }

    private fun sourceFileFor(assetDir: File, manifest: JSONObject): File {
        val sourcePath = manifest.optString("sourcePath", "")
        if (sourcePath.isNotBlank()) {
            return File(sourcePath)
        }
        return assetDir.walkTopDown().firstOrNull { it.isFile && it.name != "asset.json" } ?: assetDir
    }

    private fun relativePath(root: File, file: File): String {
        return file.absolutePath.removePrefix(root.absolutePath)
            .trimStart(File.separatorChar)
            .replace(File.separatorChar, '/')
    }

    private fun sourceFileName(kind: String, displayName: String): String {
        val extension = safeExtension(displayName).ifBlank { "bin" }
        val safeKind = asciiToken(kind).ifBlank { "asset" }
        return "source_$safeKind.$extension"
    }

    private fun normalizeZipPath(path: String): String {
        val segments = path
            .replace('\\', '/')
            .split('/')
            .filter { it.isNotBlank() && it != "." }
        require(segments.none { it == ".." }) { "Blocked unsafe zip entry: $path" }
        return segments.joinToString("/")
    }

    private fun safeRelativePath(
        originalPath: String,
        usedPaths: MutableSet<String>,
        isFile: Boolean,
    ): String {
        val segments = originalPath.split('/').filter { it.isNotBlank() }
        val safeSegments = segments.mapIndexed { index, segment ->
            safePathSegment(segment, isFile && index == segments.lastIndex)
        }.toMutableList()
        if (safeSegments.isEmpty()) return ""

        var candidate = safeSegments.joinToString("/")
        if (!isFile) return candidate

        var suffix = 2
        while (candidate in usedPaths) {
            safeSegments[safeSegments.lastIndex] = appendPathSuffix(
                safePathSegment(segments.last(), true),
                suffix,
            )
            candidate = safeSegments.joinToString("/")
            suffix += 1
        }
        usedPaths.add(candidate)
        return candidate
    }

    private fun safePathSegment(segment: String, isFile: Boolean): String {
        if (!isFile) return asciiToken(segment).ifBlank { "dir" }
        val base = segment.substringBeforeLast('.', segment)
        val extension = safeExtension(segment)
        val safeBase = asciiToken(base).ifBlank { "asset" }
        return if (extension.isBlank()) safeBase else "$safeBase.$extension"
    }

    private fun appendPathSuffix(fileName: String, suffix: Int): String {
        val dot = fileName.lastIndexOf('.')
        if (dot <= 0) return "${fileName}_$suffix"
        return "${fileName.substring(0, dot)}_$suffix${fileName.substring(dot)}"
    }

    private fun safeExtension(name: String): String {
        val extension = name.substringAfterLast('.', "")
        return asciiToken(extension).take(12)
    }

    private fun asciiToken(value: String): String {
        val normalized = Normalizer.normalize(value, Normalizer.Form.NFKD)
        return normalized
            .replace(Regex("\\p{M}+"), "")
            .lowercase(Locale.US)
            .replace(Regex("[^a-z0-9._-]+"), "_")
            .trim('_', '.', '-')
    }

    private fun mergeAliases(target: JSONObject, source: JSONObject) {
        val keys = source.keys()
        while (keys.hasNext()) {
            val key = keys.next()
            target.put(key, source.getString(key))
        }
    }

    private fun addPathAliases(aliases: JSONObject, originalPath: String, safePath: String) {
        val originalSegments = originalPath.split('/').filter { it.isNotBlank() }
        val safeSegments = safePath.split('/').filter { it.isNotBlank() }
        val limit = minOf(originalSegments.size, safeSegments.size)
        for (depth in 0 until limit) {
            val alias = (safeSegments.take(depth) + originalSegments.drop(depth)).joinToString("/")
            if (alias != safePath) {
                aliases.put(alias, safePath)
            }
        }
    }

    private fun mimeTypeForKind(kind: String): String {
        return when (kind) {
            "audio" -> "audio/*"
            else -> "*/*"
        }
    }

    private fun mimeAlternatesForKind(kind: String): Array<String> {
        return when (kind) {
            "model" -> arrayOf(
                "application/zip",
                "application/x-zip-compressed",
                "application/octet-stream",
            )
            "audio" -> arrayOf("audio/wav", "audio/mpeg", "audio/mp4", "audio/ogg")
            else -> arrayOf("application/octet-stream", "text/plain", "audio/*")
        }
    }
}
