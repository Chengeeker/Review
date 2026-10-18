import 'dart:convert';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Direct interface to Weibo Android Native Client API (api.weibo.cn)
/// Uses native HMAC signatures (WeicoSecurityUtils / NativeRuntime),
/// bypassing Web Cookie expiration and maintaining full dual-channel redundancy.
class WeiboNativeApi {
  static const MethodChannel _defaultChannel = MethodChannel(
    'com.review/weibo_auth',
  );

  final MethodChannel _channel;

  WeiboNativeApi({MethodChannel? channel})
      : _channel = channel ?? _defaultChannel;

  /// Check whether the native keystore holds an active authenticated session.
  Future<bool> hasNativeSession() async {
    try {
      final result = await _channel.invokeMethod<bool>('hasNativeSession');
      return result == true;
    } catch (_) {
      return false;
    }
  }

  /// Send an authenticated request to `https://api.weibo.cn/2/$endpoint`.
  /// Returns the raw JSON response string, or null on error.
  Future<String?> request(
    String endpoint, [
    Map<String, String>? params,
  ]) async {
    try {
      final result = await _channel.invokeMethod<String>(
        'requestWeiboApi',
        {
          'endpoint': endpoint,
          if (params != null) 'params': params,
        },
      );
      return result;
    } catch (_) {
      return null;
    }
  }

  /// Send an authenticated request and decode the response Map.
  /// Returns null if the request fails or is non-JSON.
  Future<Map<String, dynamic>?> getJson(
    String endpoint, [
    Map<String, String>? params,
  ]) async {
    final raw = await request(endpoint, params);
    if (raw == null || raw.isEmpty) return null;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map<String, dynamic>) return decoded;
      if (decoded is Map) return Map<String, dynamic>.from(decoded);
      return null;
    } catch (_) {
      return null;
    }
  }
}

final weiboNativeApiProvider = Provider<WeiboNativeApi>((ref) {
  return WeiboNativeApi();
});
