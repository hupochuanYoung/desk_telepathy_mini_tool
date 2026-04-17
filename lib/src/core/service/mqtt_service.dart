import 'dart:async';
import 'dart:convert';
import 'package:mqtt_client/mqtt_client.dart';
import 'package:mqtt_client/mqtt_server_client.dart';
import '../utils/platform_utils.dart';

/// 消息类型
///
/// - [action]  一次性互动（knock / heart / ...）
/// - [status]  我的在线状态（online / busy / focus / offline），**retained**
/// - [ambient] 氛围同步
/// - [hello]   上线通知，对端收到后应回传自己的 status
enum MsgType { action, status, ambient, hello }

/// MQTT 消息体
class TelepathyMessage {
  final MsgType type;
  final String data;
  final String from; // 发送者设备标识，如 "mac:MacBook Pro"
  final DateTime timestamp;

  TelepathyMessage({required this.type, required this.data, this.from = '', DateTime? timestamp})
    : timestamp = timestamp ?? DateTime.now();

  String encode(String deviceId) =>
      jsonEncode({'t': type.name, 'd': data, 'f': deviceId, 'ts': timestamp.millisecondsSinceEpoch});

  static TelepathyMessage? decode(String raw) {
    try {
      final map = jsonDecode(raw) as Map<String, dynamic>;
      return TelepathyMessage(
        type: MsgType.values.firstWhere((e) => e.name == map['t']),
        data: map['d'] as String,
        from: map['f'] as String? ?? '',
        timestamp: DateTime.fromMillisecondsSinceEpoch(map['ts'] as int),
      );
    } catch (_) {
      return TelepathyMessage(type: MsgType.action, data: raw);
    }
  }

  /// 构造一条 LWT 用的遗嘱消息（无需 from，LWT 在连接阶段序列化一次）
  static String encodeLwt(String deviceId, String data) =>
      jsonEncode({'t': MsgType.status.name, 'd': data, 'f': deviceId, 'ts': DateTime.now().millisecondsSinceEpoch});
}

class MqttService {
  late MqttServerClient client;
  final String uid;
  final String topic;

  /// 当前设备标识，connect() 时初始化
  late String _deviceId;

  String get deviceId => _deviceId;

  final _msgController = StreamController<TelepathyMessage>.broadcast();

  Stream<TelepathyMessage> get messages => _msgController.stream;

  final _connectionController = StreamController<bool>.broadcast();

  Stream<bool> get connectionStream => _connectionController.stream;

  bool _isConnected = false;

  bool get isConnected => _isConnected;

  /// 记住本端最新的状态，用于重连后重播 / 响应 hello
  String _myStatus = 'online';

  MqttService({required this.uid, this.topic = 'desktop0001'});

  Future<bool> connect() async {
    // 获取设备唯一标识
    _deviceId = await DeviceId.get();
    print('[MQTT] 设备标识: $_deviceId');

    client = MqttServerClient('bemfa.com', uid);
    client.port = 9501;
    client.keepAlivePeriod = 60;
    client.logging(on: false);
    client.autoReconnect = true;

    // 遗嘱消息：异常断开时，broker 会代我们发一条 retained 的 offline 状态，
    // 对端因此能感知到我们掉线。
    //
    // 注意：bemfa.com 用 clientIdentifier 做鉴权，必须等于 uid(私钥)，
    // 否则会返回 MqttConnectReturnCode.notAuthorized。
    // 设备区分通过消息体里的 from 字段实现。
    client.connectionMessage = MqttConnectMessage()
        .withClientIdentifier(uid)
        .withWillTopic(topic)
        .withWillMessage(TelepathyMessage.encodeLwt(_deviceId, 'offline'))
        .withWillQos(MqttQos.atLeastOnce)
        .withWillRetain()
        .startClean();

    client.onAutoReconnect = () {
      print('[MQTT] 正在重连...');
      _setConnected(false);
    };
    client.onAutoReconnected = () {
      print('[MQTT] 重连成功');
      _setConnected(true);
      _onLinkUp();
    };
    client.onDisconnected = () {
      print('[MQTT] 已断开');
      _setConnected(false);
    };

    try {
      await client.connect();
      if (client.connectionStatus?.state == MqttConnectionState.connected) {
        print('[MQTT] 连接成功！topic: $topic');
        _setConnected(true);
        client.subscribe(topic, MqttQos.atMostOnce);

        client.updates!.listen((List<MqttReceivedMessage<MqttMessage>> c) {
          final recMess = c[0].payload as MqttPublishMessage;
          final payload = MqttPublishPayload.bytesToStringAsString(recMess.payload.message);
          final msg = TelepathyMessage.decode(payload);
          if (msg == null) return;
          // 过滤掉自己设备发的消息（retained 的 LWT 也会被过滤）
          if (msg.from == _deviceId) return;
          print('[MQTT] 收到 ${msg.from} 的消息: $payload');

          // 收到对端的 hello：立刻回传自己最新的 status，帮助对端脱离 offline 态
          if (msg.type == MsgType.hello) {
            sendStatus(_myStatus);
          }

          _msgController.add(msg);
        });

        _onLinkUp();
        return true;
      }
    } catch (e) {
      print('[MQTT] 连接失败: $e');
    }
    _setConnected(false);
    return false;
  }

  /// 连接建立 / 自动重连成功后的握手：
  /// 1. retained 发一次自己的状态 —— 让未来的订阅者立刻拿到
  /// 2. 广播 hello —— 让当前在线的对端主动回传自己的状态
  void _onLinkUp() {
    sendStatus(_myStatus);
    send(TelepathyMessage(type: MsgType.hello, data: ''));
  }

  void _setConnected(bool value) {
    _isConnected = value;
    _connectionController.add(value);
  }

  void send(TelepathyMessage msg, {bool retain = false}) {
    if (!_isConnected) return;
    final builder = MqttClientPayloadBuilder();
    final encoded = msg.encode(_deviceId);
    builder.addString(encoded);
    client.publishMessage(topic, MqttQos.atMostOnce, builder.payload!, retain: retain);
    print('[MQTT] 发送${retain ? '(retained)' : ''}: $encoded');
  }

  void sendAction(String action) => send(TelepathyMessage(type: MsgType.action, data: action));

  /// 状态用 retained 发布，保证晚加入的订阅者立刻拿到我们的在线状态。
  void sendStatus(String status) {
    _myStatus = status;
    send(TelepathyMessage(type: MsgType.status, data: status), retain: true);
  }

  void sendAmbient(String ambient) => send(TelepathyMessage(type: MsgType.ambient, data: ambient));

  void dispose() {
    // 优雅退出：retained 写一条 offline，覆盖之前的 online retained。
    // 否则对端再次上线时会读到旧的 online，以为我们还活着。
    if (_isConnected) {
      try {
        sendStatus('offline');
      } catch (_) {}
    }
    client.disconnect();
    _msgController.close();
    _connectionController.close();
  }
}
