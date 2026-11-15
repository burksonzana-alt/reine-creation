import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:qr_flutter/qr_flutter.dart';

import 'db.dart';
import 'i18n.dart';
import 'screens_messages.dart';
import 'screens_orders.dart';
import 'services.dart';
import 'state.dart';
import 'ui.dart';

// Champs de mesures par type (clé affichée → valeur en cm, sauf Poids en kg)
const Map<String, List<String>> kMeasureFields = {
  'Femme': [
    'Tour de poitrine', 'Tour de taille', 'Tour de hanches', 'Longueur robe',
    'Carrure dos', 'Longueur manche', 'Tour bras', 'Tour cou',
  ],
  'Homme': [
    'Tour poitrine', 'Tour taille', 'Tour bassin', 'Épaule',
    'Longueur pantalon', 'Longueur manche', 'Tour cou',
  ],
  'Enfant': ['Taille', 'Poids', 'Tour poitrine', 'Longueur tenue'],
};

// =====================================================================
// Liste des clients
// =====================================================================
class ClientsPage extends StatelessWidget {
  const ClientsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final aid = context.read<AppState>().atelierId!;
    return AppScaffold(
      body: DbBuilder<List<Map<String, Object?>>>(
        load: () => Db.i.q('SELECT * FROM clients WHERE atelier_id=? ORDER BY nom COLLATE NOCASE', [aid]),
        builder: (c, rows) => rows.isEmpty
            ? emptyState('Aucun client. Appuyez sur + pour en ajouter.', Icons.people_outline)
            : ListView.builder(
                padding: const EdgeInsets.all(8),
                itemCount: rows.length,
                itemBuilder: (c, i) {
                  final r = rows[i];
                  return Card(
                    child: ListTile(
                      leading: photoBox(s(r['photo'])),
                      title: Text(s(r['nom'])),
                      subtitle: Text('${s(r['telephone'])}  ${s(r['ville'])}'),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () => Navigator.push(
                          c, MaterialPageRoute(builder: (_) => ClientDetailPage(r['id'] as int))),
                    ),
                  );
                },
              ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const ClientFormPage())),
        child: const Icon(Icons.person_add),
      ),
    );
  }
}

// =====================================================================
// Formulaire client
// =====================================================================
class ClientFormPage extends StatefulWidget {
  final int? clientId;
  const ClientFormPage({super.key, this.clientId});
  @override
  State<ClientFormPage> createState() => _ClientFormPageState();
}

class _ClientFormPageState extends State<ClientFormPage> {
  final key = GlobalKey<FormState>();
  final nom = TextEditingController();
  final tel = TextEditingController();
  final adr = TextEditingController();
  final ville = TextEditingController();
  final notes = TextEditingController();
  String? photo;
  String date = today();
  String? code;

  @override
  void initState() {
    super.initState();
    if (widget.clientId != null) _load();
  }

  Future<void> _load() async {
    final r = (await Db.i.q('SELECT * FROM clients WHERE id=?', [widget.clientId])).first;
    setState(() {
      nom.text = s(r['nom']);
      tel.text = s(r['telephone']);
      adr.text = s(r['adresse']);
      ville.text = s(r['ville']);
      notes.text = s(r['notes']);
      photo = s(r['photo']).isEmpty ? null : s(r['photo']);
      date = s(r['date_inscription']);
      code = s(r['code']);
    });
  }

  Future<void> _save() async {
    if (!key.currentState!.validate()) return;
    final aid = context.read<AppState>().atelierId!;
    final v = {
      'atelier_id': aid,
      'nom': nom.text.trim(),
      'telephone': tel.text.trim(),
      'adresse': adr.text.trim(),
      'ville': ville.text.trim(),
      'notes': notes.text.trim(),
      'photo': photo,
      'date_inscription': date,
    };
    if (widget.clientId == null) {
      final id = await Db.i.ins('clients', v);
      await Db.i.upd('clients', {'code': 'RC-$aid-$id'}, id);
    } else {
      await Db.i.upd('clients', v, widget.clientId!);
    }
    bump();
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) => AppScaffold(
        appBar: AppBar(title: Text(tr(widget.clientId == null ? 'Nouveau client' : 'Modifier le client'))),
        body: Form(
          key: key,
          child: ListView(padding: const EdgeInsets.all(16), children: [
            Center(
              child: GestureDetector(
                onTap: () async {
                  final f = await choosePhoto(context);
                  if (f != null) setState(() => photo = f);
                },
                child: Stack(alignment: Alignment.bottomRight, children: [
                  photoBox(photo, size: 100),
                  const CircleAvatar(radius: 14, backgroundColor: kGold, child: Icon(Icons.camera_alt, size: 16)),
                ]),
              ),
            ),
            const SizedBox(height: 16),
            field(nom, 'Nom complet', icon: Icons.person, required: true),
            field(tel, 'Téléphone', type: TextInputType.phone, icon: Icons.phone),
            field(adr, 'Adresse', icon: Icons.home),
            field(ville, 'Ville', icon: Icons.location_city),
            dateTile(context, 'Date d\'inscription', date, (v) => setState(() => date = v)),
            field(notes, 'Notes', lines: 3, icon: Icons.notes),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: kViolet, padding: const EdgeInsets.all(14)),
              onPressed: _save,
              child: Text(tr('Enregistrer')),
            ),
          ]),
        ),
      );
}

