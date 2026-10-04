import 'package:flutter/services.dart';

/// Capture is reader-specific. Identification and attendance stay on the server.
abstract class FingerprintCapture {
  String get providerId;
  Future<bool> isAvailable();
  Future<String> captureTemplate();
}

class SecuGenFingerprintCapture implements FingerprintCapture {
  static const _channel = MethodChannel('schoolbase/fingerprint/secugen');

  @override
  String get providerId => 'secugen';

  @override
  Future<bool> isAvailable() async {
    try {
      return await _channel.invokeMethod<bool>('isAvailable') ?? false;
    } on MissingPluginException {
      return false;
    }
  }

  @override
  Future<String> captureTemplate() async {
    try {
      final template = await _channel.invokeMethod<String>('captureTemplate');
      if (template == null || template.isEmpty) {
        throw StateError('Fingerprint capture returned no template');
      }
      return template;
    } on MissingPluginException {
      throw StateError('SecuGen capture SDK is not installed on this app');
    }
  }
}

FingerprintCapture fingerprintCaptureFor(String providerId) {
  if (providerId == 'secugen') return SecuGenFingerprintCapture();
  throw UnsupportedError('Fingerprint provider $providerId is not installed');
}
