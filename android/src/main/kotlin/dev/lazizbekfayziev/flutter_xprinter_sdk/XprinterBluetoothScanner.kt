package dev.lazizbekfayziev.flutter_xprinter_sdk

import android.annotation.SuppressLint
import android.app.Application
import android.bluetooth.BluetoothAdapter
import android.bluetooth.BluetoothDevice
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.util.Log
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel.Result

/**
 * Bluetooth discovery + bonded-list helpers for the XPrinter plugin.
 *
 * The XPrinter SDK itself doesn't ship Bluetooth scanning — it expects the
 * caller to hand it a MAC.  This scanner wraps the platform
 * [BluetoothAdapter] APIs the same way `flutter_bluetooth_printer` did, so
 * we can drop that dependency entirely and keep one source of truth for
 * printer connectivity.
 *
 * Two surfaces:
 *
 * - [getBondedDevices] — one-shot snapshot of every device the OS already
 *   knows about (paired in system Bluetooth settings).  This is the
 *   important one for cheap thermal printers that go silent on inquiry
 *   after first pairing.
 * - [discoveryHandler] — an [EventChannel.StreamHandler] that runs
 *   classic-BT inquiry while a Dart listener is attached and emits each
 *   newly-found device as a `{address, name}` map.  Cancelling the
 *   subscription stops discovery and releases the [BroadcastReceiver].
 */
class XprinterBluetoothScanner(private val appContext: Context) {

    /** Best-effort: returns `null` and logs if permission is missing. */
    @SuppressLint("MissingPermission") // checked via try/catch below
    fun getBondedDevices(result: Result) {
        try {
            val adapter = BluetoothAdapter.getDefaultAdapter()
            if (adapter == null) {
                result.success(emptyList<Map<String, String?>>())
                return
            }
            val bonded = adapter.bondedDevices ?: emptySet()
            val out = bonded.map { d ->
                mapOf(
                    "address" to d.address,
                    "name" to (d.name ?: ""),
                )
            }
            result.success(out)
        } catch (e: SecurityException) {
            Log.w(LOG_TAG, "getBondedDevices: BLUETOOTH_CONNECT not granted: ${e.message}")
            result.error(
                "BLUETOOTH_PERMISSION",
                "BLUETOOTH_CONNECT runtime permission required on Android 12+",
                null,
            )
        } catch (e: Throwable) {
            Log.w(LOG_TAG, "getBondedDevices failed: ${e.message}")
            result.error("BONDED_FAIL", e.message ?: "unknown", null)
        }
    }

    /**
     * Stream handler for the discovery EventChannel.
     *
     * onListen → starts inquiry, registers receiver for `ACTION_FOUND`.
     * onCancel → stops inquiry, unregisters receiver.
     */
    val discoveryHandler: EventChannel.StreamHandler = object : EventChannel.StreamHandler {
        private var receiver: BroadcastReceiver? = null
        private val mainHandler = Handler(Looper.getMainLooper())

        @SuppressLint("MissingPermission") // checked via try/catch below
        override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
            if (events == null) return
            val adapter = BluetoothAdapter.getDefaultAdapter()
            if (adapter == null) {
                events.error("NO_ADAPTER", "Bluetooth not available on this device", null)
                events.endOfStream()
                return
            }

            // Always cancel any in-flight discovery before starting a new
            // one — otherwise startDiscovery is a no-op and our receiver
            // never fires.
            try { adapter.cancelDiscovery() } catch (_: Throwable) { /* best-effort */ }

            receiver = object : BroadcastReceiver() {
                override fun onReceive(context: Context?, intent: Intent?) {
                    if (intent?.action != BluetoothDevice.ACTION_FOUND) return
                    val device = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                        intent.getParcelableExtra(BluetoothDevice.EXTRA_DEVICE, BluetoothDevice::class.java)
                    } else {
                        @Suppress("DEPRECATION")
                        intent.getParcelableExtra<BluetoothDevice>(BluetoothDevice.EXTRA_DEVICE)
                    }
                    if (device == null) return
                    val name = try { device.name ?: "" } catch (_: SecurityException) { "" }
                    mainHandler.post {
                        events.success(
                            mapOf(
                                "address" to device.address,
                                "name" to name,
                            ),
                        )
                    }
                }
            }

            try {
                appContext.registerReceiver(receiver, IntentFilter(BluetoothDevice.ACTION_FOUND))
            } catch (e: Throwable) {
                Log.w(LOG_TAG, "registerReceiver failed: ${e.message}")
                events.error("RECEIVER_FAIL", e.message ?: "unknown", null)
                events.endOfStream()
                receiver = null
                return
            }

            try {
                if (!adapter.startDiscovery()) {
                    Log.w(LOG_TAG, "startDiscovery returned false (permission or adapter state?)")
                    events.error(
                        "START_DISCOVERY_FAIL",
                        "BluetoothAdapter.startDiscovery() returned false",
                        null,
                    )
                    cleanupReceiver()
                    events.endOfStream()
                }
            } catch (e: SecurityException) {
                Log.w(LOG_TAG, "startDiscovery: BLUETOOTH_SCAN not granted: ${e.message}")
                events.error(
                    "BLUETOOTH_PERMISSION",
                    "BLUETOOTH_SCAN runtime permission required on Android 12+",
                    null,
                )
                cleanupReceiver()
                events.endOfStream()
            }
        }

        @SuppressLint("MissingPermission")
        override fun onCancel(arguments: Any?) {
            try {
                BluetoothAdapter.getDefaultAdapter()?.cancelDiscovery()
            } catch (_: Throwable) { /* best-effort */ }
            cleanupReceiver()
        }

        private fun cleanupReceiver() {
            val r = receiver ?: return
            receiver = null
            try {
                appContext.unregisterReceiver(r)
            } catch (_: Throwable) { /* not registered */ }
        }
    }

    /** Companion factory: builds the scanner from a Flutter plugin binding context. */
    companion object {
        private const val LOG_TAG = "XprinterSdk"
        const val DISCOVERY_CHANNEL = "dev.lazizbekfayziev.flutter_xprinter_sdk/discovery"

        fun fromApplicationContext(context: Context): XprinterBluetoothScanner {
            // Always use the Application context so the receiver outlives any
            // single Activity (the user might background the app while a
            // 5-second scan is in flight).
            val app = (context.applicationContext as? Application) ?: context
            return XprinterBluetoothScanner(app)
        }
    }
}
