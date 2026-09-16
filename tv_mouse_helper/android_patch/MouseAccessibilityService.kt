package com.caglarplay.tv_mouse_helper

import android.accessibilityservice.AccessibilityService
import android.accessibilityservice.GestureDescription
import android.content.Context
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Paint
import android.graphics.Path
import android.graphics.PixelFormat
import android.os.Handler
import android.os.Looper
import android.view.Gravity
import android.view.View
import android.view.WindowManager
import android.view.accessibility.AccessibilityEvent
import java.io.BufferedReader
import java.io.InputStreamReader
import java.net.ServerSocket
import java.net.Socket
import kotlin.concurrent.thread
import kotlin.math.abs

class MouseAccessibilityService : AccessibilityService() {
    private val mainHandler = Handler(Looper.getMainLooper())
    private var serverSocket: ServerSocket? = null
    private var running = false
    private var windowManager: WindowManager? = null
    private var cursorView: CursorView? = null
    private var cursorParams: WindowManager.LayoutParams? = null
    private var cursorX = 640f
    private var cursorY = 360f
    private var screenWidth = 1280
    private var screenHeight = 720

    override fun onServiceConnected() {
        super.onServiceConnected()
        windowManager = getSystemService(Context.WINDOW_SERVICE) as WindowManager
        val metrics = resources.displayMetrics
        screenWidth = metrics.widthPixels
        screenHeight = metrics.heightPixels
        cursorX = screenWidth / 2f
        cursorY = screenHeight / 2f
        startServer()
    }

    override fun onAccessibilityEvent(event: AccessibilityEvent?) {}

    override fun onInterrupt() {}

    override fun onDestroy() {
        running = false
        try { serverSocket?.close() } catch (_: Exception) {}
        hideCursor()
        super.onDestroy()
    }

    private fun startServer() {
        if (running) return
        running = true
        thread(name = "tv-mouse-server", isDaemon = true) {
            try {
                serverSocket = ServerSocket(9090)
                while (running) {
                    val client = serverSocket?.accept() ?: break
                    handleClient(client)
                }
            } catch (_: Exception) {
                running = false
            }
        }
    }

    private fun handleClient(socket: Socket) {
        thread(name = "tv-mouse-client", isDaemon = true) {
            try {
                socket.tcpNoDelay = true
                val reader = BufferedReader(InputStreamReader(socket.getInputStream()))
                while (running) {
                    val line = reader.readLine() ?: break
                    val parts = line.trim().split(" ")
                    when (parts.firstOrNull()?.uppercase()) {
                        "SHOW" -> mainHandler.post { showCursor() }
                        "HIDE" -> mainHandler.post { hideCursor() }
                        "MOVE" -> if (parts.size >= 3) {
                            val dx = parts[1].toFloatOrNull() ?: 0f
                            val dy = parts[2].toFloatOrNull() ?: 0f
                            mainHandler.post { moveCursor(dx, dy) }
                        }
                        "CLICK" -> mainHandler.post { clickCursor() }
                        "SCROLL" -> if (parts.size >= 2) {
                            val amount = parts[1].toFloatOrNull() ?: 0f
                            mainHandler.post { scroll(amount) }
                        }
                    }
                }
            } catch (_: Exception) {
            } finally {
                try { socket.close() } catch (_: Exception) {}
                mainHandler.post { hideCursor() }
            }
        }
    }

    private fun showCursor() {
        if (cursorView != null) return
        val wm = windowManager ?: return
        val view = CursorView(this)
        val params = WindowManager.LayoutParams(
            54,
            54,
            WindowManager.LayoutParams.TYPE_ACCESSIBILITY_OVERLAY,
            WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE or
                WindowManager.LayoutParams.FLAG_NOT_TOUCHABLE or
                WindowManager.LayoutParams.FLAG_LAYOUT_NO_LIMITS,
            PixelFormat.TRANSLUCENT
        ).apply {
            gravity = Gravity.TOP or Gravity.START
            x = cursorX.toInt()
            y = cursorY.toInt()
        }
        cursorView = view
        cursorParams = params
        try { wm.addView(view, params) } catch (_: Exception) {}
    }

    private fun hideCursor() {
        val wm = windowManager ?: return
        val view = cursorView ?: return
        try { wm.removeView(view) } catch (_: Exception) {}
        cursorView = null
        cursorParams = null
    }

    private fun moveCursor(dx: Float, dy: Float) {
        showCursor()
        cursorX = (cursorX + dx).coerceIn(0f, (screenWidth - 20).toFloat())
        cursorY = (cursorY + dy).coerceIn(0f, (screenHeight - 20).toFloat())
        val params = cursorParams ?: return
        params.x = cursorX.toInt()
        params.y = cursorY.toInt()
        try { windowManager?.updateViewLayout(cursorView, params) } catch (_: Exception) {}
    }

    private fun clickCursor() {
        showCursor()
        val path = Path().apply { moveTo(cursorX + 6f, cursorY + 6f) }
        val gesture = GestureDescription.Builder()
            .addStroke(GestureDescription.StrokeDescription(path, 0, 70))
            .build()
        dispatchGesture(gesture, null, null)
    }

    private fun scroll(amount: Float) {
        if (abs(amount) < 1f) return
        val x = cursorX.coerceIn(80f, screenWidth - 80f)
        val startY = cursorY.coerceIn(180f, screenHeight - 180f)
        val delta = amount.coerceIn(-420f, 420f)
        val endY = (startY + delta).coerceIn(80f, screenHeight - 80f)
        val path = Path().apply {
            moveTo(x, startY)
            lineTo(x, endY)
        }
        val gesture = GestureDescription.Builder()
            .addStroke(GestureDescription.StrokeDescription(path, 0, 180))
            .build()
        dispatchGesture(gesture, null, null)
    }

    private class CursorView(context: Context) : View(context) {
        private val fill = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            color = Color.WHITE
            style = Paint.Style.FILL
            setShadowLayer(5f, 1f, 2f, Color.BLACK)
        }
        private val border = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            color = Color.rgb(64, 55, 110)
            style = Paint.Style.STROKE
            strokeWidth = 2.2f
        }

        init {
            setLayerType(LAYER_TYPE_SOFTWARE, fill)
        }

        override fun onDraw(canvas: Canvas) {
            super.onDraw(canvas)
            val p = Path().apply {
                moveTo(6f, 4f)
                lineTo(7f, 39f)
                lineTo(16f, 31f)
                lineTo(24f, 48f)
                lineTo(31f, 44f)
                lineTo(23f, 28f)
                lineTo(36f, 27f)
                close()
            }
            canvas.drawPath(p, fill)
            canvas.drawPath(p, border)
        }
    }
}
