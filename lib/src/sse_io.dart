import 'package:dio/dio.dart';
import 'package:sse_processor/src/sse_offline.dart';

import 'chain/src/sse_chain.dart';
import 'chain/sse_chain_exposure.dart';
import 'filter/src/sse_filter.dart';
import 'filter/sse_filter_exposure.dart';
import 'sse_ex.dart';
import 'sse_log.dart';
import 'sse_processor.dart';

/// The particular request mode for receive sse in net request trigger location.
///
/// It it mainly used to replace Dio to perform network requests that can receive streaming data, avoiding requests for streaming data in A module and receiving streaming data in
/// B module (another module)
///
/// It also supports receiving json format data return from server side, completely according wishes of server side, usually api request error will return json format response data.
/// If stream return successfully, it also return a mock json represent invoke api success.(code is 200)
final class Sio {
  static const tag = "SSEIoClient";

  final Dio _dio;
  final SSEInterceptorManager _interceptorManager;
  final SSEProcessor _sseProcessor;
  late final SSEFilterService _filterService;

  final _headers = <String, dynamic>{
    r'Accept': 'text/event-stream',
    r'Client-Api-Timeout': 120000,
  };

  Sio(this._dio, this._interceptorManager, this._sseProcessor, this._filterService);

  /// Post request, response will bridge to sse interceptor if server return in stream and [SSEInterceptor] parameter is not null.
  /// Response return json format if server return by json format (Usually api error situation)
  /// [sseInterceptor] Interceptor for receive server send event.
  /// [interceptor] A interceptor add to dio component, purpose is provide more degrees of freedom to control the logic of stream sending and receiving.
  /// Will remove when requester done.
  /// [onJsonResponse] A callback that pass response in json format data from server (usually api error return json format data)
  /// [sseFilter] Each converted sse structure from stream will get through [SSEFilterService] filter firstly, process by [SSEFilter] then put to [SSECacheDeliverer]
  void post(String path,
      {Object? data,
      Map<String, dynamic>? queryParameters,
      SSEInterceptor? sseInterceptor,
      Interceptor? interceptor,
      SSEFilter? sseFilter,
      SseOfflineProvider? offlineProvider,
      CancelToken? cancelToken,
      Function(Map<String, dynamic> response)? onJsonResponse}) async {
    _dio.interceptors.insert(
        0,
        DisposableSioInterceptor(
            _dio, sseInterceptor, _interceptorManager, sseFilter, _filterService,
            offlineProvider: offlineProvider, outsideInterceptor: interceptor));
    RequestOptions requestOptions = Options(headers: _headers, method: "POST").compose(
        _dio.options, path,
        queryParameters: queryParameters, data: data, cancelToken: cancelToken);
    Response response = await _dio.fetch(requestOptions);
    _resolveResponse(response, onJsonResponse);
  }

  /// Put request, response will bridge to sse interceptor if server return in stream and [SSEInterceptor] parameter is not null.
  /// Response return json format if server return by json format (Usually api error situation)
  /// [sseInterceptor] Interceptor for receive server send event.
  /// [interceptor] A interceptor add to dio component, purpose is provide more degrees of freedom to control the logic of stream sending and receiving.
  /// Will remove when requester done.
  /// [onJsonResponse] A callback that pass response in json format data from server (usually api error return json format data)
  /// [sseFilter] Each converted sse structure from stream will get through [SSEFilterService] filter firstly, process by [SSEFilter] then put to [SSECacheDeliverer]
  void put(String path,
      {Object? data,
      Map<String, dynamic>? queryParameters,
      Interceptor? interceptor,
      SSEInterceptor? sseInterceptor,
      SSEFilter? sseFilter,
      CancelToken? cancelToken,
      Function(Map<String, dynamic> response)? onJsonResponse}) async {
    _dio.interceptors.insert(
        0,
        DisposableSioInterceptor(
            _dio, sseInterceptor, _interceptorManager, sseFilter, _filterService,
            outsideInterceptor: interceptor));
    RequestOptions requestOptions = Options(headers: _headers, method: "PUT").compose(
        _dio.options, path,
        queryParameters: queryParameters, data: data, cancelToken: cancelToken);
    Response response = await _dio.fetch(requestOptions);
    _resolveResponse(response, onJsonResponse);
  }

  /// Get request, response will bridge to sse interceptor if server return in stream and [SSEInterceptor] parameter is not null.
  /// Response return json format if server return by json format (Usually api error situation)
  /// [sseInterceptor] Interceptor for receive server send event.
  /// [onJsonResponse] A callback that pass response in json format data from server (usually api error return json format data)
  /// [interceptor] A interceptor add to dio component, purpose is provide more degrees of freedom to control the logic of stream sending and receiving.
  /// Will remove when requester done.
  /// [sseFilter] Each converted sse structure from stream will get through [SSEFilterService] filter firstly, process by [SSEFilter] then put to [SSECacheDeliverer]
  void get(String path,
      {Map<String, dynamic>? queryParameters,
      SSEInterceptor? sseInterceptor,
      Interceptor? interceptor,
      SSEFilter? sseFilter,
      CancelToken? cancelToken,
      SseOfflineProvider? offlineProvider,
      Function(Map<String, dynamic> response)? onJsonResponse}) async {
    _dio.interceptors.insert(
        0,
        DisposableSioInterceptor(
            _dio, sseInterceptor, _interceptorManager, sseFilter, _filterService,
            outsideInterceptor: interceptor, offlineProvider: offlineProvider));
    RequestOptions requestOptions = Options(headers: _headers, method: "GET")
        .compose(_dio.options, path, queryParameters: queryParameters, cancelToken: cancelToken);
    Response response = await _dio.fetch(requestOptions);
    _resolveResponse(response, onJsonResponse);
  }

