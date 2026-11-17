package com.kajolno.TrafArch.platform

import android.content.Context
import android.graphics.Color
import android.view.View
import com.hihonor.uikit.hnmagicsystem.compatibility.TransparencyCompat
import com.hihonor.uikit.transparency.api.HnGlassEffect
import com.hihonor.uikit.transparency.api.HnSceneType
import com.hihonor.uikit.transparency.api.HnVisualEffectLayout
import com.hihonor.uikit.transparency.api.HnWidgetSize
import io.flutter.plugin.common.StandardMessageCodec
import io.flutter.plugin.platform.PlatformView
import io.flutter.plugin.platform.PlatformViewFactory

/**
 * Platform view that paints the MagicOS glass material behind the 2.x bottom
 * bars. Flutter keeps layout, labels and gestures; this view only supplies the
 * native `HnVisualEffectLayout` backdrop, which a Flutter-painted widget
 * cannot host on its own.
 *
 * Creation arguments: `radius` (dp, double). The view never reads user data,
 * draws no children and takes no input.
 */
internal class TranslucentGlassViewFactory :
    PlatformViewFactory(StandardMessageCodec.INSTANCE) {
    override fun create(context: Context, id: Int, args: Any?): PlatformView {
        val radiusDp = ((args as? Map<*, *>)?.get("radius") as? Number)?.toFloat() ?: 0f
        return TranslucentGlassView(context, radiusDp)
    }
}

private class TranslucentGlassView(context: Context, radiusDp: Float) : PlatformView {
    private val view: View = createGlass(context, radiusDp)

    override fun getView(): View = view

    override fun dispose() = Unit

    private fun createGlass(context: Context, radiusDp: Float): View {
        // Only draw the material where Honor reports support; everywhere else
        // the transparent fallback lets the Flutter tint carry the bar alone.
        val supported = runCatching {
            TransparencyCompat.isSupportTransparencyView()
        }.getOrDefault(false)
        if (!supported) return View(context)
        return runCatching {
            val density = context.resources.displayMetrics.density
            val radiusPx = (radiusDp.coerceAtLeast(0f) * density).toInt()
            HnVisualEffectLayout(context).apply {
                setBackgroundColor(Color.TRANSPARENT)
                // SMALL + GENERAL is Honor's guidance for navigation bars:
                // light blur, moderate tint, no interactive deformation.
                setVisualEffect(
                    HnGlassEffect().apply {
                        setWidgetSize(HnWidgetSize.SMALL)
                        setSceneType(HnSceneType.GENERAL)
                        setInteractive(false)
                    },
                )
                if (radiusPx > 0) {
                    setRadius(radiusPx)
                    setCornerRadiusWithClipChildren(radiusPx.toFloat(), true)
                }
            }
        }.getOrElse { View(context) }
    }
}