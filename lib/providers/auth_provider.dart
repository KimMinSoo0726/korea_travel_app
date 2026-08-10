import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../services/auth_service.dart';

final authServiceProvider = Provider((ref) => AuthService());

final authStateProvider = StreamProvider<User?>((ref) {
  return ref.watch(authServiceProvider).authStateChanges;
});

/// 현재 uid (로그인 안됐으면 null)
final uidProvider = Provider<String?>((ref) {
  return ref.watch(authStateProvider).value?.uid;
});