  /// Delete request, response will bridge to sse interceptor if server return in stream and [SSEInterceptor] parameter is not null.
  /// Response return json format if server return by json format (Usually api error situation)
  /// [sseInterceptor] Interceptor for receive server send event.
  /// [interceptor] A interceptor add to dio component, purpose is provide more degrees of freedom to control the logic of stream sending and receiving.
  /// Will remove when requester done.
  /// [onJsonResponse] A callback that pass response in json format data from server (usually api error return json format data)
  /// [sseFilter] Each converted sse structure from stream will get through [SSEFilterService] filter firstly, process by [SSEFilter] then put to [SSECacheDeliverer]
  void delete(String path,
      {Object? data,
      Map<String, dynamic>? queryParameters,
      SSEInterceptor? sseInterceptor,
      Interceptor? interceptor,
      SSEFilter? sseFilter,
      CancelToken? cancelToken,
      Function(Map<String, dynamic> response)? onJsonResponse}) async {
    _dio.interceptors.insert(
        0,
        DisposableSioInterceptor(
            _dio, sseInterceptor, _interceptorManager, sseFilter, _filterService,
            outsideInterceptor: interceptor));
    RequestOptions requestOptions = Options(headers: _headers, method: "DELETE").compose(
        _dio.options, path,
        queryParameters: queryParameters, data: data, cancelToken: cancelToken);
    Response response = await _dio.fetch(requestOptions);
    _resolveResponse(response, onJsonResponse);
  }

  void _resolveResponse(
      Response response, Function(Map<String, dynamic> response)? onJsonResponse) {
    if (response.data != null && response.data is Map<String, dynamic>) {
      if ((response.data as Map<String, dynamic>).isNotEmpty) {
        _sseProcessor.suspendConnect();
        onJsonResponse?.call(response.data!);
        return;
      }
    }
    onJsonResponse?.call({"message": "success", "code": 200});
    slog.d("get request by stream mode", tag: tag);
  }
}

class DisposableSioInterceptor extends Interceptor {
  static const tag = "SSEIoClient";

  SSEInterceptor? sseApiInterceptor;
  SSEFilter? sseFilter;
  final SSEInterceptorManager sseInterceptorManager;
  final SSEFilterService filterService;
  Interceptor? _outsideInterceptor;
  final Dio _dio;
  String? streamPath;
  SseOfflineProvider? offlineProvider;

  DisposableSioInterceptor(this._dio, this.sseApiInterceptor, this.sseInterceptorManager,
      this.sseFilter, this.filterService,
      {Interceptor? outsideInterceptor, this.offlineProvider}) {
    _outsideInterceptor = outsideInterceptor;
  }

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    if (options.isStream()) {
      slog.d("request stream ${options.path}", tag: tag);
      streamPath = options.path;
      if (sseApiInterceptor != null) {
        sseInterceptorManager.addSSEInterceptor(sseApiInterceptor!);
      }
      if (sseFilter != null) {
        filterService.setFilter(sseFilter!);
      }
      if (offlineProvider != null) {
        options.putOfflineProvider(offlineProvider!);
      }
    }
    if (_outsideInterceptor != null) {
      _outsideInterceptor!.onRequest(options, handler);
    } else {
      super.onRequest(options, handler);
    }
  }

  @override
  void onResponse(Response response, ResponseInterceptorHandler handler) {
    if (_outsideInterceptor != null) {
      _outsideInterceptor!.onResponse(response, handler);
    } else {
      super.onResponse(response, handler);
    }
    slog.d("onResponse remove dio interceptor", tag: tag);
    _dio.interceptors.remove(this);
    _dio.interceptors.remove(_outsideInterceptor);
    _outsideInterceptor = null;
  }

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) {
    if (_outsideInterceptor != null) {
      _outsideInterceptor!.onError(err, handler);
    } else {
      super.onError(err, handler);
    }
    slog.d("onError ${err.message}", tag: tag);
    _removeInterceptor();
    _dio.interceptors.remove(this);
    _dio.interceptors.remove(_outsideInterceptor);
    _outsideInterceptor = null;
    filterService.reset();
  }

  void _removeInterceptor() {
    if (sseApiInterceptor != null) {
      sseInterceptorManager.removeSSEInterceptor(sseApiInterceptor!);
    }
  }
}
