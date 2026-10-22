import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import '../config/app_config.dart';
import '../storage/token_store.dart';
import 'api_response.dart';

/// REST 客户端。
///
/// 把三件容易写错的事收敛在一个地方：
/// 1. **业务错误码判定**：后端 HTTP 200 也可能带 `code != 0`，
///    所以调用方永远不需要自己判断 code，[getRaw] 等方法的返回即「成功的数据」。
/// 2. **令牌自动刷新**：401 时用 refreshToken 换一次新令牌并重放原请求，
///    且并发请求只会触发一次刷新（否则多个请求同时 401 会打出多次刷新，
///    后面几次因为 refreshToken 已被使用而失败，把用户踢下线）。
/// 3. **错误归一**：所有失败都变成 [ApiException]，UI 层不用区分
///    DioException / SocketException / 业务错误码三种形态。
class ApiClient {
  // Dart 不允许命名参数以下划线开头，因此无法写成 this._store 这样的
  // initializing formal，只能走初始化列表。以下两处 lint 属误报。
  // ignore: prefer_initializing_formals
  ApiClient({required TokenStore store, VoidCallback? onSessionExpired})
      // ignore: prefer_initializing_formals
      : _store = store,
        // ignore: prefer_initializing_formals
        _onSessionExpired = onSessionExpired {
    _dio = Dio(BaseOptions(
      baseUrl: AppConfig.apiBaseUrl,
      connectTimeout: AppConfig.connectTimeout,
      receiveTimeout: AppConfig.receiveTimeout,
      contentType: Headers.jsonContentType,
      // 交给我们自己处理：4xx 也要读 body 里的业务错误码
      validateStatus: (status) => status != null && status < 500,
    ));
    // 刷新令牌专用实例：不走下面的拦截器，避免刷新请求本身 401 时递归调用自己
    _refreshDio = Dio(BaseOptions(
      baseUrl: AppConfig.apiBaseUrl,
      connectTimeout: AppConfig.connectTimeout,
      receiveTimeout: AppConfig.receiveTimeout,
      contentType: Headers.jsonContentType,
    ));
    _dio.interceptors.add(InterceptorsWrapper(
      onRequest: _onRequest,
      onResponse: _onResponse,
    ));
  }

  final TokenStore _store;
  final VoidCallback? _onSessionExpired;

  late final Dio _dio;
  late final Dio _refreshDio;

  /// 正在进行的刷新操作。多个请求同时 401 时共享同一个 Future。
  Future<bool>? _refreshing;

  TokenStore get store => _store;

  // ------------------------------------------------------------------
  // 对外方法：返回已解包的 data
  // ------------------------------------------------------------------

  Future<Object?> getRaw(String path, {Map<String, dynamic>? query}) {
    return _send(() => _dio.get<dynamic>(path, queryParameters: _clean(query)));
  }

  Future<Object?> postRaw(String path,
      {Object? body, Map<String, dynamic>? query}) {
    return _send(
        () => _dio.post<dynamic>(path, data: body, queryParameters: _clean(query)));
  }

  Future<Object?> putRaw(String path,
      {Object? body, Map<String, dynamic>? query}) {
    return _send(
        () => _dio.put<dynamic>(path, data: body, queryParameters: _clean(query)));
  }

  /// DELETE。电子围栏删除需要它；后端 DELETE 接口返回 data 为 null，
  /// 所以调用方拿到的是 null，不要试图解包。
  Future<Object?> deleteRaw(String path, {Map<String, dynamic>? query}) {
    return _send(() => _dio.delete<dynamic>(path, queryParameters: _clean(query)));
  }

  // ------------------------------------------------------------------
  // 拦截器
  // ------------------------------------------------------------------

