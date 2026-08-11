import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

/// 统一的 HTTP 请求工具。
///
/// 解决核心问题：部分站点（如无忧书城）会返回 `Content-Encoding: gzip` 的
/// 压缩响应，而 Dart 的 http 包不会自动解压，导致 [http.Response.body] 拿到
/// 压缩乱码、HTML 解析失败。本工具统一处理 gzip 解压。
///
/// 注意：不主动发送 `Accept-Encoding: gzip` 请求头——部分站点对带该头的
/// 请求会返回 403（反爬），而服务器侧仍可能返回 gzip 压缩响应，只需在
/// 响应侧统一解压即可。
class HttpUtil {
  static const Map<String, String> defaultHeaders = {
    // 桌面 UA 更不容易被小说站风控（移动 UA + 非浏览器 TLS 指纹易被 403）
    'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
        '(KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
  };

  /// 发送 GET 请求并返回已解码的文本内容（自动解压 gzip）。
  static Future<String> getText(
    String url, {
    Map<String, String>? headers,
    Duration? timeout,
  }) async {
    final response = await http.get(
      Uri.parse(url),
      headers: {...defaultHeaders, ...?headers},
    ).timeout(timeout ?? const Duration(seconds: 20));
    return decodeBody(response);
  }

  /// 发送 GET 请求并返回原始响应（含已解码的 body 文本）。
  static Future<http.Response> get(
    String url, {
    Map<String, String>? headers,
    Duration? timeout,
  }) async {
    final response = await http.get(
      Uri.parse(url),
      headers: {...defaultHeaders, ...?headers},
    ).timeout(timeout ?? const Duration(seconds: 20));
    if (response.headers['content-encoding']?.toLowerCase() == 'gzip') {
      return _gunzipResponse(response);
    }
    return response;
  }

  /// 把响应体按 content-encoding 解码为字符串。
  static String decodeBody(http.Response response) {
    final encoding = response.headers['content-encoding']?.toLowerCase();
    if (encoding == 'gzip') {
      try {
        final bytes = gzip.decode(response.bodyBytes);
        return utf8.decode(bytes, allowMalformed: true);
      } catch (_) {
        // 解压失败时回退原始 body
      }
    }
    return utf8.decode(response.bodyBytes, allowMalformed: true);
  }

  static http.Response _gunzipResponse(http.Response response) {
    try {
      final bytes = gzip.decode(response.bodyBytes);
      return http.Response.bytes(
        bytes,
        response.statusCode,
        headers: response.headers..remove('content-encoding'),
        request: response.request,
      );
    } catch (_) {
      return response;
    }
  }
}
