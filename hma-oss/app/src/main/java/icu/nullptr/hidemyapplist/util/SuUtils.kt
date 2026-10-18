package icu.nullptr.hidemyapplist.util

object SuUtils {

    fun execPrivileged(cmd: String): Boolean {
        return try {
            val exec = Runtime.getRuntime().exec("su -c $cmd")
            exec.waitFor()
            return exec.exitValue() == 0
        } catch (_: Throwable) {
            false
        }
    }

    /**
     * Same as [execPrivileged] but returns the merged stdout/stderr of the
     * command, and passes the command as a single argument to keep the
     * quoting intact.
     *
     * @return null when the root shell could not be started
     */
    fun execPrivilegedWithOutput(cmd: String): String? {
        return try {
            val exec = ProcessBuilder("su", "-c", cmd)
                .redirectErrorStream(true)
                .start()

            val output = exec.inputStream.bufferedReader().use { it.readText() }
            exec.waitFor()

            output
        } catch (_: Throwable) {
            null
        }
    }
}
