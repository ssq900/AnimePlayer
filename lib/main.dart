import 'dart:io';
import 'package:flutter/material.dart';
import 'pages/home_page.dart';
import 'services/notification_service.dart'; // 新增

void main() async {
  WidgetsFlutterBinding.ensureInitialized(); // 新增
  await NotificationService.init(); // 新增
  HttpOverrides.global = _MyHttpOverrides();
  runApp(const AnimeApp());
}

class _MyHttpOverrides extends HttpOverrides {
  @override
  HttpClient createHttpClient(SecurityContext? context) {
    return super.createHttpClient(context)
      ..findProxy = (uri) {
        final host = uri.host;
        final noProxy = Platform.environment['no_proxy'] ?? Platform.environment['NO_PROXY'];
        if (noProxy != null && noProxy.isNotEmpty) {
          final domains = noProxy.split(',');
          for (final d in domains) {
            if (host.endsWith(d.trim())) return 'DIRECT';
          }
        }
        String? proxy = Platform.environment['https_proxy'] ?? 
                         Platform.environment['http_proxy'] ?? 
                         Platform.environment['HTTP_PROXY'];
        if (proxy != null && proxy.isNotEmpty) {
          String cleanProxy = proxy;
          if (cleanProxy.startsWith('http://')) cleanProxy = cleanProxy.substring(7);
          if (cleanProxy.startsWith('https://')) cleanProxy = cleanProxy.substring(8);
          if (cleanProxy.endsWith('/')) cleanProxy = cleanProxy.substring(0, cleanProxy.length - 1);
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
