package com.albonik.bgremover

import android.content.Intent
import android.net.Uri
import android.os.Bundle
import java.io.File
import java.io.FileOutputStream
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {

    // ---- Share / "Open with" image receiving ----
    private val SHARE_CHANNEL = "com.albonik.bgremover/share"
    private var shareChannel: MethodChannel? = null
    private val pendingSharedImages = mutableListOf<String>()

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        shareChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, SHARE_CHANNEL).also { ch ->
            ch.setMethodCallHandler { call, result ->
                if (call.method == "getSharedImages") {
                    val list = synchronized(pendingSharedImages) {
                        val copy = pendingSharedImages.toList()
                        pendingSharedImages.clear()
                        copy
                    }
                    result.success(list)
                } else result.notImplemented()
            }
        }
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        if (savedInstanceState == null) handleShareIntent(intent)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        handleShareIntent(intent)
    }

    private fun handleShareIntent(intent: Intent?) {
        if (intent == null) return
        val uris = mutableListOf<Uri>()
        when (intent.action) {
            Intent.ACTION_SEND -> {
                @Suppress("DEPRECATION")
                (intent.getParcelableExtra<Uri>(Intent.EXTRA_STREAM))?.let { uris.add(it) }
            }
            Intent.ACTION_SEND_MULTIPLE -> {
                @Suppress("DEPRECATION")
                intent.getParcelableArrayListExtra<Uri>(Intent.EXTRA_STREAM)?.let { uris.addAll(it) }
            }
            Intent.ACTION_VIEW -> intent.data?.let { uris.add(it) }
            else -> return
        }
        if (uris.isEmpty()) return

        // Copy into app cache on a background thread (content:// URIs are only
        // readable while we hold the grant), then tell Dart to pick them up.
        Thread {
            val copied = mutableListOf<String>()
            uris.forEachIndexed { i, uri ->
                try {
                    val out = File(cacheDir, "shared_${System.currentTimeMillis()}_$i.jpg")
                    contentResolver.openInputStream(uri)?.use { input ->
                        FileOutputStream(out).use { input.copyTo(it) }
                    }
                    if (out.length() > 0) copied.add(out.absolutePath)
                } catch (e: Exception) {
                    android.util.Log.w("ShareIntent", "Could not read shared image", e)
                }
            }
            runOnUiThread {
                if (copied.isNotEmpty()) {
                    synchronized(pendingSharedImages) { pendingSharedImages.addAll(copied) }
                    shareChannel?.invokeMethod("onSharedImages", null)
                }
            }
        }.start()
        // Don't re-process the same intent later
        intent.action = null
    }
}
