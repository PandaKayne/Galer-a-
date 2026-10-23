package com.example.galeria_cristal  // cámbialo si tu paquete es otro

import android.app.WallpaperManager
import android.content.ContentUris
import android.content.Intent
import android.graphics.Bitmap
import android.graphics.Canvas
import android.provider.MediaStore
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.ByteArrayOutputStream

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(engine: FlutterEngine) {
        super.configureFlutterEngine(engine)
        MethodChannel(engine.dartExecutor.binaryMessenger, "wallpaper").setMethodCallHandler { call, result ->
            when (call.method) {
                "share" -> compartir(call.argument<String>("id"), call.argument<Boolean>("video") ?: false, result)
                else -> fondo(result)
            }
        }
    }

    private fun compartir(id: String?, video: Boolean, result: MethodChannel.Result) {
        try {
            val base = if (video) MediaStore.Video.Media.EXTERNAL_CONTENT_URI else MediaStore.Images.Media.EXTERNAL_CONTENT_URI
            val uri = ContentUris.withAppendedId(base, id!!.toLong())
            val i = Intent(Intent.ACTION_SEND).apply {
                type = if (video) "video/*" else "image/*"
                putExtra(Intent.EXTRA_STREAM, uri)
                addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
            }
            startActivity(Intent.createChooser(i, null))
            result.success(true)
        } catch (e: Exception) {
            result.success(false)
        }
    }

    private fun fondo(result: MethodChannel.Result) {
        try {
            val wm = WallpaperManager.getInstance(this)
            val info = wm.wallpaperInfo // no es null si el fondo es animado
            val d = if (info != null) info.loadThumbnail(packageManager) else wm.drawable
            if (d == null) { result.success(null); return }
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
