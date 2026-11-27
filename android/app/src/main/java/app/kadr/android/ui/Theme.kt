package app.kadr.android.ui

import androidx.compose.material3.*
import androidx.compose.runtime.Composable
import androidx.compose.ui.graphics.Color

@Composable fun KadrTheme(accent: String, content: @Composable () -> Unit) {
    val primary = when (accent) { "mint" -> Color(0xFFA3D9BC); "violet" -> Color(0xFFD0BCFF); "blue" -> Color(0xFFAAC7FF); "rose" -> Color(0xFFF5B4D2); else -> Color(0xFFFFB59A) }
    MaterialExpressiveTheme(
        colorScheme = darkColorScheme(primary = primary, onPrimary = Color(0xFF422B22), primaryContainer = Color(0xFF614536), onPrimaryContainer = Color(0xFFFFDBC9), secondary = Color(0xFFD8C2B5), tertiary = Color(0xFFBDCC9E), background = Color(0xFF101115), surface = Color(0xFF141419), surfaceContainer = Color(0xFF222329), surfaceContainerHigh = Color(0xFF2C2D34)),
        motionScheme = MotionScheme.expressive(),
        content = content
    )
}
