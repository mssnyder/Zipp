import 'dart:io';

/// Reads ZIPP_SERVER_URL from the environment.
/// Falls back to localhost for development.
String nativeServerUrl() =>
    Platform.environment['ZIPP_SERVER_URL'] ?? 'http://localhost:4200';
