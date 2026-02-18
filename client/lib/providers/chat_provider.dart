import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:cryptography/cryptography.dart';
import '../models/conversation.dart';
import '../models/message.dart';
import '../models/reaction.dart';
import '../services/api_service.dart';
import '../services/crypto_service.dart';
import '../services/websocket_service.dart';

class ChatProvider extends ChangeNotifier {
  final ApiService _api;
  final WebSocketService _ws;

  // Key pair set by AuthProvider after login
  SimpleKeyPair? keyPair;

  // Public key cache: userId -> base64 pubkey
  final Map<String, String> _pubKeyCache = {};

  // Desktop two-pane: selected conversation
  String? _selectedConvId;
  String? _selectedParticipantId;
  String _selectedParticipantName = '';

  String? get selectedConvId => _selectedConvId;
  String? get selectedParticipantId => _selectedParticipantId;
  String get selectedParticipantName => _selectedParticipantName;

  void selectConversation(Conversation conv) {
    _selectedConvId = conv.id;
    _selectedParticipantId = conv.participant?.id ?? '';
    _selectedParticipantName = conv.participant?.name ?? '';
    notifyListeners();
    if (_messages[conv.id] == null) loadMessages(conv.id);
  }

  void clearSelection() {
    _selectedConvId = null;
    _selectedParticipantId = null;
    _selectedParticipantName = '';
    notifyListeners();
  }

  // Conversations
  List<Conversation> _conversations = [];
  bool _convsLoading = false;

  // Messages per conversation
  final Map<String, List<ZippMessage>> _messages = {};
  final Map<String, bool> _hasMore = {};   // can load older messages
  final Map<String, bool> _msgLoading = {};

  // Typing indicators: conversationId -> Set<userId>
  final Map<String, Set<String>> _typing = {};

  // Online users
  final Set<String> _online = {};

  ChatProvider(this._api, this._ws) {
    _ws.addListener(_onWsEvent);
  }

  List<Conversation> get conversations => _conversations;
  bool get convsLoading => _convsLoading;

  List<ZippMessage> messagesFor(String convId) => _messages[convId] ?? [];
  bool hasMoreFor(String convId) => _hasMore[convId] ?? true;
  bool msgLoadingFor(String convId) => _msgLoading[convId] ?? false;
  Set<String> typingIn(String convId) => _typing[convId] ?? {};
  bool isOnline(String userId) => _online.contains(userId);

  // ── Conversations ─────────────────────────────────────────────────────────

  Future<void> loadConversations() async {
    _convsLoading = true;
    notifyListeners();
    try {
      _conversations = await _api.getConversations();
    } finally {
      _convsLoading = false;
      notifyListeners();
    }
  }

  Future<Conversation> getOrCreateConversation(String userId) async {
    final conv = await _api.getOrCreateConversation(userId);
    if (!_conversations.any((c) => c.id == conv.id)) {
      _conversations.insert(0, conv);
      notifyListeners();
    }
    return conv;
  }

  // ── Messages ──────────────────────────────────────────────────────────────

  Future<void> loadMessages(String convId) async {
    if (_msgLoading[convId] == true) {
      print('[ChatProvider] Already loading messages for $convId');
      return;
    }
    _msgLoading[convId] = true;
    print('[ChatProvider] Starting to load messages for $convId');
    notifyListeners();

    try {
      print('[ChatProvider] Fetching messages from API...');
      final msgs = await _api.getMessages(convId);
      print('[ChatProvider] Fetched ${msgs.length} messages');
      _messages[convId] = msgs;
      _hasMore[convId] = msgs.length >= 50;
      print('[ChatProvider] Starting decryption for ${msgs.length} messages...');
      // Decrypt all messages (will retry if keyPair not available yet)
      await _decryptAllWithRetry(msgs);
      print('[ChatProvider] Decryption complete for $convId');
    } catch (e) {
      print('[ChatProvider] ERROR loading messages for $convId: $e');
    } finally {
      _msgLoading[convId] = false;
      notifyListeners();
    }
  }

  /// Load older messages (scroll-up pagination).
  Future<void> loadMoreMessages(String convId) async {
    if (_msgLoading[convId] == true || _hasMore[convId] == false) return;
    final existing = _messages[convId];
    if (existing == null || existing.isEmpty) return;

    _msgLoading[convId] = true;
    notifyListeners();

    try {
      final oldest = existing.first.createdAt.toIso8601String();
      final older = await _api.getMessages(convId, before: oldest);
      if (older.isEmpty) {
        _hasMore[convId] = false;
      } else {
        print('[ChatProvider] Loading ${older.length} older messages');
        await _decryptAllWithRetry(older);
        _messages[convId] = [...older, ...existing];
        _hasMore[convId] = older.length >= 50;
      }
    } finally {
      _msgLoading[convId] = false;
      notifyListeners();
    }
  }

