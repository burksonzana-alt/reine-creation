import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:table_calendar/table_calendar.dart';

import 'db.dart';
import 'i18n.dart';
import 'screens_orders.dart';
import 'services.dart';
import 'state.dart';
import 'ui.dart';

// =====================================================================
// Galerie des créations
// =====================================================================
class GalleryPage extends StatefulWidget {
  const GalleryPage({super.key});
  @override
  State<GalleryPage> createState() => _GalleryPageState();
}

class _GalleryPageState extends State<GalleryPage> {
  String? type;

  Future<void> _add() async {
    final f = await choosePhoto(context);
    if (f == null || !mounted) return;
    final res = await _editDialog(null, null);
    if (res == null) return;
    await Db.i.ins('galerie', {
      'atelier_id': context.read<AppState>().atelierId!,
      'image': f,
      'type': res.$1,
      'legende': res.$2,
      'date': today(),
    });
    bump();
  }

  Future<(String, String)?> _editDialog(String? t, String? legende) async {
    var sel = t ?? kGalerieTypes.first;
    final cap = TextEditingController(text: legende ?? '');
    return showDialog<(String, String)>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, set) => AlertDialog(
          title: Text(tr('Détails de la photo')),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            DropdownButtonFormField<String>(
              value: sel,
              decoration: InputDecoration(labelText: tr('Type'), border: const OutlineInputBorder()),
              items: [for (final k in kGalerieTypes) DropdownMenuItem(value: k, child: Text(tr(k)))],
              onChanged: (v) => set(() => sel = v!),
            ),
            const SizedBox(height: 12),
            field(cap, 'Légende', icon: Icons.notes),
          ]),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: Text(tr('Annuler'))),
            FilledButton(onPressed: () => Navigator.pop(ctx, (sel, cap.text.trim())), child: Text(tr('Enregistrer'))),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final aid = context.read<AppState>().atelierId!;
    return AppScaffold(
      appBar: AppBar(title: Text(tr('Galerie des créations'))),
      floatingActionButton: FloatingActionButton(onPressed: _add, child: const Icon(Icons.add_a_photo)),
      body: Column(children: [
        SizedBox(
          height: 52,
          child: ListView(scrollDirection: Axis.horizontal, padding: const EdgeInsets.all(8), children: [
            Padding(
              padding: const EdgeInsets.only(right: 6),
              child: ChoiceChip(label: Text(tr('Tous')), selected: type == null, onSelected: (_) => setState(() => type = null)),
            ),
            for (final k in kGalerieTypes)
              Padding(
                padding: const EdgeInsets.only(right: 6),
                child: ChoiceChip(label: Text(tr(k)), selected: type == k, onSelected: (_) => setState(() => type = k)),
              ),
          ]),
        ),
        Expanded(
          child: DbBuilder<List<Map<String, Object?>>>(
            load: () => type == null
                ? Db.i.q('SELECT * FROM galerie WHERE atelier_id=? ORDER BY id DESC', [aid])
                : Db.i.q('SELECT * FROM galerie WHERE atelier_id=? AND type=? ORDER BY id DESC', [aid, type]),
            builder: (c, rows) => rows.isEmpty
                ? emptyState('Aucune photo. Appuyez sur l\'appareil photo pour en ajouter.', Icons.photo_library)
                : GridView.builder(
                    padding: const EdgeInsets.all(6),
                    gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: 3, mainAxisSpacing: 4, crossAxisSpacing: 4),
                    itemCount: rows.length,
                    itemBuilder: (c, i) {
                      final r = rows[i];
                      final f = imageFile(s(r['image']));
                      return GestureDetector(
                        onTap: () => _open(r),
                        child: Stack(fit: StackFit.expand, children: [
                          f != null ? Image.file(f, fit: BoxFit.cover) : Container(color: Colors.grey),
                          Positioned(
                            left: 0,
                            right: 0,
                            bottom: 0,
                            child: Container(
                              color: Colors.black54,
                              padding: const EdgeInsets.all(2),
                              child: Text(tr(s(r['type'])),
                                  style: const TextStyle(color: Colors.white, fontSize: 11), textAlign: TextAlign.center),
                            ),
                          ),
                        ]),
                      );
                    },
                  ),
          ),
        ),
      ]),
    );
  }

  void _open(Map<String, Object?> r) {
    final f = imageFile(s(r['image']));
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        contentPadding: EdgeInsets.zero,
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          if (f != null) InteractiveViewer(child: Image.file(f)),
          Padding(
            padding: const EdgeInsets.all(12),
            child: Text('${tr(s(r['type']))} - ${showDate(s(r['date']))}\n${s(r['legende'])}'),
          ),
        ]),
        actions: [
          TextButton(
            onPressed: () async {
              Navigator.pop(ctx);
              final res = await _editDialog(s(r['type']), s(r['legende']));
              if (res != null) {
                await Db.i.upd('galerie', {'type': res.$1, 'legende': res.$2}, r['id'] as int);
                bump();
              }
            },
            child: Text(tr('Modifier')),
          ),
          TextButton(
            onPressed: () async {
              Navigator.pop(ctx);
              if (await confirm(context, tr('Supprimer cette photo ?'))) {
                await Db.i.del('galerie', r['id'] as int);
                bump();
              }
            },
            child: Text(tr('Supprimer'), style: const TextStyle(color: Colors.red)),
          ),
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text(tr('Fermer'))),
        ],
      ),
    );
  }
}

