import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/cupertino.dart';
import 'package:get/get_rx/src/rx_types/rx_types.dart';
import 'package:sse_processor/src/default/src/sse_default.dart';

import '../sse.dart';
import 'cache/src/sse_cache.dart';
import 'connect/src/sse_connect.dart';
import 'convert/src/sse_adapter.dart';
import 'core/src/sse_core.dart';
import 'destroyable.dart';
import 'filter/src/sse_filter.dart';
import 'sse_io.dart';
import 'sse_log.dart';

/// Why:
///
/// In the theater module, AI-generated data is usually distributed in the form of a stream, and the client also needs to receive it in the form of a stream. Interacting in this mode will face several problems:
/// 1. Parsing: How to parse the streamed data after it is distributed? It is necessary to negotiate a protocol with the server and then convert it into the data structure object of the client.
/// 2. Rate control: Usually, the rate of the streamed data distributed by the server is irregular. After the client receives it, rate control is required for display.
/// 3. Distribution: How to display (logic processing) after obtaining the streamed data? Because the project is developed in modules, a data object transformed from a stream may be used for logic processing by multiple modules. At this time, a distribution mechanism is required.
/// 4. Priority level: When it comes to distribution, should priority be considered?
/// 5. Caching: For rate control, a loop cache pool can be looped should be designed for timed distribution.
/// 6. Automatic cleaning: In order for the user to not consider the cumbersome operations such as interceptor registration and deregistration,
/// a set of automatic cleaning processes needs to be completed.
/// 7. Distribution status control: Including pausing/resuming distribution and monitoring the distribution status.
/// 8. Lifecycle: Since there is an automatic cleaning function, should lifecycle callbacks also be arranged?
/// 9. Native stream bridging: Because the network-related logic is placed in the native layer, the network stream data request should also be initiated by the native layer, so that a set of network components can be uniformly used.
/// 10. Connection status management: Although SSE is not a long connection, it is a little longer than the usual short connection, and then the connection status will be involved.
///
/// In order to solve the above problems, a set of SSE distribution components needs to be designed.
///
/// How:
///
/// A net request flow（Contain SSE deliver)）
///
///                               [Retrofit]
///                                   |
///                                Options
///                                   |
///                                 [Dio]
///                                   |
///                                Request
///                                   |
///                           Request Interceptor
///                                   |
///              transformer.transformRequest (NativeTransformer)
///                                   |
///                 httpClientAdapter.fetch (NativeClientAdapter)
///                                   |
///          ----------------------------------------------------
///
///       (Flutter net component)		    （Native net component in Android for example）
///
///             [HttpClient]			           [OkHttp]
///
///              [Socket]				             [Socket]
///
///          ----------------------------------------------------
///                                   |
///                 transformer.transformResponse (NativeTransformer)
///                                   |
///                        If is return sse stream
///                                   ｜
/// ------------(No)-------------               ------(Yes)------
///              |                                      |
///              | -----------------------Dio(Interceptor SSEProcessor)Receive native stream data---------------------
///       Response Interceptor                          |                                                            |
///              |                              SSECore(Parse stream data transform to sse)    ----------------------- SSEConnectManager
///       Error Interceptor                             ｜                                                           |
///              |                         SSEFilterService (The client processes,cutting and merging) --------------
///            Response                                 ｜                                                           |
///                                             SSECacheDeliverer（Cache SSE and deliver it into interceptor）--------
///                                                     ｜
///                                         SSEInterceptorManager(Deliver SSE to receiver)
///                                                     ｜
///                                               SSEInterceptor(SSE)
///
/// [SSEProcessor] is responsible parse sse stream data, cache sse and deliver sse to corresponding receiver. It also provide a connect manager by [SSEConnectManager]
///
/// [SSEProcessor] it's actually a dio interceptor, In order to associate the stream received after the dio component initiates a network request.
///
/// There is a [SSEProcessor._agentStream] parameter, it give a change to load data from outside data (Maybe is real stream or mock, Follow [ISSEStream] interface)
///
/// This class depend on 5 core class to operation. (Stream manager [SSECore], Cache manager [SSECacheDeliverer], Interceptor manager [SSEInterceptorManager], Connection state manager [SSEConnectManager],
/// A bridge class transform from native net request stream [SSEBridge])
///
/// Below will introduce them detail.
///
/// Stream management [SSECore] : Responsible open a stream, transform stream to [ServerSentEvent], when completing a complete parsing [ServerSentEvent], package as [ServerSentEventCache] put to [SSECacheDeliverer].
///
/// Stream adapter [StreamAdapter[ : At first, the format of the streaming data issued by the server side was fixed.
/// However, later, different business scenarios would have different formats of streaming data. Externally,
/// it is desired to use the same [ServerSentEvent] format.
/// Therefore, a custom protocol conversion mechanism is provided here for the upper-layer business to use.
///
/// Cache management [SSECacheDeliverer] : This will loop deliver [ServerSentEventCache] to [SSEInterceptorManager] by timer. It provide some feature. Such as set interval, set active and pause deliver state.
///
/// Now have 2 chance to flush cache data, send to the interceptors that meets the requirements.
/// Chance 1, When after add sse interceptor, this hope to guarantee added interceptor will receive cache sse data instantly.
/// Change 2, Switch deliver state [DelivererState.active] by [SSECacheDeliverer.setState]
///
/// About cache auto remove : Now each [ServerSentEventCache] will generate a time stamp, when remove a [ServerSentEventCache] from cache by [SSEInterceptor] return [SSEResponse],
/// Before this time stamp cache sse will auto remove.
///
/// This action is for guarantee cache pool doesn't exist redundancy cache event, but there are some special situation. You can use [SSEResponse] to prevent auto remove. More detail please link to [SSEResponse]
///
/// About cache deliver state switch : cache deliver provide pause and resume ability. Switch by [SSEProcessor.setDeliverState]
/// [DelivererState.active] Active cache event deliver to sse interceptor.
/// [DelivererState.pause] Pause cache event deliver to sse interceptor.
///
/// SSE Interceptor management [SSEInterceptorManager] : [SSECacheDeliverer] delivered sse will to match interceptor, first according to [SSEInterceptor.watchEvents] match sse.
/// Then create a responsible chain [SSEChain], delivered sse according order in [SSEChain], [SSEInterceptor] that in [SSEChain] will invoke [SSEInterceptor.intercept] process it.
/// [SSEChain.proceed] invoke in [SSEInterceptor] will continue deliver to next interceptor. If return [SSEResponse] straightway will break off deliver in [SSEChain].
///
/// [SSEResponse.removeCache] As whether remove from cache pool. (Generally need to remove)
/// [SSEResponse.autoRemove] Whether auto remove from cache pool. This flag only available when [removeCache] is false, set ture is auto remove event according to last time stamp matched. false will wait interceptor
/// to remove it.
///
/// Connection state management [SSEConnectManager] : Responsible switch connection state by sse stream state, add and remove connection state observer.
/// Add connection observer [SSEConnectManager.addConnectStateObserver] call back as [ConnectState] to receive new connection state.
/// [SSEConnectManager.removeConnectStateObserver] remove when appropriate time.
///
/// * About interceptor auto remove mechanism *
/// In order to receive hopeless sse, For example, add an interceptor receive A event, then an interceptor is created to receive A event, Now deliver A event will notified previous two interceptors,
/// maybe you expect not like as. For meet this situation, provide auto remove interceptors mechanism. [SSEInterceptor.autoClean] represent whether auto remove when appropriate time.
/// (This appropriate time will change according requirement in the future)
///
/// Now auto remove mechanism refer to [SSEChain.deliver]
///
/// Native sse stream bridge [SSEBridge] : Cache byte stream from native, create new stream to [SSECore], Thought dio to adapt it.
///
/// [Sio] It it mainly used to replace Dio to perform network requests that can receive streaming data, avoiding requests for streaming data in A module and receiving streaming data in
/// B module (another module).
/// It also supports receiving json format data return from server side, completely according wishes of server side,
/// usually api request error will return json format response data.
///
/// Way of use:
///
/// Step 1：Init config
///
/// SSEProcessor.init(SSEProcessorConfig config, Dio dio);
///
/// Step 2：Add connection state observer
///
/// sseProcessor.addConnectStateObserver();
///
/// Step 3：Add sse interceptors
///
/// sseProcessor.addSSEInterceptor();
///
/// Step 4: Request stream, Now send request that support response stream by retrofit. Associating dio must use the dio object passed in at initialization.
///
///   @GET("/v2/interaction/keep-on/{sessionId}")
///   @Headers(<String, dynamic>{
///     'Accept': 'text/event-stream',
///     'Client-Api-Timeout': 1000 * 60 * 2,
///   })
///  Future<dynamic> keepOn(@Path("sessionId") int sessionId, {@Query('npc') String? npc, @Query('batch') bool? batch, @Query('useDice') bool? useDice});
///
/// Step 5：destroy resource
///
/// sseProcessor.destroy()
///
/// * This mode compared with Stream *
///
/// In Flutter, Stream itself also provides transformation and distribution functions, but there are some limitations.
/// There are two types of Streams here. One is the Single subscription stream, and the other is the Broadcast Stream.
/// The Single subscription stream is abandoned first because it can only have one listener registered.
/// The Broadcast Stream also cannot meet the requirements. Although it can register multiple Listeners,
/// it cannot guarantee to receive all events in the stream and has no concept of priority.
/// So simply using Stream for distribution does not meet the requirements.
/// (In addition to the deficiencies mentioned above, there are many other places that cannot be satisfied)

