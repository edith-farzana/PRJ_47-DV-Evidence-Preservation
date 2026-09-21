package com.pocketcalc.calculator

import android.os.Bundle
import android.view.WindowManager
import io.flutter.embedding.android.FlutterActivity

class MainActivity : FlutterActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        // Before super.onCreate, so no frame is ever drawn without it.
        // Blocks screenshots and screen recording, and blanks the
        // recents-screen thumbnail, which would otherwise show whatever
        // was on screen (the vault, not the calculator) to anyone who
        // opens the app switcher.
        window.setFlags(
            WindowManager.LayoutParams.FLAG_SECURE,
            WindowManager.LayoutParams.FLAG_SECURE,
        )
        super.onCreate(savedInstanceState)
    }
}
