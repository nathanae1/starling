import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../services/qr_scanner_service.dart';

part 'qr_scanner_provider.g.dart';

/// Default to the real method-channel scanner; widget tests override with
/// `MockQrScannerService` via `ProviderScope.overrides`.
@riverpod
QrScannerService qrScannerService(Ref ref) => MethodChannelQrScannerService();
