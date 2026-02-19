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

  // Track recently sent message IDs to deduplicate with WS echo
  final Set<String> _sentMsgIds = {};

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
      await _decryptPreviews();
    } finally {
      _convsLoading = false;
      notifyListeners();
    }
  }

  /// Decrypt last-message previews for the conversation list.
  Future<void> _decryptPreviews() async {
    if (keyPair == null) return;
    final myPubKey = await CryptoService.getPublicKeyBase64(keyPair!);

    for (final conv in _conversations) {
      final lm = conv.lastMessage;
      if (lm == null || lm.plaintext != null) continue;
      if (lm.type != 'TEXT') continue; // non-text types use static labels
      if (lm.recipientCiphertext == null || lm.senderCiphertext == null || lm.nonce == null) continue;

      final senderKey = await _getPublicKey(lm.senderId);
      if (senderKey == null) continue;

      // Try recipient ciphertext first (works if someone else sent it to me)
      final plain = await CryptoService.decrypt(
        lm.recipientCiphertext!, lm.nonce!, keyPair!, senderKey,
      );
      if (plain != null) {
        lm.plaintext = plain;
      } else {
        // Try sender copy (works if I sent it) – use local public key
        final senderPlain = await CryptoService.decryptForSender(
          lm.senderCiphertext!, lm.nonce!, keyPair!, myPubKey,
        );
        if (senderPlain != null) lm.plaintext = senderPlain;
      }
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
    if (_msgLoading[convId] == true) return;
    _msgLoading[convId] = true;
    notifyListeners();

    try {
      final msgs = await _api.getMessages(convId);
      _messages[convId] = msgs;
      _hasMore[convId] = msgs.length >= 50;
      await _decryptAll(msgs);
    } catch (_) {
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
        await _decryptAll(older);
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

    // Encrypt for recipient (generates random nonce)
    final encRecipient = await CryptoService.encrypt(text, keyPair!, recipientKey);
    // Encrypt sender copy with the SAME nonce so a single stored nonce decrypts both
    final sharedNonce = base64Url.decode(encRecipient.nonce);
    final myPubKey = await CryptoService.getPublicKeyBase64(keyPair!);
    final encSender = await CryptoService.encrypt(text, keyPair!, myPubKey, nonce: sharedNonce);

    final msg = await _api.sendMessage(
      conversationId: conversationId,
      recipientCiphertext: encRecipient.ciphertext,
      senderCiphertext: encSender.ciphertext,
      nonce: encRecipient.nonce,
      type: 'TEXT',
      replyToId: replyToId,
    );
    msg.plaintext = text;
    _sentMsgIds.add(msg.id);
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

    final payload = jsonEncode({
      'gifUrl': gifResult['file']?['md']?['gif']?['url'] ?? '',
      'tinyUrl': gifResult['file']?['xs']?['gif']?['url'] ?? '',
      'title': gifResult['title'] ?? '',
    });

    final encRecipient = await CryptoService.encrypt(payload, keyPair!, recipientKey);
    final sharedNonce = base64Url.decode(encRecipient.nonce);
    final myPubKey = await CryptoService.getPublicKeyBase64(keyPair!);
    final encSender = await CryptoService.encrypt(payload, keyPair!, myPubKey, nonce: sharedNonce);

    final msg = await _api.sendMessage(
      conversationId: conversationId,
      recipientCiphertext: encRecipient.ciphertext,
      senderCiphertext: encSender.ciphertext,
      nonce: encRecipient.nonce,
      type: 'GIF',
    );
    msg.plaintext = payload;
    _sentMsgIds.add(msg.id);
    _appendMessage(conversationId, msg);
    return msg;
  }

  Future<ZippMessage?> sendAttachmentMessage({
    required String conversationId,
    required Map<String, dynamic> attachment,
    required String recipientId,
    required String type, // IMAGE | VIDEO | FILE
    String? caption,
  }) async {
    final recipientKey = await _getPublicKey(recipientId);
    if (recipientKey == null || keyPair == null) return null;

    if (caption != null && caption.isNotEmpty) {
      attachment['caption'] = caption;
    }
    final payload = jsonEncode(attachment);
    final encRecipient = await CryptoService.encrypt(payload, keyPair!, recipientKey);
    final sharedNonce = base64Url.decode(encRecipient.nonce);
    final myPubKey = await CryptoService.getPublicKeyBase64(keyPair!);
    final encSender = await CryptoService.encrypt(payload, keyPair!, myPubKey, nonce: sharedNonce);

    final msg = await _api.sendMessage(
      conversationId: conversationId,
      recipientCiphertext: encRecipient.ciphertext,
      senderCiphertext: encSender.ciphertext,
      nonce: encRecipient.nonce,
      type: type,
    );
    msg.plaintext = payload;
    _sentMsgIds.add(msg.id);
    _appendMessage(conversationId, msg);
    return msg;
  }

  void _appendMessage(String convId, ZippMessage msg) {
    final msgs = _messages.putIfAbsent(convId, () => []);
    // Dedup: if message already in list (race between HTTP response and WS), skip
    if (msgs.any((m) => m.id == msg.id)) return;
    msgs.add(msg);
    _bumpConversation(convId, msg);
    notifyListeners();
  }

  void _bumpConversation(String convId, ZippMessage msg) {
    final idx = _conversations.indexWhere((c) => c.id == convId);
    if (idx < 0) return;
    final old = _conversations.removeAt(idx);
    // Update the lastMessage preview with the new message
    final preview = LastMessagePreview(
      id: msg.id,
      type: msg.type.name.toUpperCase(),
      createdAt: msg.createdAt,
      senderId: msg.senderId,
      recipientCiphertext: msg.recipientCiphertext,
      senderCiphertext: msg.senderCiphertext,
      nonce: msg.nonce,
      plaintext: msg.plaintext,
    );
    final updated = Conversation(
      id: old.id,
      participant: old.participant,
      lastMessage: preview,
      updatedAt: msg.createdAt,
    );
    _conversations.insert(0, updated);
  }

  // ── Read receipts ────────────────────────────────────────────────────────

  /// Mark the latest unread message from the other person as read.
  /// The server only marks the specified message, so we find the newest
  /// unread incoming message and mark it.
  Future<void> markLastMessageRead(String convId, String myId) async {
    final msgs = _messages[convId];
    if (msgs == null || msgs.isEmpty) return;

    // Find the last message from someone else that hasn't been read
    ZippMessage? lastUnread;
    for (int i = msgs.length - 1; i >= 0; i--) {
      final m = msgs[i];
      if (m.senderId != myId && !m.isRead) {
        lastUnread = m;
        break;
      }
    }
    if (lastUnread == null) return;

    try {
      await _api.markRead(convId, lastUnread.id);
    } catch (_) {}
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
    // Extract our own public key from the local key pair – this is used for
    // decryptForSender so we always use the key matching our private key,
    // regardless of what the server returns.
    final myPubKey = await CryptoService.getPublicKeyBase64(keyPair!);

    for (final msg in msgs) {
      if (msg.plaintext != null) continue;
      final senderKey = await _getPublicKey(msg.senderId);
      if (senderKey == null) continue;
      // For received messages: decrypt recipientCiphertext using sender's public key.
      // For own messages: this will fail (wrong shared secret), then fall through to
      // decryptForSender which uses our own local public key on the senderCiphertext copy.
      final plain = await CryptoService.decrypt(
          msg.recipientCiphertext, msg.nonce, keyPair!, senderKey);
      if (plain != null) {
        msg.plaintext = plain;
      } else {
        final senderPlain = await CryptoService.decryptForSender(
            msg.senderCiphertext, msg.nonce, keyPair!, myPubKey);
        if (senderPlain != null) msg.plaintext = senderPlain;
      }

      // Decrypt reply preview if present
      final reply = msg.replyTo;
      if (reply != null && reply.plaintext == null) {
        final replyKey = await _getPublicKey(reply.senderId);
        if (replyKey != null) {
          final rPlain = await CryptoService.decrypt(
              reply.recipientCiphertext, reply.nonce, keyPair!, replyKey);
          if (rPlain != null) {
            reply.plaintext = rPlain;
          } else {
            final rSender = await CryptoService.decryptForSender(
                reply.senderCiphertext, reply.nonce, keyPair!, myPubKey);
            if (rSender != null) reply.plaintext = rSender;
          }
        }
      }
    }
  }

  Future<String?> _getPublicKey(String userId) async {
    if (_pubKeyCache.containsKey(userId)) return _pubKeyCache[userId];
    final key = await _api.fetchPublicKey(userId);
    if (key != null) _pubKeyCache[userId] = key;
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
      case 'presence:list':
        final userIds = (payload['userIds'] as List<dynamic>?)
            ?.map((id) => id as String)
            .toList() ?? [];
        _online.addAll(userIds);
        notifyListeners();
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

    final msg = ZippMessage.fromJson(msgJson);

    // Skip if this is an echo of a message we sent (already added locally)
    if (_sentMsgIds.remove(msg.id)) return;

    final existingMsgs = _messages[convId];
    if (existingMsgs?.any((m) => m.id == msg.id) ?? false) return;

    await _decryptAll([msg]);
    _appendMessage(convId, msg);
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

    // Find the target message to know the cutoff
    final targetIdx = msgs.indexWhere((m) => m.id == msgId);
    if (targetIdx < 0) return;

    final parsedReadAt = readAt != null ? DateTime.parse(readAt) : null;
    final targetSenderId = msgs[targetIdx].senderId;
    bool changed = false;

    // Mark all messages from the same sender up to and including this one
    for (int i = 0; i <= targetIdx; i++) {
      final m = msgs[i];
      if (m.senderId == targetSenderId && !m.isRead) {
        msgs[i] = m.copyWith(readAt: parsedReadAt);
        changed = true;
      }
    }

    if (changed) notifyListeners();
  }

  @override
  void dispose() {
    _ws.removeListener(_onWsEvent);
    super.dispose();
  }
}