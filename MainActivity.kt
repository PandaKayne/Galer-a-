package com.example.galeria_cristal  // cámbialo si tu paquete es otro

import android.annotation.TargetApi
import android.app.WallpaperManager
import android.content.ContentResolver
import android.content.ContentUris
import android.content.Intent
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.Canvas
import android.media.ThumbnailUtils
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.os.Environment
import android.provider.MediaStore
import android.provider.Settings
import android.util.Size
import android.view.WindowManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.ByteArrayOutputStream
import java.io.File

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(engine: FlutterEngine) {
        super.configureFlutterEngine(engine)
        MethodChannel(engine.dartExecutor.binaryMessenger, "wallpaper").setMethodCallHandler { call, result ->
            when (call.method) {
                "share" -> compartir(call.argument<String>("id"), call.argument<Boolean>("video") ?: false, result)
                "necesita" -> result.success(necesitaPermiso())
                "pedir" -> pedirPermiso(result)
                "papelera" -> papelera(result)
                "accion" -> accion(call.argument<List<*>>("ids"), call.argument<List<*>>("videos"), call.argument<Boolean>("borrar") ?: false, result)
                "pantalla" -> {
                    pantalla(call.argument<Boolean>("on") ?: false)
                    result.success(true)
                }
                else -> fondo(result)
            }
        }
    }

    // ── Mantener la pantalla encendida mientras se ve un vídeo ──
    private fun pantalla(on: Boolean) {
        if (on) window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
        else window.clearFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
    }

    // ── Compartir ──
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

    // ── Fondo de pantalla ──
    // Desde Android 13 el permiso de galería no basta para leer el fondo: hace falta "acceso a todos los archivos".
    // Los fondos animados solo entregan una vista previa y no necesitan ese permiso.
    private fun necesitaPermiso(): Boolean {
        if (Build.VERSION.SDK_INT < 33) return false
        val animado = WallpaperManager.getInstance(this).wallpaperInfo != null
        return !animado && !Environment.isExternalStorageManager()
    }

    private fun pedirPermiso(result: MethodChannel.Result) {
        try {
            if (Build.VERSION.SDK_INT >= 30) {
                startActivity(Intent(Settings.ACTION_MANAGE_APP_ALL_FILES_ACCESS_PERMISSION, Uri.parse("package:$packageName")))
            }
            result.success(true)
        } catch (e: Exception) {
            result.success(false)
        }
    }

    private fun fondo(result: MethodChannel.Result) {
        try {
            if (necesitaPermiso()) { result.success(null); return }
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
            result.success(null)
        }
    }

    // ── Papelera del sistema (Android 11 o superior) ──
    @TargetApi(30)
    private fun papelera(result: MethodChannel.Result) {
        if (Build.VERSION.SDK_INT < 30) { result.success(ArrayList<Map<String, Any?>>()); return }
        Thread {
            val lista = ArrayList<Map<String, Any?>>()
            try {
                val args = Bundle().apply {
                    putInt(MediaStore.QUERY_ARG_MATCH_TRASHED, MediaStore.MATCH_ONLY)
                    putString(ContentResolver.QUERY_ARG_SQL_SELECTION, "${MediaStore.Files.FileColumns.MEDIA_TYPE} IN (1,3)")
                }
                val cols = arrayOf(
                    MediaStore.Files.FileColumns._ID,
                    MediaStore.Files.FileColumns.MEDIA_TYPE,
                    MediaStore.MediaColumns.DISPLAY_NAME,
                    MediaStore.MediaColumns.DATE_EXPIRES,
                    MediaStore.MediaColumns.DATA
                )
                contentResolver.query(MediaStore.Files.getContentUri("external"), cols, args, null)?.use { c ->
                    while (c.moveToNext() && lista.size < 300) {
                        val id = c.getLong(0)
                        val video = c.getInt(1) == MediaStore.Files.FileColumns.MEDIA_TYPE_VIDEO
                        val nombre = c.getString(2) ?: ""
                        val expira = c.getLong(3)
                        val ruta: String? = c.getString(4)
                        var thumb: ByteArray? = null
                        var bmp: Bitmap? = null
                        try {
                            bmp = contentResolver.loadThumbnail(uriDe(id, video), Size(256, 256), null)
                        } catch (e: Exception) {
                        }
                        if (bmp == null && ruta != null) {
                            try {
                                bmp = if (video) {
                                    ThumbnailUtils.createVideoThumbnail(File(ruta), Size(256, 256), null)
                                } else {
                                    BitmapFactory.decodeFile(ruta, BitmapFactory.Options().apply { inSampleSize = 4 })
                                }
                            } catch (e: Exception) {
                            }
                        }
                        if (bmp != null) {
                            val out = ByteArrayOutputStream()
                            bmp.compress(Bitmap.CompressFormat.JPEG, 70, out)
                            thumb = out.toByteArray()
                        }
                        lista.add(mapOf("id" to id, "video" to video, "nombre" to nombre, "expira" to expira, "thumb" to thumb))
                    }
                }
            } catch (e: Exception) {
            }
            runOnUiThread { result.success(lista) }
        }.start()
    }

    private fun uriDe(id: Long, video: Boolean): Uri {
        val base = if (video) MediaStore.Video.Media.EXTERNAL_CONTENT_URI else MediaStore.Images.Media.EXTERNAL_CONTENT_URI
        return ContentUris.withAppendedId(base, id)
    }

    // Restaurar (borrar=false) o eliminar definitivamente (borrar=true). Android pide confirmación.
    @TargetApi(30)
    private fun accion(ids: List<*>?, videos: List<*>?, borrar: Boolean, result: MethodChannel.Result) {
        try {
            if (Build.VERSION.SDK_INT >= 30 && ids != null && videos != null && ids.isNotEmpty()) {
                val uris = ids.indices.map { uriDe((ids[it] as Number).toLong(), videos[it] == true) }
                val pi = if (borrar) MediaStore.createDeleteRequest(contentResolver, uris)
                else MediaStore.createTrashRequest(contentResolver, uris, false)
                startIntentSenderForResult(pi.intentSender, 4242, null, 0, 0, 0)
            }
            result.success(true)
        } catch (e: Exception) {
            result.success(false)
        }
    }
}
