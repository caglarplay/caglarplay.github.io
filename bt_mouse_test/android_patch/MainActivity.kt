package com.caglarplay.bt_mouse_test

import android.Manifest
import android.app.Activity
import android.bluetooth.BluetoothAdapter
import android.bluetooth.BluetoothDevice
import android.bluetooth.BluetoothHidDevice
import android.bluetooth.BluetoothHidDeviceAppSdpSettings
import android.bluetooth.BluetoothProfile
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import kotlin.math.roundToInt

class MainActivity : FlutterActivity() {
    private val channelName = "bt_mouse/hid"
    private lateinit var channel: MethodChannel
    private val adapter: BluetoothAdapter? = BluetoothAdapter.getDefaultAdapter()
    private var hid: BluetoothHidDevice? = null
    private var connectedDevice: BluetoothDevice? = null
    private var hidRegistered = false

    private val descriptor: ByteArray = intArrayOf(
        0x05,0x01, 0x09,0x02, 0xA1,0x01, 0x09,0x01, 0xA1,0x00,
        0x05,0x09, 0x19,0x01, 0x29,0x03, 0x15,0x00, 0x25,0x01,
        0x95,0x03, 0x75,0x01, 0x81,0x02, 0x95,0x01, 0x75,0x05, 0x81,0x03,
        0x05,0x01, 0x09,0x30, 0x09,0x31, 0x09,0x38, 0x15,0x81, 0x25,0x7F,
        0x75,0x08, 0x95,0x03, 0x81,0x06, 0xC0, 0xC0
    ).map { it.toByte() }.toByteArray()

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        channel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName)
        channel.setMethodCallHandler { call, result ->
            when (call.method) {
                "startHid" -> result.success(startHid())
                "discoverable" -> {
                    makeDiscoverable()
                    result.success(true)
                }
                "bondedDevices" -> result.success(bondedDevices())
                "connect" -> {
                    val address = call.argument<String>("address") ?: ""
                    result.success(connectTo(address))
                }
                "move" -> {
                    val dx = (call.argument<Double>("dx") ?: 0.0).roundToInt().coerceIn(-127,127)
                    val dy = (call.argument<Double>("dy") ?: 0.0).roundToInt().coerceIn(-127,127)
                    result.success(sendMouse(0, dx, dy, 0))
                }
                "click" -> result.success(click())
                "scroll" -> {
                    val amount = (call.argument<Int>("amount") ?: 0).coerceIn(-127,127)
                    result.success(sendMouse(0, 0, 0, amount))
                }
                else -> result.notImplemented()
            }
        }
    }

    private fun requiredPermissions(): Array<String> = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
        arrayOf(Manifest.permission.BLUETOOTH_CONNECT, Manifest.permission.BLUETOOTH_ADVERTISE, Manifest.permission.BLUETOOTH_SCAN)
    } else emptyArray()

    private fun hasPermissions(): Boolean = requiredPermissions().all {
        ContextCompat.checkSelfPermission(this, it) == PackageManager.PERMISSION_GRANTED
    }

    private fun requestBtPermissions() {
        val p = requiredPermissions()
        if (p.isNotEmpty()) ActivityCompat.requestPermissions(this, p, 900)
    }

    private fun startHid(): String {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.P) return "Android sürümü Bluetooth HID Device için eski"
        if (adapter == null) return "Bluetooth donanımı bulunamadı"
        if (!hasPermissions()) {
            requestBtPermissions()
            return "Bluetooth izinlerini ver, sonra HID Başlat’a tekrar bas"
        }
        if (hidRegistered) return "HID hazır"
        val ok = adapter.getProfileProxy(this, profileListener, BluetoothProfile.HID_DEVICE)
        return if (ok) "HID servisi hazırlanıyor…" else "HID servisi açılamadı"
    }

    private val profileListener = object : BluetoothProfile.ServiceListener {
        override fun onServiceConnected(profile: Int, proxy: BluetoothProfile) {
            if (profile != BluetoothProfile.HID_DEVICE) return
            hid = proxy as BluetoothHidDevice
            val sdp = BluetoothHidDeviceAppSdpSettings(
                "Kumanda Mouse",
                "Android TV Bluetooth Mouse",
                "Caglarplay",
                0x80.toByte(),
                descriptor
            )
            val ok = hid?.registerApp(sdp, null, null, mainExecutor, hidCallback) == true
            sendStatus(if (ok) "HID kaydı başlatıldı" else "Telefon HID modunu kabul etmedi", ok, false)
        }

        override fun onServiceDisconnected(profile: Int) {
            hid = null
            hidRegistered = false
            connectedDevice = null
            sendStatus("HID servisi kapandı", false, false)
        }
    }

    private val hidCallback = object : BluetoothHidDevice.Callback() {
        override fun onAppStatusChanged(pluggedDevice: BluetoothDevice?, registered: Boolean) {
            hidRegistered = registered
            sendStatus(if (registered) "HID hazır - TV ile eşleştir" else "HID kaydı kapandı", registered, connectedDevice != null)
        }

        override fun onConnectionStateChanged(device: BluetoothDevice?, state: Int) {
            connectedDevice = if (state == BluetoothProfile.STATE_CONNECTED) device else null
            val name = try { device?.name } catch (_: SecurityException) { null } ?: "TV"
            val text = when (state) {
                BluetoothProfile.STATE_CONNECTED -> "$name bağlı - touchpad hazır"
                BluetoothProfile.STATE_CONNECTING -> "$name bağlanıyor…"
                BluetoothProfile.STATE_DISCONNECTING -> "$name bağlantısı kapanıyor…"
                else -> "$name bağlı değil"
            }
            sendStatus(text, hidRegistered, state == BluetoothProfile.STATE_CONNECTED)
        }
    }

    private fun makeDiscoverable() {
        if (!hasPermissions()) {
            requestBtPermissions()
            return
        }
        val intent = Intent(BluetoothAdapter.ACTION_REQUEST_DISCOVERABLE).apply {
            putExtra(BluetoothAdapter.EXTRA_DISCOVERABLE_DURATION, 300)
        }
        startActivity(intent)
    }

    private fun bondedDevices(): List<Map<String, String>> {
        if (!hasPermissions()) return emptyList()
        return try {
            adapter?.bondedDevices?.map {
                mapOf("name" to (it.name ?: "Bluetooth cihazı"), "address" to it.address)
            } ?: emptyList()
        } catch (_: SecurityException) { emptyList() }
    }

    private fun connectTo(address: String): Boolean {
        if (!hidRegistered || !hasPermissions() || address.isBlank()) return false
        return try {
            val d = adapter?.getRemoteDevice(address) ?: return false
            hid?.connect(d) == true
        } catch (_: Exception) { false }
    }

    private fun sendMouse(buttons: Int, dx: Int, dy: Int, wheel: Int): Boolean {
        val d = connectedDevice ?: return false
        val report = byteArrayOf(buttons.toByte(), dx.toByte(), dy.toByte(), wheel.toByte())
        return try { hid?.sendReport(d, 0, report) == true } catch (_: Exception) { false }
    }

    private fun click(): Boolean {
        val down = sendMouse(1, 0, 0, 0)
        window.decorView.postDelayed({ sendMouse(0, 0, 0, 0) }, 55)
        return down
    }

    private fun sendStatus(text: String, ready: Boolean, connected: Boolean) {
        runOnUiThread {
            channel.invokeMethod("status", mapOf("text" to text, "hidReady" to ready, "connected" to connected))
        }
    }

    override fun onDestroy() {
        try { if (hasPermissions()) hid?.unregisterApp() } catch (_: Exception) {}
        try { hid?.let { adapter?.closeProfileProxy(BluetoothProfile.HID_DEVICE, it) } } catch (_: Exception) {}
        super.onDestroy()
    }
}
