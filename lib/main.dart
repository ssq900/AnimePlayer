import 'dart:io';
import 'package:flutter/material.dart';
import 'pages/home_page.dart';

void main() {
  // 强制接管代理设置
  HttpOverrides.global = _MyHttpOverrides();
  runApp(const AnimeApp());
}

class _MyHttpOverrides extends HttpOverrides {
  @override
  HttpClient createHttpClient(SecurityContext? context) {
    return super.createHttpClient(context)
      ..findProxy = (uri) {
        // 尝试读取环境变量中的代理（部分 VPN 会注入此变量）
        final proxy = Platform.environment['https_proxy'] ?? 
                      Platform.environment['http_proxy'] ?? 
                      Platform.environment['HTTP_PROXY'];
        return proxy != null ? 'PROXY $proxy' : 'DIRECT';
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
