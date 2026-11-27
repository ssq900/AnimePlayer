import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/material.dart';
import 'pages/main_layout.dart';
import 'services/notification_service.dart';
import 'services/storage_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  // 初始化通知与清理临时文件
  await NotificationService.init();
  await StorageService().init();
  
  // 核心修复：彻底移除 HttpOverrides.global，让视频流走系统原生网络栈
  runApp(const AnimeApp());
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
        brightness: Brightness.dark,
      ),
      home: const MainLayout(),
    );
  }
}
