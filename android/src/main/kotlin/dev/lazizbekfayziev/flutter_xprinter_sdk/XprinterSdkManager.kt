package dev.lazizbekfayziev.flutter_xprinter_sdk

import android.bluetooth.BluetoothAdapter
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.Color
import android.os.Handler
import android.os.Looper
import android.util.Log
import io.flutter.plugin.common.MethodChannel.Result
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit
import net.posprinter.IConnectListener
import net.posprinter.IDeviceConnection
import net.posprinter.POSConnect
import net.posprinter.POSPrinter
import net.posprinter.posprinterface.IStatusCallback

/**
 * Holds the single active [IDeviceConnection] and routes connection-layer Method
 * Channel calls to the underlying [POSConnect] / [IDeviceConnection] APIs.
 *
 * **Single-connection model**: only one printer at a time.  Re-connecting closes the
 * previous connection automatically.  This is sufficient for receipt printing and
 * avoids the keyed-registry abstraction the original plan proposed.
 *
 * Print methods (printText / printColumnsText / printBitmap / cutPaper / etc.) land in
 * part 2 of the plan; this class only owns the connection lifecycle for now.
 */
class XprinterSdkManager {

    private var currentConnection: IDeviceConnection? = null
    private var currentPrinter: POSPrinter? = null
    private val mainHandler = Handler(Looper.getMainLooper())

    /** Current method name set by the plugin before each onMethodCall dispatch. */
    var currentMethodName: String = "<unknown>"

    // ── Public API (called by XprinterSdkPlugin.onMethodCall) ─────────────────

    fun connect(args: Map<String, Any?>, result: Result) {
        val type = args["type"] as? String
        val address = args["address"] as? String

        if (type == null || address == null) {
            result.error(
                ERR_INVALID_ARGS,
                "connect requires 'type' (bluetooth|usb|tcp) and 'address' string args",
                null,
            )
            return
        }

        // Close any pre-existing connection first.
        disconnect()

        // The XPrinter SDK's only confirmed-working connection pattern (per
        // the vendor's PrinterDemo `App.kt`) is the *async* `connect()` —
        // NOT `connectSync()`.  Flow:
        //   1. `POSConnect.createDevice(deviceType)` → IDeviceConnection
        //   2. `connection.connect(address, listener)` — returns immediately
        //   3. The listener fires CONNECT_SUCCESS / CONNECT_FAIL / _INTERRUPT
        //      asynchronously on the SDK's main-thread executor.
        //
        // We register the listener and let it deliver the Result.  No
        // background thread, no latch — the call is genuinely async.  Main
        // thread stays free so the SDK's main-thread dispatch can reach us.
        connectAsync(type, address, result)
    }

