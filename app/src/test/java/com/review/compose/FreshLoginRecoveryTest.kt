package com.review.compose
import androidx.lifecycle.viewModelScope
import kotlinx.coroutines.test.setMain
import kotlinx.coroutines.test.resetMain
import android.content.Context
import androidx.test.core.app.ApplicationProvider
import kotlinx.coroutines.*
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config
import java.io.File
import javax.crypto.KeyGenerator
import javax.crypto.SecretKey

@RunWith(RobolectricTestRunner::class)
@Config(sdk=[35],manifest=Config.NONE,shadows=[ReplacingAtomicFileShadow::class])
@OptIn(kotlinx.coroutines.ExperimentalCoroutinesApi::class)
class FreshLoginRecoveryTest {
    private val context=ApplicationProvider.getApplicationContext<Context>()
    private fun newKey()=KeyGenerator.getInstance("AES").apply{init(256)}.generateKey()
    private var deviceKey:SecretKey?=newKey()
    private val keys:(Boolean)->SecretKey={create->deviceKey?:if(create)newKey().also{deviceKey=it}else throw SecretReadFailure(SecretFailureKind.MISSING_KEY)}
    private fun archived(bytes:ByteArray)=File(context.noBackupFilesDir,"account-recovery").listFiles().orEmpty().any{it.readBytes().contentEquals(bytes)}

    private val session=SessionStore(context,keyProvider=keys)
    private val file get()=File(context.applicationInfo.dataDir,"shared_prefs/session.xml")
    private val prefs=context.getSharedPreferences("preferences",0)
    private suspend fun withModel(block:suspend(ReviewModel)->Unit) {
        Dispatchers.setMain(kotlinx.coroutines.test.StandardTestDispatcher())
        val model=ReviewModel(context as android.app.Application)
        ReviewModel::class.java.getDeclaredField("session").apply{isAccessible=true}.set(model,session)
        try{block(model)}finally{model.viewModelScope.cancel();Dispatchers.resetMain()}
    }
    private fun seed():ByteArray{session.save("SUB=synthetic-old");prefs.edit().putString("uid","1").commit();return file.readBytes()}
    @Test fun freshWebLoginAfterTransferPersistsAndArchives()=runBlocking {
        val old=seed();deviceKey=null
        withModel{model->
            assertTrue(model.commitAccount("SUB=synthetic-new","2",false,false,freshLogin=true))
            assertEquals("SUB=synthetic-new",session.load());assertEquals("2",prefs.getString("uid",""));assertTrue(archived(old))
        }
    }
    @Test fun backgroundRefreshCannotReplaceUnreadableLogin()=runBlocking {
        val old=seed();deviceKey=null
        withModel{model->try{model.commitAccount("SUB=synthetic-new","1",false,false,expectedCookie="SUB=synthetic-old");fail()}catch(_:SecretReadFailure){}}
        assertArrayEquals(old,file.readBytes());assertNull(deviceKey)
    }
    @Test fun archiveFailureKeepsBothIdentityAndCiphertext()=runBlocking {
        val old=seed();deviceKey=null;File(context.noBackupFilesDir,"account-recovery").writeText("synthetic obstruction")
        withModel{model->try{model.commitAccount("SUB=synthetic-new","2",false,false,freshLogin=true);fail()}catch(_:IllegalStateException){}}
        assertArrayEquals(old,file.readBytes());assertEquals("1",prefs.getString("uid",""));assertNull(deviceKey)
    }
    @Test fun nativeCommitFailureRollsBackRawUnreadableWebSession()=runBlocking {
        val old=seed();deviceKey=null
        withModel{model->try{model.commitAccount("","2",false,true,freshLogin=true);fail()}catch(_:IllegalStateException){}}
        assertArrayEquals(old,file.readBytes());assertEquals("1",prefs.getString("uid",""));assertNull(deviceKey)
    }
    private suspend fun withNativeKey(block:suspend()->Unit) {
        val provider=object:java.security.Provider("LoginRecoveryTests", 1.0, "Synthetic test keys only"){}
        provider.put("KeyStore.AndroidKeyStore", LoginRecoveryKeyStore::class.java.name)
        java.security.Security.insertProviderAt(provider,1)
        try{block()}finally{java.security.Security.removeProvider(provider.name);LoginRecoveryKeyStore.key=null}
    }
    private fun oldNativeCiphertext():ByteArray {
        val cipher=javax.crypto.Cipher.getInstance("AES/GCM/NoPadding").apply{init(javax.crypto.Cipher.ENCRYPT_MODE,newKey())}
        val prefs=context.getSharedPreferences("weibo_android_session_ciphertext",0)
        prefs.edit().putString("iv",android.util.Base64.encodeToString(cipher.iv,2))
            .putString("data",android.util.Base64.encodeToString(cipher.doFinal("synthetic old session".toByteArray()),2)).commit()
        return File(context.applicationInfo.dataDir,"shared_prefs/weibo_android_session_ciphertext.xml").readBytes()
    }
    @Test fun webLoginCanReplaceMissingNativeKeyWithoutDecryptingOldAccount()=runBlocking {
        withNativeKey {
            val web=seed();val native=oldNativeCiphertext();deviceKey=null;LoginRecoveryKeyStore.key=null
            withModel{model->assertTrue(model.commitAccount("SUB=synthetic-new","1",false,false,freshLogin=true))}
            assertEquals("SUB=synthetic-new",session.load());assertTrue(archived(web));assertTrue(archived(native))
            assertFalse(context.getSharedPreferences("weibo_android_session_ciphertext",0).contains("data"))
        }
    }
    @Test fun nativeLoginArchivesBothOldStoresAndClearsWebCookie()=runBlocking {
        withNativeKey {
            val web=seed();val native=oldNativeCiphertext();deviceKey=null;LoginRecoveryKeyStore.key=newKey()
            withModel{model->
                val klass=Class.forName("com.review.weiboauth.WeiboSession")
                val pending=klass.getDeclaredMethod("fromJson",org.json.JSONObject::class.java).apply{isAccessible=true}
                    .invoke(null,org.json.JSONObject().put("uid","2").put("gsid","synthetic-new").put("cookie","SUB=synthetic-new"))
                model.nativeAuth.javaClass.getDeclaredField("pendingSession").apply{isAccessible=true}.set(model.nativeAuth,pending)
                assertTrue(model.commitAccount("","2",false,true,freshLogin=true))
                assertTrue(model.nativeAuth.hasNativeSession());assertNull(model.nativeAuth.sessionReadError)
                assertEquals("2",org.json.JSONObject(model.nativeAuth.exportBackupSession("2")!!).getString("uid"))
            }
            assertEquals("",session.load());assertTrue(archived(web));assertTrue(archived(native))
        }
    }

}
