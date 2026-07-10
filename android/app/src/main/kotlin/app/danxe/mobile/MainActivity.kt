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
import java.util.zip.ZipEntry
import java.util.zip.ZipFile
import java.util.zip.ZipOutputStream

class MainActivity : FlutterActivity() {
    private val channelName = "danxe/host"
    private val viewerEventsName = "danxe/viewer_events"
    private val importRequestCode = 7301
    private var pendingImportResult: MethodChannel.Result? = null
    private var pendingKind: String = "other"
    private lateinit var viewerEvents: MethodChannel

    private data class ZipEntryRecord(
        val entry: ZipEntry,
        val originalPath: String,
    )

    private data class TextRead(
        val text: String,
        val next: Int,
    )

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
                    "viewerSetLook" -> viewerSetLook(call, result)
                    "viewerSetViewOptions" -> viewerSetViewOptions(call, result)
                    "viewerSetPartVisibility" -> viewerSetPartVisibility(call, result)
                    "viewerSetModelTransform" -> viewerSetModelTransform(call, result)
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
                importUri(pendingKind, uri).forEach { item ->
                    metadata.put(item)
                }
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
                packageId = manifest.optString("packageId", ""),
                packageName = manifest.optString("packageName", ""),
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
                packageId = manifest.optString("packageId", ""),
                packageName = manifest.optString("packageName", ""),
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

    private fun viewerSetLook(call: MethodCall, result: MethodChannel.Result) {
        val payload = JSONObject(call.argument<String>("look") ?: "{}")
        viewerCommand("setLook", result, payload)
    }

    private fun viewerSetViewOptions(call: MethodCall, result: MethodChannel.Result) {
        val payload = JSONObject(call.argument<String>("view") ?: "{}")
        viewerCommand("setView", result, payload)
    }

    private fun viewerSetPartVisibility(call: MethodCall, result: MethodChannel.Result) {
        val payload = JSONObject()
            .put("id", call.argument<String>("id") ?: "")
            .put("visible", call.argument<Boolean>("visible") ?: true)
        viewerCommand("setPartVisibility", result, payload)
    }

    private fun viewerSetModelTransform(call: MethodCall, result: MethodChannel.Result) {
        val payload = JSONObject()
            .put("id", call.argument<String>("id") ?: "")
            .put("x", call.argument<Double>("x") ?: 0.0)
            .put("y", call.argument<Double>("y") ?: 0.0)
            .put("z", call.argument<Double>("z") ?: 0.0)
        viewerCommand("setModelTransform", result, payload)
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

    private fun importUri(kind: String, uri: Uri): List<JSONObject> {
        val displayName = queryDisplayName(uri)
        val extension = safeExtension(displayName).lowercase(Locale.US)
        val packageDisplayName = cleanedImportName(displayName)

        if (kind != "model" && extension == "zip") {
            val tempZip = File(cacheDir, "danxe_import_${UUID.randomUUID()}.zip")
            contentResolver.openInputStream(uri).use { input ->
                requireNotNull(input) { "Unable to open selected file." }
                FileOutputStream(tempZip).use { output -> input.copyTo(output) }
            }
            return try {
                importDancePackageZip(
                    requestedKind = kind,
                    displayName = displayName,
                    packageDisplayName = packageDisplayName,
                    zipFile = tempZip,
                )
            } finally {
                tempZip.delete()
            }
        }

        return listOf(importSingleAsset(kind, displayName, uri, singleImportDisplayName(kind, displayName)))
    }

    private fun importSingleAsset(
        kind: String,
        displayName: String,
        uri: Uri,
        cleanedDisplayName: String = cleanedImportName(displayName),
    ): JSONObject {
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
            rewriteZipToEnglish(sourceFile)
        }
        val metadata = scanAssetDirectory(
            assetDir = assetDir,
            kind = kind,
            id = id,
            displayName = cleanedDisplayName,
            sourceFile = sourceFile,
            sourceDisplayName = displayName,
            pathAliases = aliases,
        )
        File(assetDir, "asset.json").writeText(metadata.toString(2))
        return metadata
    }