    /**
     * Async connect.  Supports `bluetooth` / `usb` / `tcp` — for each, opens
     * an [IDeviceConnection] of the right device type and calls its async
     * `connect()`.  The listener delivers [result] exactly once.
     */
    private fun connectAsync(type: String, rawAddress: String, result: Result) {
        val deviceType = when (type) {
            "bluetooth" -> POSConnect.DEVICE_TYPE_BLUETOOTH
            "usb"       -> POSConnect.DEVICE_TYPE_USB
            "tcp"       -> POSConnect.DEVICE_TYPE_ETHERNET
            else -> {
                result.error(ERR_INVALID_ARGS, "unknown connection type: $type", null)
                return
            }
        }

        val address = if (type == "bluetooth") {
            val normalized = rawAddress.uppercase()
            logBondedDevices(normalized)
            normalized
        } else {
            rawAddress
        }

        val connection = POSConnect.createDevice(deviceType)
        if (connection == null) {
            result.error(ERR_CONNECT_FAIL, "POSConnect.createDevice returned null", null)
            return
        }

        // Deliver the Result exactly once.  `connect()` may fire the listener
        // multiple times (USB_ATTACHED / _INTERRUPT etc. after the initial
        // success), so we track whether we've already replied.
        val replied = java.util.concurrent.atomic.AtomicBoolean(false)

        val timeoutRunnable = Runnable {
            if (replied.compareAndSet(false, true)) {
                tryClose(connection)
                result.error(
                    ERR_CONNECT_FAIL,
                    "Connect timed out (15 s, no listener callback)",
                    null,
                )
            }
        }
        mainHandler.postDelayed(timeoutRunnable, 15_000)

        val listener = IConnectListener { code, _, message ->
            when (code) {
                POSConnect.CONNECT_SUCCESS -> {
                    if (replied.compareAndSet(false, true)) {
                        mainHandler.removeCallbacks(timeoutRunnable)
                        mainHandler.post {
                            currentConnection = connection
                            currentPrinter = POSPrinter(connection)
                            result.success(true)
                        }
                    }
                }
                POSConnect.CONNECT_FAIL -> {
                    if (replied.compareAndSet(false, true)) {
                        mainHandler.removeCallbacks(timeoutRunnable)
                        tryClose(connection)
                        mainHandler.post {
                            result.error(
                                ERR_CONNECT_FAIL,
                                "Connect failed: code=$code message=${message ?: ""}",
                                null,
                            )
                        }
                    }
                }
                // CONNECT_INTERRUPT, USB_DETACHED, BLUETOOTH_INTERRUPT etc.
                // can fire after a successful connect when the link drops.
                // We don't surface them as connect failures; they're noted
                // post-connect only (logged for diagnosis).
                else -> {
                    Log.i(LOG_TAG, "Listener post-connect status: code=$code message=${message ?: ""}")
                }
            }
        }

        try {
            connection.connect(address, listener)
        } catch (e: Throwable) {
            if (replied.compareAndSet(false, true)) {
                mainHandler.removeCallbacks(timeoutRunnable)
                tryClose(connection)
                result.error(ERR_CONNECT_FAIL, "connect threw: ${e.message}", null)
            }
        }
    }

    /**
     * Logs every OS-bonded Bluetooth device for diagnostic purposes.  Tag
     * `XprinterSdk` — surfaces in `flutter logs` and `adb logcat`.
     *
     * Failures (no permission, adapter null, etc.) are caught and logged
     * — never thrown, since this is purely diagnostic.
     */
    @Suppress("DEPRECATION")
    private fun logBondedDevices(requestedMac: String) {
        try {
            val adapter = BluetoothAdapter.getDefaultAdapter()
            if (adapter == null) {
                Log.w(LOG_TAG, "No Bluetooth adapter on this device")
                return
            }
            val bonded = adapter.bondedDevices ?: emptySet()
            if (bonded.isEmpty()) {
                Log.w(
                    LOG_TAG,
                    "No bonded Bluetooth devices visible to this app — " +
                        "either nothing is paired OR BLUETOOTH_CONNECT runtime " +
                        "permission has not been granted on Android 12+. " +
                        "Requested: $requestedMac",
                )
                return
            }
            Log.i(LOG_TAG, "Requested Bluetooth MAC: $requestedMac")
            Log.i(LOG_TAG, "OS-bonded Bluetooth devices (${bonded.size}):")
            bonded.forEach { device ->
                val matches = device.address.equals(requestedMac, ignoreCase = true)
                val marker = if (matches) "  ✓ MATCH" else ""
                Log.i(LOG_TAG, "  - ${device.address} '${device.name}'$marker")
            }
        } catch (e: SecurityException) {
            Log.w(LOG_TAG, "Cannot read bonded devices — missing BLUETOOTH_CONNECT permission?: ${e.message}")
        } catch (e: Throwable) {
            Log.w(LOG_TAG, "Failed to enumerate bonded devices: ${e.message}")
        }
    }

    private fun tryClose(connection: IDeviceConnection) {
        try {
            connection.close()
        } catch (_: Throwable) {
            // best-effort
        }
    }

    fun disconnectAndRespond(result: Result) {
        disconnect()
        result.success(null)
    }

    fun isConnected(result: Result) {
        result.success(currentConnection?.isConnect == true)
    }