// =====================================================================
// Fiche client (infos, QR code, mesures, commandes)
// =====================================================================
class ClientDetailPage extends StatelessWidget {
  final int id;
  const ClientDetailPage(this.id, {super.key});

  @override
  Widget build(BuildContext context) {
    return DbBuilder<List<Object>>(
      load: () async => [
        await Db.i.q('SELECT * FROM clients WHERE id=?', [id]),
        await Db.i.q('SELECT * FROM mesures WHERE client_id=? ORDER BY id DESC', [id]),
        await Db.i.q('''SELECT c.*, m.nom AS modele FROM commandes c LEFT JOIN modeles m ON m.id=c.modele_id
                        WHERE c.client_id=? ORDER BY c.id DESC''', [id]),
      ],
      builder: (c, data) {
        final cl = (data[0] as List<Map<String, Object?>>);
        if (cl.isEmpty) return AppScaffold(appBar: AppBar(), body: const SizedBox());
        final r = cl.first;
        final ms = data[1] as List<Map<String, Object?>>;
        final os = data[2] as List<Map<String, Object?>>;
        return AppScaffold(
          appBar: AppBar(title: Text(s(r['nom'])), actions: [
            IconButton(
              tooltip: tr('Messagerie'),
              icon: const Icon(Icons.chat),
              onPressed: () => Navigator.push(c, MaterialPageRoute(builder: (_) => ChatPage(id))),
            ),
            IconButton(
              icon: const Icon(Icons.edit),
              onPressed: () =>
                  Navigator.push(c, MaterialPageRoute(builder: (_) => ClientFormPage(clientId: id))),
            ),
            IconButton(
              icon: const Icon(Icons.delete),
              onPressed: () async {
                if (await confirm(c, tr('Supprimer ce client et toutes ses données ?'))) {
                  await Db.i.del('clients', id);
                  bump();
                  if (c.mounted) Navigator.pop(c);
                }
              },
            ),
          ]),
          floatingActionButton: FloatingActionButton.extended(
            onPressed: () =>
                Navigator.push(c, MaterialPageRoute(builder: (_) => OrderFormPage(clientId: id))),
            icon: const Icon(Icons.add),
            label: Text(tr('Nouvelle commande')),
          ),
          body: ListView(padding: const EdgeInsets.all(12), children: [
            Row(children: [
              photoBox(s(r['photo']), size: 84),
              const SizedBox(width: 14),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(s(r['nom']), style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                  Text('📞 ${s(r['telephone'])}'),
                  Text('📍 ${s(r['adresse'])} ${s(r['ville'])}'),
                  Text('${tr('Inscrit le')} ${showDate(s(r['date_inscription']))}',
                      style: const TextStyle(fontSize: 12)),
                ]),
              ),
              InkWell(
                onTap: () => showDialog(
                  context: c,
                  builder: (_) => AlertDialog(
                    title: Text(s(r['nom'])),
                    content: SizedBox(
                      width: 220,
                      height: 220,
                      child: QrImageView(data: s(r['code']), backgroundColor: Colors.white),
                    ),
                    actions: [Text(s(r['code']))],
                  ),
                ),
                child: QrImageView(data: s(r['code']), size: 64, backgroundColor: Colors.white),
              ),
            ]),
            if (s(r['notes']).isNotEmpty)
              Card(child: Padding(padding: const EdgeInsets.all(12), child: Text(s(r['notes'])))),
            // ---- Mesures ----
            Row(children: [
              Expanded(child: sectionTitle('Mesures')),
              TextButton.icon(
                icon: const Icon(Icons.add),
                label: Text(tr('Ajouter')),
                onPressed: () => Navigator.push(
                    c, MaterialPageRoute(builder: (_) => MeasureFormPage(clientId: id))),
              ),
              if (ms.isNotEmpty)
                IconButton(
                  tooltip: 'PDF',
                  icon: const Icon(Icons.picture_as_pdf, color: kViolet),
                  onPressed: () async => Pdfs.print(await Pdfs.measures(id), 'mesures_${s(r['nom'])}.pdf'),
                ),
            ]),
            if (ms.isEmpty) Text(tr('Aucune mesure enregistrée.')),
            for (var i = 0; i < ms.length; i++) _MeasureCard(ms[i], latest: i == 0),
            // ---- Commandes ----
            sectionTitle('Commandes'),
            if (os.isEmpty) Text(tr('Aucune commande.')),
            for (final o in os)
              Card(
                child: ListTile(
                  title: Text('${tr('Commande')} n°${o['id']} - ${s(o['modele']).isEmpty ? s(o['description']) : s(o['modele'])}'),
                  subtitle: Text('${money(d(o['prix']))}  -  ${showDate(s(o['date_livraison']))}'),
                  trailing: StatutChip(s(o['statut'])),
                  onTap: () => Navigator.push(
                      c, MaterialPageRoute(builder: (_) => OrderDetailPage(o['id'] as int))),
                ),
              ),
            const SizedBox(height: 80),
          ]),
        );
      },
    );
  }
}