// =====================================================================
// Agenda couture (jour / semaine / mois)
// =====================================================================
class AgendaPage extends StatefulWidget {
  const AgendaPage({super.key});
  @override
  State<AgendaPage> createState() => _AgendaPageState();
}

class _AgendaPageState extends State<AgendaPage> {
  String view = 'Mois';
  DateTime focused = DateTime.now();
  DateTime selected = DateTime.now();

  String _iso(DateTime d) => DateFormat('yyyy-MM-dd').format(d);

  Future<Map<String, List<_Ev>>> _load(int aid) async {
    final map = <String, List<_Ev>>{};
    void add(String? date, _Ev e) {
      if (date == null || date.length < 10) return;
      map.putIfAbsent(date.substring(0, 10), () => []).add(e);
    }

    final cmds = await Db.i.q('''
      SELECT c.id, c.date_essayage, c.date_livraison, cl.nom FROM commandes c
      JOIN clients cl ON cl.id=c.client_id WHERE c.atelier_id=? AND c.statut!='Livré' ''', [aid]);
    for (final r in cmds) {
      add(s(r['date_essayage']), _Ev('Essayage', s(r['nom']), Icons.checkroom, Colors.purple, orderId: r['id'] as int));
      add(s(r['date_livraison']), _Ev('Livraison', s(r['nom']), Icons.local_shipping, Colors.teal, orderId: r['id'] as int));
    }
    for (final r in await Db.i.q('SELECT * FROM rdv WHERE atelier_id=?', [aid])) {
      add(s(r['date']), _Ev('Rendez-vous', '${s(r['heure'])} ${s(r['titre'])}', Icons.person_pin_circle, kGold, rdvId: r['id'] as int));
    }
    return map;
  }

