import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:excel/excel.dart' as xl;
import 'package:file_picker/file_picker.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:intl/intl.dart';
import 'package:local_auth/local_auth.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:share_plus/share_plus.dart';
import 'package:timezone/data/latest.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import 'db.dart';
import 'ui.dart';

// =====================================================================
// Biométrie (empreinte digitale)
// =====================================================================
class Bio {
  static final LocalAuthentication _a = LocalAuthentication();

  static Future<bool> available() async {
    try {
      return await _a.canCheckBiometrics && (await _a.getAvailableBiometrics()).isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  static Future<bool> auth() async {
    try {
      return await _a.authenticate(
        localizedReason: 'Confirmez votre identité',
        options: const AuthenticationOptions(biometricOnly: true, stickyAuth: true),
      );
    } catch (_) {
      return false;
    }
  }
}

// =====================================================================
// Notifications locales Android
// =====================================================================
class Notif {
  static final FlutterLocalNotificationsPlugin _p = FlutterLocalNotificationsPlugin();

  static const NotificationDetails _details = NotificationDetails(
    android: AndroidNotificationDetails(
      'reine_rappels',
      'Rappels atelier',
      channelDescription: 'Livraisons, essayages et paiements',
      importance: Importance.high,
      priority: Priority.high,
    ),
  );

  static Future<void> init() async {
    tzdata.initializeTimeZones();
    await _p.initialize(
      const InitializationSettings(android: AndroidInitializationSettings('@mipmap/ic_launcher')),
    );
    await _p
        .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
        ?.requestNotificationsPermission();
  }

  static Future<void> _sched(int id, String title, String body, String? date, int hour) async {
    if (date == null || date.length < 10) return;
    final dt = DateTime.tryParse(date.substring(0, 10));
    if (dt == null) return;
    final when = tz.TZDateTime(tz.local, dt.year, dt.month, dt.day, hour);
    if (when.isBefore(tz.TZDateTime.now(tz.local))) return;
    await _p.zonedSchedule(
      id,
      title,
      body,
      when,
      _details,
      androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      uiLocalNotificationDateInterpretation: UILocalNotificationDateInterpretation.absoluteTime,
    );
  }

  /// Reprogramme tous les rappels de l'atelier (à appeler après chaque modification).
  static Future<void> rescheduleAll(int atelierId) async {
    try {
      await _p.cancelAll();
      final rows = await Db.i.q('''
        SELECT c.id, c.date_livraison, c.date_essayage, cl.nom,
          c.prix - IFNULL((SELECT SUM(montant) FROM paiements WHERE commande_id=c.id),0) AS reste
        FROM commandes c JOIN clients cl ON cl.id=c.client_id
        WHERE c.atelier_id=? AND c.statut!='Livré' ''', [atelierId]);
      for (final r in rows) {
        final id = r['id'] as int;
        final nom = s(r['nom']);
        await _sched(id * 3, 'Client à livrer aujourd\'hui', '$nom : commande n°$id', s(r['date_livraison']), 8);
        await _sched(id * 3 + 1, 'Essayage aujourd\'hui', '$nom : commande n°$id', s(r['date_essayage']), 8);
        if (d(r['reste']) > 0) {
          await _sched(id * 3 + 2, 'Paiement en attente',
              '$nom doit encore ${money(d(r['reste']))}', s(r['date_livraison']), 9);
        }
      }
    } catch (_) {
      // Les notifications ne doivent jamais bloquer l'application.
    }
  }

  /// Notification immédiate au lancement si quelque chose est prévu aujourd'hui.
  static Future<void> showToday(int atelierId) async {
    try {
      final t = today();
      final liv = await Db.i.q(
          "SELECT COUNT(*) AS n FROM commandes WHERE atelier_id=? AND statut!='Livré' AND date_livraison=?",
          [atelierId, t]);
      final ess = await Db.i.q(
          "SELECT COUNT(*) AS n FROM commandes WHERE atelier_id=? AND statut!='Livré' AND date_essayage=?",
          [atelierId, t]);
      final nl = (liv.first['n'] as int?) ?? 0;
      final ne = (ess.first['n'] as int?) ?? 0;
      if (nl > 0) await _p.show(900001, 'Livraisons du jour', '$nl client(s) à livrer aujourd\'hui', _details);
      if (ne > 0) await _p.show(900002, 'Essayages du jour', '$ne essayage(s) prévu(s) aujourd\'hui', _details);
    } catch (_) {}
  }
}

// =====================================================================
// PDF : facture, fiche de mesures, rapport des commandes
// (police PDF standard : évitez les caractères hors Latin-1)
// =====================================================================
class Pdfs {
  static pw.Widget _title(String t) => pw.Padding(
        padding: const pw.EdgeInsets.only(top: 14, bottom: 6),
        child: pw.Text(t, style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 13)),
      );

  static pw.Widget _kv(String k, String v) => pw.Padding(
        padding: const pw.EdgeInsets.symmetric(vertical: 1.5),
        child: pw.Row(children: [
          pw.SizedBox(width: 120, child: pw.Text(k, style: const pw.TextStyle(color: PdfColors.grey700))),
          pw.Expanded(child: pw.Text(v)),
        ]),
      );

  static const _brand = PdfColor.fromInt(0xFF6B1D34);
  static const _gold = PdfColor.fromInt(0xFFB8912F);

  static Future<pw.MemoryImage> _logo() async {
    final data = await rootBundle.load('assets/logo.png');
    return pw.MemoryImage(data.buffer.asUint8List());
  }

  /// Police PDF standard : on remplace les caractères hors Latin-1 pour éviter les cases vides.
  static String _l(String t) {
    const map = {
      '’': "'", '‘': "'", '“': '"', '”': '"', '«': '"', '»': '"',
      '–': '-', '—': '-', '…': '...', 'œ': 'oe', 'Œ': 'OE', '€': 'EUR',
    };
    final b = StringBuffer();
    for (final r in t.runes) {
      final ch = String.fromCharCode(r);
      if (map.containsKey(ch)) {
        b.write(map[ch]);
      } else if (r <= 255) {
        b.write(ch);
      } else {
        b.write('?');
      }
    }
    return b.toString();
  }

  static pw.Widget _header(String atelier, String doc, pw.MemoryImage logo) => pw.Container(
        padding: const pw.EdgeInsets.all(10),
        color: _brand,
        child: pw.Row(children: [
          pw.Container(width: 48, height: 48, child: pw.Image(logo)),
          pw.SizedBox(width: 10),
          pw.Expanded(
            child: pw.Text(_l(atelier),
                style: pw.TextStyle(color: PdfColors.white, fontSize: 16, fontWeight: pw.FontWeight.bold)),
          ),
          pw.Text(_l(doc), style: const pw.TextStyle(color: PdfColor.fromInt(0xFFE8CF8A), fontSize: 14)),
        ]),
      );

  static pw.Widget _table(List<String> head, List<List<String>> rows) => pw.Table(
        border: pw.TableBorder.all(color: PdfColors.grey400),
        children: [
          pw.TableRow(
            decoration: const pw.BoxDecoration(color: _brand),
            children: [
              for (final h in head)
                pw.Padding(
                  padding: const pw.EdgeInsets.all(4),
                  child: pw.Text(h, style: pw.TextStyle(color: PdfColors.white, fontWeight: pw.FontWeight.bold)),
                ),
            ],
          ),
          for (final r in rows)
            pw.TableRow(children: [
              for (final c in r) pw.Padding(padding: const pw.EdgeInsets.all(4), child: pw.Text(c)),
            ]),
        ],
      );

  static Future<Uint8List> invoice(int id) async {
    final r = await Db.i.q('''
      SELECT c.*, cl.nom AS client, cl.telephone, cl.adresse, cl.ville, m.nom AS modele, a.name AS atelier
      FROM commandes c JOIN clients cl ON cl.id=c.client_id
      LEFT JOIN modeles m ON m.id=c.modele_id JOIN ateliers a ON a.id=c.atelier_id
      WHERE c.id=?''', [id]);
    final o = r.first;
    final pays = await Db.i.q('SELECT * FROM paiements WHERE commande_id=? ORDER BY date, id', [id]);
    final paid = pays.fold<double>(0, (t, e) => t + d(e['montant']));
    final prix = d(o['prix']);
    final s64 = s(o['signature']);
    final pw.MemoryImage? sig = s64.isEmpty ? null : pw.MemoryImage(base64Decode(s64));

    final logo = await _logo();
    final doc = pw.Document();
    doc.addPage(pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.all(32),
      build: (_) => [
        _header(s(o['atelier']), 'FACTURE N° $id', logo),
        pw.Padding(
          padding: const pw.EdgeInsets.only(top: 4),
          child: pw.Text('WhatsApp : $kWhatsappShow - $kQuartier',
              style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey700)),
        ),
        _title('Client'),
        _kv('Nom', s(o['client'])),
        _kv('Telephone', s(o['telephone'])),
        _kv('Adresse', '${s(o['adresse'])} ${s(o['ville'])}'),
        _title('Commande'),
        _kv('Modele', s(o['modele']).isEmpty ? '-' : s(o['modele'])),
        _kv('Description', s(o['description']).isEmpty ? '-' : s(o['description'])),
        _kv('Date de commande', showDate(s(o['date_commande']))),
        _kv('Essayage', showDate(s(o['date_essayage']))),
        _kv('Retrait / livraison', showDate(s(o['date_livraison']))),
        _kv('Statut', s(o['statut'])),
        _title('Paiements'),
        if (pays.isEmpty)
          pw.Text('Aucun paiement enregistre')
        else
          _table(['Date', 'Note', 'Montant'], [
            for (final e in pays) [showDate(s(e['date'])), s(e['note']), money(d(e['montant']))],
          ]),
        pw.SizedBox(height: 12),
        pw.Align(
          alignment: pw.Alignment.centerRight,
          child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.end, children: [
            pw.Text('Montant total : ${money(prix)}'),
            pw.Text('Total paye : ${money(paid)}'),
            pw.Text('Reste a payer : ${money(prix - paid)}',
                style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 14)),
          ]),
        ),
        if (sig != null) ...[
          _title('Signature du client'),
          pw.Container(height: 80, alignment: pw.Alignment.centerLeft, child: pw.Image(sig)),
        ],
        pw.SizedBox(height: 20),
        pw.Text('Merci de votre confiance.', style: const pw.TextStyle(color: PdfColors.grey700)),
      ],
    ));
    return doc.save();
  }

  /// Reçu d'achat (format A5, imprimable sur A4).
  static Future<Uint8List> receipt(int id) async {
    final r = (await Db.i.q('SELECT * FROM recus WHERE id=?', [id])).first;
    final ls = await Db.i.q('SELECT * FROM recu_lignes WHERE recu_id=? ORDER BY id', [id]);
    final total = ls.fold<double>(0, (t, e) => t + d(e['qte']) * d(e['prix']));
    final paye = d(r['paye']);
    final reste = total - paye;
    final logo = await _logo();
    String q(num v) => v == v.roundToDouble() ? v.round().toString() : v.toStringAsFixed(1);
    final no = recuNumero(r['numero']);

    pw.Widget right(String k, String v, {bool bold = false, PdfColor? color}) => pw.Padding(
          padding: const pw.EdgeInsets.symmetric(vertical: 1.5),
          child: pw.Row(mainAxisAlignment: pw.MainAxisAlignment.end, children: [
            pw.Text(_l('$k : '), style: const pw.TextStyle(color: PdfColors.grey700)),
            pw.Text(_l(v),
                style: pw.TextStyle(
                    fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal,
                    fontSize: bold ? 13 : 11,
                    color: color)),
          ]),
        );

    final doc = pw.Document();
    doc.addPage(pw.MultiPage(
      pageFormat: PdfPageFormat.a5,
      margin: const pw.EdgeInsets.all(24),
      build: (_) => [
        pw.Container(
          padding: const pw.EdgeInsets.all(10),
          decoration: const pw.BoxDecoration(color: _brand),
          child: pw.Row(children: [
            pw.Container(width: 56, height: 56, child: pw.Image(logo)),
            pw.SizedBox(width: 10),
            pw.Expanded(
              child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
                pw.Text(_l(kAtelierName),
                    style: pw.TextStyle(color: PdfColors.white, fontSize: 16, fontWeight: pw.FontWeight.bold)),
                pw.Text(_l(kQuartier),
                    style: const pw.TextStyle(color: PdfColor.fromInt(0xFFE8CF8A), fontSize: 9)),
                pw.Text(_l('WhatsApp $kWhatsappShow'),
                    style: const pw.TextStyle(color: PdfColor.fromInt(0xFFE8CF8A), fontSize: 9)),
              ]),
            ),
          ]),
        ),
        pw.SizedBox(height: 10),
        pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, children: [
          pw.Text(_l("RE\u00c7U D'ACHAT"),
              style: pw.TextStyle(fontSize: 15, fontWeight: pw.FontWeight.bold, color: _brand)),
          pw.Text(_l('N\u00b0 $no'), style: pw.TextStyle(fontSize: 13, fontWeight: pw.FontWeight.bold, color: _gold)),
        ]),
        pw.SizedBox(height: 6),
        _kv('Date', showDate(s(r['date']))),
        _kv('Client', _l(s(r['client_nom']))),
        if (s(r['client_tel']).isNotEmpty) _kv('Telephone', _l(s(r['client_tel']))),
        pw.SizedBox(height: 10),
        _table(['Designation', 'Qte', 'Prix unit.', 'Montant'], [
          for (final e in ls)
            [
              _l(s(e['designation'])),
              q(d(e['qte'])),
              money(d(e['prix'])),
              money(d(e['qte']) * d(e['prix'])),
            ],
        ]),
        pw.SizedBox(height: 10),
        pw.Align(
          alignment: pw.Alignment.centerRight,
          child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.end, children: [
            right('Total', money(total), bold: true),
            right('Paye (${s(r['mode'])})', money(paye)),
            if (reste > 0) right('Reste a payer', money(reste), bold: true, color: PdfColors.red800),
          ]),
        ),
        if (s(r['note']).isNotEmpty) ...[
          pw.SizedBox(height: 8),
          pw.Text(_l(s(r['note'])), style: pw.TextStyle(fontStyle: pw.FontStyle.italic, fontSize: 10)),
        ],
        pw.SizedBox(height: 22),
        pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, crossAxisAlignment: pw.CrossAxisAlignment.end, children: [
          pw.Text(_l("L'\u00e9l\u00e9gance prend forme avec vous"),
              style: pw.TextStyle(fontStyle: pw.FontStyle.italic, color: _brand, fontSize: 10)),
          pw.Column(children: [
            pw.Container(width: 90, height: 0.8, color: PdfColors.grey600),
            pw.Text('Signature', style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey700)),
          ]),
        ]),
        pw.SizedBox(height: 8),
        pw.Center(child: pw.Text('Merci de votre confiance.', style: const pw.TextStyle(color: PdfColors.grey700))),
      ],
    ));
    return doc.save();
  }

  static Future<Uint8List> measures(int clientId) async {
    final c = (await Db.i.q(
            'SELECT cl.*, a.name AS atelier FROM clients cl JOIN ateliers a ON a.id=cl.atelier_id WHERE cl.id=?',
            [clientId]))
        .first;
    final ms = await Db.i.q('SELECT * FROM mesures WHERE client_id=? ORDER BY id DESC', [clientId]);
    final logo = await _logo();
    final doc = pw.Document();
    doc.addPage(pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.all(32),
      build: (_) => [
        _header(s(c['atelier']), 'FICHE DE MESURES', logo),
        _title('Client'),
        _kv('Nom', s(c['nom'])),
        _kv('Telephone', s(c['telephone'])),
        _kv('Ville', s(c['ville'])),
        if (ms.isEmpty) pw.Text('Aucune mesure enregistree'),
        for (final m in ms) ...[
          _title('${s(m['type'])} - ${showDate(s(m['date']))}'),
          _table(['Mesure', 'Valeur'], [
            for (final e in (jsonDecode(s(m['data'])) as Map<String, dynamic>).entries)
              [e.key, '${e.value} ${e.key == 'Poids' ? 'kg' : 'cm'}'],
          ]),
        ],
      ],
    ));
    return doc.save();
  }

  static Future<Uint8List> ordersReport(int atelierId) async {
    final a = (await Db.i.q('SELECT name FROM ateliers WHERE id=?', [atelierId])).first;
    final rows = await Db.i.q('''
      SELECT c.id, c.statut, c.prix, c.date_livraison, cl.nom,
        c.prix - IFNULL((SELECT SUM(montant) FROM paiements WHERE commande_id=c.id),0) AS reste
      FROM commandes c JOIN clients cl ON cl.id=c.client_id
      WHERE c.atelier_id=? ORDER BY c.id DESC''', [atelierId]);
    final logo = await _logo();
    final doc = pw.Document();
    doc.addPage(pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.all(32),
      build: (_) => [
        _header(s(a['name']), 'COMMANDES', logo),
        pw.SizedBox(height: 10),
        _table(['N°', 'Client', 'Statut', 'Livraison', 'Prix', 'Reste'], [
          for (final r in rows)
            [
              '${r['id']}',
              s(r['nom']),
              s(r['statut']),
              showDate(s(r['date_livraison'])),
              money(d(r['prix'])),
              money(d(r['reste'])),
            ],
        ]),
      ],
    ));
    return doc.save();
  }

  /// Ouvre la boîte d'impression Android (imprimantes Wi-Fi, Bluetooth via plugin de service d'impression, PDF).
  static Future<void> print(Uint8List bytes, String name) =>
      Printing.layoutPdf(onLayout: (_) async => bytes, name: name);

  static Future<void> share(Uint8List bytes, String filename) =>
      Printing.sharePdf(bytes: bytes, filename: filename);
}

