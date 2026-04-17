import 'dart:io' show Platform;

bool get isDesktop =>
    Platform.isMacOS || Platform.isWindows || Platform.isLinux;

bool get isMobile => Platform.isIOS || Platform.isAndroid;