  Future<ZippMessage?> sendTextMessage({
    required String conversationId,
    required String text,
    required String recipientId,
    String? replyToId,
  }) async {
    final recipientKey = await _getPublicKey(recipientId);
    if (recipientKey == null || keyPair == null) return null;

    // Encrypt for recipient
    final encRecipient = await CryptoService.encrypt(text, keyPair!, recipientKey);
    
    // Encrypt for sender (my own public key)
    final encSender = await CryptoService.encrypt(text, keyPair!, await CryptoService.getPublicKeyBase64(keyPair!));
    
    final msg = await _api.sendMessage(
      conversationId: conversationId,
      recipientCiphertext: encRecipient.ciphertext,
      senderCiphertext: encSender.ciphertext,
      nonce: encRecipient.nonce,
      type: 'TEXT',
      replyToId: replyToId,
    );
    msg.plaintext = text;
    _appendMessage(conversationId, msg);
    return msg;
  }

  Future<ZippMessage?> sendGifMessage({
    required String conversationId,
    required Map<String, dynamic> gifResult,
    required String recipientId,
  }) async {
    final recipientKey = await _getPublicKey(recipientId);
    if (recipientKey == null || keyPair == null) return null;

    // Encrypt for recipient
    final encRecipient = await CryptoService.encrypt(
      jsonEncode({
        'gifUrl': gifResult['file']?['md']?['gif']?['url'] ?? '',
        'tinyUrl': gifResult['file']?['xs']?['gif']?['url'] ?? '',
        'title': gifResult['title'] ?? '',
      }),
      keyPair!,
      recipientKey,
    );
    
    // Encrypt for sender (my own public key)
    final encSender = await CryptoService.encrypt(
      jsonEncode({
        'gifUrl': gifResult['file']?['md']?['gif']?['url'] ?? '',
        'tinyUrl': gifResult['file']?['xs']?['gif']?['url'] ?? '',
        'title': gifResult['title'] ?? '',
      }),
      keyPair!,
      await CryptoService.getPublicKeyBase64(keyPair!),
    );
    
    final msg = await _api.sendMessage(
      conversationId: conversationId,
      recipientCiphertext: encRecipient.ciphertext,
      senderCiphertext: encSender.ciphertext,
      nonce: encRecipient.nonce,
      type: 'GIF',
    );
    msg.plaintext = jsonEncode({
      'gifUrl': gifResult['file']?['md']?['gif']?['url'] ?? '',
      'tinyUrl': gifResult['file']?['xs']?['gif']?['url'] ?? '',
      'title': gifResult['title'] ?? '',
    });
    _appendMessage(conversationId, msg);
    return msg;
  }

  Future<ZippMessage?> sendAttachmentMessage({
    required String conversationId,
    required Map<String, dynamic> attachment,
    required String recipientId,
    required String type, // IMAGE | VIDEO | FILE
  }) async {
    final recipientKey = await _getPublicKey(recipientId);
    if (recipientKey == null || keyPair == null) return null;

    // Encrypt for recipient
    final encRecipient = await CryptoService.encrypt(
      jsonEncode(attachment),
      keyPair!,
      recipientKey,
    );
    
    // Encrypt for sender (my own public key)
    final encSender = await CryptoService.encrypt(
      jsonEncode(attachment),
      keyPair!,
      await CryptoService.getPublicKeyBase64(keyPair!),
    );
    
    final msg = await _api.sendMessage(
      conversationId: conversationId,
      recipientCiphertext: encRecipient.ciphertext,
      senderCiphertext: encSender.ciphertext,
      nonce: encRecipient.nonce,
      type: type,
    );
    msg.plaintext = jsonEncode(attachment);
    _appendMessage(conversationId, msg);
    return msg;
  }

  void _appendMessage(String convId, ZippMessage msg) {
    _messages.putIfAbsent(convId, () => []).add(msg);
    _bumpConversation(convId);
    notifyListeners();
  }

  void _bumpConversation(String convId) {
    final idx = _conversations.indexWhere((c) => c.id == convId);
    if (idx > 0) {
      final conv = _conversations.removeAt(idx);
      _conversations.insert(0, conv);
    }
  }

  // ── Reactions ─────────────────────────────────────────────────────────────

  Future<void> toggleReaction(String messageId, String convId, String emoji) async {
    final reactions = await _api.toggleReaction(messageId, emoji);
    _updateReactions(convId, messageId, reactions);
  }

