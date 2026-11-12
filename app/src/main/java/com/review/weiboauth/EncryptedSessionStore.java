package com.review.weiboauth;

import android.content.Context;
import android.content.SharedPreferences;
import android.security.keystore.KeyGenParameterSpec;
import android.security.keystore.KeyProperties;
import android.util.Base64;

import org.json.JSONObject;

import java.nio.charset.StandardCharsets;
import java.security.KeyStore;
import javax.crypto.Cipher;
import javax.crypto.KeyGenerator;
import javax.crypto.SecretKey;
import javax.crypto.spec.GCMParameterSpec;

final class EncryptedSessionStore {
    private static final String ALIAS = "review-weibo-session-v1";
    private static final String PREFS = "weibo_android_session_ciphertext";
    private static final String IV = "iv";
    private static final String DATA = "data";
    private final Context context;

    EncryptedSessionStore(Context context) {
        this.context = context.getApplicationContext();
    }

    void save(WeiboSession session) throws Exception { save(session, false); }

    void save(WeiboSession session, boolean recoverUnreadable) throws Exception {
        preserveBeforeReplacement(recoverUnreadable);
        Cipher cipher = Cipher.getInstance("AES/GCM/NoPadding");
        cipher.init(Cipher.ENCRYPT_MODE, getKey(true));
        byte[] plaintext = session.toJson().toString().getBytes(StandardCharsets.UTF_8);
        byte[] encrypted;
        try {
            encrypted = cipher.doFinal(plaintext);
        } finally {
            java.util.Arrays.fill(plaintext, (byte) 0);
        }
        String original = encryptedSnapshot();
        boolean saved = preferences().edit()
                .putString(IV, Base64.encodeToString(cipher.getIV(), Base64.NO_WRAP))
                .putString(DATA, Base64.encodeToString(encrypted, Base64.NO_WRAP))
                .commit();
        if (!saved) {
            java.io.IOException failure = new java.io.IOException("原生加密资料写入失败");
            try { restoreEncryptedSnapshot(original); } catch (Exception rollback) { failure.addSuppressed(rollback); }
            throw failure;
        }
    }

    WeiboSession load() throws com.review.compose.SecretReadFailure {
        try {
            SharedPreferences prefs = preferences();
            String ivValue = prefs.getString(IV, null);
            String dataValue = prefs.getString(DATA, null);
            if (ivValue == null && dataValue == null) return null;
            if (ivValue == null || dataValue == null || Base64.decode(ivValue, Base64.NO_WRAP).length != 12
                    || Base64.decode(dataValue, Base64.NO_WRAP).length < 16 || dataValue.length() > 16 * 1024 * 1024) throw new IllegalArgumentException();

            Cipher cipher = Cipher.getInstance("AES/GCM/NoPadding");
            cipher.init(Cipher.DECRYPT_MODE, getKey(false), new GCMParameterSpec(128,
                    Base64.decode(ivValue, Base64.NO_WRAP)));
            byte[] plaintext = cipher.doFinal(Base64.decode(dataValue, Base64.NO_WRAP));
            try {
                WeiboSession session = WeiboSession.fromJson(new JSONObject(new String(plaintext, StandardCharsets.UTF_8)));
                if (!session.hasRequiredFields()) throw new IllegalArgumentException();
                return session;
            } finally {
                java.util.Arrays.fill(plaintext, (byte) 0);
            }
        } catch (com.review.compose.SecretReadFailure failure) {
            throw failure;
        } catch (javax.crypto.AEADBadTagException failure) {
            throw new com.review.compose.SecretReadFailure(com.review.compose.SecretFailureKind.AUTHENTICATION);
        } catch (java.security.InvalidKeyException | java.security.UnrecoverableKeyException failure) {
            throw new com.review.compose.SecretReadFailure(com.review.compose.SecretFailureKind.UNUSABLE_KEY);
        } catch (IllegalArgumentException | org.json.JSONException failure) {
            throw new com.review.compose.SecretReadFailure(com.review.compose.SecretFailureKind.FORMAT);
        } catch (Exception failure) {
            throw new com.review.compose.SecretReadFailure(com.review.compose.SecretFailureKind.IO);
        }
    }

    void preserveBeforeReplacement(boolean allowed) throws Exception {
        try { load(); }
        catch (com.review.compose.SecretReadFailure failure) {
            if (!allowed || !failure.getRecoverable()) throw failure;
            com.review.compose.SecretProtectionKt.archiveEncryptedFile(context,
                    new java.io.File(context.getApplicationInfo().dataDir, "shared_prefs/" + PREFS + ".xml"));
        }
    }

    String encryptedSnapshot() { return new JSONObject(preferences().getAll()).toString(); }
    void restoreEncryptedSnapshot(String value) throws Exception {
        JSONObject raw = new JSONObject(value);
        SharedPreferences.Editor editor = preferences().edit().clear();
        java.util.Iterator<String> keys = raw.keys();
        while (keys.hasNext()) { String key = keys.next(); editor.putString(key, raw.getString(key)); }
        if (!editor.commit()) throw new IllegalStateException("原生加密资料回滚未完成");
    }

    void clear() {
        if (!preferences().edit().clear().commit()) throw new IllegalStateException("原生登录退出保存失败");
    }

    private SharedPreferences preferences() {
        return context.getSharedPreferences(PREFS, Context.MODE_PRIVATE);
    }

    private SecretKey getKey(boolean create) throws Exception {
        KeyStore keyStore = KeyStore.getInstance("AndroidKeyStore");
        keyStore.load(null);
        java.security.Key existing = keyStore.getKey(ALIAS, null);
        if (existing instanceof SecretKey) return (SecretKey) existing;

        if (!create) throw new com.review.compose.SecretReadFailure(com.review.compose.SecretFailureKind.MISSING_KEY);
        KeyGenerator generator = KeyGenerator.getInstance(KeyProperties.KEY_ALGORITHM_AES, "AndroidKeyStore");
        generator.init(new KeyGenParameterSpec.Builder(ALIAS,
                KeyProperties.PURPOSE_ENCRYPT | KeyProperties.PURPOSE_DECRYPT)
                .setBlockModes(KeyProperties.BLOCK_MODE_GCM)
                .setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE)
                .setKeySize(256)
                .build());
        return generator.generateKey();
    }
}