  void _onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    final token = _store.accessToken;
    if (token != null && token.isNotEmpty) {
      options.headers['Authorization'] = 'Bearer $token';
    }
    handler.next(options);
  }

  void _onResponse(Response<dynamic> response, ResponseInterceptorHandler handler) {
    final body = response.data;
    // 非 JSON（理论上不会出现）直接放过，让调用方拿到原始内容
    if (body is! Map<String, dynamic>) {
      handler.next(response);
      return;
    }
    final code = (body['code'] as num?)?.toInt() ?? 0;
    if (code == 0) {
      handler.next(response);
      return;
    }
    // 业务失败一律转成 DioException 交给 _send 统一处理：
    // 这里不直接决定「是否刷新令牌后重放」，因为拦截器里没法重放原请求
    // （handler.next 只是把当前这个失败响应透传下去，拿到的仍是旧的 code）。
    handler.reject(DioException(
      requestOptions: response.requestOptions,
      response: response,
      error: ApiException(code, body['message'] as String? ?? '请求失败'),
      type: DioExceptionType.badResponse,
    ));
  }

  // ------------------------------------------------------------------
  // 发送 + 解包 + 刷新重试
  // ------------------------------------------------------------------

  Future<Object?> _send(Future<Response<dynamic>> Function() request) async {
    try {
      return _unwrap(await request());
    } on DioException catch (e) {
      // 令牌失效（业务码 101xxx）或 HTTP 401：刷新一次后重放原请求
      if (shouldRefreshToken(e)) {
        if (await _refreshToken()) {
          try {
            return _unwrap(await request());
          } on DioException catch (retryError) {
            // 刷新后仍失败才判登录态失效，避免把偶发失败变成强制登出
            _onSessionExpired?.call();
            throw _toApiException(retryError);
          }
        }
        _onSessionExpired?.call();
      }
      throw _toApiException(e);
    }
  }

  /// 是否值得尝试刷新令牌。
  @visibleForTesting
  static bool shouldRefreshToken(DioException e) {
    final wrapped = e.error;
    if (wrapped is ApiException && wrapped.isAuthError) {
      return true;
    }
    return e.response?.statusCode == 401;
  }

  /// 解包响应：成功返回 data，失败抛 [ApiException]。
  Object? _unwrap(Response<dynamic> response) {
    final body = response.data;
    if (body is! Map<String, dynamic>) {
      // 非标准响应体：按 HTTP 状态码判断
      final status = response.statusCode ?? 0;
      if (status >= 200 && status < 300) {
        return body;
      }
      throw ApiException(status * 1000, 'HTTP $status');
    }
    final code = (body['code'] as num?)?.toInt() ?? -1;
    if (code == 0) {
      return body['data'];
    }
    throw ApiException(code, body['message'] as String? ?? '请求失败');
  }

  /// 用 refreshToken 换新令牌。并发去重：[_refreshing] 非空时直接复用。
  Future<bool> _refreshToken() {
    final existing = _refreshing;
    if (existing != null) {
      return existing;
    }
    final future = _doRefresh();
    _refreshing = future;
    return future.whenComplete(() => _refreshing = null);
  }

  Future<bool> _doRefresh() async {
    final refreshToken = _store.refreshToken;
    if (refreshToken == null || refreshToken.isEmpty) {
      return false;
    }
    try {
      final response = await _refreshDio.post<dynamic>(
        '${AppConfig.apiPrefix}/auth/refresh',
        data: {'refreshToken': refreshToken},
      );
      final body = response.data;
      if (body is! Map<String, dynamic>) {
        return false;
      }
      if ((body['code'] as num?)?.toInt() != 0) {
        return false;
      }
      final data = body['data'] as Map<String, dynamic>?;
      final newAccess = data?['accessToken'] as String?;
      final newRefresh = data?['refreshToken'] as String?;
      if (newAccess == null || newRefresh == null) {
        return false;
      }
      await _store.updateTokens(accessToken: newAccess, refreshToken: newRefresh);
      return true;
    } catch (e) {
      // 刷新失败（网络问题 / refreshToken 已过期）一律按登录态失效处理，
      // 交给调用方跳登录页；这里不抛异常，避免把网络抖动也变成"被登出"
      debugPrint('[ApiClient] 刷新令牌失败: $e');
      return false;
    }
  }

  ApiException _toApiException(DioException e) {
    final wrapped = e.error;
    if (wrapped is ApiException) {
      return wrapped;
    }
    final body = e.response?.data;
    if (body is Map<String, dynamic>) {
      final code = (body['code'] as num?)?.toInt();
      if (code != null) {
        return ApiException(code, body['message'] as String? ?? '请求失败');
      }
    }
    final status = e.response?.statusCode;
    final message = switch (e.type) {
      DioExceptionType.connectionTimeout => '连接服务器超时，请检查网络',
      DioExceptionType.receiveTimeout => '服务器响应超时，请稍后重试',
      DioExceptionType.sendTimeout => '请求发送超时，请检查网络',
      DioExceptionType.connectionError => '无法连接服务器，请确认后端已启动',
      DioExceptionType.cancel => '请求已取消',
      _ => status == 403 ? '没有访问权限' : '网络异常，请稍后重试',
    };
    return ApiException(status == null ? -1 : status * 1000, message);
  }

  /// 丢掉值为 null 的查询参数：Dio 会把 null 序列化成空字符串，
  /// 后端 `@RequestParam(required = false)` 收到空串会当成"传了但为空"，
  /// 对 Integer 类型直接 400。
  Map<String, dynamic>? _clean(Map<String, dynamic>? query) {
    if (query == null || query.isEmpty) {
      return null;
    }
    final cleaned = <String, dynamic>{};
    query.forEach((key, value) {
      if (value != null) {
        cleaned[key] = value;
      }
    });
    return cleaned.isEmpty ? null : cleaned;
  }
}
