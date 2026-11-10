@file:OptIn(androidx.compose.material3.ExperimentalMaterial3Api::class)
package com.review.compose

import androidx.compose.foundation.border
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.BasicTextField
import androidx.compose.foundation.text.KeyboardActions
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.outlined.ArrowBack
import androidx.compose.material.icons.outlined.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.rememberGraphicsLayer
import androidx.compose.ui.focus.onFocusChanged
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.*
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import kotlinx.coroutines.delay

@Composable
fun AccountScreen(model: ReviewModel) {
    var importing by remember { mutableStateOf(false) }
    var cookie by remember { mutableStateOf("") }
    var sms by rememberSaveable { mutableStateOf(true) }
    var phone by rememberSaveable { mutableStateOf("") }
    var area by rememberSaveable { mutableStateOf("86") }
    var account by rememberSaveable { mutableStateOf("") }
    var password by remember { mutableStateOf("") }
    var passwordVisible by remember { mutableStateOf(false) }
    var code by remember(model.smsAvailableAt) { mutableStateOf("") }
    var remaining by remember { mutableIntStateOf(0) }
    val challenge = model.smsChallenge.isNotBlank() && phone == model.smsPhone && area == model.smsArea
    val busy = model.accountLoading
    val colors = MaterialTheme.colorScheme
    val inputStyle = MaterialTheme.typography.bodyLarge.copy(color = colors.onSurface)
    val layer = rememberGraphicsLayer()
    val backdrop = remember(layer) { ReviewBackdrop(layer) }
    val top = TopAppBarDefaults.windowInsets.asPaddingValues().calculateTopPadding() + 56.dp
    LaunchedEffect(model.smsAvailableAt) {
        do { remaining = ((model.smsAvailableAt - System.currentTimeMillis() + 999) / 1000).coerceAtLeast(0).toInt(); if (remaining > 0) delay(1000) } while (remaining > 0)
    }
    fun login() { model.loginNative(account, password, phone, area, code, sms) }
    CompositionLocalProvider(LocalBackdrop provides backdrop) {
    Box(Modifier.fillMaxSize()) {
        Box(Modifier.fillMaxSize().recordBackdrop(backdrop).imePadding().verticalScroll(rememberScrollState()).padding(start = 32.dp, end = 32.dp, top = top + 36.dp, bottom = 24.dp), contentAlignment = Alignment.TopCenter) {
            Column(Modifier.widthIn(max = 440.dp).fillMaxWidth().testTag("login-form")) {
                if (!sms) {
                    LoginInput(account, { account = it.take(128) }, "手机号、邮箱或微博账号", enabled = !busy, keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Email, imeAction = ImeAction.Next))
                    Spacer(Modifier.height(14.dp))
                    LoginInput(password, { password = it.take(256) }, "登录密码", enabled = !busy,
                        visualTransformation = if (passwordVisible) VisualTransformation.None else PasswordVisualTransformation(), keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Password, imeAction = ImeAction.Done), keyboardActions = KeyboardActions(onDone = { if (!busy) login() }),
                        trailingIcon = { IconButton(onClick = hapticClick { passwordVisible = !passwordVisible }) { Icon(if (passwordVisible) Icons.Outlined.VisibilityOff else Icons.Outlined.Visibility, if (passwordVisible) "隐藏密码" else "显示密码", tint = colors.onSurfaceVariant) } })
                } else {
                    Row(Modifier.fillMaxWidth().border(1.dp, MaterialTheme.colorScheme.outline, RoundedCornerShape(16.dp)).padding(1.dp).padding(horizontal = 18.dp), verticalAlignment = Alignment.CenterVertically) {
                        BasicTextField(area, { area = it.filter(Char::isDigit).take(6); code = "" }, Modifier.width(68.dp).padding(vertical = 15.dp), enabled = !busy, singleLine = true, textStyle = inputStyle.copy(textAlign = TextAlign.Center), cursorBrush = SolidColor(colors.primary), keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Phone), decorationBox = { inner -> Row(verticalAlignment = Alignment.CenterVertically) { Text("+", style = inputStyle); Box(Modifier.weight(1f)) { inner() } } })
                        VerticalDivider(Modifier.height(34.dp), color = MaterialTheme.colorScheme.outlineVariant); Spacer(Modifier.width(14.dp))
                        BasicTextField(phone, { phone = it.filter(Char::isDigit).take(20); code = "" }, Modifier.weight(1f).padding(vertical = 15.dp), enabled = !busy, singleLine = true, textStyle = inputStyle, cursorBrush = SolidColor(colors.primary), keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Phone, imeAction = ImeAction.Next), decorationBox = { inner -> Box { if (phone.isEmpty()) Text("输入手机号", style = inputStyle, color = colors.onSurfaceVariant); inner() } })
                    }
                    if (challenge) {
                        Spacer(Modifier.height(18.dp))
                        LoginInput(code, { code = it.filter(Char::isDigit).take(12) }, "输入短信验证码", enabled = !busy, keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Number, imeAction = ImeAction.Done), keyboardActions = KeyboardActions(onDone = { if (!busy) login() }))
                    }
                }
                Spacer(Modifier.height(22.dp))
                Button(onClick = hapticClick { if (sms && !challenge) model.requestSms(phone, area) else login() }, Modifier.fillMaxWidth().height(56.dp), enabled = !busy) {
                    if (busy) CircularProgressIndicator(Modifier.size(22.dp), strokeWidth = 2.dp) else Text(if (sms && !challenge) "获取验证码" else "登录", style = MaterialTheme.typography.titleMedium)
                }
                if (sms && challenge) { Spacer(Modifier.height(14.dp)); TextButton(onClick = hapticClick { model.requestSms(phone, area) }, Modifier.align(Alignment.End), enabled = !busy && remaining == 0) { Text(if (remaining > 0) "$remaining 秒后重新获取" else "重新获取验证码") } }
                Spacer(Modifier.height(14.dp))
                OutlinedButton(onClick = hapticClick { sms = !sms; password = ""; code = "" }, Modifier.fillMaxWidth().height(50.dp), enabled = !busy, colors = ButtonDefaults.outlinedButtonColors(contentColor = colors.primary), border = androidx.compose.foundation.BorderStroke(1.dp, colors.outline)) { Text(if (sms) "用账号密码登录" else "用验证码登录") }
                model.accountError?.let { Text(it, Modifier.padding(top = 16.dp), color = MaterialTheme.colorScheme.error) }
            }
        }
        TopAppBar(title = { Text("账号登录", Modifier.padding(start = 16.dp), fontSize = 18.sp, fontWeight = reviewWeight(FontWeight.Bold)) }, modifier = Modifier.frostedBackdrop(colors.background), navigationIcon = { IconButton(onClick = hapticClick(model::back)) { Icon(Icons.AutoMirrored.Outlined.ArrowBack, "返回") } }, actions = { TextButton(onClick = hapticClick { importing = true }, enabled = !busy) { Text("Cookie 导入") }; Spacer(Modifier.width(8.dp)) }, expandedHeight = 56.dp, colors = TopAppBarDefaults.topAppBarColors(containerColor = Color.Transparent))
    }
    }
    if (importing) ReviewAlertDialog(onDismissRequest = { importing = false; cookie = "" }, title = { Text("导入 Cookie") }, text = {
        Column { Text("粘贴微博 Cookie，或单独粘贴 SUB。", fontSize = 13.sp); Spacer(Modifier.height(12.dp)); LoginInput(cookie, { cookie = it.take(32768) }, "SUB=...; SUBP=...", lines = 4) }
    }, confirmButton = { Button(onClick = hapticClick { if (cookie.isNotBlank()) { model.login(cookie); importing = false; cookie = "" } }, enabled = cookie.isNotBlank() && !busy) { Text("验证并导入") } }, dismissButton = { TextButton(onClick = hapticClick { importing = false; cookie = "" }) { Text("取消") } })
}

