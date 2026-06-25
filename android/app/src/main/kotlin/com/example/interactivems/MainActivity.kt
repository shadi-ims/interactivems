package com.example.interactivems

import android.os.Bundle
import android.view.WindowManager
import io.flutter.embedding.android.FlutterActivity

class MainActivity : FlutterActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        // Keep the screen on and stop the Android TV screensaver/daydream
        // for as long as the app is in the foreground. No permission needed;
        // the flag is dropped automatically when the activity is destroyed.
        window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
    }
}
