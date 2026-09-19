/// 后端统一响应体：`{ code, message, data, timestamp }`。
///
/// 后端约定 HTTP 200 也携带业务错误码（仅认证失败走 401、无权限走 403），
/// 因此**判断成功与否必须看 [code]，不能只看 HTTP 状态码**。
class ApiResponse<T> {
  const ApiResponse({
    required this.code,
    required this.message,
    this.data,
    this.timestamp,
  });

  final int code;
  final String message;
  final T? data;
  final int? timestamp;

  bool get isSuccess => code == 0;

  factory ApiResponse.fromJson(
    Map<String, dynamic> json,
    T Function(Object? data) parse,
  ) {
    return ApiResponse<T>(
      code: (json['code'] as num?)?.toInt() ?? -1,
      message: json['message'] as String? ?? '未知错误',
      data: json['data'] == null ? null : parse(json['data']),
      timestamp: (json['timestamp'] as num?)?.toInt(),
    );
  }
}

/// 分页响应体：`{ total, page, size, records }`。
class PageResult<T> {
  const PageResult({
    required this.total,
    required this.page,
    required this.size,
    required this.records,
  });

  final int total;
  final int page;
  final int size;
  final List<T> records;

  bool get hasMore => page * size < total;

  factory PageResult.fromJson(
    Map<String, dynamic> json,
    T Function(Map<String, dynamic> item) parseItem,
  ) {
    final rawRecords = (json['records'] as List<dynamic>?) ?? const [];
    return PageResult<T>(
      total: (json['total'] as num?)?.toInt() ?? 0,
      page: (json['page'] as num?)?.toInt() ?? 1,
      size: (json['size'] as num?)?.toInt() ?? 20,
      records: rawRecords
          .whereType<Map<String, dynamic>>()
          .map(parseItem)
          .toList(growable: false),
    );
  }
}

/// 业务异常。[code] 与后端 ErrorCode 一一对应，便于按前缀做通用处理。
class ApiException implements Exception {
  const ApiException(this.code, this.message);

  final int code;
  final String message;

  /// 错误码前缀：101 认证 / 103 监护权限 / 104 设备 / 106 告警 / 109 通用。
  int get category => code ~/ 1000;

  /// 令牌失效类错误，拦截器据此决定是否尝试刷新。
  bool get isAuthError => code == 101003 || code == 101004 || code == 101006;

  /// 监护权限不足。
  bool get isPermissionDenied => code == 103001;

  @override
  String toString() => 'ApiException($code): $message';
}