  Future<void> _addRdv(int aid) async {
    final titre = TextEditingController();
    final heure = TextEditingController();
    var date = _iso(selected);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, set) => AlertDialog(
          title: Text(tr('Nouveau rendez-vous')),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            field(titre, 'Titre / client', icon: Icons.person),
            field(heure, 'Heure (ex. 14:30)', icon: Icons.schedule),
            dateTile(ctx, 'Date', date, (v) => set(() => date = v)),
          ]),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(tr('Annuler'))),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(tr('Enregistrer'))),
          ],
        ),
      ),
    );
    if (ok == true && titre.text.trim().isNotEmpty) {
      await Db.i.ins('rdv', {'atelier_id': aid, 'titre': titre.text.trim(), 'heure': heure.text.trim(), 'date': date});
      bump();
    }
  }

  @override
  Widget build(BuildContext context) {
    final aid = context.read<AppState>().atelierId!;
    return AppScaffold(
      floatingActionButton: FloatingActionButton(onPressed: () => _addRdv(aid), child: const Icon(Icons.add)),
      body: DbBuilder<Map<String, List<_Ev>>>(
        load: () => _load(aid),
        builder: (c, map) {
          final dayEvents = map[_iso(selected)] ?? [];
          return Column(children: [
            Padding(
              padding: const EdgeInsets.all(8),
              child: SegmentedButton<String>(
                segments: [for (final v in ['Jour', 'Semaine', 'Mois']) ButtonSegment(value: v, label: Text(tr(v)))],
                selected: {view},
                onSelectionChanged: (v) => setState(() => view = v.first),
              ),
            ),
            if (view == 'Jour')
              ListTile(
                leading: IconButton(
                    icon: const Icon(Icons.chevron_left),
                    onPressed: () => setState(() => selected = focused = selected.subtract(const Duration(days: 1)))),
                trailing: IconButton(
                    icon: const Icon(Icons.chevron_right),
                    onPressed: () => setState(() => selected = focused = selected.add(const Duration(days: 1)))),
                title: Text(DateFormat('EEEE dd MMMM yyyy', 'fr_FR').format(selected), textAlign: TextAlign.center),
              )
            else
              TableCalendar<_Ev>(
                locale: 'fr_FR',
                firstDay: DateTime(2020),
                lastDay: DateTime(2100),
                focusedDay: focused,
                calendarFormat: view == 'Semaine' ? CalendarFormat.week : CalendarFormat.month,
                availableCalendarFormats: const {CalendarFormat.month: 'Mois', CalendarFormat.week: 'Semaine'},
                headerStyle: const HeaderStyle(formatButtonVisible: false, titleCentered: true),
                startingDayOfWeek: StartingDayOfWeek.monday,
                selectedDayPredicate: (d) => isSameDay(d, selected),
                eventLoader: (d) => map[_iso(d)] ?? [],
                onDaySelected: (sel, foc) => setState(() {
                  selected = sel;
                  focused = foc;
                }),
                onPageChanged: (f) => focused = f,
                calendarStyle: const CalendarStyle(
                  todayDecoration: BoxDecoration(color: kGold, shape: BoxShape.circle),
                  selectedDecoration: BoxDecoration(color: kViolet, shape: BoxShape.circle),
                  markerDecoration: BoxDecoration(color: Colors.redAccent, shape: BoxShape.circle),
                ),
              ),
            const Divider(),
            Expanded(
              child: dayEvents.isEmpty
                  ? Center(child: Text(tr('Rien de prévu ce jour.')))
                  : ListView(padding: const EdgeInsets.all(8), children: [
                      for (final e in dayEvents)
                        Card(
                          child: ListTile(
                            leading: Icon(e.icon, color: e.color),
                            title: Text(tr(e.kind)),
                            subtitle: Text(e.label),
                            trailing: e.rdvId != null
                                ? IconButton(
                                    icon: const Icon(Icons.delete_outline),
                                    onPressed: () async {
                                      await Db.i.del('rdv', e.rdvId!);
                                      bump();
                                    })
                                : null,
                            onTap: e.orderId == null
                                ? null
                                : () => Navigator.push(
                                    c, MaterialPageRoute(builder: (_) => OrderDetailPage(e.orderId!))),
                          ),
                        ),
                    ]),
            ),
          ]);
        },
      ),
    );
  }
}

class _Ev {
  final String kind, label;
  final IconData icon;
  final Color color;
  final int? orderId, rdvId;
  _Ev(this.kind, this.label, this.icon, this.color, {this.orderId, this.rdvId});
}

// =====================================================================
// Rapports et statistiques
// =====================================================================
class ReportsPage extends StatefulWidget {
  const ReportsPage({super.key});
  @override
  State<ReportsPage> createState() => _ReportsPageState();
}

class _Bucket {
  final String label;
  final String from, to; // bornes incluses (yyyy-MM-dd)
  _Bucket(this.label, this.from, this.to);
}

class _ReportsPageState extends State<ReportsPage> {
  String period = 'Mois';

  List<_Bucket> _buckets() {
    final f = DateFormat('yyyy-MM-dd');
    final now = DateTime.now();
    final out = <_Bucket>[];
    switch (period) {
      case 'Jour':
        for (var i = 13; i >= 0; i--) {
          final d = now.subtract(Duration(days: i));
          out.add(_Bucket(DateFormat('dd/MM').format(d), f.format(d), f.format(d)));
        }
        break;
      case 'Semaine':
        final monday = DateTime(now.year, now.month, now.day).subtract(Duration(days: now.weekday - 1));
        for (var i = 7; i >= 0; i--) {
          final a = monday.subtract(Duration(days: 7 * i));
          out.add(_Bucket(DateFormat('dd/MM').format(a), f.format(a), f.format(a.add(const Duration(days: 6)))));
        }
        break;
      case 'Année':
        for (var i = 4; i >= 0; i--) {
          final y = now.year - i;
          out.add(_Bucket('$y', '$y-01-01', '$y-12-31'));
        }
        break;
      default:
        for (var i = 11; i >= 0; i--) {
          final a = DateTime(now.year, now.month - i, 1);
          final b = DateTime(a.year, a.month + 1, 0);
          out.add(_Bucket(DateFormat('MM/yy').format(a), f.format(a), f.format(b)));
        }
    }
    return out;
  }