    private fun importDancePackageZip(
        requestedKind: String,
        displayName: String,
        packageDisplayName: String,
        zipFile: File,
    ): List<JSONObject> {
        val entriesByKind = linkedMapOf<String, MutableList<ZipEntryRecord>>()
        ZipFile(zipFile).use { zip ->
            val records = zipRecords(zip)
            records.forEach { record ->
                val entryKind = packageEntryKind(record.originalPath, requestedKind) ?: return@forEach
                entriesByKind.getOrPut(entryKind) { mutableListOf() }.add(record)
            }

            val packageId = SimpleDateFormat("yyyyMMdd_HHmmss", Locale.US).format(Date()) +
                "_" + UUID.randomUUID().toString().substring(0, 8)
            val imported = mutableListOf<JSONObject>()

            entriesByKind.forEach { (entryKind, recordsForKind) ->
                if (recordsForKind.isEmpty()) return@forEach
                val id = "${packageId}_${entryKind}"
                val assetDir = File(File(libraryRoot(), entryKind), id)
                assetDir.mkdirs()
                val usedPaths = mutableSetOf<String>()
                var firstFile: File? = null

                recordsForKind.forEachIndexed { index, record ->
                    val safePath = dancePackageRelativePath(
                        packageDisplayName = packageDisplayName,
                        kind = entryKind,
                        originalPath = record.originalPath,
                        index = index,
                        total = recordsForKind.size,
                        usedPaths = usedPaths,
                    )
                    val outFile = File(assetDir, safePath).canonicalFile
                    require(outFile.path.startsWith(assetDir.canonicalPath + File.separator)) {
                        "Blocked unsafe zip entry: ${record.originalPath}"
                    }
                    outFile.parentFile?.mkdirs()
                    zip.getInputStream(record.entry).use { input ->
                        FileOutputStream(outFile).use { output -> input.copyTo(output) }
                    }
                    if (firstFile == null) firstFile = outFile
                }

                val metadata = scanAssetDirectory(
                    assetDir = assetDir,
                    kind = entryKind,
                    id = id,
                    displayName = dancePackageAssetName(packageDisplayName, entryKind, recordsForKind),
                    sourceFile = firstFile ?: assetDir,
                    sourceDisplayName = displayName,
                    packageId = packageId,
                    packageName = packageDisplayName,
                )
                File(assetDir, "asset.json").writeText(metadata.toString(2))
                imported.add(metadata)
            }
            return imported
        }
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
        packageId: String = "",
        packageName: String = "",
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
            .put("packageId", packageId)
            .put("packageName", packageName)
    }

    private fun extractZip(zipFile: File, targetDir: File): JSONObject {
        val canonicalTarget = targetDir.canonicalFile
        val aliases = JSONObject()
        ZipFile(zipFile).use { zip ->
            val records = zipRecords(zip)
            val renameMap = buildZipRenameMap(records.map { it.originalPath })
            records.forEach { record ->
                val originalPath = record.originalPath
                val safePath = renameMap[originalPath] ?: return@forEach
                val outFile = File(targetDir, safePath).canonicalFile
                if (!outFile.path.startsWith(canonicalTarget.path + File.separator)) {
                    throw IllegalArgumentException("Blocked unsafe zip entry: ${record.originalPath}")
                }
                outFile.parentFile?.mkdirs()
                if (originalPath.endsWith(".pmx", ignoreCase = true)) {
                    val data = zip.getInputStream(record.entry).use { input -> input.readBytes() }
                    val patched = try {
                        patchPmxTextureTable(data, originalPath, safePath, renameMap)
                    } catch (_: Exception) {
                        data
                    }
                    outFile.writeBytes(patched)
                } else {
                    zip.getInputStream(record.entry).use { input ->
                        FileOutputStream(outFile).use { output -> input.copyTo(output) }
                    }
                }
                if (safePath != originalPath) {
                    addPathAliases(aliases, originalPath, safePath)
                }
            }
        }
        return aliases
    }

    private fun rewriteZipToEnglish(zipFile: File) {
        val tempFile = File(zipFile.parentFile, "${zipFile.name}.tmp")
        ZipFile(zipFile).use { zip ->
            val records = zipRecords(zip)
            val renameMap = buildZipRenameMap(records.map { it.originalPath })
            ZipOutputStream(FileOutputStream(tempFile)).use { output ->
                records.forEach { record ->
                    val originalPath = record.originalPath
                    val safePath = renameMap[originalPath] ?: return@forEach
                    val entry = ZipEntry(safePath)
                    entry.time = record.entry.time
                    output.putNextEntry(entry)
                    if (originalPath.endsWith(".pmx", ignoreCase = true)) {
                        val data = zip.getInputStream(record.entry).use { input -> input.readBytes() }
                        val patched = try {
                            patchPmxTextureTable(data, originalPath, safePath, renameMap)
                        } catch (_: Exception) {
                            data
                        }
                        output.write(patched)
                    } else {
                        zip.getInputStream(record.entry).use { input -> input.copyTo(output) }
                    }
                    output.closeEntry()
                }
            }
        }
        if (zipFile.exists() && !zipFile.delete()) {
            tempFile.delete()
            throw IllegalStateException("Unable to replace imported zip.")
        }
        if (!tempFile.renameTo(zipFile)) {
            tempFile.delete()
            throw IllegalStateException("Unable to save converted zip.")
        }
    }

