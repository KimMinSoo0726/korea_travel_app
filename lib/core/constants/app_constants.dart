class AppConstants {
  static const String appName = '한국 여행 추천';

  // flutter build web --dart-define=API_BASE=https://xxxx.up.railway.app
  
  static const String apiBase =
      String.fromEnvironment('API_BASE', defaultValue: 'http://localhost:8080');

  static String proxyImage(String? url) {
    if (url == null || url.isEmpty) return '';
    if (url.contains('visitkorea.or.kr')) {
      return '$apiBase/imageProxy?url=${Uri.encodeComponent(url)}';
    }
    return url;
  }
}