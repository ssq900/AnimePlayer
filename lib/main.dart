import 'dart:io';
import 'package:flutter/material.dart';
import 'pages/home_page.dart';
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

        // 增强版 no_proxy 匹配逻辑
        if (noProxy != null && noProxy.isNotEmpty) {
          final domains = noProxy.split(',');
          for (var d in domains) {
            d = d.trim().toLowerCase();
            if (d.isEmpty) continue;
            
            String proxyHost = d;
            int? proxyPort;
            if (d.contains(':')) {
              final parts = d.split(':');
              proxyHost = parts[0];
              proxyPort = int.tryParse(parts[1]);
            }
            // 端口不匹配则跳过
            if (proxyPort != null && proxyPort != port) continue;

            if (proxyHost.startsWith('*.')) {
              final suffix = proxyHost.substring(2);
              if (host == suffix || host.endsWith('.$suffix')) return 'DIRECT';
            } else if (host == proxyHost) {
              return 'DIRECT';
            }
          }
        }

        String? proxy = Platform.environment['https_proxy'] ?? 
                         Platform.environment['http_proxy'] ?? 
                         Platform.environment['HTTP_PROXY'];
                         
        if (proxy != null && proxy.isNotEmpty) {
          // 兼容 socks5:// 和 http://，保留 @ 鉴权部分
          String cleanProxy = proxy.replaceFirst(RegExp(r'^[a-zA-Z0-9]+://'), '');
          if (cleanProxy.endsWith('/')) {
            cleanProxy = cleanProxy.substring(0, cleanProxy.length - 1);
          }
          return 'PROXY $cleanProxy';
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
      title: 'Anime Aggregator',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorSchemeSeed: Colors.deepPurple,
        useMaterial3: true,
      ),
      home: const HomePage(),
    );
  }
}
