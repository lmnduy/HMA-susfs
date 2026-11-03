package icu.nullptr.hidemyapplist.receiver

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.util.Log
import icu.nullptr.hidemyapplist.service.ConfigManager
import icu.nullptr.hidemyapplist.service.ServiceClient
import icu.nullptr.hidemyapplist.util.PackageHelper
import icu.nullptr.hidemyapplist.util.SusfsSyncer

class AppChangeReceiver : BroadcastReceiver() {

    companion object {
        private const val TAG = "AppChangeReceiver"

        private val actions = setOf(
            Intent.ACTION_PACKAGE_ADDED,
            Intent.ACTION_PACKAGE_REMOVED,
            Intent.ACTION_PACKAGE_REPLACED
        )

        fun register(context: Context) {
            val filter = IntentFilter().apply {
                actions.forEach(::addAction)
                addDataScheme("package")
            }
            context.registerReceiver(AppChangeReceiver(), filter)
        }
    }

    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action in actions) {
            ServiceClient.log(Log.INFO, TAG, "Received intent: $intent")
            PackageHelper.invalidateCache()

            // ABK PACKAGE_EVENT_SYNC_ABK: keep the sus_path runtime dictionary in
            // step with installs / uninstalls / updates.  The sync only appends
            // the pairs that are missing from the dictionary, so this is cheap;
            // it is skipped entirely when the SUSFS sync is disabled.
            if (ConfigManager.susfsSyncEnabled) {
                val appContext = context.applicationContext
                Thread {
                    try {
                        val result = SusfsSyncer.sync(appContext)
                        ServiceClient.log(
                            Log.INFO, TAG,
                            "sus_path sync after package event: success=${result.success}"
                        )
                    } catch (throwable: Throwable) {
                        ServiceClient.log(
                            Log.WARN, TAG,
                            "sus_path sync after package event failed: ${throwable.message}"
                        )
                    }
                }.apply { isDaemon = true }.start()
            }
        }
    }
}
