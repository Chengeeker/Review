import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import '../constants/api_constants.dart';
import '../storage/storage_service.dart';

/// Weibo Visitor Token Generation Engine
/// Automatically generates a legitimate official SUB Cookie for zero-login instant feed access.
class VisitorTokenEngine {
  final Dio _dio;
  final StorageService _storage;

  VisitorTokenEngine(this._dio, this._storage);

  static String? extractJsonpPayload(String body) {
    try {
      final startIndex = body.indexOf('{');
      final endIndex = body.lastIndexOf('}');
      if (startIndex != -1 && endIndex != -1 && endIndex > startIndex) {
        return body.substring(startIndex, endIndex + 1);
      }
    } catch (_) {}
    return null;
  }

  Future<String?> getOrGenerateVisitorSub({bool forceRefresh = false}) async {
    final cachedSub = _storage.getSubCookie();
    if (!forceRefresh && cachedSub != null && cachedSub.isNotEmpty) {
      return cachedSub;
    }

    try {
      debugPrint('[VisitorTokenEngine] Generating new official visitor token...');

      // Step 1: Request genvisitor to obtain a TID
      final genResponse = await _dio.post(
        '${ApiConstants.passportUrl}${ApiConstants.visitorGen}',
        data: {
          'cb': 'gen_callback',
          'fp': '{"os":"1","browser":"Chrome124,0,0,0","fonts":"undefined","screenResolution":"1920*1080*24","plugins":""}',
        },
        options: Options(
          contentType: Headers.formUrlEncodedContentType,
          responseType: ResponseType.plain,
          headers: {
            'User-Agent': ApiConstants.defaultUserAgent,
            'Referer': '${ApiConstants.passportUrl}/visitor/visitor?entry=miniblog&a=enter&url=https%3A%2F%2Fweibo.com%2F',
          },
        ),
      );

      final genBody = genResponse.data.toString();
      String? tid;

      final genJsonStr = extractJsonpPayload(genBody);
      if (genJsonStr != null) {
        try {
          final decoded = jsonDecode(genJsonStr);
          if (decoded is Map<String, dynamic>) {
            final dataObj = decoded['data'] is Map<String, dynamic> ? decoded['data'] as Map<String, dynamic> : decoded;
            tid = dataObj['tid']?.toString();
          }
        } catch (_) {}
      }

      if (tid == null || tid.isEmpty) {
        final tidMatch = RegExp(r'"tid"\s*:\s*"([^"]+)"').firstMatch(genBody);
        tid = tidMatch?.group(1);
      }

      if (tid == null || tid.isEmpty) {
        debugPrint('[VisitorTokenEngine] Failed to parse TID from response');
        return null;
      }

      // Step 2: Incarnate visitor session using TID
      final incarnateUrl =
          '${ApiConstants.passportUrl}${ApiConstants.visitorIncarnate}?a=incarnate&t=$tid&w=2&c=095&gc=&cb=cross_domain&from=weibo';
      final incarnateResponse = await _dio.get(
        incarnateUrl,
        options: Options(
          responseType: ResponseType.plain,
          headers: {
            'User-Agent': ApiConstants.defaultUserAgent,
            'Referer': '${ApiConstants.passportUrl}/visitor/visitor',
          },
        ),
      );

      final incarnateBody = incarnateResponse.data.toString();
      String? sub;
      String subp = '';

      final incarnateJsonStr = extractJsonpPayload(incarnateBody);
      if (incarnateJsonStr != null) {
        try {
          final decoded = jsonDecode(incarnateJsonStr);
          if (decoded is Map<String, dynamic>) {
            final dataObj = decoded['data'] is Map<String, dynamic> ? decoded['data'] as Map<String, dynamic> : decoded;
            sub = dataObj['sub']?.toString();
            subp = dataObj['subp']?.toString() ?? '';
          }
        } catch (_) {}
      }

      if (sub == null || sub.isEmpty) {
        final subMatch = RegExp(r'"sub"\s*:\s*"([^"]+)"').firstMatch(incarnateBody);
        final subpMatch = RegExp(r'"subp"\s*:\s*"([^"]+)"').firstMatch(incarnateBody);
        sub = subMatch?.group(1);
        subp = subpMatch?.group(1) ?? '';
      }

      if (sub != null && sub.isNotEmpty) {
        await _storage.setSubCookie(sub);
        await _storage.setSubpCookie(subp);
        debugPrint('[VisitorTokenEngine] Successfully obtained new visitor session');
        return sub;
      }
    } catch (e) {
      debugPrint('[VisitorTokenEngine] Error generating visitor token: $e');
    }
    return null;
  }
}
