import 'dart:convert';

import 'package:http/http.dart' as http;

import 'app_logger.dart';

const _tag = 'Location';

/// 位置信息 —— 来源于 IP 地理定位，城市级精度，无需操作系统权限。
///
/// 字段全部可空：网络失败 / API 封锁时允许降级展示。
class LocationInfo {
  final double? lat;
  final double? lon;
  final String? city;
  final String? region;
  final String? country;

  const LocationInfo({this.lat, this.lon, this.city, this.region, this.country});

  bool get isEmpty => (city ?? '').isEmpty && (region ?? '').isEmpty && (country ?? '').isEmpty;

  /// 展示用字符串，尽量简短：城市 · 国家
  String get display {
    final parts = <String>[];
    if ((city ?? '').isNotEmpty) parts.add(city!);
    if ((country ?? '').isNotEmpty && country != city) parts.add(country!);
    return parts.isEmpty ? '未知' : parts.join(' · ');
  }

  Map<String, dynamic> toJson() => {
    if (lat != null) 'lat': lat,
    if (lon != null) 'lon': lon,
    if (city != null) 'city': city,
    if (region != null) 'region': region,
    if (country != null) 'country': country,
  };

  String encode() => jsonEncode(toJson());

  static LocationInfo? decode(String raw) {
    try {
      final map = jsonDecode(raw) as Map<String, dynamic>;
      return LocationInfo(
        lat: (map['lat'] as num?)?.toDouble(),
        lon: (map['lon'] as num?)?.toDouble(),
        city: map['city'] as String?,
        region: map['region'] as String?,
        country: map['country'] as String?,
      );
    } catch (_) {
      return null;
    }
  }

  @override
  String toString() => display;
}

/// 通过公共 IP 地理定位 API 获取当前位置。
/// 先后尝试多个 provider，提高到达率（尤其国内网络环境）。
class LocationService {
  static const _timeout = Duration(seconds: 6);

  static Future<LocationInfo?> fetch() async {
    for (final provider in _providers) {
      try {
        AppLogger.d(_tag, '尝试 ${provider.name} ...');
        final info = await provider.fetch().timeout(_timeout);
        if (info != null && !info.isEmpty) {
          AppLogger.i(_tag, '${provider.name} 成功: ${info.display}');
          return info;
        }
      } catch (e) {
        AppLogger.w(_tag, '${provider.name} 失败: $e');
      }
    }
    AppLogger.e(_tag, '所有 provider 都失败');
    return null;
  }

  // 只使用 HTTPS 端点，避免 macOS/iOS 的 App Transport Security 拦截
  static final List<_Provider> _providers = [
    _Provider('ipwho.is', () async {
      final res = await http.get(Uri.parse('https://ipwho.is/?lang=zh-CN'));
      if (res.statusCode != 200) return null;
      final j = jsonDecode(res.body) as Map<String, dynamic>;
      if (j['success'] == false) return null;
      return LocationInfo(
        lat: (j['latitude'] as num?)?.toDouble(),
        lon: (j['longitude'] as num?)?.toDouble(),
        city: j['city'] as String?,
        region: j['region'] as String?,
        country: j['country'] as String?,
      );
    }),
    _Provider('ipapi.co', () async {
      final res = await http.get(Uri.parse('https://ipapi.co/json/'));
      if (res.statusCode != 200) return null;
      final j = jsonDecode(res.body) as Map<String, dynamic>;
      return LocationInfo(
        lat: (j['latitude'] as num?)?.toDouble(),
        lon: (j['longitude'] as num?)?.toDouble(),
        city: j['city'] as String?,
        region: j['region'] as String?,
        country: j['country_name'] as String?,
      );
    }),
  ];
}

class _Provider {
  final String name;
  final Future<LocationInfo?> Function() fetch;
  _Provider(this.name, this.fetch);
}
