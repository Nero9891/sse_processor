import '../../destroyable.dart';
import '../../sse_log.dart';
import '../sse_connect_exposure.dart';

final class SSEConnectManager implements Destroyable {
  static const tag = "SSEConnectManager";

  final List<SSEConnectObserver> _connectObservers = [];

  /// Current connection status
  ConnectState _connectState = ConnectState.disconnectNormal;

  ConnectState get connectState {
    return _connectState;
  }

  @override
  void destroy() {
    _connectObservers.clear();
  }

  @override
  void reset() {
    _connectObservers.clear();
  }

  /// State detail ref : [ConnectState]
  void addConnectStateObserver(SSEConnectObserver observer) {
    slog.df("add connect observer $observer", tag: tag);
    _connectObservers.removeWhere((element) => element.name == observer.name);
    _connectObservers.add(observer);
  }

  void removeConnectStateObserver(SSEConnectObserver observer) {
    slog.df("remove connect observer $observer", tag: tag);
    _connectObservers.remove(observer);
  }

  ///Change connect state and notify outside register observers.
  bool changeConnectState(ConnectState connectState, {bool force = false}) {
    if (!force) {
      if (_connectState == ConnectState.connectSuspend) {
        if (connectState == ConnectState.connectException ||
            connectState == ConnectState.connectIdle ||
            connectState == ConnectState.connectActive) {
          return false;
        }
      }
      if (_connectState == ConnectState.disconnectNormal) {
        if (connectState == ConnectState.connectException) {
          return false;
        }
      }
      if (_connectState == ConnectState.connectException ||
          _connectState == ConnectState.disconnectError) {
        if (connectState == ConnectState.connectIdle) {
          return false;
        }
      }
    }
    if (_connectState != connectState) {
      // vlog.d("change connect state $_connectState, preconnectState:$connectState, force:$force",
      //     tag: tag);
      _connectState = connectState;

      // slog.df("change connect state $_connectState", tag: tag);
      _connectObservers.sort();
      for (var element in _connectObservers) {
        if (element.onConnectStateChange(_connectState)) {
          break;
        }
      }
      return true;
    } else {
      return false;
    }
  }

  /// Check is connection state.
  bool isConnect() {
    return _connectState == ConnectState.connectActive ||
        _connectState == ConnectState.connectIdle ||
        _connectState == ConnectState.connectException ||
        _connectState == ConnectState.connectSuspend;
  }
}