SSEProcessor get sseProcessor {
  assert(SSEProcessor.sseProcessorFactory != null,
      "SSEProcessor not init, please call SSEProcessor.init first");
  SSEProcessor? sseProcessor = SSEProcessor.sseProcessorFactory?.call();
  assert(sseProcessor != null,
      "delegate error, Please check whether the delegate parameter is operating correctly");
  return sseProcessor!;
}

SSEProcessor? get sseProcessorNullable {
  SSEProcessor? sseProcessor = SSEProcessor.sseProcessorFactory?.call();
  return sseProcessor;
}

bool isInitSSEProcessor() {
  return SSEProcessor.sseProcessorFactory?.call() != null;
}

typedef SSEProcessorFactory = SSEProcessor? Function();

final class SSEProcessor extends Interceptor implements Destroyable {
  static const tag = "SSEProcessor";
  static const tagDeliver = "SSEDeliver";

  static const jsonEndTag = ">s";

  static const eventStreamOpen = "697";
  static const eventStreamOpenLogId = "69602";

  /// *Warning* : This value couldn't set too small (maybe 0 or 1), if set too small will lead to stream end quickly,
  /// when stream end will remove all interceptors that type is [AutoClearStrategy.stream] or [AutoClearStrategy.streamAndFull]
  /// these interceptors remove early lead to loss useful data that they want to receive.
  static const fastLoadInterval = 10;

