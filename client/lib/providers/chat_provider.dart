import 'dart:async';
import 'dart:convert';
import 'package:cryptography/cryptography.dart';
import 'package:flutter/foundation.dart';
import '../models/conversation.dart';
import '../models/message.dart';
import '../models/reaction.dart';
import '../services/api_service.dart';
import '../services/crypto_service.dart';
import '../services/notification_service.dart';
import '../services/websocket_service.dart';

class ChatProvider extends ChangeNotifier {
  final ApiService _api;
  final WebSocketService _ws;

  // Key pair & user ID set by AuthProvider after login
  SimpleKeyPair? keyPair;
  String? currentUserId;

  // Public key cache: userId -> base64 pubkey
  final Map<String, String> _pubKeyCache = {};

  // Epoch key cache: epochId -> raw epoch key (base64url)
  final Map<String, String> _epochKeyCache = {};

  // Desktop two-pane: selected conversation
  String? _selectedConvId;
  String? _selectedParticipantId;
  String _selectedParticipantName = '';

  String? get selectedConvId => _selectedConvId;
  String? get selectedParticipantId => _selectedParticipantId;
  String get selectedParticipantName => _selectedParticipantName;

  void selectConversation(Conversation conv) {
    _selectedConvId = conv.id;
    if (conv.isGroup) {
      _selectedParticipantId = null;
      _selectedParticipantName = conv.displayName;
    } else {
      _selectedParticipantId = conv.participant?.id ?? '';
      _selectedParticipantName = conv.participant?.name ?? '';
    }
    NotificationService.instance.activeConversationId = conv.id;
    _unreadConvIds.remove(conv.id);
    _updateTrayBadge();
    notifyListeners();
    if (_messages[conv.id] == null) loadMessages(conv.id);
  }

  void clearSelection() {
    _selectedConvId = null;
    _selectedParticipantId = null;
    _selectedParticipantName = '';
    NotificationService.instance.activeConversationId = null;
    notifyListeners();
  }

  // Conversations
  List<Conversation> _conversations = [];
  bool _convsLoading = false;

  // Messages per conversation
  final Map<String, List<ZippMessage>> _messages = {};
  final Map<String, bool> _hasMore = {};
  final Map<String, bool> _msgLoading = {};

  // Typing indicators: conversationId -> Set<userId>
  final Map<String, Set<String>> _typing = {};

  // Online users
  final Set<String> _online = {};

  // Track recently sent message IDs to deduplicate with WS echo
  final Set<String> _sentMsgIds = {};

  // Unread conversation tracking for tray badge
  final Set<String> _unreadConvIds = {};
  int get unreadCount => _unreadConvIds.length;

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

  /// Find a conversation by ID from the loaded list.
  Conversation? conversationById(String id) =>
      _conversations.cast<Conversation?>().firstWhere((c) => c!.id == id, orElse: () => null);

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
      if (lm.type != 'TEXT') continue;

