import 'dart:io';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter/foundation.dart';

Process? _backendProcess;

Future<void> startBackend() async {
  try {
    final response = await http.get(Uri.parse('http://127.0.0.1:8000/api/songs')).timeout(const Duration(seconds: 1));
    if (response.statusCode == 200) {
      debugPrint("Backend is already running.");
      return;
    }
  } catch (e) {}

  try {
    final isWindows = Platform.isWindows;
    final exeName = isWindows ? 'gg_backend_windows.exe' : 'gg_backend_linux';
    
    // First try looking for the compiled backend in the same directory (Release mode)
    final backendExe = File(exeName);
    if (await backendExe.exists()) {
      debugPrint("Starting compiled backend executable...");
      _backendProcess = await Process.start(
        backendExe.absolute.path,
        ['--host', '0.0.0.0', '--port', '8000'],
      );
    } else {
      // Fallback for development mode
      final backendDir = Directory('../gg_backend');
      if (await backendDir.exists()) {
        debugPrint("Starting Python backend via uvicorn...");
        final uvicornPath = isWindows ? 'venv\\Scripts\\uvicorn.exe' : 'venv/bin/uvicorn';
        _backendProcess = await Process.start(
          uvicornPath,
          ['main:app', '--host', '0.0.0.0', '--port', '8000'],
          workingDirectory: backendDir.path,
        );
      }
    }
      
      for (int i = 0; i < 10; i++) {
        await Future.delayed(const Duration(milliseconds: 500));
        try {
          final res = await http.get(Uri.parse('http://127.0.0.1:8000/api/songs')).timeout(const Duration(milliseconds: 500));
          if (res.statusCode == 200) {
            debugPrint("Backend is up and running.");
            break;
          }
        } catch (_) {}
      }
    }
  } catch (e) {
    debugPrint("Failed to start backend: $e");
  }
}

void stopBackend() {
  _backendProcess?.kill();
}
