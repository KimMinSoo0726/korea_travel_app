import 'package:cloud_functions/cloud_functions.dart';
import '../core/constants/app_constants.dart';

class GeminiService {
  final _functions =
      FirebaseFunctions.instanceFor(region: AppConstants.functionsRegion);

  /// 대화 히스토리를 넘기고 응답 텍스트를 받는다.
  /// 응답이 플랜이면 서버가 { text, planJson } 형태로 반환.
  Future<GeminiResponse> chat(

   

      List<Map<String, String>> history, String userMessage) async {

      print('🚀 Functions 호출 시작');
      try{
    final callable = _functions.httpsCallable(AppConstants.geminiFunctionName);
    final result = await callable.call({
      'history': history, // [{role:'user'|'model', text:'...'}]
      'message': userMessage,
    });


    print('📬 응답 받음: ${result.data}');

    final data = Map<String, dynamic>.from(result.data as Map);
    return GeminiResponse(
      text: data['text'] ?? '',
      planJson: (data['planJson'] as Map?)?.cast<String, dynamic>(),
    );
      }
    catch (e) {
      print('❌ Functions 호출 오류: $e');
      rethrow;  }
  }
}

class GeminiResponse {
  final String text;
  final Map<String, dynamic>? planJson;
  GeminiResponse({required this.text, this.planJson});
}