  Future<Map<String, Object>> _load(int aid) async {
    final bs = _buckets();
    final rev = <double>[], cnt = <double>[];
    for (final b in bs) {
      final r = await Db.i.q('''SELECT IFNULL(SUM(p.montant),0) AS t FROM paiements p
          JOIN commandes c ON c.id=p.commande_id WHERE c.atelier_id=? AND p.date>=? AND p.date<=?''', [aid, b.from, b.to]);
      rev.add(d(r.first['t']));
      final n = await Db.i.q(
          'SELECT COUNT(*) AS n FROM commandes WHERE atelier_id=? AND date_commande>=? AND date_commande<=?',
          [aid, b.from, b.to]);
      cnt.add(d(n.first['n']));
    }
    final loyal = await Db.i.q('''
      SELECT cl.nom, COUNT(c.id) AS n, IFNULL(SUM(c.prix),0) AS total FROM clients cl
      JOIN commandes c ON c.client_id=cl.id WHERE cl.atelier_id=?
      GROUP BY cl.id ORDER BY n DESC, total DESC LIMIT 5''', [aid]);
    return {'labels': bs.map((b) => b.label).toList(), 'rev': rev, 'cnt': cnt, 'loyal': loyal};
  }

  Widget _bar(List<String> labels, List<double> vals, Color col) {
    final maxV = vals.fold<double>(0, (m, v) => v > m ? v : m);
    return SizedBox(
      height: 200,
      child: BarChart(BarChartData(
        maxY: maxV == 0 ? 1 : maxV * 1.2,
        gridData: const FlGridData(show: true, drawVerticalLine: false),
        borderData: FlBorderData(show: false),
        titlesData: FlTitlesData(
          topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          leftTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 28,
              getTitlesWidget: (v, m) {
                final i = v.toInt();
                if (i < 0 || i >= labels.length) return const SizedBox();
                return Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(labels[i], style: const TextStyle(fontSize: 9)),
                );
              },
            ),
          ),
        ),
        barGroups: [
          for (var i = 0; i < vals.length; i++)
            BarChartGroupData(x: i, barRods: [BarChartRodData(toY: vals[i], color: col, width: 12, borderRadius: BorderRadius.circular(3))]),
        ],
        barTouchData: BarTouchData(
          touchTooltipData: BarTouchTooltipData(
            getTooltipItem: (g, gi, r, ri) => BarTooltipItem(
                r.toY >= 1000 ? money(r.toY) : r.toY.round().toString(), const TextStyle(color: Colors.white, fontSize: 11)),
          ),
        ),
      )),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!context.read<AppState>().isAdmin) {
      return AppScaffold(
        appBar: AppBar(title: Text(tr('Rapports et statistiques'))),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text(tr('Accès réservé à l\'administrateur.'), textAlign: TextAlign.center),
          ),
        ),
      );
    }
    final aid = context.read<AppState>().atelierId!;
    return AppScaffold(
      appBar: AppBar(title: Text(tr('Rapports et statistiques')), actions: [
        IconButton(
          tooltip: 'PDF',
          icon: const Icon(Icons.picture_as_pdf),
          onPressed: () async => Pdfs.print(await Pdfs.ordersReport(aid), 'commandes.pdf'),
        ),
        IconButton(
          tooltip: 'Excel',
          icon: const Icon(Icons.table_chart),
          onPressed: () => Exports.excel(aid),
        ),
      ]),
      body: DbBuilder<Map<String, Object>>(
        load: () => _load(aid),
        builder: (c, m) {
          final labels = (m['labels'] as List).cast<String>();
          final rev = (m['rev'] as List).cast<double>();
          final cnt = (m['cnt'] as List).cast<double>();
          final loyal = m['loyal'] as List<Map<String, Object?>>;
          return ListView(padding: const EdgeInsets.all(12), children: [
            SegmentedButton<String>(
              segments: [for (final v in ['Jour', 'Semaine', 'Mois', 'Année']) ButtonSegment(value: v, label: Text(tr(v)))],
              selected: {period},
              onSelectionChanged: (v) => setState(() => period = v.first),
            ),
            sectionTitle('Revenus (FCFA)'),
            Text('${tr('Total sur la période')} : ${money(rev.fold<double>(0, (a, b) => a + b))}'),
            const SizedBox(height: 8),
            _bar(labels, rev, kViolet),
            sectionTitle('Nombre de commandes'),
            Text('${tr('Total sur la période')} : ${cnt.fold<double>(0, (a, b) => a + b).round()}'),
            const SizedBox(height: 8),
            _bar(labels, cnt, kGold),
            sectionTitle('Clients fidèles'),
            if (loyal.isEmpty) Text(tr('Pas encore de données.')),
            for (var i = 0; i < loyal.length; i++)
              Card(
                child: ListTile(
                  leading: CircleAvatar(backgroundColor: kGold, child: Text('${i + 1}')),
                  title: Text(s(loyal[i]['nom'])),
                  subtitle: Text('${loyal[i]['n']} ${tr('commande(s)')} - ${money(d(loyal[i]['total']))}'),
                ),
              ),
          ]);
        },
      ),
    );
  }
}
