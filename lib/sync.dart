import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:crypto/crypto.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import 'db.dart';
import 'firebase_config.dart';
import 'ui.dart';

/// Catalogue partagé : chaque modèle (nom, catégorie, description, prix, photos)
/// est copié sur Firebase Firestore et reçu automatiquement par tous les téléphones.
/// Les clients, commandes, paiements et reçus restent privés sur chaque téléphone.
/// Les vidéos restent sur le téléphone qui les a ajoutées.
class CatalogSync {
  static const _maxPhotoBytes = 650 * 1024; // limite Firestore : 1 Mo par document

  static final ValueNotifier<String> status = ValueNotifier<String>('Non démarrée');

  static bool _started = false;
  static int _atelierId = 0;
  static Timer? _timer;
  static StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _sub;
  static Future<void> _tail = Future<void>.value();
  static int _skipped = 0;

  /// Exécute les tâches l'une après l'autre (envoi et réception ne se mélangent jamais).
  static Future<void> _locked(Future<void> Function() f) {
    final c = Completer<void>();
    _tail = _tail.then((_) async {
      try {
        await f();
      } catch (_) {}
      c.complete();
    });
    return c.future;
  }

  static Future<void> start(int atelierId) async {
    _atelierId = atelierId;
    if (!kFirebaseReady) {
      status.value = 'Non configurée (fichier google-services.json absent)';
      return;
    }
    if (_started) return;
    _started = true;
    try {
      await Firebase.initializeApp(
        options: const FirebaseOptions(
          apiKey: kFbApiKey,
          appId: kFbAppId,
          messagingSenderId: kFbSenderId,
          projectId: kFbProjectId,
        ),
      );
      final auth = FirebaseAuth.instance;
      if (auth.currentUser == null) await auth.signInAnonymously();
      status.value = 'Connectée, en attente...';
      _sub = FirebaseFirestore.instance.collection('catalogue').snapshots().listen(
        (snap) => _locked(() => _onSnapshot(snap)),
        onError: (Object e) => status.value = 'Hors ligne ou accès refusé : $e',
      );
      dataTick.addListener(_onLocalChange);
      _onLocalChange();
    } catch (e) {
      _started = false;
      status.value = 'Erreur : $e';
    }
  }

  /// Bouton « Synchroniser maintenant ».
  static Future<void> syncNow() async {
    if (!_started) {
      await start(_atelierId);
      return;
    }
    await _locked(_push);
  }

  static void _onLocalChange() {
    _timer?.cancel();
    _timer = Timer(const Duration(seconds: 2), () => _locked(_push));
  }

  static String _newId() {
    final r = Random.secure();
    final tail = List<int>.generate(6, (_) => r.nextInt(36)).map((e) => e.toRadixString(36)).join();
    return '${DateTime.now().millisecondsSinceEpoch.toRadixString(36)}$tail';
  }

  static Future<({List<String> photos, String hash})> _state(Map<String, Object?> m) async {
    final ms = await Db.i.q("SELECT fichier FROM modele_media WHERE modele_id=? AND type='photo' ORDER BY id", [m['id']]);
    final photos = ms.map((e) => s(e['fichier'])).where((x) => x.isNotEmpty).toList();
    if (photos.isEmpty && s(m['image']).isNotEmpty) photos.add(s(m['image']));
    final raw =
        '${s(m['nom'])}|${s(m['categorie'])}|${s(m['description'])}|${d(m['prix']).round()}|${photos.join(',')}';
    return (photos: photos, hash: sha1.convert(utf8.encode(raw)).toString());
  }

  // ------------------------------------------------------------------
  // Envoi : ce téléphone -> serveur
  // ------------------------------------------------------------------
  static Future<void> _push() async {
    if (!_started) return;
    final fs = FirebaseFirestore.instance;
    try {
      _skipped = 0;
      // 1. Modèles supprimés ici : on les supprime aussi sur le serveur.
      for (final r in await Db.i.q('SELECT remote_id FROM sync_deleted')) {
        final rid = s(r['remote_id']);
        final ph = await fs.collection('catalogue').doc(rid).collection('photos').get();
        for (final x in ph.docs) {
          await x.reference.delete();
        }
        await fs.collection('catalogue').doc(rid).delete();
        await Db.i.delWhere('sync_deleted', 'remote_id=?', [rid]);
      }

      // 2. Modèles nouveaux ou modifiés ici.
      var sent = 0;
      for (final m in await Db.i.q('SELECT * FROM modeles')) {
        final id = m['id'] as int;
        var rid = s(m['remote_id']);
        final st = await _state(m);
        if (rid.isNotEmpty && s(m['sync_hash']) == st.hash) continue;
        if (rid.isEmpty) {
          rid = _newId();
          await Db.i.upd('modeles', {'remote_id': rid}, id);
        }
        final doc = fs.collection('catalogue').doc(rid);
        final names = <String>[];
        for (final name in st.photos) {
          final ref = doc.collection('photos').doc(name);
          if (!(await ref.get()).exists) {
            final f = imageFile(name);
            if (f == null) continue;
            final bytes = await f.readAsBytes();
            if (bytes.length > _maxPhotoBytes) {
              _skipped++;
              continue;
            }
            await ref.set({'data': base64Encode(bytes), 'ts': FieldValue.serverTimestamp()});
          }
          names.add(name);
        }
        await doc.set({
          'nom': s(m['nom']),
          'categorie': s(m['categorie']),
          'description': s(m['description']),
          'prix': d(m['prix']),
          'photos': names,
          'hash': st.hash,
          'updated': DateTime.now().millisecondsSinceEpoch,
        });
        // Photos retirées du modèle : on les retire aussi du serveur.
        for (final x in (await doc.collection('photos').get()).docs) {
          if (!names.contains(x.id)) await x.reference.delete();
        }
        await Db.i.upd(
            'modeles',
            {'sync_hash': st.hash, 'remote_hash': st.hash, 'synced_at': DateTime.now().millisecondsSinceEpoch},
            id);
        sent++;
      }
      final extra = _skipped > 0 ? ' ($_skipped photo(s) trop lourde(s) non envoyée(s))' : '';
      status.value = sent > 0 ? 'À jour : $sent modèle(s) envoyé(s)$extra' : 'À jour$extra';
    } catch (e) {
      status.value = 'Envoi impossible (hors ligne ?) : $e';
    }
  }

