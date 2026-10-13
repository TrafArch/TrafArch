import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'app.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  // 临时诊断：release 下让 ErrorWidget 直接显示异常文本（定位根因后删除）
  ErrorWidget.builder = (FlutterErrorDetails details) => Material(
        color: Colors.white,
        child: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Text(
              details.exceptionAsString(),
              style: const TextStyle(
                  color: Colors.red, fontSize: 11, fontFamily: 'monospace'),
            ),
          ),
        ),
      );
  runApp(const TransitCardAnalyzerApp());
}
