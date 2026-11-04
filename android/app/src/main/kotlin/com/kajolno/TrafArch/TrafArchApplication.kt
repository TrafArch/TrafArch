package com.kajolno.TrafArch

import android.app.Application
import com.kajolno.TrafArch.memory.HonorMemoryCoordinator

class TrafArchApplication : Application() {
    internal lateinit var memory: HonorMemoryCoordinator
        private set

    override fun onCreate() {
        super.onCreate()
        memory = HonorMemoryCoordinator(this)
    }
}
