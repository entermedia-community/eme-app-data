import 'dart:convert';
import 'dart:math';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/api_client.dart';
import '../../core/settings.dart';

class AuthSession {
  const AuthSession({required this.token, required this.user});
  final String token;
  final Map<String, dynamic> user;

  String get userId => '${user['id'] ?? ''}';
  String get displayName {
    final screen = '${user['screenname'] ?? ''}'.trim();
    if (screen.isNotEmpty) return screen;
    final full = '${user['firstname'] ?? ''} ${user['lastname'] ?? ''}'.trim();
    return full.isNotEmpty ? full : userId;
  }

  String? get portrait => user['assetportrait'] as String?;
}

/// Passwordless sign-in against EME:
///  1. `sendusercode.json` emails a 6 digit code.
///  2. `token.json grant_type=otp` redeems it and registers this browser's Ed25519 public key.
///  3. Later sessions sign a challenge with that key (`grant_type=key`), so no new code is needed.
/// An application password (`emeapp.<id>.<secret>`) can be used instead.
class AuthController extends AsyncNotifier<AuthSession?> {
  static const _kToken = 'auth.token';
  static const _kExpiry = 'auth.expiry';
  static const _kUser = 'auth.user';
  static const _kKeyId = 'auth.keyId';
  static const _kSeed = 'auth.seed';
  static const _kUsername = 'auth.username';

  final _ed = Ed25519();
  Future<bool>? _refreshing;

  SharedPreferences get _prefs => ref.read(sharedPrefsProvider);
  ApiClient get _api => ref.read(apiClientProvider);
  TokenHolder get _holder => ref.read(tokenHolderProvider);

  @override
  Future<AuthSession?> build() async {
    _holder.refresh = _refreshWithKey;
    final token = _prefs.getString(_kToken);
    final expiry = _prefs.getInt(_kExpiry) ?? 0;
    final user = _decodeUser(_prefs.getString(_kUser));
    final stillValid =
        token != null && (expiry == 0 || expiry > DateTime.now().add(const Duration(hours: 1)).millisecondsSinceEpoch);
    if (stillValid && user != null) {
      _holder.token = token;
      return AuthSession(token: token, user: user);
    }
    if (_prefs.getString(_kSeed) != null) {
      try {
        return await _keyLogin();
      } catch (_) {
        // Key revoked or server unreachable: fall through to the login page.
      }
    }
    _holder.token = null;
    return null;
  }

  /// Step 1. Returns the email the code was sent to.
  Future<String> sendCode(String email) async {
    final res = await _api.postForm('authentication/sendusercode.json', {'email': email.trim()}, auth: false);
    final r = res['response'] as Map? ?? const {};
    switch (r['status']) {
      case 'ok':
        return '${r['email'] ?? email}';
      case 'nouser':
        throw ApiException('No account found for $email');
      default:
        throw ApiException('${r['error'] ?? 'Could not send the code'}');
    }
  }

  /// Step 2. Redeems the code and registers a device key for silent re-login.
  Future<void> verifyCode(String email, String code) async {
    final keyPair = await _ed.newKeyPair();
    final pub = await keyPair.extractPublicKey();
    final seed = await keyPair.extractPrivateKeyBytes();
    final res = await _api.postForm('authentication/token.json', {
      'grant_type': 'otp',
      'email': email.trim(),
      'code': code.trim(),
      'publickey': base64UrlNoPad(ed25519Spki(pub.bytes)),
      'label': 'EME Data App (web)',
    }, auth: false);
    final session = _accept(res);
    await _prefs.setString(_kSeed, base64Encode(seed));
    await _prefs.setString(_kKeyId, '${res['key_id'] ?? ''}');
    await _prefs.setString(_kUsername, session.userId);
    state = AsyncData(session);
  }