    private fun zipRecords(zip: ZipFile): List<ZipEntryRecord> {
        val records = mutableListOf<ZipEntryRecord>()
        val entries = zip.entries()
        while (entries.hasMoreElements()) {
            val entry = entries.nextElement()
            val originalPath = normalizeZipPath(entry.name)
            if (originalPath.isEmpty() || entry.isDirectory) continue
            if (originalPath.startsWith("__MACOSX/") || originalPath.substringAfterLast('/') == ".DS_Store") {
                continue
            }
            records.add(ZipEntryRecord(entry, originalPath))
        }
        return records
    }

    private fun buildZipRenameMap(filePaths: List<String>): Map<String, String> {
        val dirMap = linkedMapOf<String, String>()
        var dirCounter = 1
        var fileCounter = 1
        return filePaths.associateWith { oldPath ->
            val parts = oldPath.split('/').filter { it.isNotBlank() }
            val dirs = parts.dropLast(1)
            val filename = parts.lastOrNull().orEmpty()
            val newDirs = mutableListOf<String>()
            var prefix = ""
            dirs.forEach { dir ->
                prefix = if (prefix.isBlank()) dir else "$prefix/$dir"
                val mapped = dirMap.getOrPut(prefix) {
                    "dir_${dirCounter++.toString().padStart(3, '0')}"
                }
                newDirs.add(mapped)
            }
            val extension = safeExtension(filename).lowercase(Locale.US).ifBlank { "bin" }
            val prefixName = if (extension == "pmx") "model" else "asset"
            val newFile = "${prefixName}_${fileCounter++.toString().padStart(5, '0')}.$extension"
            (newDirs + newFile).joinToString("/")
        }
    }

    private fun patchPmxTextureTable(
        data: ByteArray,
        pmxOldPath: String,
        pmxNewPath: String,
        renameMap: Map<String, String>,
    ): ByteArray {
        if (data.size < 16 || data[0] != 'P'.code.toByte() || data[1] != 'M'.code.toByte() ||
            data[2] != 'X'.code.toByte() || data[3] != ' '.code.toByte()
        ) {
            return data
        }

        var p = 8
        val headerSize = readU8(data, p)
        p += 1
        require(p + headerSize <= data.size) { "Invalid PMX header." }
        val header = data.copyOfRange(p, p + headerSize)
        p += headerSize
        require(header.size >= 8) { "PMX header is too short." }

        val textEncoding = header[0].toInt()
        val addUvCount = header[1].toInt()
        val vertexIndexSize = header[2].toInt()
        val textureIndexSize = header[3].toInt()
        val materialIndexSize = header[4].toInt()
        val boneIndexSize = header[5].toInt()
        val morphIndexSize = header[6].toInt()
        val rigidBodyIndexSize = header[7].toInt()
        require(textEncoding == 0 || textEncoding == 1) { "Unsupported PMX text encoding." }
        require(vertexIndexSize in setOf(1, 2, 4) && boneIndexSize in setOf(1, 2, 4)) {
            "Unsupported PMX index size."
        }
        require(textureIndexSize in setOf(1, 2, 4) && materialIndexSize in setOf(1, 2, 4)) {
            "Unsupported PMX index size."
        }
        require(morphIndexSize in setOf(1, 2, 4) && rigidBodyIndexSize in setOf(1, 2, 4)) {
            "Unsupported PMX index size."
        }

        repeat(4) { p = skipPmxText(data, p) }
        val vertexCount = readI32(data, p)
        p += 4
        require(vertexCount >= 0) { "Invalid PMX vertex count." }
        repeat(vertexCount) {
            p += 12 + 12 + 8 + addUvCount * 16
            val weightType = readU8(data, p)
            p += 1
            p += when (weightType) {
                0 -> boneIndexSize
                1 -> boneIndexSize * 2 + 4
                2 -> boneIndexSize * 4 + 16
                3 -> boneIndexSize * 2 + 4 + 36
                4 -> boneIndexSize * 4 + 16
                else -> throw IllegalArgumentException("Unknown PMX weight type: $weightType")
            }
            p += 4
            require(p <= data.size) { "Truncated PMX vertex data." }
        }

        val faceIndexCount = readI32(data, p)
        p += 4
        require(faceIndexCount >= 0) { "Invalid PMX face index count." }
        p += faceIndexCount * vertexIndexSize
        require(p <= data.size) { "Truncated PMX face index data." }

        val textureCount = readI32(data, p)
        p += 4
        require(textureCount >= 0) { "Invalid PMX texture count." }

        val output = mutableListOf<Byte>()
        output.addAll(data.copyOfRange(0, p).toList())
        val pmxNewDir = pmxNewPath.substringBeforeLast('/', "")
        repeat(textureCount) {
            val read = readPmxText(data, p, textEncoding)
            val originalRef = read.text
            val fullOldTexture = resolveTexturePath(pmxOldPath, originalRef)
            val newRef = if (fullOldTexture != null && renameMap.containsKey(fullOldTexture)) {
                relativePosixPath(pmxNewDir, renameMap.getValue(fullOldTexture))
            } else {
                originalRef
            }
            output.addAll(writePmxText(newRef, textEncoding).toList())
            p = read.next
        }
        output.addAll(data.copyOfRange(p, data.size).toList())
        return output.toByteArray()
    }

