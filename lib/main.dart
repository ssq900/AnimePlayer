import 'dart:io';
import 'package:flutter/material.dart';
import 'pages/main_layout.dart';
import 'services/notification_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await NotificationService.init();
  HttpOverrides.global = _MyHttpOverrides();
  runApp(const AnimeApp());
}

class _MyHttpOverrides extends HttpOverrides {
  @override
  HttpClient createHttpClient(SecurityContext? context) {
    return super.createHttpClient(context)
      ..findProxy = (uri) {
        final host = uri.host.toLowerCase();
        final port = uri.port;
        final noProxy = Platform.environment['no_proxy'] ?? Platform.environment['NO_PROXY'];

        if (noProxy != null && noProxy.isNotEmpty) {
          final domains = noProxy.split(',');
          for (var d in domains) {
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

        final envProxy = Platform.environment['https_proxy'] ?? Platform.environment['http_proxy'] ?? Platform.environment['HTTP_PROXY'];
        if (envProxy != null && envProxy.isNotEmpty) {
          try {
            // 兼容性修复：使用 Uri 解析，避免字符串截取出错
            final pUri = Uri.parse(envProxy.contains('://') ? envProxy : 'http://$envProxy');
            final proxyHost = pUri.host;
            final proxyPort = pUri.hasPort ? pUri.port : 8080;
            // 保留鉴权信息
            final auth = pUri.userInfo.isNotEmpty ? '${pUri.userInfo}@' : '';
            return 'PROXY $auth$proxyHost:$proxyPort';
          } catch (_) {
            // 解析失败直接忽略代理
            return 'DIRECT';
          }
        }
        return 'DIRECT';
      };
  }
}

class AnimeApp extends StatelessWidget {
  const AnimeApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'AnimePlayer',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(colorSchemeSeed: Colors.deepPurple, useMaterial3: true),
      home: const MainLayout(), // 改为新的框架
    );
  }
}
