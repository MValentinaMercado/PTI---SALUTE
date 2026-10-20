
package com.example.saluteapp

import android.Manifest
import android.app.Activity
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.content.pm.PackageManager
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.telephony.SmsManager
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

/**
 * Envío REAL de SMS para el SOS. Devuelve a Dart el resultado que informa el
 * sistema (SmsManager sentIntent): solo "sent" cuando el mensaje salió del
 * teléfono hacia la red. Nunca abre la app de mensajes.
 */
class SosSmsChannel(private val activity: Activity) : MethodChannel.MethodCallHandler {

    companion object {
        const val CHANNEL = "saluteapp/sos_sms"
        const val REQ_SMS = 7711
        private const val ACTION_SENT = "saluteapp.SOS_SMS_SENT"
        private const val TIMEOUT_MS = 25_000L
    }

    private var pendingPermission: MethodChannel.Result? = null
    private val main = Handler(Looper.getMainLooper())

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "capability" -> result.success(capability())
            "requestPermission" -> requestPermission(result)
            "send" -> send(
                call.argument<String>("number") ?: "",
                call.argument<String>("message") ?: "",
                result
            )
            else -> result.notImplemented()
        }
    }

    /** "ok" | "no_telephony" | "no_permission" */
    private fun capability(): String {
        val pm = activity.packageManager
        val hasTel = pm.hasSystemFeature(PackageManager.FEATURE_TELEPHONY) ||
            pm.hasSystemFeature(PackageManager.FEATURE_TELEPHONY_MESSAGING)
        if (!hasTel) return "no_telephony"
        val granted = ContextCompat.checkSelfPermission(
            activity, Manifest.permission.SEND_SMS
        ) == PackageManager.PERMISSION_GRANTED
        return if (granted) "ok" else "no_permission"
    }

    private fun requestPermission(result: MethodChannel.Result) {
        if (capability() == "ok") { result.success(true); return }
        if (pendingPermission != null) { result.success(false); return }
        pendingPermission = result
        ActivityCompat.requestPermissions(activity, arrayOf(Manifest.permission.SEND_SMS), REQ_SMS)
    }

    /** Llamar desde MainActivity.onRequestPermissionsResult. */
    fun onPermissionResult(requestCode: Int, grantResults: IntArray) {
        if (requestCode != REQ_SMS) return
        val ok = grantResults.isNotEmpty() && grantResults[0] == PackageManager.PERMISSION_GRANTED
        pendingPermission?.success(ok)
        pendingPermission = null
    }

    private fun smsManager(): SmsManager =
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S)
            activity.getSystemService(SmsManager::class.java)
        else
            @Suppress("DEPRECATION") SmsManager.getDefault()

    private fun send(number: String, message: String, result: MethodChannel.Result) {
        when (capability()) {
            "no_telephony" -> { result.success("unsupported"); return }
            "no_permission" -> { result.success("no_permission"); return }
        }
        if (number.isBlank() || message.isBlank()) { result.success("generic_failure"); return }

        val ctx: Context = activity.applicationContext
        val manager = smsManager()
        val parts = manager.divideMessage(message)
        val total = parts.size
        val action = "$ACTION_SENT.${System.nanoTime()}"
        var received = 0
        var firstError: String? = null
        var finished = false

        lateinit var receiver: BroadcastReceiver
        fun finish(status: String) {
            if (finished) return
            finished = true
            try { ctx.unregisterReceiver(receiver) } catch (_: Exception) {}
            result.success(status)
        }

        receiver = object : BroadcastReceiver() {
            override fun onReceive(c: Context?, i: Intent?) {
                if (resultCode != Activity.RESULT_OK && firstError == null) {
                    firstError = when (resultCode) {
                        SmsManager.RESULT_ERROR_NO_SERVICE -> "no_service"
                        SmsManager.RESULT_ERROR_RADIO_OFF -> "radio_off"
                        else -> "generic_failure"
                    }
                }
                received++
                if (received >= total) finish(firstError ?: "sent")
            }
        }

        val filter = IntentFilter(action)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            ctx.registerReceiver(receiver, filter, Context.RECEIVER_NOT_EXPORTED)
        } else {
            @Suppress("UnspecifiedRegisterReceiverFlag") ctx.registerReceiver(receiver, filter)
        }

        try {
            val sentIntents = ArrayList<PendingIntent>()
            for (idx in 0 until total) {
                val intent = Intent(action).setPackage(ctx.packageName)
                sentIntents.add(
                    PendingIntent.getBroadcast(
                        ctx, idx, intent,
                        PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT
                    )
                )
            }
            if (total == 1) {
                manager.sendTextMessage(number, null, message, sentIntents[0], null)
            } else {
                manager.sendMultipartTextMessage(number, null, parts, sentIntents, null)
            }
            // Sin confirmación del sistema NO se considera enviado.
            main.postDelayed({ finish(firstError ?: "timeout") }, TIMEOUT_MS)
        } catch (e: Exception) {
            finish("generic_failure")
        }
    }
}
