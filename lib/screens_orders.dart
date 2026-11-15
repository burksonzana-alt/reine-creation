import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:signature/signature.dart';

import 'db.dart';
import 'i18n.dart';
import 'screens_media.dart';
import 'services.dart';
import 'state.dart';
import 'ui.dart';

// =====================================================================
// Catalogue des modèles
// =====================================================================
String _modelsSql(String extra) => '''SELECT m.*,
      (SELECT COUNT(*) FROM modele_media WHERE modele_id=m.id AND type='video') AS nvid,
      (SELECT COUNT(*) FROM modele_media WHERE modele_id=m.id AND type='photo') AS nph
    FROM modeles m WHERE m.atelier_id=? $extra ORDER BY m.nom COLLATE NOCASE''';

Widget _badge(IconData i, String t) => Container(
      margin: const EdgeInsets.only(left: 4),
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
      decoration: BoxDecoration(color: Colors.black54, borderRadius: BorderRadius.circular(10)),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(i, size: 14, color: Colors.white),
        if (t.isNotEmpty) Text(' $t', style: const TextStyle(color: Colors.white, fontSize: 11)),
      ]),
    );

class ModelsPage extends StatefulWidget {
  const ModelsPage({super.key});
  @override
  State<ModelsPage> createState() => _ModelsPageState();
}

class _ModelsPageState extends State<ModelsPage> {
  String? cat;

  @override
  Widget build(BuildContext context) {
    final aid = context.read<AppState>().atelierId!;
    return AppScaffold(
      appBar: AppBar(title: Text(tr('Catalogue des modèles'))),
      floatingActionButton: FloatingActionButton(
        onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const ModelFormPage())),
        child: const Icon(Icons.add),
      ),
      body: Column(children: [
        SizedBox(
          height: 52,
          child: ListView(scrollDirection: Axis.horizontal, padding: const EdgeInsets.all(8), children: [
            Padding(
              padding: const EdgeInsets.only(right: 6),
              child: ChoiceChip(label: Text(tr('Tous')), selected: cat == null, onSelected: (_) => setState(() => cat = null)),
            ),
            for (final k in kCategories)
              Padding(
                padding: const EdgeInsets.only(right: 6),
                child: ChoiceChip(label: Text(tr(k)), selected: cat == k, onSelected: (_) => setState(() => cat = k)),
              ),
          ]),
        ),
        Expanded(
          child: DbBuilder<List<Map<String, Object?>>>(
            load: () => cat == null
                ? Db.i.q(_modelsSql(''), [aid])
                : Db.i.q(_modelsSql('AND m.categorie=?'), [aid, cat]),
            builder: (c, rows) => rows.isEmpty
                ? emptyState('Aucun modèle.', Icons.style)
                : GridView.builder(
                    padding: const EdgeInsets.all(8),
                    gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: 2, childAspectRatio: .8, mainAxisSpacing: 8, crossAxisSpacing: 8),
                    itemCount: rows.length,
                    itemBuilder: (c, i) {
                      final r = rows[i];
                      return Card(
                        clipBehavior: Clip.antiAlias,
                        child: InkWell(
                          onTap: () => Navigator.push(
                              c, MaterialPageRoute(builder: (_) => ModelFormPage(modelId: r['id'] as int))),
                          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Expanded(
                              child: Stack(fit: StackFit.expand, children: [
                                imageFile(s(r['image'])) != null
                                    ? Image.file(imageFile(s(r['image']))!, fit: BoxFit.cover)
                                    : Container(color: kViolet.withAlpha(30), child: const Icon(Icons.style, size: 48, color: kViolet)),
                                Positioned(
                                  right: 6,
                                  bottom: 6,
                                  child: Row(children: [
                                    if (d(r['nph']) > 1) _badge(Icons.photo_library, '${d(r['nph']).round()}'),
                                    if (d(r['nvid']) > 0) _badge(Icons.videocam, ''),
                                  ]),
                                ),
                              ]),
                            ),
                            Padding(
                              padding: const EdgeInsets.all(8),
                              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                Text(s(r['nom']), maxLines: 1, overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(fontWeight: FontWeight.bold)),
                                Text(tr(s(r['categorie'])), style: const TextStyle(fontSize: 12)),
                                Text(money(d(r['prix'])), style: const TextStyle(color: kViolet, fontWeight: FontWeight.w600)),
                              ]),
                            ),
                          ]),
                        ),
                      );
                    },
                  ),
          ),
        ),
      ]),
    );
  }
}

