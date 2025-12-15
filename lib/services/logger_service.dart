import 'dart:io';

enum LogLevel { info, warning, error }

class LoggerService {
  static final LoggerService _instance = LoggerService._internal();

  factory LoggerService() {
    return _instance;
  }

  LoggerService._internal();

  void log(String message, {LogLevel level = LogLevel.info}) {
    final timestamp = DateTime.now().toIso8601String();
    final color = _getColor(level);
    final reset = '\x1B[0m';
    final prefix = level.toString().split('.').last.toUpperCase();

    // Print to stdout (or could be a file)
    print('$color[$timestamp] [$prefix] $message$reset');
  }

  void info(String message) => log(message, level: LogLevel.info);
  void warning(String message) => log(message, level: LogLevel.warning);
  void error(String message) => log(message, level: LogLevel.error);

  String _getColor(LogLevel level) {
    if (Platform.environment.containsKey('NO_COLOR')) return '';
    switch (level) {
      case LogLevel.info:
        return '\x1B[32m'; // Green
      case LogLevel.warning:
        return '\x1B[33m'; // Yellow
      case LogLevel.error:
        return '\x1B[31m'; // Red
    }
  }
}