  /// Alternative: an application password created in EME (never expires).
  Future<void> useAppPassword(String secret) async {
    final token = secret.trim();
    _holder.token = token;
    try {
      final res = await _api.getJson('authentication/user.json');
      final user = res['user'];
      if (user is! Map<String, dynamic>) throw ApiException('That application password was not accepted');
      await _store(token, user, 0);
      await _clearKey();
      state = AsyncData(AuthSession(token: token, user: user));
    } catch (e) {
      _holder.token = null;
      rethrow;
    }
  }

  Future<void> logout() async {
    final keyId = _prefs.getString(_kKeyId);
    if (keyId != null && keyId.isNotEmpty) {
      try {
        await _api.postForm('authentication/revokekey.json', {'keyid': keyId});
      } catch (_) {}
    }
    for (final k in [_kToken, _kExpiry, _kUser]) {
      await _prefs.remove(k);
    }
    await _clearKey();
    _holder.token = null;
    state = const AsyncData(null);
  }

  Future<bool> _refreshWithKey() {
    if (_prefs.getString(_kSeed) == null) return Future.value(false);
    return _refreshing ??= () async {
      try {
        state = AsyncData(await _keyLogin());
        return true;
      } catch (_) {
        return false;
      } finally {
        _refreshing = null;
      }
    }();
  }

  Future<AuthSession> _keyLogin() async {
    final seed = base64Decode(_prefs.getString(_kSeed)!);
    final keyId = _prefs.getString(_kKeyId) ?? '';
    final username = _prefs.getString(_kUsername) ?? '';
    final keyPair = await _ed.newKeyPairFromSeed(seed);
    final timestamp = '${DateTime.now().millisecondsSinceEpoch}';
    final nonce = _nonce();
    final message = utf8.encode('$username\n$keyId\n$timestamp\n$nonce');
    final sig = await _ed.sign(message, keyPair: keyPair);
    final res = await _api.postForm('authentication/token.json', {
      'grant_type': 'key',
      'username': username,
      'key_id': keyId,
      'timestamp': timestamp,
      'nonce': nonce,
      'signature': base64UrlNoPad(sig.bytes),
    }, auth: false);
    return _accept(res);
  }

  AuthSession _accept(Map<String, dynamic> res) {
    final token = res['access_token'] as String?;
    final user = res['user'];
    if (token == null || user is! Map<String, dynamic>) {
      throw ApiException('${res['error_description'] ?? res['error'] ?? 'Sign in failed'}');
    }
    final expiresIn = (res['expires_in'] as num?)?.toInt() ?? 0;
    final expiry = expiresIn > 0 ? DateTime.now().add(Duration(seconds: expiresIn)).millisecondsSinceEpoch : 0;
    _store(token, user, expiry);
    return AuthSession(token: token, user: user);
  }

  Future<void> _store(String token, Map<String, dynamic> user, int expiry) async {
    _holder.token = token;
    await _prefs.setString(_kToken, token);
    await _prefs.setInt(_kExpiry, expiry);
    await _prefs.setString(_kUser, jsonEncode(user));
  }

  Future<void> _clearKey() async {
    for (final k in [_kSeed, _kKeyId, _kUsername]) {
      await _prefs.remove(k);
    }
  }

  static Map<String, dynamic>? _decodeUser(String? s) {
    if (s == null) return null;
    try {
      return jsonDecode(s) as Map<String, dynamic>;
    } catch (_) {
      return null;
    }
  }

  static String _nonce() {
    final r = Random.secure();
    return base64UrlNoPad(List<int>.generate(24, (_) => r.nextInt(256)));
  }
}

/// X.509 SubjectPublicKeyInfo DER for a raw 32 byte Ed25519 key (what Java's X509EncodedKeySpec expects).
List<int> ed25519Spki(List<int> raw) => [
  0x30,
  0x2a,
  0x30,
  0x05,
  0x06,
  0x03,
  0x2b,
  0x65,
  0x70,
  0x03,
  0x21,
  0x00,
  ...raw,
];

String base64UrlNoPad(List<int> bytes) => base64Url.encode(bytes).replaceAll('=', '');

final authProvider = AsyncNotifierProvider<AuthController, AuthSession?>(AuthController.new);