  // ------------------------------------------------------------------
  // Réception : serveur -> ce téléphone
  // ------------------------------------------------------------------
  static Future<void> _onSnapshot(QuerySnapshot<Map<String, dynamic>> snap) async {
    if (_atelierId == 0) return;
    var changed = false;
    final remoteIds = <String>{};
    try {
      for (final doc in snap.docs) {
        final rid = doc.id;
        remoteIds.add(rid);
        if (doc.metadata.hasPendingWrites) continue; // notre propre envoi en cours
        final data = doc.data();
        final rh = (data['hash'] ?? '').toString();
        final rows = await Db.i.q('SELECT * FROM modeles WHERE remote_id=?', [rid]);
        final Map<String, Object?>? local = rows.isEmpty ? null : rows.first;
        if (local != null) {
          if (s(local['remote_hash']) == rh) continue; // déjà à jour
          final st = await _state(local);
          if (s(local['sync_hash']) != st.hash) continue; // modification locale : elle sera envoyée
        }

        // Télécharger les photos manquantes.
        final names = List<String>.from((data['photos'] as List?) ?? const []);
        final got = <String>[];
        for (final name in names) {
          if (imageFile(name) == null) {
            try {
              final pd = await doc.reference.collection('photos').doc(name).get();
              final b64 = pd.data()?['data'];
              if (b64 is String) {
                Directory(imagesDir).createSync(recursive: true);
                await File(p.join(imagesDir, name)).writeAsBytes(base64Decode(b64));
              }
            } catch (_) {}
          }
          if (imageFile(name) != null) got.add(name);
        }
        if (got.length < names.length) {
          status.value = 'Photos en cours de réception...';
          continue; // on réessaiera au prochain passage
        }

        final Map<String, Object?> vals = {
          'nom': s(data['nom']),
          'categorie': s(data['categorie']),
          'description': s(data['description']),
          'prix': (data['prix'] as num?)?.toDouble() ?? 0,
          'image': got.isEmpty ? null : got.first,
          'remote_id': rid,
        };
        int id;
        if (local == null) {
          id = await Db.i.ins('modeles', {...vals, 'atelier_id': _atelierId});
        } else {
          id = local['id'] as int;
          await Db.i.upd('modeles', vals, id);
        }
        await Db.i.delWhere('modele_media', "modele_id=? AND type='photo'", [id]);
        for (final n in got) {
          await Db.i.ins('modele_media', {'modele_id': id, 'type': 'photo', 'fichier': n});
        }
        final fresh = (await Db.i.q('SELECT * FROM modeles WHERE id=?', [id])).first;
        final st2 = await _state(fresh);
        await Db.i.upd(
            'modeles',
            {'sync_hash': st2.hash, 'remote_hash': rh, 'synced_at': DateTime.now().millisecondsSinceEpoch},
            id);
        changed = true;
      }

      // Modèles supprimés sur un autre téléphone : on les supprime ici aussi.
      if (!snap.metadata.isFromCache && !snap.metadata.hasPendingWrites) {
        final now = DateTime.now().millisecondsSinceEpoch;
        final locals = await Db.i.q(
            "SELECT id, remote_id, synced_at FROM modeles WHERE remote_id IS NOT NULL AND remote_id!='' AND remote_hash IS NOT NULL AND remote_hash!=''");
        for (final l in locals) {
          if (remoteIds.contains(s(l['remote_id']))) continue;
          if (now - ((l['synced_at'] as num?)?.toInt() ?? 0) < 120000) continue;
          await Db.i.del('modeles', l['id'] as int);
          changed = true;
        }
      }
      if (changed) {
        status.value = 'Catalogue mis à jour';
        bump();
      } else if (!status.value.startsWith('Photos')) {
        status.value = 'À jour';
      }
    } catch (e) {
      status.value = 'Réception impossible : $e';
    }
  }
}
