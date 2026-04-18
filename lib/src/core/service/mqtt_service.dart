import 'dart:async';
import 'dart:convert';
import 'package:mqtt_client/mqtt_client.dart';
import 'package:mqtt_client/mqtt_server_client.dart';
import '../utils/platform_utils.dart';
import 'app_logger.dart';

const _tag = 'MQTT';

/// 消息类型
///
/// - [action]   一次性丢花互动（tulip / daisy / lily / rose / sunflower）
/// - [status]   我的在线状态（online / busy / focus / offline），**retained**
/// - [ambient]  氛围同步
/// - [hello]    上线通知，对端收到后应回传自己的 status；并在 data 中携带地址 JSON
/// - [vase]     共享花瓶事件（追加 / 全量快照）。data 是一段 JSON：
///              `{"op":"add","item":{...}}` 非 retained，广播一次；
///              `{"op":"snap","items":[...]}` **retained**，晚上线方用它初始化。
enum MsgType { action, status, ambient, hello, vase }

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
        data: (map['d'] ?? '').toString(),
        from: map['f'] as String? ?? '',
        timestamp: DateTime.fromMillisecondsSinceEpoch(
          (map['ts'] as num?)?.toInt() ?? DateTime.now().millisecondsSinceEpoch,
        ),
      );
    } catch (_) {
      // 非当前协议格式（脏 retained / 旧版本残留）直接忽略，避免污染事件流。
      return null;
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

  bool _isConnected = false;

  bool get isConnected => _isConnected;

  MqttService({required this.uid, this.topic = 'desktop0001'});

  Future<bool> connect() async {
    // 获取设备唯一标识
    _deviceId = await DeviceId.get();
    AppLogger.i(_tag, '设备标识: $_deviceId');

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
      AppLogger.w(_tag, '正在重连...');
      _setConnected(false);
    };
    client.onAutoReconnected = () {
      AppLogger.i(_tag, '重连成功');
      _setConnected(true);
    };
    client.onDisconnected = () {
      AppLogger.w(_tag, '已断开');
      _setConnected(false);
    };

    try {
      await client.connect();
      if (client.connectionStatus?.state == MqttConnectionState.connected) {
        AppLogger.i(_tag, '连接成功 topic=$topic');
        _setConnected(true);
        client.subscribe(topic, MqttQos.atMostOnce);

        client.updates!.listen((List<MqttReceivedMessage<MqttMessage>> batch) {
          // 同一次 updates 可能携带多条消息；必须逐条处理，不能只取第一条。
          for (final entry in batch) {
            final recMess = entry.payload as MqttPublishMessage;
            final payload = MqttPublishPayload.bytesToStringAsString(recMess.payload.message);
            final msg = TelepathyMessage.decode(payload);
            if (msg == null) {
              AppLogger.w(_tag, '忽略非协议消息: $payload');
              continue;
            }
            // 过滤掉自己设备发的消息（retained 的 LWT 也会被过滤）
            if (msg.from == _deviceId) continue;
            AppLogger.d(_tag, '收到 ${msg.from}: ${msg.type.name}=${msg.data}');

            _msgController.add(msg);
          }
        });

        return true;
      }
    } catch (e) {
      AppLogger.e(_tag, '连接失败: $e');
    }
    _setConnected(false);
    return false;
  }

  void _setConnected(bool value) {
    _isConnected = value;
  }

  void send(
    TelepathyMessage msg, {
    bool retain = false,
    MqttQos qos = MqttQos.atMostOnce,
  }) {
    if (!_isConnected) return;
    final builder = MqttClientPayloadBuilder();
    final encoded = msg.encode(_deviceId);
    builder.addString(encoded);
    client.publishMessage(topic, qos, builder.payload!, retain: retain);
    AppLogger.d(_tag, '发送${retain ? '(retained)' : ''}: ${msg.type.name}=${msg.data}');
  }

  void sendAction(String action) => send(TelepathyMessage(type: MsgType.action, data: action));

  /// 状态用 retained 发布，保证晚加入的订阅者立刻拿到我们的在线状态。
  void sendStatus(String status) => send(
    TelepathyMessage(type: MsgType.status, data: status),
    retain: true,
    qos: MqttQos.atLeastOnce,
  );

  void sendAmbient(String ambient) => send(TelepathyMessage(type: MsgType.ambient, data: ambient));

  /// 花瓶：追加一个物品（非 retained，一次性广播）。
  /// 调用前通常已在本地 state 里加入并重新发了一次 [sendVaseSnapshot]。
  void sendVaseAdd(String itemJson) {
    final payload = jsonEncode({'op': 'add', 'item': jsonDecode(itemJson)});
    send(TelepathyMessage(type: MsgType.vase, data: payload));
  }

  /// 花瓶：全量快照（retained，覆盖历史）。晚上线的一方会从这里读到当前状态。
  void sendVaseSnapshot(List<Map<String, dynamic>> items) {
    final payload = jsonEncode({'op': 'snap', 'items': items});
    send(TelepathyMessage(type: MsgType.vase, data: payload), retain: true);
  }

  void dispose() {
    // 注意：LWT 只在“非优雅断开”才会由 broker 代发。
    // 对于主动关闭 app，这里显式发 retained offline（QoS1）保证对端尽快感知。
    if (_isConnected) {
      try {
        sendStatus('offline');
      } catch (_) {}
    }
    client.disconnect();
    _msgController.close();
  }
}
