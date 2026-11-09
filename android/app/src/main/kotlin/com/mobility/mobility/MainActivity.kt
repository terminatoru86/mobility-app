package com.mobility.mobility

import android.os.Build
import android.os.Bundle
import io.flutter.embedding.android.FlutterActivity

class MainActivity : FlutterActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        // Android 12+: its own start screen (our big "m") fades out softly over our first frame,
        // which has the same logo in the same place, so nothing jumps.
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            splashScreen.setOnExitAnimationListener { view ->
                view.animate().alpha(0f).setDuration(350L).withEndAction { view.remove() }.start()
            }
        }
    }
}
