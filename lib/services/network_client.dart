import 'dart:io';
import 'package:http/io_client.dart';
import 'package:flutter/foundation.dart';

class NetworkClient {
  static final NetworkClient _instance = NetworkClient._internal();
  factory NetworkClient() => _instance;
  NetworkClient._internal();

  // 核心改进：创建专属业务网络客户端，不再污染 video_player 等原生插件
  late final IOClient client = _createClient();

  IOClient _createClient() {
    final httpClient = HttpClient();
    
    httpClient.findProxy = (uri) {
      final host = uri.host.toLowerCase();
      final port = uri.port;
      final noProxy = Platform.environment['no_proxy'] ?? Platform.environment['NO_PROXY'];

      // 解析 no_proxy 白名单
      if (noProxy != null && noProxy.isNotEmpty) {
        for (var d in noProxy.split(',')) {
          d = d.trim().toLowerCase();
          if (d.isEmpty) continue;
          
          String checkHost = d;
          int? checkPort;
          if (d.contains(':')) {
            final parts = d.split(':');
            checkHost = parts[0];
            checkPort = int.tryParse(parts[1]);
          }
          if (checkPort != null && checkPort != port) continue;

          if (checkHost.startsWith('*.')) {
            final suffix = checkHost.substring(2);
            if (host == suffix || host.endsWith('.$suffix')) return 'DIRECT';
          } else if (host == checkHost) {
            return 'DIRECT';
          }
        }
      }

      // 读取代理环境变量
      final envProxy = Platform.environment['https_proxy'] ?? 
                       Platform.environment['http_proxy'] ?? 
                       Platform.environment['HTTP_PROXY'];
                       
      if (envProxy != null && envProxy.isNotEmpty) {
        try {
          final pUri = Uri.parse(envProxy.contains('://') ? envProxy : 'http://$envProxy');
          final proxyHost = pUri.host;
          final proxyPort = pUri.hasPort ? pUri.port : 8080;
          final auth = pUri.userInfo.isNotEmpty ? '${pUri.userInfo}@' : '';
          return 'PROXY $auth$proxyHost:$proxyPort';
        } catch (_) {
          debugPrint('[NetworkClient] Proxy parse failed: $envProxy');
          return 'DIRECT';
        }
      }
      return 'DIRECT';
    };
    
    return IOClient(httpClient);
  }
}
