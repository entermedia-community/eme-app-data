import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'settings.dart';

class ApiException implements Exception {
  ApiException(this.message, {this.statusCode});
  final String message;
  final int? statusCode;

  bool get isUnauthorized => statusCode == 401 || statusCode == 403;

  @override
  String toString() => message;
}

/// Thin wrapper over the EME MediaDB JSON services
/// (`<server>/site/mediadb/services/...`).
///
/// The server replies with `text/json`, sometimes with HTML error pages, so
/// bodies are read as plain text and decoded here.
class ApiClient {
  ApiClient({required this.serverUrl, required this.tokenReader, this.onUnauthorized})
    : dio = Dio(
        BaseOptions(
          connectTimeout: const Duration(seconds: 15),
          receiveTimeout: const Duration(seconds: 60),
          responseType: ResponseType.plain,
          validateStatus: (_) => true,
        ),
      );

  final Dio dio;
  final String serverUrl;
  final String? Function() tokenReader;

  /// Called on a 401 so the auth layer can try a silent key re-login.
  /// Returns true when the request should be retried.
  final Future<bool> Function()? onUnauthorized;

  String get servicesUrl => '$serverUrl/site/mediadb/services';

  /// Turns a server-relative URL (`/site/...`) or services path into an absolute URL.
  String absolute(String url) {
    if (url.startsWith('http://') || url.startsWith('https://')) return url;
    if (url.startsWith('/')) return '$serverUrl$url';
    return '$servicesUrl/$url';
  }

  Map<String, String> get authHeaders {
    final token = tokenReader();
    return token == null || token.isEmpty ? const {} : {'Authorization': 'Bearer $token'};
  }

  Future<Map<String, dynamic>> postJson(String path, [Map<String, dynamic>? body]) => _send(
    () => dio.post(
      absolute(path),
      data: jsonEncode(body ?? const {}),
      options: Options(headers: {...authHeaders, 'Content-Type': 'application/json'}),
    ),
  );

  Future<Map<String, dynamic>> putJson(String path, Map<String, dynamic> body) => _send(
    () => dio.put(
      absolute(path),
      data: jsonEncode(body),
      options: Options(headers: {...authHeaders, 'Content-Type': 'application/json'}),
    ),
  );

  Future<Map<String, dynamic>> getJson(String path, {Map<String, dynamic>? query}) => _send(
    () => dio.get(
      absolute(path),
      queryParameters: query,
      options: Options(headers: authHeaders),
    ),
  );

  Future<Map<String, dynamic>> delete(String path) =>
      _send(() => dio.delete(absolute(path), options: Options(headers: authHeaders)));

  Future<Map<String, dynamic>> postForm(String path, Map<String, String> fields, {bool auth = true}) => _send(
    () => dio.post(
      absolute(path),
      data: fields,
      options: Options(headers: auth ? authHeaders : const {}, contentType: Headers.formUrlEncodedContentType),
    ),
  );

  Future<Map<String, dynamic>> postMultipart(
    String path,
    FormData Function() buildForm, {
    void Function(int sent, int total)? onProgress,
    CancelToken? cancelToken,
  }) => _send(
    () => dio.post(
      absolute(path),
      data: buildForm(),
      onSendProgress: onProgress,
      cancelToken: cancelToken,
      options: Options(headers: authHeaders),
    ),
  );

  /// Raw bytes (for originals that need auth, PDFs, downloads).
  Future<Uint8List> getBytes(String url) async {
    final res = await dio.get<List<int>>(
      absolute(url),
      options: Options(headers: authHeaders, responseType: ResponseType.bytes),
    );
    if ((res.statusCode ?? 500) >= 400) {
      throw ApiException('Download failed (${res.statusCode})', statusCode: res.statusCode);
    }
    return Uint8List.fromList(res.data ?? const []);
  }

  Future<Map<String, dynamic>> _send(Future<Response<dynamic>> Function() call, {bool retried = false}) async {
    Response<dynamic> res;
    try {
      res = await call();
    } on DioException catch (e) {
      throw ApiException(_networkMessage(e));
    }
    final status = res.statusCode ?? 0;
    if (status == 401 && !retried && onUnauthorized != null && await onUnauthorized!()) {
      return _send(call, retried: true);
    }
    final decoded = decodeBody(res.data);
    if (status >= 400) {
      final msg =
          decoded?['error_description'] ??
          decoded?['error'] ??
          decoded?['response']?['details'] ??
          _statusMessage(status);
      throw ApiException('$msg', statusCode: status);
    }
    if (decoded == null) {
      throw ApiException('Unexpected response from server ($status)', statusCode: status);
    }
    final envelope = decoded['response'] ?? decoded['reponse'];
    if (envelope is Map && envelope['status'] == 'error') {
      throw ApiException('${envelope['details'] ?? decoded['error'] ?? 'Server error'}', statusCode: status);
    }
    return decoded;
  }

  static Map<String, dynamic>? decodeBody(dynamic data) {
    if (data is Map<String, dynamic>) return data;
    if (data is! String) return null;
    final text = data.trim();
    if (!text.startsWith('{')) return null;
    try {
      final v = jsonDecode(text);
      return v is Map<String, dynamic> ? v : null;
    } catch (_) {
      return null;
    }
  }

  static String _statusMessage(int status) => switch (status) {
    401 => 'Please sign in again',
    403 => 'You do not have permission for this action',
    404 => 'Not found',
    _ => 'Server error ($status)',
  };

  static String _networkMessage(DioException e) => switch (e.type) {
    DioExceptionType.connectionTimeout ||
    DioExceptionType.receiveTimeout ||
    DioExceptionType.sendTimeout => 'The server took too long to respond',
    DioExceptionType.cancel => 'Cancelled',
    _ => 'Cannot reach the server. Check the server address and that it is running.',
  };
}

/// Set by the auth layer; read lazily so the client never holds a stale token.
final tokenHolderProvider = Provider<TokenHolder>((ref) => TokenHolder());

class TokenHolder {
  String? token;
  Future<bool> Function()? refresh;
}

final apiClientProvider = Provider<ApiClient>((ref) {
  final serverUrl = ref.watch(settingsProvider.select((s) => s.serverUrl));
  final holder = ref.watch(tokenHolderProvider);
  return ApiClient(
    serverUrl: serverUrl,
    tokenReader: () => holder.token,
    onUnauthorized: () async => await holder.refresh?.call() ?? false,
  );
});
