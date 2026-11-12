package com.review.compose
import android.content.Context
import androidx.test.core.app.ApplicationProvider
import kotlinx.coroutines.runBlocking
import kotlinx.coroutines.CancellationException
import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config
@RunWith(RobolectricTestRunner::class)
@Config(sdk=[35],manifest=Config.NONE,shadows=[ReplacingAtomicFileShadow::class])
class BackupLoginRestoreTest {
    private val context=ApplicationProvider.getApplicationContext<Context>()

    private val key=javax.crypto.KeyGenerator.getInstance("AES").apply{init(256)}.generateKey()
    private val session=SessionStore(context,keyProvider={key})
    private val secrets=SessionStore(context,"webdav",keyProvider={key})
    private val prefs=context.getSharedPreferences("preferences",0)
    private val backup=BackupStore(context,com.review.weiboauth.WeiboAuthManager(context),session,secrets)
    private fun data(full:Boolean=true)=JSONObject().put("app","Review").put("version","2.0").put("backup_mode",if(full)"full"else"safe")
        .put("preferences",JSONObject().put("theme_mode",2).apply{if(full){put("user_uid","2");put("weibo_full_cookie","SUB=synthetic-two");put("webdav_password","")}})
    private fun seed(){session.save("SUB=synthetic-one");prefs.edit().putString("uid","1").putInt("theme",0).commit()}
    private fun uid()=prefs.getString("uid","")
    private fun theme()=prefs.getInt("theme",0)

    @Test fun verifiedLoginCommitsAndSurvivesARead()=runBlocking{seed();val result=backup.restore(data()){cookie,uid->VerifiedWebSession(cookie,false,uid)};assertTrue(result.contains("通过验证"));assertEquals("2",uid());assertEquals(2,theme())}
    @Test fun validationFailureRestoresOnlyNonLoginData()=runBlocking{seed();val result=backup.restore(data()){_,_->error("synthetic validation failure")};assertTrue(result.contains("账号登录未恢复"));assertEquals("1",uid());assertEquals(2,theme())}
    @Test fun safeRestoreKeepsCurrentLogin()=runBlocking{seed();backup.restore(data(false)){_,_->error("Safe restore must not verify")};assertEquals("1",uid());assertEquals(2,theme())}
    @Test fun newLoginDuringValidationOwnsTheState()=runBlocking{
        seed();try{backup.restore(data()){_,_->session.save("SUB=synthetic-three");prefs.edit().putString("uid","3").commit();VerifiedWebSession("SUB=synthetic-two",false,"2")};fail("Stale restore must stop")}catch(_:IllegalStateException){}
        assertEquals("3",uid());assertEquals(0,theme())
    }
    @Test fun cancellationDoesNotLookLikePartialSuccess()=runBlocking{
        seed();try{backup.restore(data()){_,_->throw CancellationException()};fail("Cancellation must propagate")}catch(_:CancellationException){}
        assertEquals("1",uid());assertEquals(0,theme())
    }
}
