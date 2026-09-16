package com.example.remote_app

import android.content.Context
import android.hardware.ConsumerIrManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity: FlutterActivity() {
    private val channelName = "kumanda/ir"
    private var rc5Toggle = false

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName).setMethodCallHandler { call, result ->
            val ir = getSystemService(Context.CONSUMER_IR_SERVICE) as? ConsumerIrManager
            when (call.method) {
                "hasIr" -> result.success(ir?.hasIrEmitter() == true)
                "sendTvPower" -> {
                    if (ir?.hasIrEmitter() != true) {
                        result.success(false)
                        return@setMethodCallHandler
                    }
                    try {
                        // Vestel RC5118 family: RC5, TV1 address 1, power command 0x0C.
                        val pattern = rc5Pattern(address = 1, command = 0x0C, toggle = rc5Toggle)
                        ir.transmit(36000, pattern)
                        rc5Toggle = !rc5Toggle
                        result.success(true)
                    } catch (e: Exception) {
                        result.error("IR_TV", e.message, null)
                    }
                }
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

    private fun rc5Pattern(address: Int, command: Int, toggle: Boolean): IntArray {
        // RC5: 36 kHz, Manchester coding, 889 us per half bit.
        // Logic 1 = space,mark. Logic 0 = mark,space.
        val bits = ArrayList<Int>(14)
        bits.add(1) // start
        bits.add(if (command < 64) 1 else 0) // field bit
        bits.add(if (toggle) 1 else 0)
        for (i in 4 downTo 0) bits.add((address shr i) and 1)
        val cmd = command and 0x3F
        for (i in 5 downTo 0) bits.add((cmd shr i) and 1)

        val halves = ArrayList<Boolean>(bits.size * 2)
        for (bit in bits) {
            if (bit == 1) {
                halves.add(false) // space
                halves.add(true)  // mark
            } else {
                halves.add(true)  // mark
                halves.add(false) // space
            }
        }

        // ConsumerIrManager pattern must begin with a mark. Leading idle space is implicit.
        while (halves.isNotEmpty() && !halves[0]) halves.removeAt(0)
        if (halves.isEmpty()) return intArrayOf(889, 889)

        val out = ArrayList<Int>()
        var state = halves[0]
        var count = 1
        for (i in 1 until halves.size) {
            if (halves[i] == state) {
                count++
            } else {
                out.add(count * 889)
                state = halves[i]
                count = 1
            }
        }
        out.add(count * 889)
        if (out.size % 2 == 1) out.add(889) // finish with a space
        return out.toIntArray()
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
