class AppConstants {
  static const String appName = '한국 여행 추천';

  // Firestore 컬렉션 경로
  static String userConversations(String uid) => 'users/$uid/conversations';
  static String conversationMessages(String uid, String convId) =>
      'users/$uid/conversations/$convId/messages';
  static String userPlans(String uid) => 'users/$uid/plans';

  // Cloud Functions
  static const String geminiFunctionName = 'chatWithGemini';
  static const String functionsRegion = 'asia-northeast3'; // 서울 리전

   static const String _projectId = 'koreatravelapp';

  static String get imageProxyBase =>
      'https://${functionsRegion}-${_projectId}.cloudfunctions.net/imageProxy';

  /// CORS 우회용 프록시 URL 변환
  static String proxyImage(String? url) {
    if (url == null || url.isEmpty) return '';
    // 관광공사 이미지만 프록시 경유
    if (url.contains('visitkorea.or.kr')) {
      return '$imageProxyBase?url=${Uri.encodeComponent(url)}';
    }
    return url;
  }
}