  void _updateReactions(String convId, String messageId, List<Reaction> reactions) {
    final msgs = _messages[convId];
    if (msgs == null) return;
    final idx = msgs.indexWhere((m) => m.id == messageId);
    if (idx < 0) return;
    msgs[idx] = msgs[idx].copyWith(reactions: reactions);
    notifyListeners();
  }

  // ── Decryption ────────────────────────────────────────────────────────────

  Future<void> _decryptAll(List<ZippMessage> msgs) async {
    if (keyPair == null) return;
    for (final msg in msgs) {
      final recipientKey = await _getPublicKey(msg.senderId);
      if (recipientKey == null) continue;
      // Only decrypt if not already decrypted
      if (msg.plaintext == null) {
        final plain = await CryptoService.decrypt(msg.recipientCiphertext, msg.nonce, keyPair!, recipientKey);
        if (plain != null) {
          msg.plaintext = plain;
        } else {
          // Try sender decryption for own messages
          final senderKey = await _getPublicKey(msg.senderId);
          if (senderKey != null) {
            final senderPlain = await CryptoService.decryptForSender(msg.senderCiphertext, msg.nonce, keyPair!, senderKey);
            if (senderPlain != null) {
              msg.plaintext = senderPlain;
            }
          }
        }
      }
    }
  }

  Future<String?> decryptMessage(ZippMessage msg) async {
    if (msg.plaintext != null) return msg.plaintext;
    if (keyPair == null) return null;
    
    // Try to decrypt with recipient's key first (for messages from others)
    final recipientKey = await _getPublicKey(msg.senderId);
    if (recipientKey != null) {
      print('[ChatProvider] Trying recipient decryption for message from ${msg.senderId}');
      final plain = await CryptoService.decrypt(msg.recipientCiphertext, msg.nonce, keyPair!, recipientKey);
      if (plain != null) {
        msg.plaintext = plain;
        return plain;
      }
    }
    
    // If that fails, try decrypting with sender's key (for own messages)
    final senderKey = await _getPublicKey(msg.senderId);
    if (senderKey != null) {
      print('[ChatProvider] Trying sender decryption for own message from ${msg.senderId}');
      final plain = await CryptoService.decryptForSender(msg.senderCiphertext, msg.nonce, keyPair!, senderKey);
      if (plain != null) {
        msg.plaintext = plain;
        return plain;
      }
    }
    
    return null;
  }
  
  // Decrypt with retry - keeps trying until message is decrypted
  Future<void> _decryptAllWithRetry(List<ZippMessage> msgs) async {
    print('[ChatProvider] _decryptAllWithRetry called with ${msgs.length} messages');
    print('[ChatProvider] Current keyPair: ${keyPair != null ? "present" : "null"}');
    
    // Poll until all messages are decrypted or keyPair becomes unavailable
    int attempt = 0;
    const maxAttempts = 1000; // Safety limit
    
    while (keyPair != null) {
      attempt++;
      if (attempt > maxAttempts) {
        print('[ChatProvider] Stopping retry loop after $maxAttempts attempts');
        break;
      }
      
      bool allDecrypted = true;
      int decryptedCount = 0;
      
      for (final msg in msgs) {
        if (msg.plaintext == null) {
          final senderKey = await _getPublicKey(msg.senderId);
          print('[ChatProvider] [Attempt $attempt] Decrypting message from ${msg.senderId}');
          if (senderKey != null) {
            // Try recipient decryption
            final plain = await CryptoService.decrypt(msg.recipientCiphertext, msg.nonce, keyPair!, senderKey);
            if (plain != null) {
              msg.plaintext = plain;
              print('[ChatProvider] [Attempt $attempt] Successfully decrypted message from ${msg.senderId}');
              decryptedCount++;
            } else {
              // Try sender decryption for own messages
              final senderPlain = await CryptoService.decryptForSender(msg.senderCiphertext, msg.nonce, keyPair!, senderKey);
              if (senderPlain != null) {
                msg.plaintext = senderPlain;
                print('[ChatProvider] [Attempt $attempt] Successfully decrypted own message');
                decryptedCount++;
              } else {
                print('[ChatProvider] [Attempt $attempt] FAILED to decrypt message from ${msg.senderId}');
                allDecrypted = false;
              }
            }
          }
        } else {
          decryptedCount++;
        }
      }
      
      print('[ChatProvider] [Attempt $attempt] Decrypted $decryptedCount/$msgs.length messages');
      
      // If all decrypted or keyPair is now null, break
      if (allDecrypted || keyPair == null) {
        print('[ChatProvider] Decryption complete: $allDecrypted, keyPair: ${keyPair != null}');
        break;
      }
      // Small delay before retry to avoid tight loop
      await Future.delayed(const Duration(milliseconds: 100));
    }
  }