    /** Internal close — also called from plugin detach to avoid leaks. */
    fun disconnect() {
        currentConnection?.let { conn ->
            try {
                conn.close()
            } catch (_: Throwable) { /* best-effort */ }
        }
        currentConnection = null
        currentPrinter = null
    }

    // ── Print methods (part 2) ─────────────────────────────────────────────

    fun initializePrinter(result: Result) = withPrinter(result) { p ->
        p.initializePrinter()
        result.success(null)
    }

    fun printText(args: Map<String, Any?>, result: Result) = withPrinter(result) { p ->
        val text = args["text"] as? String ?: return@withPrinter result.error(
            ERR_INVALID_ARGS, "printText requires 'text'", null,
        )
        val alignment = (args["alignment"] as? Int) ?: 0
        val attribute = (args["attribute"] as? Int) ?: 0
        val textSize = (args["textSize"] as? Int) ?: 0
        p.printText(text, alignment, attribute, textSize)
        result.success(null)
    }

    fun printBitmap(args: Map<String, Any?>, result: Result) = withPrinter(result) { p ->
        val bytes = args["bytes"] as? ByteArray ?: return@withPrinter result.error(
            ERR_INVALID_ARGS, "printBitmap requires 'bytes'", null,
        )
        val alignment = (args["alignment"] as? Int) ?: 1 // CENTER default
        // Target width in dots — third arg of the SDK's 3-param printBitmap.
        // 384 = full 58 mm print head; SDK scales the source bitmap to this
        // width preserving aspect ratio.  Passing 0 here causes the SDK's
        // internal Bitmap.createBitmap to throw "width and height must be > 0".
        val widthDots = (args["widthDots"] as? Int) ?: 384
        val bitmap = BitmapFactory.decodeByteArray(bytes, 0, bytes.size)
        if (bitmap == null || bitmap.width <= 0 || bitmap.height <= 0) {
            result.error(
                ERR_INVALID_ARGS,
                "printBitmap: decoded bitmap is null or has 0×0 dimensions " +
                    "(${bytes.size}-byte buffer)",
                null,
            )
            return@withPrinter
        }
        p.printBitmap(bitmap, alignment, widthDots)
        result.success(null)
    }

    /**
     * Prints a solid black horizontal line by generating the bitmap natively
     * (`Bitmap.createBitmap` + `eraseColor(BLACK)`).  Avoids the PNG-encode /
     * decode round-trip that `printBitmap` requires when the caller starts
     * from PNG bytes — that path was producing 0×0 bitmaps with the Dart
     * `image` package, which the SDK rejects with "width and height must
     * be > 0".
     */
    fun printHorizontalLine(args: Map<String, Any?>, result: Result) = withPrinter(result) { p ->
        val widthDots = (args["widthDots"] as? Int) ?: 384
        val heightRows = (args["heightRows"] as? Int) ?: 4
        val alignment = (args["alignment"] as? Int) ?: 1 // CENTER default
        if (widthDots <= 0 || heightRows <= 0) {
            result.error(
                ERR_INVALID_ARGS,
                "printHorizontalLine: widthDots and heightRows must be > 0 " +
                    "(got widthDots=$widthDots heightRows=$heightRows)",
                null,
            )
            return@withPrinter
        }
        val bitmap = Bitmap.createBitmap(widthDots, heightRows, Bitmap.Config.ARGB_8888)
        bitmap.eraseColor(Color.BLACK)
        // Third arg of SDK's printBitmap is target width in dots — pass the
        // actual bitmap width so the SDK doesn't try to scale to 0.
        p.printBitmap(bitmap, alignment, widthDots)
        result.success(null)
    }

    fun printQRCode(args: Map<String, Any?>, result: Result) = withPrinter(result) { p ->
        val content = args["content"] as? String ?: return@withPrinter result.error(
            ERR_INVALID_ARGS, "printQRCode requires 'content'", null,
        )
        val moduleSize = (args["moduleSize"] as? Int) ?: 4
        val ec = (args["errorCorrection"] as? Int) ?: 49 // POSConst.QRCODE_EC_LEVEL_M
        val alignment = (args["alignment"] as? Int) ?: 1
        p.printQRCode(content, moduleSize, ec, alignment)
        result.success(null)
    }

