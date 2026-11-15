import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'db.dart';
import 'i18n.dart';
import 'services.dart';
import 'ui.dart' show kAtelierName;
import 'voice.dart';

/// État global : session, atelier courant, thème, langue, verrouillage.
class AppState extends ChangeNotifier {
  late SharedPreferences prefs;

  int? userId;
  String userName = '';
  String role = 'admin';
  int? atelierId;
  String atelierName = '';
  List<Map<String, Object?>> ateliers = [];

  bool dark = false;
  bool bioEnabled = false;
  bool autoLock = true;
  bool voice = true; // voix de bienvenue
  bool locked = false;
  String lang = 'fr';

  /// Délai (secondes) en arrière-plan avant verrouillage automatique.
  static const lockDelay = 120;

  bool get isAdmin => role == 'admin';

  Future<void> init() async {
    prefs = await SharedPreferences.getInstance();
    dark = prefs.getBool('dark') ?? false;
    lang = prefs.getString('lang') ?? 'fr';
    currentLang = lang;
    bioEnabled = prefs.getBool('bio') ?? false;
    autoLock = prefs.getBool('autolock') ?? true;
    voice = prefs.getBool('voice') ?? true;
  }

  static String _salt() {
    final r = Random.secure();
    return base64Url.encode(List<int>.generate(12, (_) => r.nextInt(256)));
  }

  // ---------- Compte ----------

  Future<String?> register(String name, String email, String pw, String recovery) async {
    email = email.trim().toLowerCase();
    if (name.trim().isEmpty || !email.contains('@')) return 'Nom ou email invalide';
    if (pw.length < 6) return 'Mot de passe : 6 caractères minimum';
    if (recovery.length < 4) return 'Code de récupération : 4 caractères minimum';
    final ex = await Db.i.q('SELECT id FROM users WHERE email=?', [email]);
    if (ex.isNotEmpty) return 'Cet email est déjà utilisé';
    final salt = _salt();
    final uid = await Db.i.ins('users', {
      'email': email,
      'name': name.trim(),
      'salt': salt,
      'pass_hash': Db.hash(pw, salt),
      'recovery_hash': Db.hash(recovery, salt),
      'role': 'admin',
    });
    final aid = await Db.i.ins('ateliers', {'name': kAtelierName, 'owner_id': uid});
    await Db.i.upd('users', {'atelier_id': aid}, uid);
    return login(email, pw);
  }

  Future<String?> addEmployee(String name, String email, String pw, String recovery) async {
    email = email.trim().toLowerCase();
    if (name.trim().isEmpty || !email.contains('@')) return 'Nom ou email invalide';
    if (pw.length < 6) return 'Mot de passe : 6 caractères minimum';
    if (recovery.length < 4) return 'Code de récupération : 4 caractères minimum';
    final ex = await Db.i.q('SELECT id FROM users WHERE email=?', [email]);
    if (ex.isNotEmpty) return 'Cet email est déjà utilisé';
    final salt = _salt();
    await Db.i.ins('users', {
      'email': email,
      'name': name.trim(),
      'salt': salt,
      'pass_hash': Db.hash(pw, salt),
      'recovery_hash': Db.hash(recovery, salt),
      'role': 'employe',
      'atelier_id': atelierId,
    });
    return null;
  }

  Future<String?> login(String email, String pw) async {
    final r = await Db.i.q('SELECT * FROM users WHERE email=?', [email.trim().toLowerCase()]);
    if (r.isEmpty) return 'Compte introuvable';
    final u = r.first;
    if (Db.hash(pw, s0(u['salt'])) != u['pass_hash']) return 'Mot de passe incorrect';
    await _enter(u);
    return null;
  }

  Future<String?> bioLogin() async {
    final email = prefs.getString('last_email');
    if (email == null || !bioEnabled) return 'Connexion biométrique non activée';
    if (!await Bio.auth()) return 'Authentification annulée';
    final r = await Db.i.q('SELECT * FROM users WHERE email=?', [email]);
    if (r.isEmpty) return 'Compte introuvable';
    await _enter(r.first);
    return null;
  }