class ModelFormPage extends StatefulWidget {
  final int? modelId;
  const ModelFormPage({super.key, this.modelId});
  @override
  State<ModelFormPage> createState() => _ModelFormPageState();
}

class _ModelFormPageState extends State<ModelFormPage> {
  static const maxPhotos = 5;
  final key = GlobalKey<FormState>();
  final nom = TextEditingController();
  final desc = TextEditingController();
  final prix = TextEditingController();
  String categorie = kCategories.first;
  final List<String> photos = [];
  String? video;

  @override
  void initState() {
    super.initState();
    if (widget.modelId != null) _load();
  }

  Future<void> _load() async {
    final r = (await Db.i.q('SELECT * FROM modeles WHERE id=?', [widget.modelId])).first;
    final ms = await Db.i.q('SELECT * FROM modele_media WHERE modele_id=? ORDER BY id', [widget.modelId]);
    if (!mounted) return;
    setState(() {
      nom.text = s(r['nom']);
      desc.text = s(r['description']);
      prix.text = d(r['prix']).round().toString();
      categorie = kCategories.contains(s(r['categorie'])) ? s(r['categorie']) : kCategories.first;
      photos
        ..clear()
        ..addAll(ms.where((m) => s(m['type']) == 'photo').map((m) => s(m['fichier'])));
      if (photos.isEmpty && s(r['image']).isNotEmpty) photos.add(s(r['image']));
      final vids = ms.where((m) => s(m['type']) == 'video').toList();
      video = vids.isEmpty ? null : s(vids.first['fichier']);
    });
  }

  Future<void> _save() async {
    if (!key.currentState!.validate()) return;
    final v = {
      'atelier_id': context.read<AppState>().atelierId!,
      'nom': nom.text.trim(),
      'description': desc.text.trim(),
      'prix': double.tryParse(prix.text.replaceAll(' ', '').replaceAll(',', '.')) ?? 0,
      'categorie': categorie,
      'image': photos.isEmpty ? null : photos.first,
    };
    int id;
    if (widget.modelId == null) {
      id = await Db.i.ins('modeles', v);
    } else {
      id = widget.modelId!;
      await Db.i.upd('modeles', v, id);
      await Db.i.delWhere('modele_media', 'modele_id=?', [id]);
    }
    for (final f in photos) {
      await Db.i.ins('modele_media', {'modele_id': id, 'type': 'photo', 'fichier': f});
    }
    if (video != null) {
      await Db.i.ins('modele_media', {'modele_id': id, 'type': 'video', 'fichier': video});
    }
    bump();
    if (mounted) Navigator.pop(context);
  }

  /// Ouvre la galerie une fois : on coche jusqu'à 5 photos (et une vidéo) puis on valide.
  Future<void> _addFromGallery() async {
    PickedMedia? r;
    try {
      r = await pickFromGallery(photoSlots: maxPhotos - photos.length, videoSlot: video == null);
    } catch (e) {
      if (mounted) toast(context, tr('Impossible d\'ouvrir la galerie'));
      return;
    }
    final res = r;
    if (res == null || !mounted) return;
    setState(() {
      photos.addAll(res.photos);
      if (res.video != null) video = res.video;
    });
    if (res.ignored > 0) {
      toast(context, tr('Certains fichiers ont été ignorés (maximum 5 photos et 1 vidéo)'));
    }
  }

  Future<void> _takePhoto() async {
    final f = await takePhoto();
    if (f != null && mounted && photos.length < maxPhotos) setState(() => photos.add(f));
  }