@Composable
private fun LoginInput(value: String, edit: (String) -> Unit, hint: String, enabled: Boolean = true,
    lines: Int = 1, visualTransformation: VisualTransformation = VisualTransformation.None,
    keyboardOptions: KeyboardOptions = KeyboardOptions.Default, keyboardActions: KeyboardActions = KeyboardActions.Default,
    trailingIcon: (@Composable () -> Unit)? = null) {
    var focused by remember { mutableStateOf(false) }
    val colors = MaterialTheme.colorScheme
    val style = MaterialTheme.typography.bodyLarge.copy(color = colors.onSurface.copy(alpha = if (enabled) 1f else .38f))
    BasicTextField(value, edit, Modifier.fillMaxWidth().onFocusChanged { focused = it.isFocused },
        enabled = enabled, singleLine = lines == 1, minLines = lines, maxLines = lines,
        textStyle = style, cursorBrush = SolidColor(colors.primary), visualTransformation = visualTransformation,
        keyboardOptions = keyboardOptions, keyboardActions = keyboardActions, decorationBox = { inner ->
            Row(Modifier.border(if (focused) 2.dp else 1.dp, if (focused) colors.primary else colors.outline, RoundedCornerShape(4.dp)).padding(start = 16.dp, end = if (trailingIcon == null) 16.dp else 0.dp), verticalAlignment = Alignment.CenterVertically) {
                Box(Modifier.weight(1f).padding(vertical = 15.dp)) {
                    if (value.isEmpty()) Text(hint, style = style, color = colors.onSurfaceVariant)
                    inner()
                }
                trailingIcon?.invoke()
            }
        })
}
