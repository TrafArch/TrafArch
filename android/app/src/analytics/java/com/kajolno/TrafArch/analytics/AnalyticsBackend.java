package com.kajolno.TrafArch.analytics;

import android.content.Context;
import com.google.firebase.FirebaseApp;
import com.google.firebase.analytics.FirebaseAnalytics;

public final class AnalyticsBackend {
    public static boolean available(Context context) {
        return FirebaseApp.getApps(context).stream()
                .anyMatch(app -> FirebaseApp.DEFAULT_APP_NAME.equals(app.getName()));
    }

    public static void setEnabled(Context context, boolean enabled) {
        FirebaseAnalytics.getInstance(context).setAnalyticsCollectionEnabled(enabled);
    }
}
