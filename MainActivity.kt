package com.example.galeria_cristal  // cámbialo si tu paquete es otro

import android.app.WallpaperManager
import android.graphics.Bitmap
import android.graphics.Canvas
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.ByteArrayOutputStream

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(engine: FlutterEngine) {
        super.configureFlutterEngine(engine)
        MethodChannel(engine.dartExecutor.binaryMessenger, "wallpaper").setMethodCallHandler { _, result ->
            try {
                val wm = WallpaperManager.getInstance(this)
                val info = wm.wallpaperInfo // no es null si el fondo es animado
                val d = if (info != null) info.loadThumbnail(packageManager) else wm.drawable
                if (d == null) { result.success(null); return@setMethodCallHandler }
                val w = d.intrinsicWidth.coerceAtLeast(1)
                val h = d.intrinsicHeight.coerceAtLeast(1)
                var bmp = Bitmap.createBitmap(w, h, Bitmap.Config.ARGB_8888)
                val cv = Canvas(bmp)
                d.setBounds(0, 0, w, h)
                d.draw(cv)
                if (w > 1080) bmp = Bitmap.createScaledBitmap(bmp, 1080, h * 1080 / w, true)
                val out = ByteArrayOutputStream()
                bmp.compress(Bitmap.CompressFormat.JPEG, 80, out)
                result.success(out.toByteArray())
            } catch (e: Exception) {
                result.success(null) // sin permiso o no disponible: la app usa su degradado
            }
        }
    }
}
