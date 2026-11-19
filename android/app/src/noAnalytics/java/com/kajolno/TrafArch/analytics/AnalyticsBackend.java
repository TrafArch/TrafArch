package com.kajolno.TrafArch.analytics;

import android.content.Context;

public final class AnalyticsBackend {
    public static boolean available(Context context) {
        return false;
    }

    public static void setEnabled(Context context, boolean enabled) {
        throw new IllegalStateException("Analytics unavailable");
    }
}