    fun printBarCode(args: Map<String, Any?>, result: Result) = withPrinter(result) { p ->
        val content = args["content"] as? String ?: return@withPrinter result.error(
            ERR_INVALID_ARGS, "printBarCode requires 'content'", null,
        )
        val type = (args["type"] as? Int) ?: 73 // POSConst.BCS_Code128
        val width = (args["width"] as? Int) ?: 2
        val height = (args["height"] as? Int) ?: 80
        val alignment = (args["alignment"] as? Int) ?: 1
        val hri = (args["hri"] as? Int) ?: 0
        p.printBarCode(content, type, width, height, alignment, hri)
        result.success(null)
    }

    fun feedLine(args: Map<String, Any?>, result: Result) = withPrinter(result) { p ->
        val lines = (args["lines"] as? Int) ?: 1
        p.feedLine(lines)
        result.success(null)
    }

    fun cutPaper(args: Map<String, Any?>, result: Result) = withPrinter(result) { p ->
        val half = (args["half"] as? Boolean) ?: true
        if (half) p.cutHalfAndFeed(0) else p.cutPaper()
        result.success(null)
    }

    fun selectCodePage(args: Map<String, Any?>, result: Result) = withPrinter(result) { p ->
        val page = (args["page"] as? Int) ?: 17 // POSConst.CODE_PAGE_PC866
        p.selectCodePage(page)
        result.success(null)
    }

    fun setAlignment(args: Map<String, Any?>, result: Result) = withPrinter(result) { p ->
        val alignment = (args["alignment"] as? Int) ?: 0
        p.setAlignment(alignment)
        result.success(null)
    }

    fun getStatus(result: Result) = withPrinter(result) { p ->
        // The SDK's printerStatus is async — receive(int) on a callback.
        // Block briefly to convert to a sync-style API for Dart.
        var captured = -1 // STS_UNKNOWN default
        val latch = CountDownLatch(1)
        val cb = IStatusCallback { code ->
            captured = code
            latch.countDown()
        }
        p.printerStatus(cb)
        // 2-second cap.  If the printer is unreachable the SDK never calls back;
        // we surface STS_UNKNOWN rather than hanging.
        latch.await(2, TimeUnit.SECONDS)
        result.success(captured)
    }

    fun sendRawCommand(args: Map<String, Any?>, result: Result) = withPrinter(result) { p ->
        val bytes = args["bytes"] as? ByteArray ?: return@withPrinter result.error(
            ERR_INVALID_ARGS, "sendRawCommand requires 'bytes'", null,
        )
        p.sendData(bytes)
        result.success(null)
    }

    // ── Internal ───────────────────────────────────────────────────────────

    /**
     * Runs [block] with the active POSPrinter, or returns an error if no
     * connection is open / the printer was lost.
     *
     * Catches any native exception, logs it, and surfaces it through
     * [result.error] with the method name so the Dart side can identify
     * exactly which call failed (e.g. `print_fail [printText]: ...`).
     */
    private inline fun withPrinter(result: Result, block: (POSPrinter) -> Unit) {
        val method = currentMethodName
        val printer = currentPrinter
        if (printer == null || currentConnection?.isConnect != true) {
            result.error(
                ERR_NOT_CONNECTED,
                "no active printer connection (method=$method)",
                null,
            )
            return
        }
        try {
            block(printer)
        } catch (e: Throwable) {
            Log.e(LOG_TAG, "Native call '$method' threw: ${e.javaClass.simpleName} ${e.message}", e)
            result.error(
                ERR_PRINT_FAIL,
                "[$method] ${e.javaClass.simpleName}: ${e.message}",
                null,
            )
        }
    }

    companion object {
        private const val LOG_TAG = "XprinterSdk"
        private const val ERR_INVALID_ARGS = "invalid_args"
        private const val ERR_CONNECT_FAIL = "connect_fail"
        private const val ERR_NOT_CONNECTED = "not_connected"
        private const val ERR_PRINT_FAIL = "print_fail"
    }
}
