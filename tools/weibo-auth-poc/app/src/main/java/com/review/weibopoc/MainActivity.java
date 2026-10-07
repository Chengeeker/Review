package com.review.weibopoc;

import android.app.Activity;
import android.graphics.Typeface;
import android.os.Bundle;
import android.text.InputType;
import android.view.ViewGroup;
import android.widget.Button;
import android.widget.EditText;
import android.widget.LinearLayout;
import android.widget.ScrollView;
import android.widget.TextView;

import java.util.Arrays;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;

public final class MainActivity extends Activity {
    private final ExecutorService executor = Executors.newSingleThreadExecutor();
    private EditText accountInput;
    private EditText passwordInput;
    private EditText captchaInput;
    private EditText captchaCodeInput;
    private TextView status;
    private EncryptedSessionStore sessionStore;
    private WeiboApi api;
    private WeiboSession session;
    private boolean requestRunning;

    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);
        sessionStore = new EncryptedSessionStore(this);
        buildUi();
        restoreSession(false);
    }

    @Override
    protected void onDestroy() {
        executor.shutdownNow();
        super.onDestroy();
    }

    private void buildUi() {
        int pad = dp(16);
        LinearLayout content = new LinearLayout(this);
        content.setOrientation(LinearLayout.VERTICAL);
        content.setPadding(pad, pad, pad, pad);

        TextView title = new TextView(this);
        title.setText("微博 Android 登录 POC");
        title.setTextSize(22);
        title.setTypeface(null, Typeface.BOLD);
        content.addView(title, matchWrap());

        TextView hint = new TextView(this);
        hint.setText("仅显示状态和字段是否存在。密码不会持久化或写入日志。session 使用 Android Keystore AES-GCM 加密保存。");
        hint.setTextSize(14);
        content.addView(hint, margins(0, dp(8), 0, dp(12)));

        accountInput = field("微博账号", InputType.TYPE_CLASS_TEXT | InputType.TYPE_TEXT_VARIATION_EMAIL_ADDRESS);
        passwordInput = field("微博密码", InputType.TYPE_CLASS_TEXT | InputType.TYPE_TEXT_VARIATION_PASSWORD);
        captchaInput = field("验证码挑战值（可选）", InputType.TYPE_CLASS_TEXT);
        captchaCodeInput = field("验证码（可选）", InputType.TYPE_CLASS_TEXT);
        content.addView(accountInput, margins(0, 0, 0, dp(8)));
        content.addView(passwordInput, margins(0, 0, 0, dp(8)));
        content.addView(captchaInput, margins(0, 0, 0, dp(8)));
        content.addView(captchaCodeInput, margins(0, 0, 0, dp(8)));

        addButton(content, "登录并读取 Android Session", this::login);
        addButton(content, "恢复加密 Session", () -> restoreSession(true));
        addButton(content, "刷新 account/getoauth", () -> refresh(false));
        addButton(content, "模拟到期并自动刷新", this::simulateDueRefresh);
        addButton(content, "检查 Review 当前 API", this::checkReviewApi);
        addButton(content, "退出并清除 POC Session", this::logout);

        status = new TextView(this);
        status.setTextSize(14);
        status.setTextIsSelectable(true);
        status.setPadding(0, dp(12), 0, dp(12));
        content.addView(status, matchWrap());
        status.setText("准备就绪。请在受控 Android 设备上执行账号验收。");

        ScrollView scroll = new ScrollView(this);
        scroll.addView(content);
        setContentView(scroll);
    }

    private EditText field(String hint, int inputType) {
        EditText input = new EditText(this);
        input.setSingleLine(true);
        input.setHint(hint);
        input.setInputType(inputType);
        return input;
    }

    private void addButton(LinearLayout parent, String label, Runnable action) {
        Button button = new Button(this);
        button.setText(label);
        button.setOnClickListener(view -> action.run());
        parent.addView(button, margins(0, 0, 0, dp(6)));
    }

    private void login() {
        if (requestRunning) return;
        String account = accountInput.getText().toString().trim();
        char[] passwordChars = new char[passwordInput.length()];
        passwordInput.getText().getChars(0, passwordInput.length(), passwordChars, 0);
        String captcha = captchaInput.getText().toString();
        String captchaCode = captchaCodeInput.getText().toString();
        passwordInput.setText("");
        status.setText("正在登录。密码输入框已清空……");
        runRequest(() -> {
            String password = new String(passwordChars);
            Arrays.fill(passwordChars, '\0');
            try {
                NativeRuntime runtime = NativeRuntime.get(this);
                api = new WeiboApi(this, runtime);
                WeiboApi.ApiResult result = api.login(account, password, captcha, captchaCode);
                sessionStore.save(result.session);
                return result;
            } finally {
                password = null;
            }
        }, result -> {
            session = result.session;
            status.setText(result.httpCode + "\n" + result.session.fieldPresence()
                    + "\nKeystore AES-GCM persistence: PASS");
        });
    }

    private void restoreSession(boolean userInitiated) {
        if (requestRunning) return;
        runRequest(() -> {
            WeiboSession restored = sessionStore.load();
            if (restored == null) throw new WeiboApi.ApiFailure("no_saved_session", 0, "none");
            NativeRuntime runtime = NativeRuntime.get(this);
            return new RestoredSession(restored, new WeiboApi(this, runtime));
        }, restored -> {
            session = restored.session;
            api = restored.api;
            status.setText("Encrypted Session restore: PASS\n" + session.fieldPresence());
            if (session.shouldRefresh(System.currentTimeMillis())) refresh(true);
        }, error -> {
            if (userInitiated) status.setText("Session restore: " + safeError(error));
            else status.setText("No saved encrypted session. Start with login.");
        });
    }

    private void refresh(boolean automatic) {
        if (requestRunning) return;
        if (session == null) {
            status.setText("Session missing. Login first.");
            return;
        }
        runRequest(() -> {
            WeiboApi.ApiResult result = api.refresh(session);
            sessionStore.save(result.session);
            return result;
        }, result -> {
            session = result.session;
            status.setText("account/getoauth HTTP " + result.httpCode + ", response=" + result.responseCode
                    + "\n" + session.fieldPresence() + "\nEncrypted Session update: PASS");
        }, error -> status.setText((automatic ? "sessionExpired · automatic refresh failed: " : "Refresh failed: ")
                + safeError(error)));
    }

    private void simulateDueRefresh() {
        if (session == null) {
            status.setText("Session missing. Login first.");
            return;
        }
        session = session.withLastRefreshAt(System.currentTimeMillis() - 21_000_000L);
        try {
            sessionStore.save(session);
            status.setText("已将刷新时间设为到期，正在验证自动刷新……");
            if (session.shouldRefresh(System.currentTimeMillis())) refresh(true);
        } catch (Exception error) {
            status.setText("模拟到期失败：" + error.getClass().getSimpleName());
        }
    }

    private void checkReviewApi() {
        if (session == null) {
            status.setText("Session missing. Login first.");
            return;
        }
        runRequest(() -> api.checkReviewApi(session), result -> {
            status.setText("Review /ajax/config/getconfig HTTP " + result.httpCode
                    + ", response=" + result.responseCode
                    + "\nReview API logged-in check: " + (result.reviewApiAccepted ? "PASS" : "FAIL")
                    + "\nUID match: " + (result.reviewUidMatches ? "PASS" : "FAIL"));
        });
    }

    private void logout() {
        if (requestRunning) return;
        runRequest(() -> {
            sessionStore.clear();
            return true;
        }, ignored -> {
            session = null;
            api = null;
            status.setText("POC session and Keystore key cleared.");
        });
    }

    private <T> void runRequest(Work<T> work, ResultHandler<T> success) {
        runRequest(work, success, error -> status.setText("Request failed: " + safeError(error)));
    }

    private <T> void runRequest(Work<T> work, ResultHandler<T> success,
                                ErrorHandler failure) {
        if (requestRunning) return;
        requestRunning = true;
        executor.execute(() -> {
            try {
                T result = work.run();
                runOnUiThread(() -> {
                    requestRunning = false;
                    success.accept(result);
                });
            } catch (Exception error) {
                runOnUiThread(() -> {
                    requestRunning = false;
                    failure.accept(error);
                });
            }
        });
    }

    private static String safeError(Throwable error) {
        if (error instanceof WeiboApi.ApiFailure) {
            WeiboApi.ApiFailure failure = (WeiboApi.ApiFailure) error;
            return failure.category + " (HTTP " + failure.httpCode + ", response=" + failure.responseCode + ")";
        }
        return error.getClass().getSimpleName();
    }

    private ViewGroup.LayoutParams matchWrap() {
        return new LinearLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT,
                ViewGroup.LayoutParams.WRAP_CONTENT);
    }

    private ViewGroup.LayoutParams margins(int left, int top, int right, int bottom) {
        LinearLayout.LayoutParams params = new LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT);
        params.setMargins(left, top, right, bottom);
        return params;
    }

    private int dp(int value) {
        return (int) (value * getResources().getDisplayMetrics().density + 0.5f);
    }

    private interface Work<T> {
        T run() throws Exception;
    }

    private interface ResultHandler<T> {
        void accept(T result);
    }

    private interface ErrorHandler {
        void accept(Throwable error);
    }

    private static final class RestoredSession {
        final WeiboSession session;
        final WeiboApi api;

        RestoredSession(WeiboSession session, WeiboApi api) {
            this.session = session;
            this.api = api;
        }
    }
}
