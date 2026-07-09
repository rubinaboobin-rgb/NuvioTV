package com.nuvio.tv.core.auth

import android.util.Log
import com.nuvio.tv.core.sync.androidtv.AndroidTvChannelManager
import javax.inject.Inject
import javax.inject.Singleton
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext

private const val ACCOUNT_RESET_TAG = "AccountDataReset"

@Singleton
class AccountLocalDataResetService @Inject constructor(
    private val androidTvChannelManager: AndroidTvChannelManager
) {
    suspend fun clearAfterSignOut() = withContext(Dispatchers.IO) {
        runCatching { androidTvChannelManager.clearAll() }
            .onFailure { Log.w(ACCOUNT_RESET_TAG, "Failed to clear Android TV channel data", it) }
    }
}