  /// The application usually uses the [sseProcessorFactory] object create a [SSEProcessor] to receive sse events, because the early theater only runs one, usually only one [SSEProcessor],
  /// so the structure is designed according to the singleton, currently for multiple theater situations,
  /// still want to extend the singleton use mode, to avoid major changes.
  static SSEProcessorFactory? sseProcessorFactory; // Must be set.

  static const _errorTransformingMsg = 'stream is transforming';

  static bool isInitDelegate() {
    SSEProcessor? sp = sseProcessorFactory?.call();
    return sp != null && sp.isInit();
  }

  static void setProcessorFactory(SSEProcessorFactory? factory) {
    SSEProcessor.sseProcessorFactory = factory;
  }

  static void clearProcessorFactory() {
    SSEProcessor.sseProcessorFactory = null;
  }

  late final SSECacheDeliverer _sseCacheDeliverer;
  late final SSEInterceptorManager _interceptorManager = SSEInterceptorManager();
  late final SSEConnectManager _connectManager = SSEConnectManager();
  late final SSEFilterService _filterService = SSEFilterService();
  late final StreamAdapterService _adapterService = StreamAdapterService();
  ISSEStream? _sseStream;
  final Map<String, ISSEStream> _agentStreams = {};
  late final SSEBridge _sseBridge = SSEBridge();
  late final Sio _sio;

  SSEProcessorConfig? _sseConfig;

  final NativeStreamRouter _streamRouter = NativeStreamRouter();

  final RxBool _streamTransforming = false.obs; // 流是否正在接收

  late Dio _dio;

  late final List<Destroyable> _releaseAbles = [];

  /// Determine the sse active timeout period
  late double _idleTimeout;

  /// abnormal connection status
  late int _exceptionTimeout;

  /// Used to compute connection active state time stamp
  int _sseActiveTimeStamp = 0;

