package icu.nullptr.hidemyapplist

import android.app.Application
import android.util.Log
import androidx.appcompat.app.AppCompatDelegate
import icu.nullptr.hidemyapplist.receiver.AppChangeReceiver
import icu.nullptr.hidemyapplist.service.ConfigManager
import icu.nullptr.hidemyapplist.service.PrefManager
import icu.nullptr.hidemyapplist.service.ServiceClient
import icu.nullptr.hidemyapplist.util.ConfigUtils.getLocale
import icu.nullptr.hidemyapplist.util.SusfsSyncer
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import java.util.Locale

class MyApp : Application() {
    companion object {
        lateinit var hmaApp: MyApp
    }

    val globalScope = CoroutineScope(Dispatchers.Default)
    var updateDialogSkipped: Boolean = false

    fun loadConfiguration() {
        if (ServiceClient.serviceVersion > 0) {
            ConfigManager.init()
        }
    }

    fun loadPreferences() {
        AppCompatDelegate.setDefaultNightMode(PrefManager.darkTheme)

        reloadLocale(getLocale())
    }

    @Suppress("DEPRECATION")
    fun reloadLocale(locale: Locale) {
        val config = resources.configuration
        config.setLocale(locale)
        resources.updateConfiguration(config, resources.displayMetrics)
    }

    override fun onCreate() {
        super.onCreate()
        hmaApp = this
        loadPreferences()
        AppChangeReceiver.register(this)

        // ABK SCRIPT_DEPLOY_ABK: keep /data/adb/hma_susfs/sync.sh in step with
        // the APK.  The boot pass runs whatever script is on disk, so after an
        // update the module used to keep executing the previous logic.
        Thread {
            try {
                SusfsSyncer.deployScript(applicationContext)
            } catch (_: Throwable) {
                // root not granted yet: the next sync will deploy it anyway
            }
        }.apply { isDaemon = true }.start()

        val handler = Thread.getDefaultUncaughtExceptionHandler()
        Thread.setDefaultUncaughtExceptionHandler { t, e ->
            ServiceClient.log(Log.ERROR, t.name, e.stackTraceToString())
            handler?.uncaughtException(t, e)
        }
    }
}
