import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart'; // 新增：引入 Riverpod
import 'pages/main_layout.dart';
import 'services/notification_service.dart';
import 'services/storage_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  // 初始化通知与清理临时文件
  await NotificationService.init();
  await StorageService().init();
  
  // 核心：彻底移除了 HttpOverrides.global
  // 网络代理现在交由 NetworkClient 专属处理，避免污染 video_player 等原生音视频流
  
  // ⚠️ 改动点：用 ProviderScope 包裹你的根组件 AnimeApp
  runApp(const ProviderScope(child: AnimeApp()));
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
        brightness: Brightness.dark, // 全局默认暗色模式
      ),
      home: const MainLayout(),
    );
  }
}
