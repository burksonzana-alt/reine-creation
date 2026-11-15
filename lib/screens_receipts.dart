import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'db.dart';
import 'i18n.dart';
import 'screens_messages.dart';
import 'services.dart';
import 'state.dart';
import 'ui.dart';

double? _num(String t) => double.tryParse(t.trim().replaceAll(' ', '').replaceAll(',', '.'));

String _qte(num v) => v == v.roundToDouble() ? v.round().toString() : v.toStringAsFixed(1);

// =====================================================================
// Liste des reçus d'achat
// =====================================================================
class ReceiptsPage extends StatefulWidget {
  const ReceiptsPage({super.key});
  @override
  State<ReceiptsPage> createState() => _ReceiptsPageState();
}

class _ReceiptsPageState extends State<ReceiptsPage> {
  String q = '';

  @override
  Widget build(BuildContext context) {
    final st = context.read<AppState>();
    final aid = st.atelierId!;
    return AppScaffold(
      appBar: AppBar(title: Text(tr('Reçus d\'achat'))),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const ReceiptFormPage())),
        icon: const Icon(Icons.add),
        label: Text(tr('Nouveau reçu')),
      ),
      body: Column(children: [
        Padding(
          padding: const EdgeInsets.all(8),
          child: TextField(
            decoration: InputDecoration(
              prefixIcon: const Icon(Icons.search),
              hintText: tr('Rechercher un reçu ou un client'),
              border: const OutlineInputBorder(),
              filled: true,
              fillColor: Theme.of(context).cardTheme.color,
            ),
            onChanged: (v) => setState(() => q = v.trim().toLowerCase()),
          ),
        ),
        Expanded(
          child: DbBuilder<List<Map<String, Object?>>>(
            load: () => Db.i.q('''
              SELECT r.*, IFNULL((SELECT SUM(qte*prix) FROM recu_lignes WHERE recu_id=r.id),0) AS total
              FROM recus r WHERE r.atelier_id=? ORDER BY r.id DESC''', [aid]),
            builder: (c, all) {
              final rows = q.isEmpty
                  ? all
                  : all
                      .where((r) =>
                          s(r['client_nom']).toLowerCase().contains(q) ||
                          recuNumero(r['numero']).toLowerCase().contains(q))
                      .toList();
              if (rows.isEmpty) return emptyState('Aucun reçu pour le moment', Icons.receipt_long);
              final sum = rows.fold<double>(0, (t, r) => t + d(r['total']));
              return ListView(padding: const EdgeInsets.fromLTRB(8, 0, 8, 90), children: [
                if (st.isAdmin)
                  Card(
                    child: ListTile(
                      leading: const Icon(Icons.summarize, color: kViolet),
                      title: Text('${rows.length} ${tr('reçu(s)')}'),
                      trailing: Text(money(sum), style: const TextStyle(fontWeight: FontWeight.bold)),
                    ),
                  ),
                for (final r in rows)
                  Card(
                    child: ListTile(
                      leading: const Icon(Icons.receipt_long, color: kGold),
                      title: Text('${recuNumero(r['numero'])} - ${s(r['client_nom'])}'),
                      subtitle: Text('${showDate(s(r['date']))}  ${s(r['mode'])}'),
                      trailing: Text(money(d(r['total'])), style: const TextStyle(fontWeight: FontWeight.bold)),
                      onTap: () => Navigator.push(
                          c, MaterialPageRoute(builder: (_) => ReceiptDetailPage(r['id'] as int))),
                    ),
                  ),
              ]);
            },
          ),
        ),
      ]),
    );
  }
}

// =====================================================================
// Création / modification d'un reçu
// =====================================================================
class _Line {
  final TextEditingController des;
  final TextEditingController qte;
  final TextEditingController prix;
  _Line({String des = '', String qte = '1', String prix = ''})
      : des = TextEditingController(text: des),
        qte = TextEditingController(text: qte),
        prix = TextEditingController(text: prix);

