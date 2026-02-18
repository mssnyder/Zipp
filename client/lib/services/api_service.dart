import 'dart:io';
import 'package:dio/dio.dart';
import 'package:cookie_jar/cookie_jar.dart';
import 'package:dio_cookie_manager/dio_cookie_manager.dart';
import '../config/constants.dart';
import '../models/user.dart';
import '../models/conversation.dart';
import '../models/message.dart';
import '../models/reaction.dart';

class ApiException implements Exception {
  final int statusCode;
  final String message;
  const ApiException(this.statusCode, this.message);
  @override
  String toString() => 'ApiException($statusCode): $message';
}

class ApiService {
  late final Dio _dio;
  final CookieJar _cookieJar = CookieJar();

  ApiService() {
    _dio = Dio(BaseOptions(
      baseUrl: ZippConfig.serverUrl,
      connectTimeout: const Duration(seconds: 15),
      receiveTimeout: const Duration(seconds: 30),
      headers: {'Content-Type': 'application/json'},
      validateStatus: (_) => true, // Handle errors manually
    ));
    _dio.interceptors.add(CookieManager(_cookieJar));
  }

  Future<Map<String, dynamic>> _check(Response r) async {
    final data = r.data as Map<String, dynamic>? ?? {};
    if (r.statusCode != null && r.statusCode! >= 400) {
      throw ApiException(r.statusCode!, data['error']?.toString() ?? 'Request failed');
    }
    return data;
  }

  // ── Auth ──────────────────────────────────────────────────────────────────

  Future<ZippUser> register({
    required String email,
    required String username,
    required String password,
    String? displayName,
  }) async {
    final r = await _dio.post('/api/auth/register', data: {
      'email': email,
      'username': username,
      'password': password,
      if (displayName != null) 'displayName': displayName,
    });
    final data = await _check(r);
    return ZippUser.fromJson(data['user'] as Map<String, dynamic>);
  }

  Future<ZippUser> login({required String email, required String password}) async {
    final r = await _dio.post('/api/auth/login', data: {'email': email, 'password': password});
    final data = await _check(r);
    return ZippUser.fromJson(data['user'] as Map<String, dynamic>);
  }

  Future<void> logout() async {
    await _dio.post('/api/auth/logout');
  }

  Future<void> resendVerification(String email) async {
    final r = await _dio.post('/api/auth/resend-verification', data: {'email': email});
    await _check(r);
  }

  // ── Me ────────────────────────────────────────────────────────────────────

  Future<ZippUser> getMe() async {
    final r = await _dio.get('/api/me');
    final data = await _check(r);
    return ZippUser.fromJson(data['user'] as Map<String, dynamic>);
  }

  Future<ZippUser> updateMe({String? displayName, String? username}) async {
    final r = await _dio.patch('/api/me', data: {
      if (displayName != null) 'displayName': displayName,
      if (username != null) 'username': username,
    });
    final data = await _check(r);
    return ZippUser.fromJson(data['user'] as Map<String, dynamic>);
  }

  Future<ZippUser> uploadAvatar(File file) async {
    final form = FormData.fromMap({
      'file': await MultipartFile.fromFile(file.path, filename: file.path.split('/').last),
    });
    final r = await _dio.post('/api/me/avatar', data: form);
    final data = await _check(r);
    return ZippUser.fromJson(data['user'] as Map<String, dynamic>);
  }

  // ── Keys ──────────────────────────────────────────────────────────────────

  Future<String?> fetchPublicKey(String userId) async {
    final r = await _dio.get('/api/keys/$userId');
    if (r.statusCode == 404) return null;
    final data = await _check(r);
    return data['publicKey'] as String?;
  }

  Future<void> uploadPublicKey(String publicKey) async {
    final r = await _dio.put('/api/keys', data: {'publicKey': publicKey});
    await _check(r);
  }

  // ── Users ─────────────────────────────────────────────────────────────────

  Future<List<Map<String, dynamic>>> searchUsers(String q) async {
    final r = await _dio.get('/api/users', queryParameters: {'q': q});
    final data = await _check(r);
    return List<Map<String, dynamic>>.from(data['users'] as List);
  }

  // ── Conversations ─────────────────────────────────────────────────────────

  Future<List<Conversation>> getConversations() async {
    final r = await _dio.get('/api/conversations');
    final data = await _check(r);
    return (data['conversations'] as List)
        .map((c) => Conversation.fromJson(c as Map<String, dynamic>))
        .toList();
  }

  Future<Conversation> getOrCreateConversation(String userId) async {
    final r = await _dio.post('/api/conversations', data: {'userId': userId});
    final data = await _check(r);
    return Conversation.fromJson(data['conversation'] as Map<String, dynamic>);
  }

  // ── Messages ──────────────────────────────────────────────────────────────

  Future<List<ZippMessage>> getMessages(String conversationId, {String? before}) async {
    final r = await _dio.get(
      '/api/conversations/$conversationId/messages',
      queryParameters: {
        if (before != null) 'before': before,
        'limit': 50,
      },
    );
    final data = await _check(r);
    return (data['messages'] as List)
        .map((m) => ZippMessage.fromJson(m as Map<String, dynamic>))
        .toList();
  }

  Future<ZippMessage> sendMessage({
    required String conversationId,
    required String ciphertext,
    required String nonce,
    String type = 'TEXT',
    String? replyToId,
  }) async {
    final r = await _dio.post('/api/conversations/$conversationId/messages', data: {
      'ciphertext': ciphertext,
      'nonce': nonce,
      'type': type,
      if (replyToId != null) 'replyToId': replyToId,
    });
    final data = await _check(r);
    return ZippMessage.fromJson(data['message'] as Map<String, dynamic>);
  }

  Future<void> markRead(String conversationId, String messageId) async {
    await _dio.patch('/api/conversations/$conversationId/messages/$messageId/read');
  }

  // ── Reactions ─────────────────────────────────────────────────────────────

  Future<List<Reaction>> toggleReaction(String messageId, String emoji) async {
    final r = await _dio.post('/api/messages/$messageId/reactions', data: {'emoji': emoji});
    final data = await _check(r);
    return (data['reactions'] as List)
        .map((rx) => Reaction.fromJson(rx as Map<String, dynamic>))
        .toList();
  }

  // ── Tenor GIFs ────────────────────────────────────────────────────────────

  Future<List<dynamic>> searchGifs(String query) async {
    final r = await _dio.get('/api/tenor/search', queryParameters: {'q': query, 'limit': 20});
    final data = await _check(r);
    return data['results'] as List? ?? [];
  }

  Future<List<dynamic>> getTrendingGifs() async {
    final r = await _dio.get('/api/tenor/trending', queryParameters: {'limit': 20});
    final data = await _check(r);
    return data['results'] as List? ?? [];
  }

  // ── Attachments ───────────────────────────────────────────────────────────

  Future<Map<String, dynamic>> uploadAttachment(File file) async {
    final form = FormData.fromMap({
      'file': await MultipartFile.fromFile(file.path, filename: file.path.split('/').last),
    });
    final r = await _dio.post(
      '/api/upload',
      data: form,
      options: Options(receiveTimeout: const Duration(minutes: 10)),
    );
    final data = await _check(r);
    return data['attachment'] as Map<String, dynamic>;
  }

  String resolveUrl(String path) =>
      path.startsWith('http') ? path : '${ZippConfig.serverUrl}$path';
}
