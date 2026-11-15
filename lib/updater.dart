import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import 'i18n.dart';
import 'ui.dart';

/// Dépôt GitHub qui publie chaque nouvelle version (workflow .github/workflows/build.yml).
/// Le dépôt doit être PUBLIC pour que tous les téléphones puissent lire la version.
const kRepo = 'burksonzana-alt/reine-creation';
const kApkUrl = 'https://github.com/$kRepo/releases/latest/download/MadameZANACouture.apk';
const kLatestApi = 'https://api.github.com/repos/$kRepo/releases/latest';

class UpdateInfo {
  final String version;
  final String notes;
  final bool force;
  const UpdateInfo(this.version, this.notes, this.force);
}

/// Mise à jour de l'application sur tous les téléphones :
/// au démarrage (et à la demande dans Paramètres), l'appli compare sa version
/// à la dernière version publiée et propose de télécharger la nouvelle.
/// Si les notes de version contiennent [OBLIGATOIRE], la mise à jour ne peut pas être ignorée.
class Updater {
  static final ValueNotifier<String> status = ValueNotifier<String>('Pas encore vérifié');
  static bool _asked = false;

  static List<int> _parse(String v) {
    final m = RegExp(r'(\d+)\.(\d+)\.(\d+)').firstMatch(v);
    if (m == null) return [0, 0, 0];
    return [for (var i = 1; i <= 3; i++) int.parse(m.group(i)!)];
  }

  static bool _newer(String a, String b) {
    final x = _parse(a), y = _parse(b);
    for (var i = 0; i < 3; i++) {
      if (x[i] != y[i]) return x[i] > y[i];
    }
    return false;
  }

  /// Retourne la nouvelle version disponible, ou null (à jour / hors ligne).
  static Future<UpdateInfo?> check() async {
    final c = HttpClient()..connectionTimeout = const Duration(seconds: 10);
    try {
      final req = await c.getUrl(Uri.parse(kLatestApi));
      req.headers.set('Accept', 'application/vnd.github+json');
      req.headers.set('User-Agent', 'MadameZANACouture');
      final res = await req.close().timeout(const Duration(seconds: 15));
      final body = await res.transform(utf8.decoder).join();
      if (res.statusCode != 200) {
        status.value = 'Vérification impossible (code ${res.statusCode})';
        return null;
      }
      final j = jsonDecode(body) as Map<String, dynamic>;
      final tag = (j['tag_name'] ?? '').toString();
      final notes = (j['body'] ?? '').toString();
      if (_newer(tag, kAppVersion)) {
        status.value = 'Nouvelle version disponible : $tag';
        return UpdateInfo(tag.replaceFirst(RegExp(r'^[vV]'), ''), notes, notes.contains('[OBLIGATOIRE]'));
      }
      status.value = 'Application à jour ($kAppVersion)';
      return null;
    } catch (_) {
      status.value = 'Vérification impossible (hors ligne ?)';
      return null;
    } finally {
      c.close(force: true);
    }
  }

  static Future<void> download() =>
      launchUrl(Uri.parse(kApkUrl), mode: LaunchMode.externalApplication);

  /// [manual] : appelé depuis Paramètres (affiche aussi « déjà à jour »).
  static Future<void> checkAndPrompt(BuildContext context, {bool manual = false}) async {
    if (!manual && _asked) return;
    _asked = true;
    final info = await check();
    if (!context.mounted) return;
    if (info == null) {
      if (manual) toast(context, status.value);
      return;
    }
    var notes = info.notes.replaceAll('[OBLIGATOIRE]', '').trim();
    if (notes.length > 600) notes = '${notes.substring(0, 600)}...';
    await showDialog<void>(
      context: context,
      barrierDismissible: !info.force,
      builder: (ctx) => PopScope(
        canPop: !info.force,
        child: AlertDialog(
          title: Text(tr('Nouvelle version ${info.version}')),
          content: SingleChildScrollView(
            child: Text([
              '${tr('Version installée')} : $kAppVersion',
              if (notes.isNotEmpty) '\n$notes',
              if (info.force) '\n${tr('Cette mise à jour est obligatoire.')}',
              '\n${tr('Vos données (clients, commandes, photos) sont conservées.')}',
            ].join('\n')),
          ),
          actions: [
            if (!info.force)
              TextButton(onPressed: () => Navigator.pop(ctx), child: Text(tr('Plus tard'))),
            FilledButton(
              onPressed: () async {
                await download();
                if (!info.force && ctx.mounted) Navigator.pop(ctx);
              },
              child: Text(tr('Mettre à jour')),
            ),
          ],
        ),
      ),
    );
  }
}