  double get total => (_num(qte.text) ?? 0) * (_num(prix.text) ?? 0);

  void dispose() {
    des.dispose();
    qte.dispose();
    prix.dispose();
  }
}

class ReceiptFormPage extends StatefulWidget {
  final int? receiptId;
  const ReceiptFormPage({super.key, this.receiptId});
  @override
  State<ReceiptFormPage> createState() => _ReceiptFormPageState();
}

class _ReceiptFormPageState extends State<ReceiptFormPage> {
  final nom = TextEditingController();
  final tel = TextEditingController();
  final note = TextEditingController();
  final payeCtl = TextEditingController();
  final List<_Line> lines = [_Line()];
  int? clientId;
  String date = today();
  String mode = kModesPaiement.first;
  bool payeTouched = false;
  bool ready = false;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    final id = widget.receiptId;
    if (id != null) {
      final r = await Db.i.q('SELECT * FROM recus WHERE id=?', [id]);
      final ls = await Db.i.q('SELECT * FROM recu_lignes WHERE recu_id=? ORDER BY id', [id]);
      if (r.isNotEmpty) {
        final o = r.first;
        nom.text = s(o['client_nom']);
        tel.text = s(o['client_tel']);
        note.text = s(o['note']);
        clientId = o['client_id'] as int?;
        date = s(o['date']).isEmpty ? today() : s(o['date']);
        mode = s(o['mode']).isEmpty ? kModesPaiement.first : s(o['mode']);
        payeCtl.text = d(o['paye']).round().toString();
        payeTouched = true;
        for (final l in lines) {
          l.dispose();
        }
        lines
          ..clear()
          ..addAll(ls.map((e) => _Line(
                des: s(e['designation']),
                qte: _qte(d(e['qte'])),
                prix: d(e['prix']).round().toString(),
              )));
        if (lines.isEmpty) lines.add(_Line());
      }
    }
    if (mounted) setState(() => ready = true);
  }

  @override
  void dispose() {
    nom.dispose();
    tel.dispose();
    note.dispose();
    payeCtl.dispose();
    for (final l in lines) {
      l.dispose();
    }
    super.dispose();
  }

  double get total => lines.fold<double>(0, (t, l) => t + l.total);

  void _refresh() {
    if (!payeTouched) payeCtl.text = total.round().toString();
    setState(() {});
  }

  Future<void> _pickClient() async {
    final aid = context.read<AppState>().atelierId!;
    final clients = await Db.i.q('SELECT id, nom, telephone FROM clients WHERE atelier_id=? ORDER BY nom COLLATE NOCASE', [aid]);
    if (!mounted) return;
    if (clients.isEmpty) {
      toast(context, tr('Aucun client enregistré.'));
      return;
    }
    final pick = await showModalBottomSheet<Map<String, Object?>>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => SafeArea(
        child: SizedBox(
          height: MediaQuery.of(ctx).size.height * 0.7,
          child: ListView(children: [
            for (final c in clients)
              ListTile(
                leading: const Icon(Icons.person, color: kViolet),
                title: Text(s(c['nom'])),
                subtitle: Text(s(c['telephone'])),
                onTap: () => Navigator.pop(ctx, c),
              ),
          ]),
        ),
      ),
    );
    if (pick != null) {
      clientId = pick['id'] as int?;
      nom.text = s(pick['nom']);
      tel.text = s(pick['telephone']);
      setState(() {});
    }
  }

  Future<void> _save() async {
    final items = lines.where((l) => l.des.text.trim().isNotEmpty).toList();
    if (nom.text.trim().isEmpty) {
      toast(context, tr('Indiquez le nom du client.'));
      return;
    }
    if (items.isEmpty) {
      toast(context, tr('Ajoutez au moins un article.'));
      return;
    }
    final aid = context.read<AppState>().atelierId!;
    final tot = items.fold<double>(0, (t, l) => t + l.total);
    final paye = _num(payeCtl.text) ?? tot;
    final Map<String, Object?> vals = {
      'client_id': clientId,
      'client_nom': nom.text.trim(),
      'client_tel': tel.text.trim(),
      'date': date,
      'mode': mode,
      'paye': paye,
      'note': note.text.trim(),
    };
    int rid;
    if (widget.receiptId == null) {
      final last = await Db.i.q('SELECT IFNULL(MAX(numero),0) AS n FROM recus WHERE atelier_id=?', [aid]);
      vals['atelier_id'] = aid;
      vals['numero'] = ((last.first['n'] as num?)?.toInt() ?? 0) + 1;
      rid = await Db.i.ins('recus', vals);
    } else {
      rid = widget.receiptId!;
      await Db.i.upd('recus', vals, rid);
      await Db.i.delWhere('recu_lignes', 'recu_id=?', [rid]);
    }
    for (final l in items) {
      await Db.i.ins('recu_lignes', {
        'recu_id': rid,
        'designation': l.des.text.trim(),
        'qte': _num(l.qte.text) ?? 1,
        'prix': _num(l.prix.text) ?? 0,
      });
    }
    bump();
    if (!mounted) return;
    if (widget.receiptId == null) {
      Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => ReceiptDetailPage(rid)));
    } else {
      Navigator.pop(context);
    }
  }

  Widget _tf(TextEditingController c, String label,
          {TextInputType? type, ValueChanged<String>? onChanged, IconData? icon, int lines = 1}) =>
      TextField(
        controller: c,
        keyboardType: type,
        maxLines: lines,
        onChanged: onChanged,
        decoration: InputDecoration(
          labelText: tr(label),
          prefixIcon: icon == null ? null : Icon(icon),
          border: const OutlineInputBorder(),
          isDense: true,
        ),
      );

  @override
  Widget build(BuildContext context) {
    final tot = total;
    final paye = _num(payeCtl.text) ?? tot;
    final reste = tot - paye;
    return AppScaffold(
      appBar: AppBar(title: Text(tr(widget.receiptId == null ? 'Nouveau reçu' : 'Modifier le reçu'))),
      body: !ready
          ? const Center(child: CircularProgressIndicator())
          : ListView(padding: const EdgeInsets.all(12), children: [
              sectionTitle('Client'),
              _tf(nom, 'Nom du client', icon: Icons.person),
              const SizedBox(height: 8),
              _tf(tel, 'Téléphone', type: TextInputType.phone, icon: Icons.phone),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: _pickClient,
                  icon: const Icon(Icons.people),
                  label: Text(tr('Choisir un client enregistré')),
                ),
              ),
              dateTile(context, 'Date', date, (v) => setState(() => date = v)),
              sectionTitle('Articles'),
              for (var i = 0; i < lines.length; i++)
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(10),
                    child: Column(children: [
                      Row(children: [
                        Expanded(child: _tf(lines[i].des, 'Désignation (ex : tissu wax, robe...)')),
                        IconButton(
                          icon: const Icon(Icons.delete_outline),
                          onPressed: lines.length == 1
                              ? null
                              : () {
                                  lines[i].dispose();
                                  lines.removeAt(i);
                                  _refresh();
                                },
                        ),
                      ]),
                      const SizedBox(height: 8),
                      Row(children: [
                        SizedBox(
                            width: 80,
                            child: _tf(lines[i].qte, 'Qté', type: TextInputType.number, onChanged: (_) => _refresh())),
                        const SizedBox(width: 8),
                        Expanded(
                            child: _tf(lines[i].prix, 'Prix unitaire (FCFA)',
                                type: TextInputType.number, onChanged: (_) => _refresh())),
                      ]),
                      Align(
                        alignment: Alignment.centerRight,
                        child: Padding(
                          padding: const EdgeInsets.only(top: 6),
                          child: Text(money(lines[i].total), style: const TextStyle(fontWeight: FontWeight.w600)),
                        ),
                      ),
                    ]),
                  ),
                ),
              OutlinedButton.icon(
                onPressed: () {
                  lines.add(_Line());
                  _refresh();
                },
                icon: const Icon(Icons.add),
                label: Text(tr('Ajouter un article')),
              ),
              sectionTitle('Paiement'),
              Wrap(spacing: 6, children: [
                for (final m in kModesPaiement)
                  ChoiceChip(label: Text(tr(m)), selected: mode == m, onSelected: (_) => setState(() => mode = m)),
              ]),
              const SizedBox(height: 10),
              _tf(payeCtl, 'Montant payé (FCFA)', type: TextInputType.number, icon: Icons.payments, onChanged: (_) {
                payeTouched = true;
                setState(() {});
              }),
              const SizedBox(height: 8),
              _tf(note, 'Note', icon: Icons.notes, lines: 2),
              const SizedBox(height: 10),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Column(children: [
                    _row('Total', money(tot), bold: true),
                    _row('Payé', money(paye)),
                    if (reste > 0) _row('Reste à payer', money(reste), color: Colors.red),
                  ]),
                ),
              ),
              const SizedBox(height: 8),
              FilledButton.icon(
                style: FilledButton.styleFrom(backgroundColor: kViolet, padding: const EdgeInsets.all(14)),
                onPressed: _save,
                icon: const Icon(Icons.check),
                label: Text(tr('Enregistrer le reçu')),
              ),
              const SizedBox(height: 40),
            ]),
    );
  }
}

