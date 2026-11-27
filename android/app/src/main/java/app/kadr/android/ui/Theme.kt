package app.kadr.android.ui

import androidx.compose.material3.*
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.ui.graphics.Color

@Composable fun KadrTheme(accent: String, content: @Composable () -> Unit) {
    val tones = when (accent) {
        "mint" -> listOf(0xFFA3D9BC, 0xFF073826, 0xFF24513C, 0xFFBFF5D6, 0xFF3B4B40, 0xFFD3E8D7)
        "violet" -> listOf(0xFFD0BCFF, 0xFF381E72, 0xFF4F378B, 0xFFEADDFF, 0xFF4A4458, 0xFFE8DEF8)
        "blue" -> listOf(0xFFAAC7FF, 0xFF0A305F, 0xFF284777, 0xFFD6E3FF, 0xFF3F4759, 0xFFDFE2F9)
        "rose" -> listOf(0xFFF5B4D2, 0xFF4C1F36, 0xFF66354D, 0xFFFFD8E8, 0xFF55414A, 0xFFF3DDE6)
        else -> listOf(0xFFFFB59A, 0xFF55200A, 0xFF73351D, 0xFFFFDBCE, 0xFF5C4034, 0xFFFFDBCE)
    }.map { Color(it) }
    MaterialExpressiveTheme(
        colorScheme = darkColorScheme(primary = tones[0], onPrimary = tones[1], primaryContainer = tones[2], onPrimaryContainer = tones[3], secondary = tones[0], onSecondary = tones[1], secondaryContainer = tones[4], onSecondaryContainer = tones[5], background = Color(0xFF101115), onBackground = Color(0xFFF1EFF4), surface = Color(0xFF141419), onSurface = Color(0xFFF1EFF4), onSurfaceVariant = Color(0xFFCCC7D1), surfaceContainerLowest = Color(0xFF0F1014), surfaceContainerLow = Color(0xFF1A1B20), surfaceContainer = Color(0xFF222329), surfaceContainerHigh = Color(0xFF2C2D34)),
        motionScheme = MotionScheme.expressive(),
        content = { CompositionLocalProvider(LocalContentColor provides MaterialTheme.colorScheme.onSurface, content = content) }
    )
}
