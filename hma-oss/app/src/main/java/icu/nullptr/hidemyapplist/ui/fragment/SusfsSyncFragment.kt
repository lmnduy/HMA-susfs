package icu.nullptr.hidemyapplist.ui.fragment

import android.os.Bundle
import android.widget.EditText
import androidx.preference.Preference
import androidx.preference.PreferenceCategory
import androidx.preference.PreferenceFragmentCompat
import androidx.preference.SwitchPreferenceCompat
import com.google.android.material.dialog.MaterialAlertDialogBuilder
import icu.nullptr.hidemyapplist.service.ConfigManager
import icu.nullptr.hidemyapplist.ui.util.showToast
import icu.nullptr.hidemyapplist.util.PackageHelper
import icu.nullptr.hidemyapplist.util.SusfsSyncer
import org.frknkrc44.hma_oss.R
import java.util.concurrent.Executors

/**
 * Settings screen of the SUSFS package path hiding sync.
 *
 * It edits [ConfigManager.susfsSyncEnabled], [ConfigManager.susfsHidePkgs] and
 * [ConfigManager.susfsExtraPaths], and it can apply them right away through
 * [SusfsSyncer].
 */
class SusfsSyncFragment : PreferenceFragmentCompat() {

    private val executor = Executors.newSingleThreadExecutor()

    private var pkgsPreference: Preference? = null
    private var extraPathsPreference: Preference? = null

    override fun onCreatePreferences(savedInstanceState: Bundle?, rootKey: String?) {
        val context = requireContext()
        val screen = preferenceManager.createPreferenceScreen(context)

        val category = PreferenceCategory(context).apply {
            key = "categorySusfsSync"
            title = getString(R.string.settings_susfs_sync)
            isPersistent = false
        }
        screen.addPreference(category)

        category.addPreference(SwitchPreferenceCompat(context).apply {
            key = "susfsSyncEnabled"
            isPersistent = false
            title = getString(R.string.settings_susfs_sync_enabled)
            summary = getString(R.string.settings_susfs_sync_enabled_summary)
            isChecked = ConfigManager.susfsSyncEnabled
            setOnPreferenceChangeListener { _, newValue ->
                ConfigManager.susfsSyncEnabled = newValue as Boolean

                // publish the new state (and the current lists) to root
                runSync(showResult = false)

                true
            }
        })

        val pkgsPreference = Preference(context).apply {
            key = "susfsHidePkgs"
            isPersistent = false
            title = getString(R.string.settings_susfs_hide_pkgs)
            setOnPreferenceClickListener {
                showPackageSelectDialog()
                true
            }
        }
        this.pkgsPreference = pkgsPreference
        category.addPreference(pkgsPreference)

        category.addPreference(Preference(context).apply {
            key = "susfsFillFromHma"
            isPersistent = false
            title = getString(R.string.settings_susfs_fill_from_hma)
            summary = getString(R.string.settings_susfs_fill_from_hma_summary)
            setOnPreferenceClickListener {
                fillFromHma()
                true
            }
        })

        val extraPathsPreference = Preference(context).apply {
            key = "susfsExtraPaths"
            isPersistent = false
            title = getString(R.string.settings_susfs_extra_paths)
            setOnPreferenceClickListener {
                showExtraPathsDialog()
                true
            }
        }
        this.extraPathsPreference = extraPathsPreference
        category.addPreference(extraPathsPreference)

        category.addPreference(Preference(context).apply {
            key = "susfsSyncNow"
            isPersistent = false
            title = getString(R.string.settings_susfs_sync_now)
            summary = getString(R.string.settings_susfs_sync_now_summary)
            setOnPreferenceClickListener {
                startSync()
                true
            }
        })

        category.addPreference(Preference(context).apply {
            key = "susfsSyncInfo"
            isPersistent = false
            isSelectable = false
            summary = getString(R.string.settings_susfs_sync_info, SusfsSyncer.SUSFS_DIR)
        })

        preferenceScreen = screen
        refreshSummaries()
    }

    override fun onDestroy() {
        executor.shutdownNow()
        super.onDestroy()
    }