Widget _row(String k, String v, {bool bold = false, Color? color}) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
        Text(tr(k), style: TextStyle(fontWeight: bold ? FontWeight.bold : null)),
        Text(v, style: TextStyle(fontWeight: bold ? FontWeight.bold : null, color: color)),
      ]),
    );

// =====================================================================
// Détail d'un reçu : aperçu, PDF, impression, partage, WhatsApp
// =====================================================================
class ReceiptDetailPage extends StatelessWidget {
  final int id;
  const ReceiptDetailPage(this.id, {super.key});

  String _text(Map<String, Object?> r, List<Map<String, Object?>> ls, double total) {
    final b = StringBuffer()
      ..writeln('*$kAtelierName*')
      ..writeln('Reçu d\'achat ${recuNumero(r['numero'])} du ${showDate(s(r['date']))}')
      ..writeln('Client : ${s(r['client_nom'])}')
      ..writeln();
    for (final l in ls) {
      b.writeln('- ${s(l['designation'])} : ${_qte(d(l['qte']))} x ${money(d(l['prix']))} = ${money(d(l['qte']) * d(l['prix']))}');
    }
    final paye = d(r['paye']);
    b
      ..writeln()
      ..writeln('Total : ${money(total)}')
      ..writeln('Payé : ${money(paye)} (${s(r['mode'])})');
    if (total - paye > 0) b.writeln('Reste à payer : ${money(total - paye)}');
    b
      ..writeln()
      ..writeln('Merci de votre confiance.')
      ..write('$kQuartier - WhatsApp $kWhatsappShow');
    return b.toString();
  }

