package com.example.secure_evidence_app

import android.os.Bundle
import android.view.WindowManager
import io.flutter.embedding.android.FlutterActivity

class MainActivity : FlutterActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        // Before super.onCreate, so not even the first frame can be
        // captured. Blocks screenshots, screen recording, casting, and the
        // thumbnail in the recent-apps list, which would otherwise show
        // the vault to anyone who opens recents.
        window.setFlags(
            WindowManager.LayoutParams.FLAG_SECURE,
            WindowManager.LayoutParams.FLAG_SECURE,
        )
        super.onCreate(savedInstanceState)
    }
}