  Future<void> _removePhoto(int i) async {
    if (await confirm(context, tr('Retirer cette photo ?'))) {
      if (mounted) setState(() => photos.removeAt(i));
    }
  }

  Future<void> _addVideo() async {
    final f = await chooseVideo(context);
    if (f != null && mounted) setState(() => video = f);
  }

  Widget _photosBlock() => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        sectionTitle('Photos du modèle'),
        Text('${photos.length} / $maxPhotos', style: const TextStyle(fontSize: 12)),
        if (photos.isNotEmpty)
          Text(tr('Appui long sur une photo pour la retirer'), style: const TextStyle(fontSize: 11)),
        const SizedBox(height: 8),
        Wrap(spacing: 8, runSpacing: 8, children: [
          for (var i = 0; i < photos.length; i++)
            GestureDetector(
              onTap: () => showPhoto(context, photos[i]),
              onLongPress: () => _removePhoto(i),
              child: photoBox(photos[i], size: 96, icon: Icons.image),
            ),
          if (photos.length < maxPhotos || video == null)
            // Galerie : on coche plusieurs photos / vidéos d'un coup.
            InkWell(
              onTap: _addFromGallery,
              child: Container(
                width: 96,
                height: 96,
                decoration: BoxDecoration(
                  border: Border.all(color: kViolet),
                  borderRadius: BorderRadius.circular(24),
                ),
                child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                  const Icon(Icons.photo_library, color: kViolet),
                  const SizedBox(height: 4),
                  Text(tr('Galerie'), style: const TextStyle(fontSize: 12, color: kViolet)),
                ]),
              ),
            ),
          if (photos.length < maxPhotos)
            InkWell(
              onTap: _takePhoto,
              child: Container(
                width: 96,
                height: 96,
                decoration: BoxDecoration(
                  border: Border.all(color: kViolet),
                  borderRadius: BorderRadius.circular(24),
                ),
                child: const Icon(Icons.add_a_photo, color: kViolet),
              ),
            ),
        ]),
      ]);

  Widget _videoBlock() => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        sectionTitle('Vidéo du modèle'),
        if (video == null)
          OutlinedButton.icon(
            onPressed: _addVideo,
            icon: const Icon(Icons.videocam),
            label: Text(tr('Ajouter une vidéo')),
          )
        else
          Card(
            child: ListTile(
              leading: const Icon(Icons.play_circle_fill, color: kViolet, size: 36),
              title: Text(tr('Voir la vidéo')),
              onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => VideoPage(video!))),
              trailing: IconButton(
                icon: const Icon(Icons.delete_outline),
                onPressed: () => setState(() => video = null),
              ),
            ),
          ),
      ]);

  @override
  Widget build(BuildContext context) => AppScaffold(
        appBar: AppBar(
          title: Text(tr(widget.modelId == null ? 'Nouveau modèle' : 'Modifier le modèle')),
          actions: [
            if (widget.modelId != null)
              IconButton(
                icon: const Icon(Icons.delete),
                onPressed: () async {
                  if (await confirm(context, tr('Supprimer ce modèle ?'))) {
                    await Db.i.del('modeles', widget.modelId!);
                    bump();
                    if (context.mounted) Navigator.pop(context);
                  }
                },
              ),
          ],
        ),
        body: Form(
          key: key,
          child: ListView(padding: const EdgeInsets.all(16), children: [
            field(nom, 'Nom du modèle', icon: Icons.style, required: true),
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: DropdownButtonFormField<String>(
                value: categorie,
                decoration: InputDecoration(labelText: tr('Catégorie'), border: const OutlineInputBorder(), prefixIcon: const Icon(Icons.category)),
                items: [for (final k in kCategories) DropdownMenuItem(value: k, child: Text(tr(k)))],
                onChanged: (v) => setState(() => categorie = v!),
              ),
            ),
            field(desc, 'Description', lines: 3, icon: Icons.notes),
            field(prix, 'Prix (FCFA)', type: TextInputType.number, icon: Icons.payments),
            _photosBlock(),
            _videoBlock(),
            const SizedBox(height: 20),
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
// Liste des commandes
// =====================================================================
class OrdersPage extends StatefulWidget {
  const OrdersPage({super.key});
  @override
  State<OrdersPage> createState() => _OrdersPageState();
}

class _OrdersPageState extends State<OrdersPage> {
  String? statut;

  @override
  Widget build(BuildContext context) {
    final aid = context.read<AppState>().atelierId!;
    return AppScaffold(
      floatingActionButton: FloatingActionButton(
        onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const OrderFormPage())),
        child: const Icon(Icons.add),
      ),
      body: Column(children: [
        SizedBox(
          height: 52,
          child: ListView(scrollDirection: Axis.horizontal, padding: const EdgeInsets.all(8), children: [
            Padding(
              padding: const EdgeInsets.only(right: 6),
              child: ChoiceChip(label: Text(tr('Toutes')), selected: statut == null, onSelected: (_) => setState(() => statut = null)),
            ),
            for (final k in kStatuts)
              Padding(
                padding: const EdgeInsets.only(right: 6),
                child: ChoiceChip(label: Text(tr(k)), selected: statut == k, onSelected: (_) => setState(() => statut = k)),
              ),
          ]),
        ),
        Expanded(
          child: DbBuilder<List<Map<String, Object?>>>(
            load: () => Db.i.q('''
              SELECT c.*, cl.nom AS client, m.nom AS modele,
                IFNULL((SELECT SUM(montant) FROM paiements WHERE commande_id=c.id),0) AS paye
              FROM commandes c JOIN clients cl ON cl.id=c.client_id LEFT JOIN modeles m ON m.id=c.modele_id
              WHERE c.atelier_id=? ${statut == null ? '' : 'AND c.statut=?'}
              ORDER BY c.id DESC''', statut == null ? [aid] : [aid, statut]),
            builder: (c, rows) => rows.isEmpty
                ? emptyState('Aucune commande.', Icons.checkroom)
                : ListView.builder(
                    padding: const EdgeInsets.all(8),
                    itemCount: rows.length,
                    itemBuilder: (c, i) {
                      final r = rows[i];
                      final reste = d(r['prix']) - d(r['paye']);
                      return Card(
                        child: ListTile(
                          title: Text('n°${r['id']} - ${s(r['client'])}'),
                          subtitle: Text(
                              '${s(r['modele']).isEmpty ? s(r['description']) : s(r['modele'])}\n${tr('Retrait')} : ${showDate(s(r['date_livraison']))}  -  ${tr('Reste')} : ${money(reste)}'),
                          isThreeLine: true,
                          trailing: StatutChip(s(r['statut'])),
                          onTap: () => Navigator.push(
                              c, MaterialPageRoute(builder: (_) => OrderDetailPage(r['id'] as int))),
                        ),
                      );
                    },
                  ),
          ),
        ),
      ]),
    );
  }
}

// =====================================================================
// Création / modification de commande
// =====================================================================
class OrderFormPage extends StatefulWidget {
  final int? orderId;
  final int? clientId;
  const OrderFormPage({super.key, this.orderId, this.clientId});
  @override
  State<OrderFormPage> createState() => _OrderFormPageState();
}

class _OrderFormPageState extends State<OrderFormPage> {
  int? clientId;
  int? modeleId;
  final desc = TextEditingController();
  final prix = TextEditingController();
  final avance = TextEditingController();
  String statut = kStatuts.first;
  String dateCmd = today();
  String? dateEss;
  String? dateLiv;
  List<Map<String, Object?>> clients = [], modeles = [];

  @override
  void initState() {
    super.initState();
    clientId = widget.clientId;
    _load();
  }

  Future<void> _load() async {
    final aid = context.read<AppState>().atelierId!;
    clients = await Db.i.q('SELECT id, nom FROM clients WHERE atelier_id=? ORDER BY nom COLLATE NOCASE', [aid]);
    modeles = await Db.i.q('SELECT id, nom, prix FROM modeles WHERE atelier_id=? ORDER BY nom COLLATE NOCASE', [aid]);
    if (widget.orderId != null) {
      final r = (await Db.i.q('SELECT * FROM commandes WHERE id=?', [widget.orderId])).first;
      clientId = r['client_id'] as int;
      modeleId = r['modele_id'] as int?;
      desc.text = s(r['description']);
      prix.text = d(r['prix']).round().toString();
      statut = s(r['statut']);
      dateCmd = s(r['date_commande']);
      dateEss = s(r['date_essayage']).isEmpty ? null : s(r['date_essayage']);
      dateLiv = s(r['date_livraison']).isEmpty ? null : s(r['date_livraison']);
    }
    if (mounted) setState(() {});
  }

  double get _prix => double.tryParse(prix.text.replaceAll(' ', '').replaceAll(',', '.')) ?? 0;
  double get _avance => double.tryParse(avance.text.replaceAll(' ', '').replaceAll(',', '.')) ?? 0;

  Future<void> _save() async {
    if (clientId == null) {
      toast(context, tr('Choisissez un client'));
      return;
    }
    final v = {
      'atelier_id': context.read<AppState>().atelierId!,
      'client_id': clientId,
      'modele_id': modeleId,
      'description': desc.text.trim(),
      'prix': _prix,
      'statut': statut,
      'date_commande': dateCmd,
      'date_essayage': dateEss,
      'date_livraison': dateLiv,
    };
    if (widget.orderId == null) {
      final id = await Db.i.ins('commandes', v);
      if (_avance > 0) {
        await Db.i.ins('paiements', {'commande_id': id, 'montant': _avance, 'date': today(), 'note': 'Avance'});
      }
    } else {
      await Db.i.upd('commandes', v, widget.orderId!);
    }
    bump();
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final editing = widget.orderId != null;
    return AppScaffold(
      appBar: AppBar(title: Text(tr(editing ? 'Modifier la commande' : 'Nouvelle commande'))),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: DropdownButtonFormField<int>(
            value: clientId,
            isExpanded: true,
            decoration: InputDecoration(labelText: tr('Client'), border: const OutlineInputBorder(), prefixIcon: const Icon(Icons.person)),
            items: [for (final c in clients) DropdownMenuItem(value: c['id'] as int, child: Text(s(c['nom'])))],
            onChanged: (v) => setState(() => clientId = v),
          ),
        ),
        Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: DropdownButtonFormField<int>(
            value: modeleId,
            isExpanded: true,
            decoration: InputDecoration(labelText: tr('Modèle choisi'), border: const OutlineInputBorder(), prefixIcon: const Icon(Icons.style)),
            items: [for (final m in modeles) DropdownMenuItem(value: m['id'] as int, child: Text(s(m['nom'])))],
            onChanged: (v) => setState(() {
              modeleId = v;
              final m = modeles.firstWhere((e) => e['id'] == v);
              if (prix.text.isEmpty) prix.text = d(m['prix']).round().toString();
            }),
          ),
        ),
        field(desc, 'Description / détails', lines: 2, icon: Icons.notes),
        field(prix, 'Prix (FCFA)', type: TextInputType.number, icon: Icons.payments),
        if (!editing) ...[
          Focus(
            onFocusChange: (_) => setState(() {}),
            child: field(avance, 'Avance reçue (FCFA)', type: TextInputType.number, icon: Icons.savings),
          ),
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text('${tr('Reste à payer')} : ${money(_prix - _avance)}',
                style: const TextStyle(fontWeight: FontWeight.bold, color: kViolet)),
          ),
        ],
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: DropdownButtonFormField<String>(
            value: statut,
            decoration: InputDecoration(labelText: tr('Statut'), border: const OutlineInputBorder(), prefixIcon: const Icon(Icons.flag)),
            items: [for (final k in kStatuts) DropdownMenuItem(value: k, child: Text(tr(k)))],
            onChanged: (v) => setState(() => statut = v!),
          ),
        ),
        dateTile(context, 'Date de commande', dateCmd, (v) => setState(() => dateCmd = v)),
        dateTile(context, 'Date d\'essayage', dateEss, (v) => setState(() => dateEss = v)),
        dateTile(context, 'Date de retrait', dateLiv, (v) => setState(() => dateLiv = v)),
        const SizedBox(height: 8),
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: kViolet, padding: const EdgeInsets.all(14)),
          onPressed: _save,
          child: Text(tr('Enregistrer')),
        ),
      ]),
    );
  }
}

