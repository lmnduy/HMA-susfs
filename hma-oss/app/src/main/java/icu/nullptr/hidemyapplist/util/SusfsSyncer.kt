package icu.nullptr.hidemyapplist.util

import android.content.Context
import android.content.pm.ApplicationInfo
import icu.nullptr.hidemyapplist.service.ConfigManager
import java.io.File

/**
 * Synchronizes the SUSFS sus_path (kernel/disk level) hiding with the
 * HMA-OSS application hiding config.
 *
 * The manager app cannot touch the kernel directly, so this object:
 *
 * 1. writes the selected package list and extra paths to the app cache,
 * 2. pushes them to [SUSFS_DIR] as root (readable by the module boot script),
 * 3. copies the bundled `susfs_sync.sh` script next to them,
 * 4. runs the script as root, which calls the ksu_susfs CLI.
 *
 * Every step is idempotent: sus_path entries live in the kernel memory and
 * they are dropped on reboot, so re-adding them is always safe.
 */
object SusfsSyncer {
    /** Root owned directory those files are kept in */
    const val SUSFS_DIR = "/data/adb/hma_susfs"

    /** Package list applied by both the app and the module boot script */
    const val PKGS_FILE = "$SUSFS_DIR/pkgs.txt"

    /**
     * ABK: per-target hide list, one "targetPkg<TAB>hiddenPkg" pair per line.
     *
     * Applied with the kernel command that hides a path from ONE uid only, so
     * the disk layer mirrors the per-target hiding of the API layer.
     */
    const val TARGETS_FILE = "$SUSFS_DIR/targets.txt"

    /** Extra path list (may contain the [PKG_PLACEHOLDER]) */
    const val EXTRA_PATHS_FILE = "$SUSFS_DIR/extra_paths.txt"

    /** Root owned copy of the bundled script */
    const val SCRIPT_FILE = "$SUSFS_DIR/sync.sh"

    /**
     * Root owned flag file (1/0)
     *
     * The module boot script only applies the lists when it contains 1
     */
    const val ENABLED_FILE = "$SUSFS_DIR/enabled"

    /** Placeholder those gets replaced with a package name */
    const val PKG_PLACEHOLDER = "<PKG>"

    private const val ASSET_NAME = "susfs_sync.sh"
    private const val CACHE_DIR_NAME = "hma_susfs"
    private const val SUCCESS_MARKER = "SUSFS_SYNC_OK"

    data class SyncResult(val success: Boolean, val message: String)

    /**
     * ABK: the legacy flat "global hide" list is DEPRECATED.
     *
     * It used to hold "the packages whose paths are hidden from everyone", which
     * cannot express per-target hiding and used to be auto filled with the wrong
     * set. Per-target hiding ([buildTargetsList]) replaces it, so nothing is
     * written here any more.
     */
    /**
     * ABK: GLOBAL hiding is disabled by design.
     *
     * Hiding a package's /data/app from every process breaks that app (launcher
     * icon degrades, the app cannot read its own APK). Only per-target hiding
     * ([buildTargetsList]) is used: a configured target app must answer "not
     * exist" for the hidden packages, while everything else keeps the truth.
     */
    fun buildPkgsList(): List<String> = emptyList()

    fun buildExtraPathsList(): List<String> =
        ConfigManager.susfsExtraPaths.map { it.trim() }.filter { it.isNotEmpty() }.distinct()

    /**
     * ABK: per-target hide list derived from the HMA-OSS black/white list config.
     *
     * @see ConfigManager.getSusfsTargetHides
     */
    fun buildTargetsList(): List<String> {
        val cache = PackageHelper.packageCache.replayCache.lastOrNull().orEmpty()
        if (cache.isEmpty()) return emptyList()

        val userPackages = mutableSetOf<String>()
        val systemPackages = mutableSetOf<String>()

        cache.forEach { (pkg, entry) ->
            val flags = entry.info.applicationInfo?.flags ?: 0
            if (flags and ApplicationInfo.FLAG_SYSTEM != 0) systemPackages.add(pkg)
            else userPackages.add(pkg)
        }

        val installed = userPackages + systemPackages
        val lines = mutableListOf<String>()
        ConfigManager.getSusfsTargetHides(userPackages, systemPackages).forEach { (target, hidden) ->
            // Only installed apps can be targeted; the config may reference apps
            // that are not on this device, and the root script would waste a
            // stat() per line on them (and used to time out).
            if (target !in installed) return@forEach

            fun emit(pkg: String, dataOnly: Boolean) {
                if (pkg !in installed) return
                lines.add(if (dataOnly) target + "\t" + pkg + "\tdata" else target + "\t" + pkg)
            }

            hidden.forEach { pkg -> emit(pkg, false) }
        }

        return lines.sorted()
    }

    /**
     * Writes the current config to [SUSFS_DIR] and applies it.
     *
     * The caller is responsible for running it on a background thread.
     */
    fun sync(context: Context): SyncResult {
        val script = try {
            context.assets.open(ASSET_NAME).bufferedReader().use { it.readText() }
        } catch (throwable: Throwable) {
            return SyncResult(false, "Cannot read $ASSET_NAME: ${throwable.message}")
        }

        val workDir = File(context.cacheDir, CACHE_DIR_NAME).apply { mkdirs() }
        val pkgsFile = File(workDir, "pkgs.txt")
        val extraPathsFile = File(workDir, "extra_paths.txt")
        val targetsFile = File(workDir, "targets.txt")
        val scriptFile = File(workDir, "sync.sh")
        val enabledFile = File(workDir, "enabled")

        pkgsFile.writeText(toFileContent(buildPkgsList()))
        extraPathsFile.writeText(toFileContent(buildExtraPathsList()))
        targetsFile.writeText(toFileContent(buildTargetsList()))
        scriptFile.writeText(script)
        enabledFile.writeText(if (ConfigManager.susfsSyncEnabled) "1\n" else "0\n")

        val cmd = buildString {
            append("mkdir -p '$SUSFS_DIR' && ")
            append("cp '${pkgsFile.absolutePath}' '$PKGS_FILE' && ")
            append("cp '${extraPathsFile.absolutePath}' '$EXTRA_PATHS_FILE' && ")
            append("cp '${targetsFile.absolutePath}' '$TARGETS_FILE' && ")
            append("cp '${scriptFile.absolutePath}' '$SCRIPT_FILE' && ")
            append("cp '${enabledFile.absolutePath}' '$ENABLED_FILE' && ")
            append("chmod 755 '$SUSFS_DIR' && ")
            append("chmod 644 '$PKGS_FILE' '$EXTRA_PATHS_FILE' '$TARGETS_FILE' '$ENABLED_FILE' && ")
            append("chmod 755 '$SCRIPT_FILE' && ")
            append("sh '$SCRIPT_FILE'")
        }

        val output = SuUtils.execPrivilegedWithOutput(cmd)
            ?: return SyncResult(false, "Cannot start the root shell (su)")

        return SyncResult(output.contains(SUCCESS_MARKER), output.trim())
    }

    private fun toFileContent(items: List<String>): String =
        if (items.isEmpty()) "" else items.joinToString("") { "$it\n" }
}
