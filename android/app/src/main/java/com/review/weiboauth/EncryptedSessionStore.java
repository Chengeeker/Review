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

    void save(WeiboSession session) throws Exception {
        Cipher cipher = Cipher.getInstance("AES/GCM/NoPadding");
        cipher.init(Cipher.ENCRYPT_MODE, getKey());
        byte[] plaintext = session.toJson().toString().getBytes(StandardCharsets.UTF_8);
        byte[] encrypted;
        try {
            encrypted = cipher.doFinal(plaintext);
        } finally {
            java.util.Arrays.fill(plaintext, (byte) 0);
        }
        boolean saved = preferences().edit()
                .putString(IV, Base64.encodeToString(cipher.getIV(), Base64.NO_WRAP))
                .putString(DATA, Base64.encodeToString(encrypted, Base64.NO_WRAP))
                .commit();
        if (!saved) throw new IllegalStateException("encrypted session write failed");
    }

    WeiboSession load() {
        try {
            SharedPreferences prefs = preferences();
            String ivValue = prefs.getString(IV, null);
            String dataValue = prefs.getString(DATA, null);
            if (ivValue == null || dataValue == null) return null;

            Cipher cipher = Cipher.getInstance("AES/GCM/NoPadding");
            cipher.init(Cipher.DECRYPT_MODE, getKey(), new GCMParameterSpec(128,
                    Base64.decode(ivValue, Base64.NO_WRAP)));
            byte[] plaintext = cipher.doFinal(Base64.decode(dataValue, Base64.NO_WRAP));
            try {
                return WeiboSession.fromJson(new JSONObject(new String(plaintext, StandardCharsets.UTF_8)));
            } finally {
                java.util.Arrays.fill(plaintext, (byte) 0);
            }
        } catch (Throwable t) {
            android.util.Log.w("EncryptedSessionStore",
                    "Failed to load/decrypt session (" + t.getClass().getSimpleName() + "): " + t.getMessage());
            try {
                preferences().edit().clear().apply();
            } catch (Throwable ignored) {}
            return null;
        }
    }

    void clear() {
        try {
            preferences().edit().clear().apply();
        } catch (Throwable ignored) {}
        try {
            KeyStore keyStore = KeyStore.getInstance("AndroidKeyStore");
            keyStore.load(null);
            if (keyStore.containsAlias(ALIAS)) keyStore.deleteEntry(ALIAS);
        } catch (Throwable ignored) {}
    }

    private SharedPreferences preferences() {
        return context.getSharedPreferences(PREFS, Context.MODE_PRIVATE);
    }

    private SecretKey getKey() throws Exception {
        KeyStore keyStore = KeyStore.getInstance("AndroidKeyStore");
        keyStore.load(null);
        java.security.Key existing = keyStore.getKey(ALIAS, null);
        if (existing instanceof SecretKey) return (SecretKey) existing;

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
