package icu.nullptr.hidemyapplist.receiver

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.util.Log
import icu.nullptr.hidemyapplist.service.ServiceClient
import icu.nullptr.hidemyapplist.util.PackageHelper

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

            // ABK PACKAGE_EVENT_ABK: nothing else here on purpose.
            //
            // The sus_path tables are reconciled by an explicit sync and by the
            // boot pass (two minutes after boot) - that is enough and it keeps
            // the cost predictable.  A sync triggered here would not even run on
            // MIUI/HyperOS: the ROM rejects ACTION_PACKAGE_ADDED for third party
            // apps ("MIUILOG- Reject ACTION_PACKAGE_ADDED dispatch to ..."), and a
            // manifest receiver is blocked the same way.
        }
    }
}