// =====================================================================
// Détail commande : paiements, facture, signature
// =====================================================================
class OrderDetailPage extends StatelessWidget {
  final int id;
  const OrderDetailPage(this.id, {super.key});

  Future<void> _addPayment(BuildContext c, double reste) async {
    final amount = TextEditingController(text: reste > 0 ? reste.round().toString() : '');
    final note = TextEditingController();
    final ok = await showDialog<bool>(
      context: c,
      builder: (ctx) => AlertDialog(
        title: Text(tr('Nouveau paiement')),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          field(amount, 'Montant (FCFA)', type: TextInputType.number, icon: Icons.payments),
          field(note, 'Note', icon: Icons.notes),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(tr('Annuler'))),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(tr('Enregistrer'))),
        ],
      ),
    );
    final v = double.tryParse(amount.text.replaceAll(' ', '').replaceAll(',', '.'));
    if (ok == true && v != null && v > 0) {
      await Db.i.ins('paiements', {'commande_id': id, 'montant': v, 'date': today(), 'note': note.text.trim()});
      bump();
    }
  }

  Future<void> _sign(BuildContext c) async {
    final ctl = SignatureController(penStrokeWidth: 3, penColor: Colors.black, exportBackgroundColor: Colors.white);
    final ok = await showDialog<bool>(
      context: c,
      builder: (ctx) => AlertDialog(
        title: Text(tr('Signature du client')),
        content: SizedBox(
          width: 320,
          height: 180,
          child: DecoratedBox(
            decoration: BoxDecoration(border: Border.all(color: kGold)),
            child: Signature(controller: ctl, backgroundColor: Colors.white),
          ),
        ),
        actions: [
          TextButton(onPressed: ctl.clear, child: Text(tr('Effacer'))),
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(tr('Annuler'))),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(tr('Valider'))),
        ],
      ),
    );
    if (ok == true && ctl.isNotEmpty) {
      final png = await ctl.toPngBytes();
      if (png != null) {
        await Db.i.upd('commandes', {'signature': base64Encode(png)}, id);
        bump();
      }
    }
    ctl.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return DbBuilder<List<Object>>(
      load: () async => [
        await Db.i.q('''SELECT c.*, cl.nom AS client, cl.telephone, m.nom AS modele
            FROM commandes c JOIN clients cl ON cl.id=c.client_id LEFT JOIN modeles m ON m.id=c.modele_id WHERE c.id=?''', [id]),
        await Db.i.q('SELECT * FROM paiements WHERE commande_id=? ORDER BY date DESC, id DESC', [id]),
      ],
      builder: (c, data) {
        final rows = data[0] as List<Map<String, Object?>>;
        if (rows.isEmpty) return AppScaffold(appBar: AppBar(), body: const SizedBox());
        final o = rows.first;
        final pays = data[1] as List<Map<String, Object?>>;
        final paid = pays.fold<double>(0, (t, e) => t + d(e['montant']));
        final prix = d(o['prix']);
        final reste = prix - paid;
        final st = s(o['statut']);
        return AppScaffold(
          appBar: AppBar(title: Text('${tr('Commande')} n°$id'), actions: [
            IconButton(
              icon: const Icon(Icons.edit),
              onPressed: () => Navigator.push(c, MaterialPageRoute(builder: (_) => OrderFormPage(orderId: id))),
            ),
            IconButton(
              icon: const Icon(Icons.delete),
              onPressed: () async {
                if (await confirm(c, tr('Supprimer cette commande ?'))) {
                  await Db.i.del('commandes', id);
                  bump();
                  if (c.mounted) Navigator.pop(c);
                }
              },
            ),
          ]),
          body: ListView(padding: const EdgeInsets.all(12), children: [
            Card(
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    Expanded(child: Text(s(o['client']), style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold))),
                    StatutChip(st),
                  ]),
                  Text(s(o['telephone'])),
                  const Divider(),
                  Text('${tr('Modèle')} : ${s(o['modele']).isEmpty ? '-' : s(o['modele'])}'),
                  if (s(o['description']).isNotEmpty) Text(s(o['description'])),
                  Text('${tr('Commande')} : ${showDate(s(o['date_commande']))}'),
                  Text('${tr('Essayage')} : ${showDate(s(o['date_essayage']))}'),
                  Text('${tr('Retrait')} : ${showDate(s(o['date_livraison']))}'),
                ]),
              ),
            ),
            sectionTitle('Changer le statut'),
            Wrap(spacing: 6, children: [
              for (final k in kStatuts)
                ChoiceChip(
                  label: Text(tr(k)),
                  selected: st == k,
                  onSelected: (_) async {
                    await Db.i.upd('commandes', {'statut': k}, id);
                    bump();
                  },
                ),
            ]),
            sectionTitle('Paiements'),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(children: [
                  _line('Montant total', money(prix)),
                  _line('Avance / payé', money(paid)),
                  const Divider(),
                  _line('Solde restant', money(reste), bold: true, color: reste > 0 ? Colors.red : Colors.green),
                ]),
              ),
            ),
            for (final p in pays)
              Card(
                child: ListTile(
                  leading: const Icon(Icons.payments, color: kGold),
                  title: Text(money(d(p['montant']))),
                  subtitle: Text('${showDate(s(p['date']))}  ${s(p['note'])}'),
                  trailing: !c.read<AppState>().isAdmin
                      ? null
                      : IconButton(
                          icon: const Icon(Icons.delete_outline),
                          onPressed: () async {
                            if (await confirm(c, tr('Supprimer ce paiement ?'))) {
                              await Db.i.del('paiements', p['id'] as int);
                              bump();
                            }
                          },
                        ),
                ),
              ),
            OutlinedButton.icon(
              onPressed: () => _addPayment(c, reste),
              icon: const Icon(Icons.add),
              label: Text(tr('Ajouter un paiement')),
            ),
            sectionTitle('Facture et signature'),
            if (s(o['signature']).isNotEmpty)
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(8),
                  child: Image.memory(base64Decode(s(o['signature'])), height: 90),
                ),
              ),
            Wrap(spacing: 8, children: [
              FilledButton.icon(
                style: FilledButton.styleFrom(backgroundColor: kViolet),
                onPressed: () async => Pdfs.print(await Pdfs.invoice(id), 'facture_$id.pdf'),
                icon: const Icon(Icons.picture_as_pdf),
                label: Text(tr('Facture PDF / Imprimer')),
              ),
              OutlinedButton.icon(
                onPressed: () async => Pdfs.share(await Pdfs.invoice(id), 'facture_$id.pdf'),
                icon: const Icon(Icons.share),
                label: Text(tr('Partager')),
              ),
              OutlinedButton.icon(
                onPressed: () => _sign(c),
                icon: const Icon(Icons.draw),
                label: Text(tr('Signature')),
              ),
            ]),
            const SizedBox(height: 40),
          ]),
        );
      },
    );
  }

  Widget _line(String k, String v, {bool bold = false, Color? color}) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Text(tr(k), style: TextStyle(fontWeight: bold ? FontWeight.bold : null)),
          Text(v, style: TextStyle(fontWeight: bold ? FontWeight.bold : null, color: color)),
        ]),
      );
}