  Future<String?> _getPublicKey(String userId) async {
    if (_pubKeyCache.containsKey(userId)) {
      print('[ChatProvider] Using cached public key for $userId');
      return _pubKeyCache[userId];
    }
    print('[ChatProvider] Fetching public key for $userId from API...');
    final key = await _api.fetchPublicKey(userId);
    if (key != null) {
      _pubKeyCache[userId] = key;
      print('[ChatProvider] Cached public key for $userId');
    }
    return key;
  }

  // ── WebSocket events ──────────────────────────────────────────────────────

  void _onWsEvent(String event, Map<String, dynamic> payload) {
    switch (event) {
      case 'message:new':
        _handleNewMessage(payload);
      case 'message:reaction':
        _handleReaction(payload);
      case 'message:typing':
        _handleTyping(payload);
      case 'message:read':
        _handleRead(payload);
      case 'user:online':
        _online.add(payload['userId'] as String? ?? '');
        notifyListeners();
      case 'user:offline':
        _online.remove(payload['userId'] as String? ?? '');
        notifyListeners();
    }
  }

  Future<void> _handleNewMessage(Map<String, dynamic> payload) async {
    final convId = payload['conversationId'] as String?;
    final msgJson = payload['message'] as Map<String, dynamic>?;
    if (convId == null || msgJson == null) return;

    print('[ChatProvider] Received new message for $convId');

    final msg = ZippMessage.fromJson(msgJson);
    // Decrypt immediately when received via WebSocket
    if (keyPair != null) {
      final senderKey = await _getPublicKey(msg.senderId);
      print('[ChatProvider] Decrypting WebSocket message from ${msg.senderId}');
      if (senderKey != null) {
        // Try recipient decryption first
        final plain = await CryptoService.decrypt(msg.recipientCiphertext, msg.nonce, keyPair!, senderKey);
        if (plain != null) {
          msg.plaintext = plain;
          print('[ChatProvider] Successfully decrypted WebSocket message from ${msg.senderId}');
        } else {
          // Try sender decryption for own messages
          print('[ChatProvider] Trying sender decryption for own message');
          final senderPlain = await CryptoService.decryptForSender(msg.senderCiphertext, msg.nonce, keyPair!, senderKey);
          if (senderPlain != null) {
            msg.plaintext = senderPlain;
            print('[ChatProvider] Successfully decrypted own message');
          } else {
            print('[ChatProvider] FAILED to decrypt message from ${msg.senderId}');
          }
        }
      } else {
        print('[ChatProvider] FAILED to get public key for ${msg.senderId}');
      }
    }
    await _decryptAllWithRetry([msg]);

    // Check if message already exists in current conversation
    final existingMsgs = _messages[convId];
    final exists = existingMsgs?.any((m) => m.id == msg.id) ?? false;
    if (!exists) {
      _appendMessage(convId, msg);
    }
  }

  void _handleReaction(Map<String, dynamic> payload) {
    final messageId = payload['messageId'] as String?;
    final reactionsJson = payload['reactions'] as List<dynamic>?;
    if (messageId == null || reactionsJson == null) return;

    final reactions = reactionsJson
        .map((r) => Reaction.fromJson(r as Map<String, dynamic>))
        .toList();

    for (final entry in _messages.entries) {
      final idx = entry.value.indexWhere((m) => m.id == messageId);
      if (idx >= 0) {
        entry.value[idx] = entry.value[idx].copyWith(reactions: reactions);
        notifyListeners();
        return;
      }
    }
  }

  void _handleTyping(Map<String, dynamic> payload) {
    final convId = payload['conversationId'] as String?;
    final userId = payload['userId'] as String?;
    final isTyping = payload['isTyping'] as bool? ?? false;
    if (convId == null || userId == null) return;

    _typing.putIfAbsent(convId, () => {});
    if (isTyping) {
      _typing[convId]!.add(userId);
    } else {
      _typing[convId]!.remove(userId);
    }
    notifyListeners();
  }

  void _handleRead(Map<String, dynamic> payload) {
    final convId = payload['conversationId'] as String?;
    final msgId = payload['messageId'] as String?;
    final readAt = payload['readAt'] as String?;
    if (convId == null || msgId == null) return;

    final msgs = _messages[convId];
    if (msgs == null) return;
    final idx = msgs.indexWhere((m) => m.id == msgId);
    if (idx >= 0) {
      msgs[idx] = msgs[idx].copyWith(readAt: readAt != null ? DateTime.parse(readAt) : null);
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _ws.removeListener(_onWsEvent);
    super.dispose();
  }
}