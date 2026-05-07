package dev.lazizbekfayziev.flutter_xprinter_sdk

import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.MethodChannel.MethodCallHandler
import io.flutter.plugin.common.MethodChannel.Result
import net.posprinter.POSConnect

/**
 * Flutter plugin entry point for the XPrinter SDK wrapper.
 *
 * Owns one MethodChannel ("dev.lazizbekfayziev.flutter_xprinter_sdk") and delegates all calls to
 * [XprinterSdkManager], which holds the single active [net.posprinter.IDeviceConnection].
 *
 * Initializes the XPrinter SDK once on engine attach via [POSConnect.init].
 */
class XprinterSdkPlugin : FlutterPlugin, MethodCallHandler {

    private lateinit var methodChannel: MethodChannel
    private lateinit var discoveryChannel: EventChannel
    private val sdkManager = XprinterSdkManager()
    private lateinit var bluetoothScanner: XprinterBluetoothScanner

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        // POSConnect.init must be called once with an Application context before any
        // POSConnect.createDevice / connectMac call.  Safe to call multiple times — the
        // SDK guards against re-init internally.
        POSConnect.init(binding.applicationContext)

        methodChannel = MethodChannel(binding.binaryMessenger, CHANNEL)
        methodChannel.setMethodCallHandler(this)

        bluetoothScanner = XprinterBluetoothScanner.fromApplicationContext(binding.applicationContext)
        discoveryChannel = EventChannel(binding.binaryMessenger, XprinterBluetoothScanner.DISCOVERY_CHANNEL)
        discoveryChannel.setStreamHandler(bluetoothScanner.discoveryHandler)
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        methodChannel.setMethodCallHandler(null)
        discoveryChannel.setStreamHandler(null)
        sdkManager.disconnect()
    }

    @Suppress("UNCHECKED_CAST")
    override fun onMethodCall(call: MethodCall, result: Result) {
        val args = (call.arguments as? Map<String, Any?>) ?: emptyMap()
        // Pass the method name into the manager so its catch-all error
        // path can include it — otherwise every native exception surfaces
        // as a generic "print call threw" with no clue which method failed.
        sdkManager.currentMethodName = call.method
        when (call.method) {
            // Connection layer (part 1)
            "connect"     -> sdkManager.connect(args, result)
            "disconnect"  -> sdkManager.disconnectAndRespond(result)
            "isConnected" -> sdkManager.isConnected(result)

            // Bluetooth scan/pair helpers (replaces flutter_bluetooth_printer
            // discovery — see XprinterBluetoothScanner).
            "getBondedDevices" -> bluetoothScanner.getBondedDevices(result)

            // Print methods (part 2)
            "initialize"      -> sdkManager.initializePrinter(result)
            "printText"       -> sdkManager.printText(args, result)
            "printBitmap"     -> sdkManager.printBitmap(args, result)
            "printHorizontalLine" -> sdkManager.printHorizontalLine(args, result)
            "printQRCode"     -> sdkManager.printQRCode(args, result)
            "printBarCode"    -> sdkManager.printBarCode(args, result)
            "feedLine"        -> sdkManager.feedLine(args, result)
            "cutPaper"        -> sdkManager.cutPaper(args, result)
            "selectCodePage"  -> sdkManager.selectCodePage(args, result)
            "setAlignment"    -> sdkManager.setAlignment(args, result)
            "getStatus"       -> sdkManager.getStatus(result)
            "sendRawCommand"  -> sdkManager.sendRawCommand(args, result)

            else -> result.notImplemented()
        }
    }

    companion object {
        private const val CHANNEL = "dev.lazizbekfayziev.flutter_xprinter_sdk"
    }
}