class _MeasureCard extends StatelessWidget {
  final Map<String, Object?> m;
  final bool latest;
  const _MeasureCard(this.m, {required this.latest});

  @override
  Widget build(BuildContext context) {
    final data = jsonDecode(s(m['data'])) as Map<String, dynamic>;
    return Card(
      child: ExpansionTile(
        initiallyExpanded: latest,
        leading: Icon(Icons.straighten, color: latest ? kGold : Colors.grey),
        title: Text('${tr(s(m['type']))} - ${showDate(s(m['date']))}'),
        subtitle: latest ? Text(tr('Dernières mesures')) : Text(tr('Historique')),
        children: [
          for (final e in data.entries)
            ListTile(
              dense: true,
              title: Text(tr(e.key)),
              trailing: Text('${e.value} ${e.key == 'Poids' ? 'kg' : 'cm'}'),
            ),
          Row(mainAxisAlignment: MainAxisAlignment.end, children: [
            TextButton.icon(
              icon: const Icon(Icons.edit),
              label: Text(tr('Modifier')),
              onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                      builder: (_) => MeasureFormPage(clientId: m['client_id'] as int, measureId: m['id'] as int))),
            ),
            TextButton.icon(
              icon: const Icon(Icons.delete, color: Colors.red),
              label: Text(tr('Supprimer'), style: const TextStyle(color: Colors.red)),
              onPressed: () async {
                if (await confirm(context, tr('Supprimer cette prise de mesures ?'))) {
                  await Db.i.del('mesures', m['id'] as int);
                  bump();
                }
              },
            ),
          ]),
        ],
      ),
    );
  }
}

// =====================================================================
// Formulaire de mesures (nouvelle prise = nouvel élément d'historique)
// =====================================================================
class MeasureFormPage extends StatefulWidget {
  final int clientId;
  final int? measureId;
  const MeasureFormPage({super.key, required this.clientId, this.measureId});
  @override
  State<MeasureFormPage> createState() => _MeasureFormPageState();
}

class _MeasureFormPageState extends State<MeasureFormPage> {
  String type = 'Femme';
  final Map<String, TextEditingController> ctl = {};

  @override
  void initState() {
    super.initState();
    _build();
    if (widget.measureId != null) _load();
  }

  void _build() {
    for (final c in ctl.values) {
      c.dispose();
    }
    ctl
      ..clear()
      ..addEntries(kMeasureFields[type]!.map((k) => MapEntry(k, TextEditingController())));
  }

  Future<void> _load() async {
    final r = (await Db.i.q('SELECT * FROM mesures WHERE id=?', [widget.measureId])).first;
    type = s(r['type']);
    _build();
    final data = jsonDecode(s(r['data'])) as Map<String, dynamic>;
    setState(() {
      data.forEach((k, v) => ctl[k]?.text = '$v');
    });
  }

  Future<void> _save() async {
    final data = <String, String>{};
    ctl.forEach((k, c) {
      final t = c.text.trim().replaceAll(',', '.');
      if (t.isNotEmpty) data[k] = t;
    });
    final v = {'client_id': widget.clientId, 'type': type, 'data': jsonEncode(data), 'date': today()};
    if (widget.measureId == null) {
      await Db.i.ins('mesures', v);
    } else {
      await Db.i.upd('mesures', v, widget.measureId!);
    }
    bump();
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) => AppScaffold(
        appBar: AppBar(title: Text(tr(widget.measureId == null ? 'Nouvelles mesures' : 'Modifier les mesures'))),
        body: ListView(padding: const EdgeInsets.all(16), children: [
          SegmentedButton<String>(
            segments: [for (final t in kMeasureFields.keys) ButtonSegment(value: t, label: Text(tr(t)))],
            selected: {type},
            onSelectionChanged: widget.measureId != null
                ? null
                : (v) => setState(() {
                      type = v.first;
                      _build();
                    }),
          ),
          const SizedBox(height: 16),
          for (final e in ctl.entries)
            field(e.value, e.key == 'Poids' ? '${e.key} (kg)' : '${e.key} (cm)',
                type: const TextInputType.numberWithOptions(decimal: true), icon: Icons.straighten),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: kViolet, padding: const EdgeInsets.all(14)),
            onPressed: _save,
            child: Text(tr('Enregistrer')),
          ),
        ]),
      );
}