    private fun readI32(data: ByteArray, offset: Int): Int {
        require(offset + 4 <= data.size) { "PMX data is truncated." }
        return (data[offset].toInt() and 0xff) or
            ((data[offset + 1].toInt() and 0xff) shl 8) or
            ((data[offset + 2].toInt() and 0xff) shl 16) or
            ((data[offset + 3].toInt()) shl 24)
    }

    private fun readU8(data: ByteArray, offset: Int): Int {
        require(offset + 1 <= data.size) { "PMX data is truncated." }
        return data[offset].toInt() and 0xff
    }

    private fun skipPmxText(data: ByteArray, offset: Int): Int {
        val length = readI32(data, offset)
        val start = offset + 4
        require(length >= 0 && start + length <= data.size) { "Invalid PMX string length." }
        return start + length
    }

    private fun readPmxText(data: ByteArray, offset: Int, encodingFlag: Int): TextRead {
        val length = readI32(data, offset)
        val start = offset + 4
        require(length >= 0 && start + length <= data.size) { "Invalid PMX string length." }
        val charset = if (encodingFlag == 0) Charsets.UTF_16LE else Charsets.UTF_8
        return TextRead(String(data, start, length, charset), start + length)
    }

    private fun writePmxText(text: String, encodingFlag: Int): ByteArray {
        val charset = if (encodingFlag == 0) Charsets.UTF_16LE else Charsets.UTF_8
        val bytes = text.toByteArray(charset)
        return byteArrayOf(
            (bytes.size and 0xff).toByte(),
            ((bytes.size shr 8) and 0xff).toByte(),
            ((bytes.size shr 16) and 0xff).toByte(),
            ((bytes.size shr 24) and 0xff).toByte(),
        ) + bytes
    }

    private fun resolveTexturePath(pmxOldPath: String, textureRef: String): String? {
        val ref = textureRef.replace('\\', '/').trim()
        if (ref.isBlank() || ref.startsWith("/") || Regex("^[A-Za-z]:/").containsMatchIn(ref)) {
            return null
        }
        val pmxDir = pmxOldPath.substringBeforeLast('/', "")
        return normalizePosixPath(listOf(pmxDir, ref).filter { it.isNotBlank() }.joinToString("/"))
    }

    private fun normalizePosixPath(path: String): String {
        val stack = mutableListOf<String>()
        path.replace('\\', '/').split('/').forEach { segment ->
            when {
                segment.isBlank() || segment == "." -> Unit
                segment == ".." -> if (stack.isNotEmpty()) stack.removeAt(stack.lastIndex)
                else -> stack.add(segment)
            }
        }
        return stack.joinToString("/")
    }

    private fun relativePosixPath(fromDir: String, toPath: String): String {
        val from = normalizePosixPath(fromDir).split('/').filter { it.isNotBlank() }
        val to = normalizePosixPath(toPath).split('/').filter { it.isNotBlank() }
        var common = 0
        while (common < from.size && common < to.size && from[common] == to[common]) {
            common += 1
        }
        val up = List(from.size - common) { ".." }
        return (up + to.drop(common)).joinToString("/").ifBlank { to.lastOrNull().orEmpty() }
    }

