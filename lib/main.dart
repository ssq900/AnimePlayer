import 'dart:io';
import 'package:flutter/material.dart';
import 'pages/main_layout.dart';
import 'services/notification_service.dart';
import 'services/storage_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  // 初始化通知与清理临时文件
  await NotificationService.init();
  await StorageService().init();
  
  // 全局代理拦截（注：这会接管所有 HttpClient 请求，包括 video_player 的视频流）
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

        // no_proxy 匹配
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

        // 代理提取
        final envProxy = Platform.environment['https_proxy'] ?? Platform.environment['http_proxy'] ?? Platform.environment['HTTP_PROXY'];
        if (envProxy != null && envProxy.isNotEmpty) {
          try {
            final pUri = Uri.parse(envProxy.contains('://') ? envProxy : 'http://$envProxy');
            final proxyHost = pUri.host;
            final proxyPort = pUri.hasPort ? pUri.port : 8080;
            final auth = pUri.userInfo.isNotEmpty ? '${pUri.userInfo}@' : '';
            // 核心改进：增加代理命中日志，方便用户排查
            debugPrint('[Proxy] Routing $host:$port via $auth$proxyHost:$proxyPort');
            return 'PROXY $auth$proxyHost:$proxyPort';
          } catch (_) {
            debugPrint('[Proxy] Failed to parse proxy string: $envProxy');
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
      theme: ThemeData(
        colorSchemeSeed: Colors.deepPurple,
        useMaterial3: true,
        brightness: Brightness.dark, // 核心 UI 改进：全局默认暗色模式，适配看番场景
      ),
      home: const MainLayout(),
    );
  }
}