    private fun refreshSummaries() {
        pkgsPreference?.summary = "全局隐藏已停用（按目标隐藏；残留 " +
            ConfigManager.susfsHidePkgs.size + " 项，点一下清空）"

        val extraPaths = ConfigManager.susfsExtraPaths

        extraPathsPreference?.summary = if (extraPaths.isEmpty()) {
            getString(R.string.settings_susfs_extra_paths_empty)
        } else {
            extraPaths.joinToString("\n")
        }
    }

    private fun loadPackageList(): List<String> {
        val installed = PackageHelper.appList.replayCache.lastOrNull().orEmpty()

        return (installed + ConfigManager.susfsHidePkgs).distinct().sorted()
    }

    /**
     * ABK: the legacy flat list is deprecated; this now clears it and lets the
     * per-target list (targets.txt) do the work instead.
     */
    /**
     * ABK: global hiding is disabled; this button now only clears the legacy list
     * so that a stale value cannot come back through an old configuration.
     */
    private fun fillFromHma() {
        ConfigManager.susfsHidePkgs = emptySet()
        refreshSummaries()

        showToast("全局隐藏已停用：现在只按目标隐藏（targets.txt）")
    }

    private fun showPackageSelectDialog() {
        val packages = loadPackageList()

        if (packages.isEmpty()) {
            showToast(R.string.settings_susfs_no_packages)
            return
        }

        val entries = packages.map { packageName ->
            val label = PackageHelper.loadAppLabel(packageName)

            if (label == packageName) packageName else "$label ($packageName)"
        }.toTypedArray()

        val selected = ConfigManager.susfsHidePkgs.toMutableSet()
        val checkedItems = BooleanArray(packages.size) { packages[it] in selected }

        MaterialAlertDialogBuilder(requireContext())
            .setTitle(R.string.settings_susfs_hide_pkgs)
            .setMultiChoiceItems(entries, checkedItems) { _, which, isChecked ->
                if (isChecked) selected.add(packages[which]) else selected.remove(packages[which])
            }
            .setPositiveButton(android.R.string.ok) { _, _ ->
                ConfigManager.susfsHidePkgs = selected
                refreshSummaries()
            }
            .setNeutralButton(R.string.settings_susfs_fill_from_hma) { _, _ -> fillFromHma() }
            .setNegativeButton(android.R.string.cancel, null)
            .show()
    }

    private fun showExtraPathsDialog() {
        val extraPaths = ConfigManager.susfsExtraPaths.toList()

        MaterialAlertDialogBuilder(requireContext())
            .setTitle(R.string.settings_susfs_extra_paths_remove_hint)
            .setItems(extraPaths.toTypedArray()) { _, which ->
                ConfigManager.susfsExtraPaths = extraPaths.filterIndexed { index, _ -> index != which }
                refreshSummaries()

                showToast(getString(R.string.settings_susfs_path_removed, extraPaths[which]))
            }
            .setPositiveButton(R.string.settings_susfs_add_path) { _, _ -> showAddPathDialog() }
            .setNegativeButton(android.R.string.cancel, null)
            .show()
    }

    private fun showAddPathDialog() {
        val input = EditText(requireContext()).apply {
            hint = getString(R.string.settings_susfs_path_hint)
            isSingleLine = true
        }

        MaterialAlertDialogBuilder(requireContext())
            .setTitle(R.string.settings_susfs_add_path)
            .setMessage(R.string.settings_susfs_path_placeholder_hint)
            .setView(input)
            .setPositiveButton(android.R.string.ok) { _, _ ->
                val path = input.text.toString().trim()

                if (path.isEmpty()) return@setPositiveButton

                ConfigManager.susfsExtraPaths = ConfigManager.susfsExtraPaths + path
                refreshSummaries()
            }
            .setNegativeButton(android.R.string.cancel, null)
            .show()
    }

    private fun startSync() = runSync(showResult = true)

    private fun runSync(showResult: Boolean) {
        val context = requireContext().applicationContext

        if (showResult) showToast(R.string.settings_susfs_sync_started)

        executor.execute {
            val result = SusfsSyncer.sync(context)

            if (!showResult) return@execute

            activity?.runOnUiThread {
                if (!isAdded) return@runOnUiThread

                if (result.success) {
                    showToast(getString(R.string.settings_susfs_sync_done))
                } else {
                    showToast(getString(R.string.settings_susfs_sync_failed, result.message))
                }
            }
        }
    }
}