  /// Serves the fast distribution function，use it when recover normal speed.
  int _backupDeliverInterval = fastLoadInterval;

  Sio get sio {
    return _sio;
  }

  /// This method is used within the module and needs to ensure that it is not null.
  /// If there is an external call involved, the [isInit] method needs to be called first to check the status.
  SSEProcessorConfig get sseConfig {
    return _sseConfig!;
  }

  SSEProcessorConfig? get sseConfigNullable {
    return _sseConfig;
  }

  SSEBridge get sseBridge {
    return _sseBridge;
  }

  bool isInit() {
    return _sseConfig != null;
  }

  ///  A flag represent sse cache loop is dispatching event to sse interceptor.
  ///
  ///   streamTransforming     isDelivering
  ///           \                   \
  /// (Server) ----> (Cache Pool) -----> (Interceptor)
  bool get isDelivering {
    return _sseCacheDeliverer.isDelivering;
  }

  bool get isFastDeliver {
    return _backupDeliverInterval != fastLoadInterval;
  }

  /// get the sse dispatch state (active or pause)
  DelivererState get delivererState {
    return _sseCacheDeliverer.state;
  }

  /// A flag represent stream is transforming, meaning data is receiving from server.
  bool get streamTransforming {
    final anyAgentStreamTransforming =
        _agentStreams.values.any((stream) => stream.isTransforming().value);
    return _streamTransforming.value || anyAgentStreamTransforming;
  }

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) async {
    void registerIdleObs() {
      if (_sseCacheDeliverer.idleObserver == null) {
        _updateActiveTimeStamp();
        _sseCacheDeliverer.setIdleObserver(() {
          int idleInterval = DateTime.now().millisecondsSinceEpoch - _sseActiveTimeStamp;
          if (idleInterval > _idleTimeout) {
            if (idleInterval > _exceptionTimeout) {
              _changeConnectState(ConnectState.connectException);
            } else {
              _changeConnectState(ConnectState.connectIdle);
            }
          }
        });
      }
    }

    bool checkShouldConnectState(String requestUrl) {
      slog.df("check should connect state url $requestUrl", tag: tag);
      if (_sseConfig!.unCheckConnectStatePaths != null) {
        for (String path in _sseConfig!.unCheckConnectStatePaths!) {
          if (requestUrl.contains(path)) {
            slog.df("state detection should not be performed $requestUrl", tag: tag);
            return false;
          }
        }
      }
      return true;
    }

    if (options.isStream() && _streamTransforming.value) {
      slog.d("reject request url ${options.uri}, because stream is transforming", tag: tag);
      handler.reject(DioException(
          error: _errorTransformingMsg,
          requestOptions: options,
          message: "stream is transforming"));
    } else {
      if (options.isStream()) {
        slog.df("onRequest invoke url ${options.uri}", tag: tag);
        _sseBridge.work();
        if (checkShouldConnectState(options.uri.toString())) {
          registerIdleObs();
        }
        _disconnect();
        _streamTransforming.value = true;
        if (options.isOfflineStream()) {
          slog.df("request was offline mode ${options.uri}", tag: tag);
          // Don't care the actual content of the ResponseBody
          // because the data read in onResponse comes from external settings.(SseOfflineProvider)
          handler.resolve(
              Response(requestOptions: options, data: ResponseBody.fromString('', 200)), true);
          return;
        }
      }
      handler.next(options);
    }
  }

  @override
  void onResponse(Response response, ResponseInterceptorHandler handler) async {
    Future appendStreamDone() async {
      List<ServerSentEvent> filteredList =
          await _filterService.resolve(SSEAutoRemoveInterceptor.genAutoRemoveSSE());
      _resolveSseEvent(filteredList, response.requestOptions.path, toPeek: true);
    }

    Future appendStreamOpen() async {
      ServerSentEvent sse = ServerSentEvent(
          elementType: eventStreamOpen, sessionLogId: eventStreamOpenLogId, result: "client_mock");
      List<ServerSentEvent> filteredList = await _filterService.resolve(sse);
      _resolveSseEvent(filteredList, response.requestOptions.path, toPeek: true);
    }

    slog.d("start resolve response", tag: tag);
    if (response.requestOptions.isStream() && response.data is ResponseBody) {
      slog.d("open stream url : ${response.requestOptions.uri}", tag: tag);
      Stream stream = (response.data as ResponseBody)
          .stream
          .map((event) => event.toList())
          .transform(utf8.decoder);
      if (response.requestOptions.isOfflineStream()) {
        _sseStream = response.requestOptions.getOfflineStream()!.onOfflineStream();
      } else {
        _sseStream = SSECore(stream, adapterService: _adapterService);
      }
      _sseCacheDeliverer.reset();
      _sseStream?.open(
          onOpened: () async {
            await appendStreamOpen();
          },
          onReceive: (event) async {
            List<ServerSentEvent> filteredList = await _filterService.resolve(event);
            _resolveSseEvent(filteredList, response.requestOptions.path, toPeek: true);
          },
          onDone: (list) async {
            await appendStreamDone();
            slog.df("stream transform done", tag: tag);
            _streamTransforming.value = false;
            _changeConnectState(ConnectState.connectSuspend);
            _sseCacheDeliverer.flushPeek(pop: (sseC) {
              _interceptorManager.deliver(sseC, isPeek: true);
            });
            _filterService.reset();
            _sseBridge.offWork();
          },
          onError: (e) async {
            await appendStreamDone();
            slog.df("stream transform error $e", tag: tag);
            _handleConnectError();
            _streamTransforming.value = false;
            _filterService.reset();
            _sseBridge.offWork();
          },
          requestOptions: response.requestOptions);
    } else {
      /// A specific scenario where the client requests stream data and the server does not return stream data.
      if (response.requestOptions.isStream()) {
        _streamTransforming.value = false;
      }
      slog.d("response is not stream format", tag: tag);
    }
    handler.next(response);
  }

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) {
    slog.df("onError invoke err $err", tag: tag);
    // If error was thrown from sse processor and its type is [_errorTransformingMsg],
    // we should ignore it, but is not, should reset [_streamTransforming] flag.
    if (err.error != _errorTransformingMsg) {
      _handleConnectError();
      if (err.requestOptions.isStream()) {
        _streamTransforming.value = false;
      }
    }
    handler.next(err);
  }

  @override
  void reset() {
    slog.df("reset invoke", tag: tag);
    _releaseAbles.reset();
    _sseStream?.reset();
    _agentStreams.forEach((key, value) {
      value.reset();
    });
    _disconnect();
  }

  @override
  void destroy() {
    slog.df("destroyed", tag: tag);
    _streamRouter.unRegister(_sseBridge);
    _releaseAbles.destroy();
    _sseStream?.destroy();
    _agentStreams.forEach((key, value) {
      value.destroy();
    });
    _disconnect();
    _dio.interceptors.remove(this);
    _dio.close(force: true);
  }

  /// Initialization method, which must be called during use
  /// [config] Configuration information used to config such as version number, logFileName, debug mode etc.
  /// [dio] Associated with dio, currently [SSEProcessor] acts as an interceptor in dio component
  void init(SSEProcessorConfig config, Dio dio) {
    _sseConfig = config;
    _idleTimeout = config.idleTimeout;
    _exceptionTimeout = config.exceptionTimeout;
    _dio = dio;
    _dio.interceptors.add(this);
    slog.init(fileName: config.logFileName, debugAble: config.debug, onLog: config.onLog);
    _sio = Sio(_dio, _interceptorManager, this, _filterService);
    _sseBridge.debugTag = config.debugTag;
    _sseCacheDeliverer = SSECacheDeliverer(
        sseBufferExtractInterval: config.sseBufferExtractInterval,
        eleTypesInInterval: _sseConfig?.eleTypesInInterval);
    _releaseAbles
      ..add(_sseCacheDeliverer)
      ..add(_interceptorManager)
      ..add(_connectManager)
      ..add(_filterService)
      ..add(_sseBridge);
    if (_sseConfig!.streamAdapter != null) {
      _adapterService.adapter = _sseConfig!.streamAdapter!;
    }
    _sseBridge.init();
    _interceptorManager.addSSEInterceptor(SSEAutoRemoveInterceptor(_interceptorManager));
    if (config.sseFilter != null) {
      _filterService.setFilter(config.sseFilter!, permanent: true);
    }
    _streamRouter.register(_sseBridge);
    slog.df("init config $config dio info ${_dio.interceptors}", tag: tag);
  }

  void clearCache() {
    _sseCacheDeliverer.clearCache();
    _interceptorManager.removeStreamInterceptor();
  }

  /// Support dynamic change idle timeout value, for show loading time that no data transfer.
  void setIdleTimeout(double idleTimeout) {
    _idleTimeout = idleTimeout;
  }

  /// Set interval time that deliver sse in cache pool
  void setDeliverInternal(int sseBufferExtractInterval) {
    _sseCacheDeliverer.sseBufferExtractInterval = sseBufferExtractInterval;
  }

  /// Sometime need to load entire message, no need display word by word.
  void enableFastDeliver() {
    if (_sseCacheDeliverer.sseBufferExtractInterval != fastLoadInterval) {
      slog.d("enable fast deliver", tag: tag);
      _backupDeliverInterval = _sseCacheDeliverer.sseBufferExtractInterval;
      _sseCacheDeliverer.sseBufferExtractInterval = fastLoadInterval;
    }
  }

  void disableFastDeliver() {
    if (_backupDeliverInterval != fastLoadInterval) {
      slog.d("disable fast deliver", tag: tag);
      _sseCacheDeliverer.sseBufferExtractInterval = _backupDeliverInterval;
      _backupDeliverInterval = fastLoadInterval;
    }
  }

  /// Set agent stream, support set outside stream for dispatch sse. (for example sse from db)
  void setAgentStream(String key, ISSEStream agentStream) {
    _agentStreams.putIfAbsent(key, () => agentStream);
  }

  /// Set a stream adapter for resolve raw data from server stream, more details reference to [StreamAdapter]，
  void setStreamAdapter(StreamAdapter? adapter) {
    _adapterService.adapter = adapter;
  }

  /// Open agent stream, support set outside stream for dispatch sse. (for example sse from db)
  /// [key] is an identity marker that is associated with the agentStream.
  /// [agentStream] takes on the proxy responsibility and is responsible for the logic of external conversion of SSE streams
  /// [goCachePool] is put in cache pool then deliver sse
  /// [autoRemove] remove [agentStream] in [_agentStreams] when stream end
  /// [supportPeekDispatch] Directly distribute to the interceptors that support peek mode, it only take effect when [goCachePool] is true.
  void openAgentStream(String key,
      {ISSEStream? agentStream,
      bool goCachePool = false,
      bool autoRemove = false,
      bool supportPeekDispatch = true,
      ValueChanged<List<ServerSentEvent>>? onDone}) {
    slog.df("open agent stream key $key", tag: tag);
    if (agentStream != null) {
      _agentStreams.putIfAbsent(key, () => agentStream);
    }
    _sseCacheDeliverer.reset();
    ISSEStream? stream = _agentStreams[key];
    stream?.open(onReceive: (event) async {
      if (goCachePool) {
        _resolveSseEvent([event], "", toPeek: supportPeekDispatch);
      } else {
        _deliverSSEC(ServerSentEventCache(event, ""));
      }
    }, onDone: (list) async {
      _resolveSseEvent([SSEAutoRemoveInterceptor.genAutoRemoveSSE()], "");
      slog.df("stream transform done", tag: tag);
      onDone?.call(list);
      if (autoRemove) {
        stream.destroy();
        _agentStreams.remove(key);
      }
    }, onError: (e) {
      _resolveSseEvent([SSEAutoRemoveInterceptor.genAutoRemoveSSE()], "");
      slog.df("stream transform error $e", tag: tag);
      _handleConnectError();
    });
  }

  /// Very rare usage scenario, for example i want to replace some scatter sse to one gathered sse.
  /// This function support the story : https://pm.ifitu.co/issues/19143
  /// [fromHit] is function to remove when match the rule, according return result, true will be delete.
  /// [toEvent] will be insert to sse cache head of [SSECacheDeliverer]
  void replaceSSEInCache(
      bool Function(ServerSentEventCache element) fromHit, ServerSentEvent toEvent) {
    if (toEvent.isIllegal()) {
      slog.df("resolve event illegal : $toEvent", tag: tag);
      return;
    }
    slog.df("replace sse cache : $toEvent", tag: tag);
    _sseCacheDeliverer.replace(fromHit, toEvent);
    _sseCacheDeliverer.flush(pop: _deliverSSEC);
  }

  /// Set cache deliver state, pause dispatch support. [DelivererState.active] continue dispatch，[DelivererState.pause] pause dispatch.
  void setDeliverState(DelivererState state, {bool isForce = false}) {
    _sseCacheDeliverer.setState(state, isForce: isForce);
    if (state == DelivererState.active) {
      _sseCacheDeliverer.flush(pop: _deliverSSEC);
    }
  }

  /// Add observer listen connection change
  /// More detail state refer [ConnectState]
  void addConnectStateObserver(SSEConnectObserver observer) {
    _connectManager.addConnectStateObserver(observer);
  }

  /// Remove connection observer, to free up memory resource, unused observer need to remove.
  void removeConnectStateObserver(SSEConnectObserver observer) {
    _connectManager.removeConnectStateObserver(observer);
  }

  /// Add SSE interceptor to listen sse dispatch. usually receive sse from cache pool, sse will dispatch to [SSEInterceptor.intercept]
  /// if need to receive from server sse immediately, please refer [SSEInterceptor.isPeek] parameter.
  /// [isOnly] represent [interceptor] don't support add multiple times by same [SSEInterceptor.name].
  void addSSEInterceptor(SSEInterceptor interceptor, {bool isOnly = false}) {
    bool result = _interceptorManager.addSSEInterceptor(interceptor, isOnly: isOnly);
    if (result) {
      if (interceptor.isPeek) {
        _sseCacheDeliverer.flushPeek(pop: (sseC) {
          _interceptorManager.deliver(sseC, isPeek: true);
        });
      }
      _sseCacheDeliverer.flush(pop: _deliverSSEC, breakLoop: true);
    }
  }

  /// Remove sse interceptor from [SSEInterceptorManager], usually you don't need to care remove invoke, [SSEProcessor] support automatic remove mechanism.
  /// please refer [SSEInterceptor.autoClearStrategy] parameter.
  void removeSSEInterceptor(SSEInterceptor interceptor) {
    _interceptorManager.removeSSEInterceptor(interceptor);
  }

  /// Toggle to suspend connection state.
  /// Long time not dispatch sse don't trigger switch to [ConnectState.connectIdle] and [ConnectState.connectException] in [ConnectState.connectSuspend].
  void suspendConnect() {
    _changeConnectState(ConnectState.connectSuspend);
  }

  /// Toggle to active connection state.
  void activeConnect() {
    _changeConnectState(ConnectState.connectActive, force: true);
  }

  void _updateActiveTimeStamp() {
    _sseActiveTimeStamp = DateTime.now().millisecondsSinceEpoch;
  }

  /// Resolve sse from server, put sse to cache pool to dispatch to interceptor chain.
  void _resolveSseEvent(List<ServerSentEvent> events, String reqUrl, {bool toPeek = false}) {
    slog.df("put to sse cache : $events toPeek $toPeek", tag: tag);
    Iterable<ServerSentEvent> okIterable = events.where((ele) {
      bool legal = ele.isLegal();
      if (!legal) {
        slog.df("format exception sse: $ele", tag: tag);
      }
      return legal;
    });
    if (toPeek) {
      _sseCacheDeliverer.putPeek(okIterable, reqUrl: reqUrl);
    }
    _sseCacheDeliverer.put(okIterable, reqUrl: reqUrl, pop: _deliverSSEC);
  }

  PopRep _deliverSSEC(ServerSentEventCache event) {
    DeliverRep deliverRep = _interceptorManager.deliver(event);
    if (deliverRep.sseResponse.removeCache) {
      _changeConnectState(ConnectState.connectActive);
      _updateActiveTimeStamp();
    }
    return PopRep(deliverRep.sseResponse.removeCache, deliverRep.sseResponse.autoRemove,
        deliverRep.notifiedInterceptors);
  }

  void _handleConnectError() {
    _changeConnectState(ConnectState.disconnectError);
  }

  void _disconnect() {
    _changeConnectState(ConnectState.disconnectNormal);
  }

  void _changeConnectState(ConnectState connectState, {bool force = false}) {
    if (_sseCacheDeliverer.state != DelivererState.active &&
        (connectState == ConnectState.connectIdle ||
            connectState == ConnectState.connectException)) {
      // slog.df("$tag cache deliver is pause state, now couldn't change connect state which is idle or exception");
      return;
    }
    // slog.d("try change connect state $connectState", tag: tag);
    if (_connectManager.changeConnectState(connectState, force: force)) {
      _updateActiveTimeStamp();
    }
  }
}
