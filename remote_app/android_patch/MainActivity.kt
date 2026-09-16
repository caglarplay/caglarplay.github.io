package com.example.remote_app

import android.content.Context
import android.hardware.ConsumerIrManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity: FlutterActivity() {
    private val channelName = "kumanda/ir"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName).setMethodCallHandler { call, result ->
            val ir = getSystemService(Context.CONSUMER_IR_SERVICE) as? ConsumerIrManager
            when (call.method) {
                "hasIr" -> result.success(ir?.hasIrEmitter() == true)
                "sendAc" -> {
                    if (ir?.hasIrEmitter() != true) { result.success(false); return@setMethodCallHandler }
                    try {
                        val power = call.argument<Boolean>("power") ?: false
                        val temp = call.argument<Int>("temp") ?: 24
                        val mode = call.argument<Int>("mode") ?: 1
                        val fan = call.argument<Int>("fan") ?: 0
                        val swing = call.argument<Boolean>("swing") ?: false
                        val pattern = auxPattern(power, temp, mode, fan, swing)
                        ir.transmit(38000, pattern)
                        result.success(true)
                    } catch (e: Exception) { result.error("IR", e.message, null) }
                }
                else -> result.notImplemented()
            }
        }
    }

    private fun auxPattern(power:Boolean, tempIn:Int, modeIn:Int, fanIn:Int, swing:Boolean):IntArray {
        val data = intArrayOf(0xC3,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x08,0x00)
        val mode = when(modeIn){0->0x00;1->0x20;2->0x40;3->0x80;else->0xC0}
        val fan = when(fanIn){0->0xA0;1->0x60;2->0x40;else->0x20}
        val temp = tempIn.coerceIn(16,30)
        if (power) data[9] = data[9] or 0x20
        data[6] = data[6] or mode
        data[1] = data[1] or ((temp - 8) shl 3)
        if (swing) data[1] = data[1] or 0x07
        data[4] = data[4] or fan
        var sum=0
        for(i in 0 until 12) sum=(sum+data[i]) and 0xFF
        data[12]=sum

        val p=ArrayList<Int>()
        p.add(8800); p.add(4580)
        for (b0 in data) {
            var b=b0
            repeat(8){
                p.add(490)
                p.add(if((b and 1)==1) 1740 else 620)
                b = b ushr 1
            }
        }
        p.add(490); p.add(20000)
        return p.toIntArray()
    }
}