// =====================================================================
// Export Excel + sauvegarde / restauration
// =====================================================================
class Exports {
  static xl.CellValue _t(Object? v) => xl.TextCellValue(s(v));
  static xl.CellValue _n(Object? v) => xl.DoubleCellValue(d(v));

  static Future<void> excel(int atelierId) async {
    final x = xl.Excel.createExcel();

    final sc = x['Clients'];
    sc.appendRow([_t('Code'), _t('Nom'), _t('Telephone'), _t('Adresse'), _t('Ville'), _t('Inscription'), _t('Notes')]);
    for (final r in await Db.i.q('SELECT * FROM clients WHERE atelier_id=? ORDER BY nom', [atelierId])) {
      sc.appendRow([_t(r['code']), _t(r['nom']), _t(r['telephone']), _t(r['adresse']), _t(r['ville']),
        _t(r['date_inscription']), _t(r['notes'])]);
    }

    final so = x['Commandes'];
    so.appendRow([_t('N°'), _t('Client'), _t('Modele'), _t('Statut'), _t('Commande'), _t('Essayage'),
      _t('Livraison'), _t('Prix'), _t('Paye'), _t('Reste')]);
    for (final r in await Db.i.q('''
        SELECT c.*, cl.nom AS client, m.nom AS modele,
          IFNULL((SELECT SUM(montant) FROM paiements WHERE commande_id=c.id),0) AS paye
        FROM commandes c JOIN clients cl ON cl.id=c.client_id LEFT JOIN modeles m ON m.id=c.modele_id
        WHERE c.atelier_id=? ORDER BY c.id''', [atelierId])) {
      so.appendRow([_t(r['id']), _t(r['client']), _t(r['modele']), _t(r['statut']), _t(r['date_commande']),
        _t(r['date_essayage']), _t(r['date_livraison']), _n(r['prix']), _n(r['paye']), _n(d(r['prix']) - d(r['paye']))]);
    }

    final sp = x['Paiements'];
    sp.appendRow([_t('Date'), _t('Commande'), _t('Client'), _t('Montant'), _t('Note')]);
    for (final r in await Db.i.q('''
        SELECT p.*, cl.nom AS client FROM paiements p
        JOIN commandes c ON c.id=p.commande_id JOIN clients cl ON cl.id=c.client_id
        WHERE c.atelier_id=? ORDER BY p.date''', [atelierId])) {
      sp.appendRow([_t(r['date']), _t(r['commande_id']), _t(r['client']), _n(r['montant']), _t(r['note'])]);
    }

    x.delete('Sheet1');
    final bytes = x.save();
    if (bytes == null) return;
    final tmp = await getTemporaryDirectory();
    final f = File(p.join(tmp.path, 'reine_creation_${DateFormat('yyyyMMdd_HHmm').format(DateTime.now())}.xlsx'));
    await f.writeAsBytes(bytes);
    await SharePlus.instance.share(ShareParams(files: [XFile(f.path)], text: 'Export Reine Creation'));
  }