      if (lm.epochId != null) {
        // Group message — epoch decryption
        if (lm.ciphertext == null || lm.nonce == null || lm.epochKey == null) continue;
        final epochKey = await _unwrapEpochKey(lm.epochKey!);
        if (epochKey == null) continue;
        lm.plaintext = await CryptoService.decryptWithEpochKey(lm.ciphertext!, lm.nonce!, epochKey);
      } else {
        // DM message
        if (lm.recipientCiphertext == null || lm.senderCiphertext == null || lm.nonce == null) continue;
        final senderKey = await _getPublicKey(lm.senderId);
        if (senderKey == null) continue;
        final plain = await CryptoService.decrypt(
          lm.recipientCiphertext!, lm.nonce!, keyPair!, senderKey,
        );
        if (plain != null) {
          lm.plaintext = plain;
        } else {
          final senderPlain = await CryptoService.decryptForSender(
            lm.senderCiphertext!, lm.nonce!, keyPair!, myPubKey,
          );
          if (senderPlain != null) lm.plaintext = senderPlain;
        }
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

  Future<Conversation> createGroup({
    required List<String> participantIds,
    required String name,
  }) async {
    final conv = await _api.createGroupConversation(participantIds: participantIds, name: name);
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

  // ── DM send methods ────────────────────────────────────────────────────────

  Future<ZippMessage?> sendTextMessage({
    required String conversationId,
    required String text,
    required String recipientId,
    String? replyToId,
  }) async {
    final recipientKey = await _getPublicKey(recipientId);
    if (recipientKey == null || keyPair == null) return null;

    final encRecipient = await CryptoService.encrypt(text, keyPair!, recipientKey);
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
    required String type,
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

  // ── Group send methods ─────────────────────────────────────────────────────

  /// Get or lazy-init the current epoch for a group conversation.
  /// Returns (epochId, rawEpochKey, epochInitPayload?).
  Future<({String epochId, String rawKey, Map<String, dynamic>? epochInit})> _ensureEpoch(
    String conversationId,
  ) async {
    // Fetch the current epoch from the server
    final epochData = await _api.getCurrentEpoch(conversationId);

    if (epochData != null && epochData['myKey'] != null) {
      // Epoch exists and we have a key — unwrap it
      final myKey = epochData['myKey'] as Map<String, dynamic>;
      final epochId = epochData['id'] as String;
      final rawKey = await _unwrapEpochKey(EpochKeyData(
        encryptedKey: myKey['encryptedKey'] as String,
        keyNonce: myKey['keyNonce'] as String,
        wrappedById: myKey['wrappedById'] as String,
      ));
      if (rawKey != null) {
        _epochKeyCache[epochId] = rawKey;
        return (epochId: epochId, rawKey: rawKey, epochInit: null);
      }
    }

    if (epochData != null && epochData['myKey'] == null) {
      // Epoch exists but has no keys — lazy init
      final epochId = epochData['id'] as String;
      final result = await _generateAndWrapEpochKey(conversationId);
      _epochKeyCache[epochId] = result.rawKey;
      return (
        epochId: epochId,
        rawKey: result.rawKey,
        epochInit: {'keys': result.wrappedKeys},
      );
    }

    // No epoch at all — create one
    final result = await _generateAndWrapEpochKey(conversationId);
    final created = await _api.createEpoch(conversationId, result.wrappedKeys);
    final epochId = created['id'] as String;
    _epochKeyCache[epochId] = result.rawKey;
    return (epochId: epochId, rawKey: result.rawKey, epochInit: null);
  }

  /// Generate a new epoch key and wrap it for all participants in the conversation.
  Future<({String rawKey, List<Map<String, dynamic>> wrappedKeys})> _generateAndWrapEpochKey(
    String conversationId,
  ) async {
    final conv = conversationById(conversationId);
    final participantIds = conv?.participants.map((p) => p.id).toList() ?? [];
    if (participantIds.isEmpty) {
      // Fallback: fetch from API
      final details = await _api.getConversationDetails(conversationId);
      final participants = details['participants'] as List<dynamic>? ?? [];
      participantIds.addAll(participants.map((p) => (p as Map<String, dynamic>)['id'] as String));
    }

    final pubKeys = await _api.fetchPublicKeys(participantIds);
    final rawKey = await CryptoService.generateEpochKey();

    final wrappedKeys = <Map<String, dynamic>>[];
    for (final entry in pubKeys.entries) {
      final wrapped = await CryptoService.wrapEpochKeyForUser(rawKey, keyPair!, entry.value);
      wrappedKeys.add({
        'userId': entry.key,
        'encryptedKey': wrapped.encryptedKey,
        'keyNonce': wrapped.keyNonce,
      });
    }

    return (rawKey: rawKey, wrappedKeys: wrappedKeys);
  }

  Future<ZippMessage?> sendGroupTextMessage({
    required String conversationId,
    required String text,
    String? replyToId,
  }) async {
    if (keyPair == null) return null;

    final epoch = await _ensureEpoch(conversationId);
    final enc = await CryptoService.encryptWithEpochKey(text, epoch.rawKey);

    final msg = await _api.sendMessage(
      conversationId: conversationId,
      ciphertext: enc.ciphertext,
      nonce: enc.nonce,
      epochId: epoch.epochId,
      epoch: epoch.epochInit,
      type: 'TEXT',
      replyToId: replyToId,
    );
    msg.plaintext = text;
    _sentMsgIds.add(msg.id);
    _appendMessage(conversationId, msg);
    return msg;
  }

  Future<ZippMessage?> sendGroupGifMessage({
    required String conversationId,
    required Map<String, dynamic> gifResult,
  }) async {
    if (keyPair == null) return null;

    final payload = jsonEncode({
      'gifUrl': gifResult['file']?['md']?['gif']?['url'] ?? '',
      'tinyUrl': gifResult['file']?['xs']?['gif']?['url'] ?? '',
      'title': gifResult['title'] ?? '',
    });

    final epoch = await _ensureEpoch(conversationId);
    final enc = await CryptoService.encryptWithEpochKey(payload, epoch.rawKey);

    final msg = await _api.sendMessage(
      conversationId: conversationId,
      ciphertext: enc.ciphertext,
      nonce: enc.nonce,
      epochId: epoch.epochId,
      epoch: epoch.epochInit,
      type: 'GIF',
    );
    msg.plaintext = payload;
    _sentMsgIds.add(msg.id);
    _appendMessage(conversationId, msg);
    return msg;
  }

  Future<ZippMessage?> sendGroupAttachmentMessage({
    required String conversationId,
    required Map<String, dynamic> attachment,
    required String type,
    String? caption,
  }) async {
    if (keyPair == null) return null;

    if (caption != null && caption.isNotEmpty) {
      attachment['caption'] = caption;
    }
    final payload = jsonEncode(attachment);

    final epoch = await _ensureEpoch(conversationId);
    final enc = await CryptoService.encryptWithEpochKey(payload, epoch.rawKey);

    final msg = await _api.sendMessage(
      conversationId: conversationId,
      ciphertext: enc.ciphertext,
      nonce: enc.nonce,
      epochId: epoch.epochId,
      epoch: epoch.epochInit,
      type: type,
    );
    msg.plaintext = payload;
    _sentMsgIds.add(msg.id);
    _appendMessage(conversationId, msg);
    return msg;
  }

  // ── Group member management ────────────────────────────────────────────────

  Future<void> inviteMembers({
    required String conversationId,
    required List<String> userIds,
    bool shareHistory = false,
  }) async {
    if (keyPair == null) return;

    // Get all participants (existing + new) public keys
    final conv = conversationById(conversationId);
    final existingIds = conv?.participants.map((p) => p.id).toList() ?? [];
    final allIds = {...existingIds, ...userIds}.toList();
    final pubKeys = await _api.fetchPublicKeys(allIds);

    // Generate new epoch key and wrap for everyone
    final rawKey = await CryptoService.generateEpochKey();
    final newEpochKeys = <Map<String, dynamic>>[];
    for (final entry in pubKeys.entries) {
      final wrapped = await CryptoService.wrapEpochKeyForUser(rawKey, keyPair!, entry.value);
      newEpochKeys.add({
        'userId': entry.key,
        'encryptedKey': wrapped.encryptedKey,
        'keyNonce': wrapped.keyNonce,
      });
    }

    // Optionally share history
    List<Map<String, dynamic>>? historyKeys;
    if (shareHistory) {
      historyKeys = await _wrapHistoryForNewMembers(conversationId, userIds, pubKeys);
    }

    await _api.inviteMembers(
      convId: conversationId,
      userIds: userIds,
      shareHistory: shareHistory,
      newEpoch: {'keys': newEpochKeys},
      epochKeys: historyKeys,
    );
  }

  Future<List<Map<String, dynamic>>> _wrapHistoryForNewMembers(
    String conversationId,
    List<String> newUserIds,
    Map<String, String> pubKeys,
  ) async {
    final epochs = await _api.getEpochs(conversationId);
    final historyKeys = <Map<String, dynamic>>[];

    for (final epoch in epochs) {
      final myKey = epoch['myKey'] as Map<String, dynamic>?;
      if (myKey == null) continue;

      final rawEpochKey = await _unwrapEpochKey(EpochKeyData(
        encryptedKey: myKey['encryptedKey'] as String,
        keyNonce: myKey['keyNonce'] as String,
        wrappedById: myKey['wrappedById'] as String,
      ));
      if (rawEpochKey == null) continue;

      for (final uid in newUserIds) {
        final pub = pubKeys[uid];
        if (pub == null) continue;
        final wrapped = await CryptoService.wrapEpochKeyForUser(rawEpochKey, keyPair!, pub);
        historyKeys.add({
          'epochId': epoch['id'] as String,
          'userId': uid,
          'encryptedKey': wrapped.encryptedKey,
          'keyNonce': wrapped.keyNonce,
        });
      }
    }

    return historyKeys;
  }

  Future<void> removeMember(String conversationId, String userId) async {
    await _api.removeMember(conversationId, userId);
  }

  Future<void> changeRole(String conversationId, String userId, String role) async {
    await _api.changeRole(conversationId, userId, role);
  }

  Future<void> leaveGroup(String conversationId) async {
    await _api.leaveGroup(conversationId);
    _conversations.removeWhere((c) => c.id == conversationId);
    _messages.remove(conversationId);
    notifyListeners();
  }

  Future<void> renameGroup(String conversationId, String name) async {
    await _api.renameGroup(conversationId, name);
  }

  // ── Message helpers ─────────────────────────────────────────────────────────

  void _appendMessage(String convId, ZippMessage msg) {
    final msgs = _messages.putIfAbsent(convId, () => []);
    if (msgs.any((m) => m.id == msg.id)) return;
    msgs.add(msg);
    _bumpConversation(convId, msg);
    notifyListeners();
  }

  void _bumpConversation(String convId, ZippMessage msg) {
    final idx = _conversations.indexWhere((c) => c.id == convId);
    if (idx < 0) return;
    final old = _conversations.removeAt(idx);

    LastMessagePreview preview;
    if (msg.isGroupMessage) {
      preview = LastMessagePreview(
        id: msg.id,
        type: msg.type.name.toUpperCase(),
        createdAt: msg.createdAt,
        senderId: msg.senderId,
        ciphertext: msg.ciphertext,
        nonce: msg.nonce,
        epochId: msg.epochId,
        epochKey: msg.epochKey,
        plaintext: msg.plaintext,
      );
    } else {
      preview = LastMessagePreview(
        id: msg.id,
        type: msg.type.name.toUpperCase(),
        createdAt: msg.createdAt,
        senderId: msg.senderId,
        recipientCiphertext: msg.recipientCiphertext,
        senderCiphertext: msg.senderCiphertext,
        nonce: msg.nonce,
        plaintext: msg.plaintext,
      );
    }

    _conversations.insert(0, old.copyWith(lastMessage: preview, updatedAt: msg.createdAt));
  }

  // ── Edit / Delete ────────────────────────────────────────────────────────

  Future<bool> editMessage({
    required String conversationId,
    required String messageId,
    required String newText,
    required String recipientId,
  }) async {
    if (keyPair == null) return false;

    final existingMsg = _messages[conversationId]?.firstWhere((m) => m.id == messageId);

    ZippMessage updated;
    if (existingMsg?.isGroupMessage == true) {
      // Group edit — re-encrypt with epoch key
      final epochKey = existingMsg!.epochKey != null
          ? await _unwrapEpochKey(existingMsg.epochKey!)
          : _epochKeyCache[existingMsg.epochId];
      if (epochKey == null) return false;

      final enc = await CryptoService.encryptWithEpochKey(newText, epochKey);
      updated = await _api.editMessage(
        conversationId: conversationId,
        messageId: messageId,
        ciphertext: enc.ciphertext,
        nonce: enc.nonce,
      );
    } else {
      // DM edit
      final recipientKey = await _getPublicKey(recipientId);
      if (recipientKey == null) return false;

      final encRecipient = await CryptoService.encrypt(newText, keyPair!, recipientKey);
      final sharedNonce = base64Url.decode(encRecipient.nonce);
      final myPubKey = await CryptoService.getPublicKeyBase64(keyPair!);
      final encSender = await CryptoService.encrypt(newText, keyPair!, myPubKey, nonce: sharedNonce);

      updated = await _api.editMessage(
        conversationId: conversationId,
        messageId: messageId,
        recipientCiphertext: encRecipient.ciphertext,
        senderCiphertext: encSender.ciphertext,
        nonce: encRecipient.nonce,
      );
    }

    final msgs = _messages[conversationId];
    if (msgs != null) {
      final idx = msgs.indexWhere((m) => m.id == messageId);
      if (idx >= 0) {
        msgs[idx] = msgs[idx].copyWith(
          plaintext: newText,
          editedAt: updated.editedAt ?? DateTime.now(),
          recipientCiphertext: updated.recipientCiphertext,
          senderCiphertext: updated.senderCiphertext,
          ciphertext: updated.ciphertext,
          nonce: updated.nonce,
        );
        _sentMsgIds.add(messageId);
        _refreshConversationPreview(conversationId, msgs);
        notifyListeners();
      }
    }
    return true;
  }

  Future<void> deleteMessage({
    required String conversationId,
    required String messageId,
  }) async {
    await _api.deleteMessage(
      conversationId: conversationId,
      messageId: messageId,
    );

    final msgs = _messages[conversationId];
    if (msgs != null) {
      final hasReplies = msgs.any((m) => m.replyToId == messageId);
      if (hasReplies) {
        final idx = msgs.indexWhere((m) => m.id == messageId);
        if (idx >= 0) {
          msgs[idx] = msgs[idx].copyWith(
            deletedAt: DateTime.now(),
            plaintext: null,
          );
        }
      } else {
        msgs.removeWhere((m) => m.id == messageId);
      }
      _sentMsgIds.add(messageId);
      _refreshConversationPreview(conversationId, msgs);
      notifyListeners();
    }
  }

  void _refreshConversationPreview(String convId, List<ZippMessage> msgs) {
    final convIdx = _conversations.indexWhere((c) => c.id == convId);
    if (convIdx < 0) return;
    final conv = _conversations[convIdx];

    final lastMsg = msgs.lastOrNull;

    LastMessagePreview? preview;
    if (lastMsg != null && !lastMsg.isDeleted) {
      if (lastMsg.isGroupMessage) {
        preview = LastMessagePreview(
          id: lastMsg.id,
          type: lastMsg.type.name.toUpperCase(),
          createdAt: lastMsg.createdAt,
          senderId: lastMsg.senderId,
          ciphertext: lastMsg.ciphertext,
          nonce: lastMsg.nonce,
          epochId: lastMsg.epochId,
          epochKey: lastMsg.epochKey,
          plaintext: lastMsg.plaintext,
        );
      } else {
        preview = LastMessagePreview(
          id: lastMsg.id,
          type: lastMsg.type.name.toUpperCase(),
          createdAt: lastMsg.createdAt,
          senderId: lastMsg.senderId,
          recipientCiphertext: lastMsg.recipientCiphertext,
          senderCiphertext: lastMsg.senderCiphertext,
          nonce: lastMsg.nonce,
          plaintext: lastMsg.plaintext,
        );
      }
    }

    _conversations[convIdx] = conv.copyWith(lastMessage: preview);
  }

  // ── Read receipts ────────────────────────────────────────────────────────

  Future<void> markLastMessageRead(String convId, String myId) async {
    final msgs = _messages[convId];
    if (msgs == null || msgs.isEmpty) return;

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
    final myPubKey = await CryptoService.getPublicKeyBase64(keyPair!);

    for (final msg in msgs) {
      if (msg.plaintext != null) continue;
      if (msg.isDeleted || msg.nonce == null) continue;

      if (msg.isGroupMessage) {
        // Group message — epoch decryption
        if (msg.ciphertext == null) continue;
        final epochKey = await _getEpochKeyForMessage(msg);
        if (epochKey == null) continue;
        msg.plaintext = await CryptoService.decryptWithEpochKey(msg.ciphertext!, msg.nonce!, epochKey);
      } else {
        // DM message — existing dual-ciphertext decryption
        if (msg.recipientCiphertext == null) continue;
        final senderKey = await _getPublicKey(msg.senderId);
        if (senderKey == null) continue;
        final plain = await CryptoService.decrypt(
            msg.recipientCiphertext!, msg.nonce!, keyPair!, senderKey);
        if (plain != null) {
          msg.plaintext = plain;
        } else if (msg.senderCiphertext != null) {
          final senderPlain = await CryptoService.decryptForSender(
              msg.senderCiphertext!, msg.nonce!, keyPair!, myPubKey);
          if (senderPlain != null) msg.plaintext = senderPlain;
        }
      }

      // Decrypt reply preview if present
      final reply = msg.replyTo;
      if (reply != null && reply.plaintext == null && reply.nonce != null) {
        if (reply.epochId != null && reply.ciphertext != null) {
          // Group reply
          final epochKey = reply.epochKey != null
              ? await _unwrapEpochKey(reply.epochKey!)
              : _epochKeyCache[reply.epochId];
          if (epochKey != null) {
            reply.plaintext = await CryptoService.decryptWithEpochKey(
                reply.ciphertext!, reply.nonce!, epochKey);
          }
        } else if (reply.recipientCiphertext != null) {
          // DM reply
          final replyKey = await _getPublicKey(reply.senderId);
          if (replyKey != null) {
            final rPlain = await CryptoService.decrypt(
                reply.recipientCiphertext!, reply.nonce!, keyPair!, replyKey);
            if (rPlain != null) {
              reply.plaintext = rPlain;
            } else if (reply.senderCiphertext != null) {
              final rSender = await CryptoService.decryptForSender(
                  reply.senderCiphertext!, reply.nonce!, keyPair!, myPubKey);
              if (rSender != null) reply.plaintext = rSender;
            }
          }
        }
      }
    }
  }

  Future<String?> _getEpochKeyForMessage(ZippMessage msg) async {
    final epochId = msg.epochId;
    if (epochId == null) return null;

    // Check cache
    if (_epochKeyCache.containsKey(epochId)) return _epochKeyCache[epochId];

    // Unwrap from message's epoch key data
    if (msg.epochKey != null) {
      final rawKey = await _unwrapEpochKey(msg.epochKey!);
      if (rawKey != null) {
        _epochKeyCache[epochId] = rawKey;
        return rawKey;
      }
    }
    return null;
  }

  Future<String?> _unwrapEpochKey(EpochKeyData keyData) async {
    if (keyPair == null) return null;
    final wrapperPub = await _getPublicKey(keyData.wrappedById);
    if (wrapperPub == null) return null;
    return await CryptoService.unwrapEpochKey(
      keyData.encryptedKey,
      keyData.keyNonce,
      keyPair!,
      wrapperPub,
    );
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
      case 'message:edit':
        _handleMessageEdit(payload);
      case 'message:delete':
        _handleMessageDelete(payload);
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
      // Group events
      case 'conversation:new':
        _handleConversationNew(payload);
      case 'conversation:member-added':
        _handleMemberAdded(payload);
      case 'conversation:member-removed':
        _handleMemberRemoved(payload);
      case 'conversation:member-left':
        _handleMemberLeft(payload);
      case 'conversation:role-changed':
        _handleRoleChanged(payload);
      case 'conversation:renamed':
        _handleRenamed(payload);
      case 'epoch:created':
        _handleEpochCreated(payload);
    }
  }

  Future<void> _handleNewMessage(Map<String, dynamic> payload) async {
    final convId = payload['conversationId'] as String?;
    final msgJson = payload['message'] as Map<String, dynamic>?;
    if (convId == null || msgJson == null) return;

    final msg = ZippMessage.fromJson(msgJson);

    if (_sentMsgIds.remove(msg.id)) return;

    final existingMsgs = _messages[convId];
    if (existingMsgs?.any((m) => m.id == msg.id) ?? false) return;

    await _decryptAll([msg]);
    _appendMessage(convId, msg);
    _notifyNewMessage(convId, msg);
  }

  /// Searches all loaded conversations for a participant with [senderId].
  /// Falls back to 'Someone' only if the user truly isn't found anywhere.
  String _findSenderName(String senderId) {
    for (final conv in _conversations) {
      for (final p in conv.participants) {
        if (p.id == senderId) return p.name;
      }
      if (conv.participant?.id == senderId) return conv.participant!.name;
    }
    return 'Someone';
  }

  void _notifyNewMessage(String convId, ZippMessage msg) {
    if (msg.senderId == currentUserId) return;

    final ns = NotificationService.instance;
    final conv = conversationById(convId);
    String senderName;
    if (conv?.isGroup == true) {
      final sender = conv!.participants.cast<ConversationParticipant?>().firstWhere(
        (p) => p!.id == msg.senderId,
        orElse: () => null,
      );
      senderName = sender?.name ?? _findSenderName(msg.senderId);
    } else {
      senderName = conv?.participant?.name ?? _findSenderName(msg.senderId);
    }

    final preview = (msg.plaintext != null && msg.type == MessageType.text)
        ? msg.plaintext!
        : switch (msg.type) {
            MessageType.gif => 'Sent a GIF',
            MessageType.image => 'Sent an image',
            MessageType.video => 'Sent a video',
            MessageType.file => 'Sent a file',
            MessageType.text => 'New message',
          };

    ns.showMessageNotification(
      conversationId: convId,
      senderName: senderName,
      messagePreview: preview,
      messageType: msg.type.name.toUpperCase(),
    );

    if (ns.activeConversationId != convId || !ns.isAppFocused) {
      _unreadConvIds.add(convId);
      _updateTrayBadge();
    }
  }

  void Function(int count)? onUnreadCountChanged;

  void _updateTrayBadge() {
    onUnreadCountChanged?.call(_unreadConvIds.length);
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

  Future<void> _handleMessageEdit(Map<String, dynamic> payload) async {
    final convId = payload['conversationId'] as String?;
    final msgJson = payload['message'] as Map<String, dynamic>?;
    if (convId == null || msgJson == null) return;

    final updated = ZippMessage.fromJson(msgJson);

    if (_sentMsgIds.remove(updated.id)) return;

    final msgs = _messages[convId];
    if (msgs == null) return;
    final idx = msgs.indexWhere((m) => m.id == updated.id);
    if (idx < 0) return;

    await _decryptAll([updated]);
    msgs[idx] = updated;
    _refreshConversationPreview(convId, msgs);
    notifyListeners();
  }

  void _handleMessageDelete(Map<String, dynamic> payload) {
    final convId = payload['conversationId'] as String?;
    final messageId = payload['messageId'] as String?;
    final softDelete = payload['softDelete'] as bool? ?? false;
    if (convId == null || messageId == null) return;

    if (_sentMsgIds.remove(messageId)) return;

    final msgs = _messages[convId];
    if (msgs == null) return;

    if (softDelete) {
      final idx = msgs.indexWhere((m) => m.id == messageId);
      if (idx >= 0) {
        msgs[idx] = msgs[idx].copyWith(
          deletedAt: DateTime.now(),
          plaintext: null,
        );
      }
    } else {
      msgs.removeWhere((m) => m.id == messageId);
    }

    _refreshConversationPreview(convId, msgs);
    notifyListeners();
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

    final targetIdx = msgs.indexWhere((m) => m.id == msgId);
    if (targetIdx < 0) return;

    final parsedReadAt = readAt != null ? DateTime.parse(readAt) : null;
    final targetSenderId = msgs[targetIdx].senderId;
    bool changed = false;

    for (int i = 0; i <= targetIdx; i++) {
      final m = msgs[i];
      if (m.senderId == targetSenderId && !m.isRead) {
        msgs[i] = m.copyWith(readAt: parsedReadAt);
        changed = true;
      }
    }

    if (changed) notifyListeners();
  }

  // ── Group WS event handlers ────────────────────────────────────────────────

  void _handleConversationNew(Map<String, dynamic> payload) {
    final convJson = payload['conversation'] as Map<String, dynamic>?;
    if (convJson == null) return;
    final conv = Conversation.fromJson(convJson);
    if (!_conversations.any((c) => c.id == conv.id)) {
      _conversations.insert(0, conv);
      notifyListeners();
    }
  }

  void _handleMemberAdded(Map<String, dynamic> payload) {
    final convId = payload['conversationId'] as String?;
    final participantsJson = payload['participants'] as List<dynamic>?;
    if (convId == null || participantsJson == null) return;

    final idx = _conversations.indexWhere((c) => c.id == convId);
    if (idx < 0) return;

    final participants = participantsJson
        .map((p) => ConversationParticipant.fromJson(p as Map<String, dynamic>))
        .toList();

    _conversations[idx] = _conversations[idx].copyWith(participants: participants);
    notifyListeners();
  }

  void _handleMemberRemoved(Map<String, dynamic> payload) {
    final convId = payload['conversationId'] as String?;
    final userId = payload['userId'] as String?;
    if (convId == null || userId == null) return;

    // If it's us being removed, remove the conversation
    if (userId == currentUserId) {
      _conversations.removeWhere((c) => c.id == convId);
      _messages.remove(convId);
      notifyListeners();
      return;
    }

    final idx = _conversations.indexWhere((c) => c.id == convId);
    if (idx < 0) return;

    final updated = _conversations[idx].participants.where((p) => p.id != userId).toList();
    _conversations[idx] = _conversations[idx].copyWith(participants: updated);
    notifyListeners();
  }

  void _handleMemberLeft(Map<String, dynamic> payload) {
    _handleMemberRemoved(payload);
  }

  void _handleRoleChanged(Map<String, dynamic> payload) {
    final convId = payload['conversationId'] as String?;
    final userId = payload['userId'] as String?;
    final role = payload['role'] as String?;
    if (convId == null || userId == null || role == null) return;

    final idx = _conversations.indexWhere((c) => c.id == convId);
    if (idx < 0) return;

    final participants = _conversations[idx].participants.map((p) {
      if (p.id == userId) {
        return ConversationParticipant(
          id: p.id, username: p.username, displayName: p.displayName, avatarUrl: p.avatarUrl, role: role,
        );
      }
      return p;
    }).toList();

    _conversations[idx] = _conversations[idx].copyWith(participants: participants);
    notifyListeners();
  }

  void _handleRenamed(Map<String, dynamic> payload) {
    final convId = payload['conversationId'] as String?;
    final name = payload['name'] as String?;
    if (convId == null || name == null) return;

    final idx = _conversations.indexWhere((c) => c.id == convId);
    if (idx < 0) return;

    _conversations[idx] = _conversations[idx].copyWith(name: name);
    notifyListeners();
  }

  void _handleEpochCreated(Map<String, dynamic> payload) {
    final convId = payload['conversationId'] as String?;
    if (convId == null) return;
    // Clear epoch cache for this conversation — new epoch means old cached keys may be stale
    // The next send will re-fetch the current epoch
    _epochKeyCache.removeWhere((key, _) {
      // We don't have a direct epochId->convId mapping in the cache,
      // so we just let the next _ensureEpoch call refresh it
      return false;
    });
  }

  @override
  void dispose() {
    _ws.removeListener(_onWsEvent);
    super.dispose();
  }
}
