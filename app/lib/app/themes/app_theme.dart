import 'package:flutter/material.dart';

class AppTheme {
  // 老年友好设计: 大字体 / 高对比度 / 统一颜色标识
  static ThemeData get lightTheme {
    return ThemeData(
      primarySwatch: Colors.blue,
      brightness: Brightness.light,
      
      // 字体设置，最小字号 20sp
      textTheme: const TextTheme(
        displayLarge: TextStyle(fontSize: 32, fontWeight: FontWeight.bold, color: Colors.black87),
        bodyLarge: TextStyle(fontSize: 24, color: Colors.black87),
        bodyMedium: TextStyle(fontSize: 20, color: Colors.black87),
        labelLarge: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Colors.white),
      ),
      
      // 按钮设置，大按钮点击区域
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          minimumSize: const Size(120, 64),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      ),
      
      // 状态颜色定义
      colorScheme: const ColorScheme.light(
        primary: Colors.blue,
        secondary: Colors.green, // 语音电话
        tertiary: Colors.orange, // 语音留言
        error: Colors.red,
      ),
    );
  }
}