  @override
  Widget build(BuildContext context) {
    final isAdmin = context.read<AppState>().isAdmin;
    return DbBuilder<List<Object>>(
      load: () async => [
        await Db.i.q('SELECT * FROM recus WHERE id=?', [id]),
        await Db.i.q('SELECT * FROM recu_lignes WHERE recu_id=? ORDER BY id', [id]),
      ],
      builder: (c, data) {
        final rows = data[0] as List<Map<String, Object?>>;
        if (rows.isEmpty) return AppScaffold(appBar: AppBar(), body: const SizedBox());
        final r = rows.first;
        final ls = data[1] as List<Map<String, Object?>>;
        final total = ls.fold<double>(0, (t, e) => t + d(e['qte']) * d(e['prix']));
        final paye = d(r['paye']);
        final reste = total - paye;
        final no = recuNumero(r['numero']);
        return AppScaffold(
          appBar: AppBar(title: Text('${tr('Reçu')} $no'), actions: [
            IconButton(
              icon: const Icon(Icons.edit),
              onPressed: () =>
                  Navigator.push(c, MaterialPageRoute(builder: (_) => ReceiptFormPage(receiptId: id))),
            ),
            if (isAdmin)
              IconButton(
                icon: const Icon(Icons.delete),
                onPressed: () async {
                  if (await confirm(c, tr('Supprimer ce reçu ?'))) {
                    await Db.i.del('recus', id);
                    bump();
                    if (c.mounted) Navigator.pop(c);
                  }
                },
              ),
          ]),
          body: ListView(padding: const EdgeInsets.all(12), children: [
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Center(child: Logo(size: 90)),
                  const SizedBox(height: 8),
                  const Center(
                      child: Text(kAtelierName,
                          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: kViolet))),
                  const Center(child: Text(kQuartier, style: TextStyle(fontSize: 12))),
                  const Center(child: Text('WhatsApp $kWhatsappShow', style: TextStyle(fontSize: 12))),
                  const Divider(height: 24),
                  Text('${tr('REÇU D\'ACHAT')} $no', style: const TextStyle(fontWeight: FontWeight.bold)),
                  Text('${tr('Date')} : ${showDate(s(r['date']))}'),
                  Text('${tr('Client')} : ${s(r['client_nom'])}'),
                  if (s(r['client_tel']).isNotEmpty) Text('${tr('Téléphone')} : ${s(r['client_tel'])}'),
                  const Divider(height: 24),
                  for (final l in ls)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 3),
                      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Expanded(
                            child: Text('${s(l['designation'])}\n${_qte(d(l['qte']))} x ${money(d(l['prix']))}')),
                        Text(money(d(l['qte']) * d(l['prix'])), style: const TextStyle(fontWeight: FontWeight.w600)),
                      ]),
                    ),
                  const Divider(height: 24),
                  _row('Total', money(total), bold: true),
                  _row('Payé', '${money(paye)} (${s(r['mode'])})'),
                  if (reste > 0) _row('Reste à payer', money(reste), color: Colors.red),
                  if (s(r['note']).isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Text(s(r['note']), style: const TextStyle(fontStyle: FontStyle.italic)),
                  ],
                  const SizedBox(height: 12),
                  const Center(
                      child: Text('L\'élégance prend forme avec vous',
                          style: TextStyle(fontStyle: FontStyle.italic, color: kViolet))),
                ]),
              ),
            ),
            Wrap(spacing: 8, runSpacing: 4, children: [
              FilledButton.icon(
                style: FilledButton.styleFrom(backgroundColor: kViolet),
                onPressed: () async => Pdfs.print(await Pdfs.receipt(id), 'recu_$no.pdf'),
                icon: const Icon(Icons.picture_as_pdf),
                label: Text(tr('PDF / Imprimer')),
              ),
              OutlinedButton.icon(
                onPressed: () async => Pdfs.share(await Pdfs.receipt(id), 'recu_$no.pdf'),
                icon: const Icon(Icons.share),
                label: Text(tr('Partager')),
              ),
              OutlinedButton.icon(
                onPressed: () async {
                  final tel = s(r['client_tel']);
                  if (tel.isEmpty) {
                    toast(c, tr('Ce client n\'a pas de numéro de téléphone.'));
                    return;
                  }
                  final ok = await openWhatsApp(tel, _text(r, ls, total));
                  if (!ok && c.mounted) toast(c, tr('WhatsApp introuvable sur ce téléphone.'));
                },
                icon: const Icon(Icons.chat, color: Color(0xFF25D366)),
                label: const Text('WhatsApp'),
              ),
            ]),
            const SizedBox(height: 40),
          ]),
        );
      },
    );
  }
}