  /// Sauvegarde complète (base SQLite + photos) dans un .zip à enregistrer / partager.
  static Future<void> backup() async {
    final arch = Archive();
    final dbBytes = await File(await Db.i.path()).readAsBytes();
    arch.addFile(ArchiveFile('reine_creation.db', dbBytes.length, dbBytes));
    final dir = Directory(imagesDir);
    if (dir.existsSync()) {
      for (final f in dir.listSync().whereType<File>()) {
        final b = f.readAsBytesSync();
        arch.addFile(ArchiveFile('images/${p.basename(f.path)}', b.length, b));
      }
    }
    final out = ZipEncoder().encode(arch);
    if (out == null) return;
    final tmp = await getTemporaryDirectory();
    final f = File(p.join(tmp.path, 'sauvegarde_reine_creation_${DateFormat('yyyyMMdd_HHmm').format(DateTime.now())}.zip'));
    await f.writeAsBytes(out);
    await SharePlus.instance.share(ShareParams(files: [XFile(f.path)], text: 'Sauvegarde Reine Creation'));
  }

  /// Restaure un .zip créé par [backup]. Remplace toutes les données actuelles.
  static Future<bool> restore() async {
    final r = await FilePicker.platform.pickFiles(type: FileType.any);
    final path = r?.files.single.path;
    if (path == null) return false;
    final arch = ZipDecoder().decodeBytes(File(path).readAsBytesSync());
    final dbFile = arch.findFile('reine_creation.db');
    if (dbFile == null) return false;
    await Db.i.close();
    await File(await Db.i.path()).writeAsBytes(dbFile.content as List<int>);
    Directory(imagesDir).createSync(recursive: true);
    for (final f in arch.files) {
      if (f.isFile && f.name.startsWith('images/')) {
        await File(p.join(imagesDir, p.basename(f.name))).writeAsBytes(f.content as List<int>);
      }
    }
    return true;
  }
}