    private fun packageEntryKind(path: String, requestedKind: String): String? {
        val extension = path.substringAfterLast('.', "").lowercase(Locale.US)
        val name = path.substringAfterLast('/').substringBeforeLast('.').lowercase(Locale.US)
        return when (extension) {
            "wav", "mp3", "m4a", "aac", "flac", "ogg" -> "audio"
            "vmd", "vpd", "vpdpose" -> when {
                requestedKind == "camera" -> "camera"
                requestedKind == "face" -> "face"
                name.contains("camera") || name.contains("cam") || name.contains("镜头") -> "camera"
                name.contains("face") || name.contains("morph") || name.contains("表情") -> "face"
                else -> "motion"
            }
            else -> null
        }
    }

    private fun dancePackageRelativePath(
        packageDisplayName: String,
        kind: String,
        originalPath: String,
        index: Int,
        total: Int,
        usedPaths: MutableSet<String>,
    ): String {
        val extension = safeExtension(originalPath).ifBlank { "bin" }
        val suffix = if (total > 1) "_${(index + 1).toString().padStart(2, '0')}" else ""
        val base = asciiToken("${packageDisplayName}_${kind}").ifBlank { kind }
        var candidate = "$base$suffix.$extension"
        var extra = 2
        while (candidate in usedPaths) {
            candidate = "$base$suffix _$extra.$extension".replace(" ", "")
            extra += 1
        }
        usedPaths.add(candidate)
        return candidate
    }

    private fun dancePackageAssetName(
        packageDisplayName: String,
        kind: String,
        records: List<ZipEntryRecord>,
    ): String {
        val extension = records.firstOrNull()?.originalPath?.substringAfterLast('.', "")?.lowercase(Locale.US)
            ?: kind
        val suffix = when {
            kind == "camera" -> "_camera.$extension"
            kind == "face" -> "_face.$extension"
            records.size > 1 -> "_${kind}.$extension"
            else -> ".$extension"
        }
        return "$packageDisplayName$suffix"
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

    private fun singleImportDisplayName(kind: String, displayName: String): String {
        val extension = safeExtension(displayName).lowercase(Locale.US)
        return if (kind == "model" && extension == "zip") {
            cleanedImportName(displayName)
        } else {
            displayName
        }
    }

    private fun cleanedImportName(displayName: String): String {
        var base = displayName.substringBeforeLast('.', displayName).trim()
        base = base.replace(Regex("(?i)[_\\-\\s]+by[_\\-\\s]+"), "_")
        base = base.replace(Regex("(?i)^by[_\\-\\s]+"), "")
        base = base.replace(Regex("(?i)[_\\-\\s]+[a-f0-9]{12,}$"), "")
        base = base.replace(Regex("^[0-9]+[_\\-\\s]*"), "")
        base = base.replace(Regex("[_\\-\\s]+"), "_")
        base = base.trim('_', '-', ' ', '.')
        return base.ifBlank {
            displayName.substringBeforeLast('.', displayName).ifBlank { "asset" }
        }
    }

    private fun normalizeZipPath(path: String): String {
        val segments = path
            .replace('\\', '/')
            .split('/')
            .filter { it.isNotBlank() && it != "." }
        require(segments.none { it == ".." }) { "Blocked unsafe zip entry: $path" }
        return segments.joinToString("/")
    }

    private fun safeExtension(name: String): String {
        val extension = name.substringAfterLast('/').substringAfterLast('.', "")
        val safe = asciiToken(extension).lowercase(Locale.US)
        return if (Regex("^[a-z0-9]{1,10}$").matches(safe)) safe else "bin"
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
                aliases.put(alias.lowercase(Locale.US), safePath)
            }
        }
    }

    private fun mimeTypeForKind(kind: String): String {
        return "*/*"
    }

    private fun mimeAlternatesForKind(kind: String): Array<String> {
        return when (kind) {
            "model" -> arrayOf(
                "application/zip",
                "application/x-zip-compressed",
                "application/octet-stream",
            )
            "audio" -> arrayOf(
                "audio/wav",
                "audio/mpeg",
                "audio/mp4",
                "audio/ogg",
                "application/zip",
                "application/x-zip-compressed",
            )
            else -> arrayOf(
                "application/octet-stream",
                "text/plain",
                "audio/*",
                "application/zip",
                "application/x-zip-compressed",
            )
        }
    }
}
