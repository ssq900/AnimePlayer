import 'dart:io';
import 'package:flutter/material.dart';
import 'pages/main_layout.dart';
import 'services/notification_service.dart';
import 'services/storage_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // 1. 初始化存储服务，清理上次意外退出残留的 .tmp 文件
  await StorageService().init();

  // 2. 初始化本地通知插件
  await NotificationService.init();

  // 3. 挂载全局代理与网络安全拦截
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

        // 检查 no_proxy 白名单
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

        // 读取系统环境变量中的代理设置
        final envProxy = Platform.environment['https_proxy'] ?? 
                         Platform.environment['http_proxy'] ?? 
                         Platform.environment['HTTP_PROXY'];
                         
        if (envProxy != null && envProxy.isNotEmpty) {
          try {
            // 使用 Uri 解析，避免字符串截取出错，同时保留鉴权信息
            final pUri = Uri.parse(envProxy.contains('://') ? envProxy : 'http://$envProxy');
            final proxyHost = pUri.host;
            final proxyPort = pUri.hasPort ? pUri.port : 8080;
            final auth = pUri.userInfo.isNotEmpty ? '${pUri.userInfo}@' : '';
            return 'PROXY $auth$proxyHost:$proxyPort';
          } catch (_) {
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
      ),
      home: const MainLayout(),
    );
  }
}