  Future<String?> resetPassword(String email, String code, String newPw) async {
    if (newPw.length < 6) return 'Mot de passe : 6 caractères minimum';
    final r = await Db.i.q('SELECT * FROM users WHERE email=?', [email.trim().toLowerCase()]);
    if (r.isEmpty) return 'Compte introuvable';
    final u = r.first;
    final salt = s0(u['salt']);
    if (Db.hash(code, salt) != u['recovery_hash']) return 'Code de récupération incorrect';
    await Db.i.upd('users', {'pass_hash': Db.hash(newPw, salt)}, u['id'] as int);
    return null;
  }

  Future<bool> checkPassword(String pw) async {
    if (userId == null) return false;
    final r = await Db.i.q('SELECT * FROM users WHERE id=?', [userId]);
    if (r.isEmpty) return false;
    return Db.hash(pw, s0(r.first['salt'])) == r.first['pass_hash'];
  }

  Future<void> _enter(Map<String, Object?> u) async {
    userId = u['id'] as int;
    userName = s0(u['name']);
    role = s0(u['role']).isEmpty ? 'admin' : s0(u['role']);
    await prefs.setString('last_email', s0(u['email']));
    await loadAteliers();
    locked = false;
    notifyListeners();
  }

  Future<void> loadAteliers() async {
    final uid = userId!;
    final u = (await Db.i.q('SELECT * FROM users WHERE id=?', [uid])).first;
    if (role == 'admin') {
      ateliers = await Db.i.q('SELECT * FROM ateliers WHERE owner_id=? ORDER BY id', [uid]);
    } else {
      ateliers = await Db.i.q('SELECT * FROM ateliers WHERE id=?', [u['atelier_id']]);
    }
    if (ateliers.isEmpty) {
      final aid = await Db.i.ins('ateliers', {'name': kAtelierName, 'owner_id': uid});
      ateliers = await Db.i.q('SELECT * FROM ateliers WHERE id=?', [aid]);
    }
    final saved = prefs.getInt('atelier_$uid');
    final cur = ateliers.firstWhere((a) => a['id'] == saved, orElse: () => ateliers.first);
    atelierId = cur['id'] as int;
    atelierName = s0(cur['name']);
  }

  Future<void> switchAtelier(int id) async {
    final cur = ateliers.firstWhere((a) => a['id'] == id);
    atelierId = id;
    atelierName = s0(cur['name']);
    await prefs.setInt('atelier_$userId', id);
    notifyListeners();
    bumpAfter();
  }

  Future<void> addAtelier(String name) async {
    final id = await Db.i.ins('ateliers', {'name': name.trim(), 'owner_id': userId});
    await loadAteliers();
    await switchAtelier(id);
  }

  Future<void> renameAtelier(int id, String name) async {
    await Db.i.upd('ateliers', {'name': name.trim()}, id);
    await loadAteliers();
    notifyListeners();
  }

  void logout() {
    userId = null;
    atelierId = null;
    locked = false;
    notifyListeners();
  }

  // ---------- Verrouillage ----------

  void lock() {
    if (userId != null && autoLock) {
      locked = true;
      notifyListeners();
    }
  }

  void unlock() {
    locked = false;
    notifyListeners();
  }

  // ---------- Préférences ----------

  Future<void> setDark(bool v) async {
    dark = v;
    await prefs.setBool('dark', v);
    notifyListeners();
  }

  Future<void> setLang(String v) async {
    lang = v;
    currentLang = v;
    await prefs.setString('lang', v);
    notifyListeners();
  }

  Future<void> setBio(bool v) async {
    bioEnabled = v;
    await prefs.setBool('bio', v);
    notifyListeners();
  }

  /// Active/désactive la voix de bienvenue. À l'activation, on la fait entendre tout de suite.
  Future<void> setVoice(bool v) async {
    voice = v;
    await prefs.setBool('voice', v);
    notifyListeners();
    if (v) {
      Voice.speakWelcome();
    } else {
      Voice.stop();
    }
  }

  Future<void> setAutoLock(bool v) async {
    autoLock = v;
    await prefs.setBool('autolock', v);
    notifyListeners();
  }

  static String s0(Object? v) => (v ?? '').toString();
}

/// Petit utilitaire pour éviter un import circulaire avec ui.dart.
void Function() bumpAfter = () {};
