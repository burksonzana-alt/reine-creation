import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import 'db.dart';
import 'i18n.dart';
import 'screens_clients.dart';
import 'screens_messages.dart';
import 'screens_more.dart';
import 'screens_orders.dart';
import 'screens_receipts.dart';
import 'screens_settings.dart';
import 'services.dart';
import 'sync.dart';
import 'updater.dart';
import 'state.dart';
import 'ui.dart';

class HomeShell extends StatefulWidget {
  const HomeShell({super.key});
  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int tab = 0;

  @override
  void initState() {
    super.initState();
    final aid = context.read<AppState>().atelierId!;
    Notif.rescheduleAll(aid).then((_) => Notif.showToday(aid));
    dataTick.addListener(_resched);
    CatalogSync.start(aid);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) Updater.checkAndPrompt(context);
    });
  }

  void _resched() {
    final aid = context.read<AppState>().atelierId;
    if (aid != null) Notif.rescheduleAll(aid);
  }

  @override
  void dispose() {
    dataTick.removeListener(_resched);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final st = context.watch<AppState>();
    final pages = <Widget>[
      const DashboardPage(),
      const ClientsPage(),
      const OrdersPage(),
      const AgendaPage(),
      const MorePage(),
    ];
    return AppScaffold(
      appBar: AppBar(
        toolbarHeight: 80,
        leadingWidth: 64,
        centerTitle: true,
        // En haut à gauche : la boîte de messages
        leading: IconButton(
          tooltip: tr('Boîte de messages'),
          icon: const Icon(Icons.mail, size: 32, color: kGoldSoft),
          onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const MessagesPage())),
        ),
        // Au centre : le logo
        title: const Logo(size: 66),
        // À droite : nom, quartier et WhatsApp
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 10),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 128),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: const [
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(kAtelierName,
                        style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.white)),
                  ),
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(kQuartier, style: TextStyle(fontSize: 10.5, color: kGoldSoft)),
                  ),
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text('WhatsApp $kWhatsappShow', style: TextStyle(fontSize: 10.5, color: kGoldSoft)),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
      body: KeyedSubtree(key: ValueKey('${st.atelierId}-$tab'), child: pages[tab]),
      bottomNavigationBar: NavigationBar(
        selectedIndex: tab,
        onDestinationSelected: (i) => setState(() => tab = i),
        destinations: [
          NavigationDestination(icon: const Icon(Icons.dashboard), label: tr('Accueil')),
          NavigationDestination(icon: const Icon(Icons.people), label: tr('Clients')),
          NavigationDestination(icon: const Icon(Icons.checkroom), label: tr('Commandes')),
          NavigationDestination(icon: const Icon(Icons.calendar_month), label: tr('Agenda')),
          NavigationDestination(icon: const Icon(Icons.menu), label: tr('Plus')),
        ],
      ),
    );
  }
}

// =====================================================================
// Tableau de bord
// =====================================================================
class DashboardPage extends StatelessWidget {
  const DashboardPage({super.key});

  Future<Map<String, num>> _load(int aid) async {
    Future<num> one(String sql, List<Object?> a) async => (await Db.i.q(sql, a)).first.values.first as num? ?? 0;
    return {
      'clients': await one('SELECT COUNT(*) FROM clients WHERE atelier_id=?', [aid]),
      'encours': await one(
          "SELECT COUNT(*) FROM commandes WHERE atelier_id=? AND statut IN ('En attente','En cours','Essayage')", [aid]),
      'finies': await one("SELECT COUNT(*) FROM commandes WHERE atelier_id=? AND statut IN ('Terminé','Livré')", [aid]),
      'modeles': await one('SELECT COUNT(*) FROM modeles WHERE atelier_id=?', [aid]),
    };
  }

  @override
  Widget build(BuildContext context) {
    final aid = context.read<AppState>().atelierId!;
    return DbBuilder<Map<String, num>>(
      load: () => _load(aid),
      builder: (c, m) {
        Widget card(String label, String value, IconData icon, Color col) => Card(
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Icon(icon, color: col, size: 28),
                  const Spacer(),
                  FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(value, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold))),
                  Text(tr(label), style: const TextStyle(fontSize: 12)),
                ]),
              ),
            );
        return ListView(padding: const EdgeInsets.all(12), children: [
          Text('${tr('Bonjour')}, ${context.read<AppState>().userName}',
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: kViolet)),
          const SizedBox(height: 6),
          Card(
            child: ListTile(
              leading: const Icon(Icons.search, color: kViolet),
              title: Text(tr('Rechercher un client, une commande, un modèle')),
              onTap: () => Navigator.push(c, MaterialPageRoute(builder: (_) => const SearchPage())),
            ),
          ),
          const SizedBox(height: 4),
          GridView.count(
            crossAxisCount: 2,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            childAspectRatio: 1.45,
            mainAxisSpacing: 8,
            crossAxisSpacing: 8,
            children: [
              card('Clients', '${m['clients']}', Icons.people, kViolet),
              card('Commandes en cours', '${m['encours']}', Icons.content_cut, Colors.blue),
              card('Commandes terminées', '${m['finies']}', Icons.check_circle, Colors.green),
              card('Modèles enregistrés', '${m['modeles']}', Icons.style, Colors.pink),
            ],
          ),
          const SizedBox(height: 8),
          Card(
            child: ListTile(
              leading: const Icon(Icons.chat, color: Color(0xFF25D366)),
              title: Text(tr('Messagerie clients')),
              subtitle: Text(tr('Écrire à un client par WhatsApp ou SMS')),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.push(c, MaterialPageRoute(builder: (_) => const MessagesPage())),
            ),
          ),
          Card(
            child: ListTile(
              leading: const Icon(Icons.receipt_long, color: kGold),
              title: Text(tr('Reçus d\'achat')),
              subtitle: Text(tr('Créer, imprimer et envoyer un reçu')),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.push(c, MaterialPageRoute(builder: (_) => const ReceiptsPage())),
            ),
          ),
          Card(
            child: ListTile(
              leading: const Icon(Icons.storefront, color: kViolet),
              title: const Text(kAtelierName),
              subtitle: const Text('WhatsApp : $kWhatsappShow\n$kQuartier'),
              isThreeLine: true,
            ),
          ),
          sectionTitle('À faire aujourd\'hui et bientôt'),
          _Upcoming(aid),
        ]);
      },
    );
  }
}

class _Upcoming extends StatelessWidget {
  final int aid;
  const _Upcoming(this.aid);

  @override
  Widget build(BuildContext context) => FutureBuilder(
        future: Db.i.q('''
          SELECT c.id, c.date_livraison, c.date_essayage, cl.nom FROM commandes c
          JOIN clients cl ON cl.id=c.client_id
          WHERE c.atelier_id=? AND c.statut!='Livré'
            AND ((c.date_livraison>=? AND c.date_livraison<=date(?, '+7 day'))
              OR (c.date_essayage>=? AND c.date_essayage<=date(?, '+7 day')))
          ORDER BY c.date_livraison LIMIT 15''', [aid, today(), today(), today(), today()]),
        builder: (c, snap) {
          final rows = snap.data ?? [];
          if (rows.isEmpty) return Padding(padding: const EdgeInsets.all(12), child: Text(tr('Rien de prévu cette semaine.')));
          return Column(children: [
            for (final r in rows)
              Card(
                child: ListTile(
                  leading: const Icon(Icons.event_available, color: kViolet),
                  title: Text('${r['nom']} - ${tr('commande')} n°${r['id']}'),
                  subtitle: Text(
                      '${tr('Essayage')} : ${showDate(s(r['date_essayage']))}   ${tr('Livraison')} : ${showDate(s(r['date_livraison']))}'),
                  onTap: () => Navigator.push(
                      context, MaterialPageRoute(builder: (_) => OrderDetailPage(r['id'] as int))),
                ),
              ),
          ]);
        },
      );
}

// =====================================================================
// Recherche intelligente
// =====================================================================
class SearchPage extends StatefulWidget {
  const SearchPage({super.key});
  @override
  State<SearchPage> createState() => _SearchPageState();
}

class _SearchPageState extends State<SearchPage> {
  final ctl = TextEditingController();
  String q = '';

  @override
  Widget build(BuildContext context) {
    final aid = context.read<AppState>().atelierId!;
    return AppScaffold(
      appBar: AppBar(
        title: TextField(
          controller: ctl,
          autofocus: true,
          style: const TextStyle(color: Colors.white),
          cursorColor: Colors.white,
          decoration: InputDecoration(
              hintText: tr('Client, téléphone, commande, modèle...'),
              hintStyle: const TextStyle(color: Colors.white70),
              border: InputBorder.none),
          onChanged: (v) => setState(() => q = v.trim()),
        ),
      ),
      body: q.isEmpty
          ? emptyState('Recherchez par nom, téléphone, numéro de commande ou modèle', Icons.search)
          : FutureBuilder(
              future: _search(aid, q),
              builder: (c, snap) {
                final r = snap.data;
                if (r == null) return const Center(child: CircularProgressIndicator());
                if (r.clients.isEmpty && r.orders.isEmpty && r.models.isEmpty) {
                  return emptyState('Aucun résultat', Icons.search_off);
                }
                return ListView(padding: const EdgeInsets.all(8), children: [
                  if (r.clients.isNotEmpty) sectionTitle('Clients'),
                  for (final x in r.clients)
                    ListTile(
                      leading: photoBox(s(x['photo'])),
                      title: Text(s(x['nom'])),
                      subtitle: Text(s(x['telephone'])),
                      onTap: () => Navigator.push(
                          context, MaterialPageRoute(builder: (_) => ClientDetailPage(x['id'] as int))),
                    ),
                  if (r.orders.isNotEmpty) sectionTitle('Commandes'),
                  for (final x in r.orders)
                    ListTile(
                      leading: const Icon(Icons.checkroom, color: kViolet),
                      title: Text('${tr('Commande')} n°${x['id']} - ${x['nom']}'),
                      subtitle: Text('${s(x['modele'])} - ${money(d(x['prix']))}'),
                      trailing: StatutChip(s(x['statut'])),
                      onTap: () => Navigator.push(
                          context, MaterialPageRoute(builder: (_) => OrderDetailPage(x['id'] as int))),
                    ),
                  if (r.models.isNotEmpty) sectionTitle('Modèles'),
                  for (final x in r.models)
                    ListTile(
                      leading: photoBox(s(x['image']), icon: Icons.style),
                      title: Text(s(x['nom'])),
                      subtitle: Text('${s(x['categorie'])} - ${money(d(x['prix']))}'),
                      onTap: () => Navigator.push(
                          context, MaterialPageRoute(builder: (_) => ModelFormPage(modelId: x['id'] as int))),
                    ),
                ]);
              },
            ),
    );
  }

  Future<({List<Map<String, Object?>> clients, List<Map<String, Object?>> orders, List<Map<String, Object?>> models})>
      _search(int aid, String q) async {
    final like = '%$q%';
    final num = int.tryParse(q.replaceAll('#', '')) ?? -1;
    return (
      clients: await Db.i.q(
          'SELECT * FROM clients WHERE atelier_id=? AND (nom LIKE ? OR telephone LIKE ? OR code LIKE ?) ORDER BY nom LIMIT 30',
          [aid, like, like, like]),
      orders: await Db.i.q('''
          SELECT c.*, cl.nom, m.nom AS modele FROM commandes c JOIN clients cl ON cl.id=c.client_id
          LEFT JOIN modeles m ON m.id=c.modele_id
          WHERE c.atelier_id=? AND (c.id=? OR cl.nom LIKE ? OR m.nom LIKE ? OR c.description LIKE ?)
          ORDER BY c.id DESC LIMIT 30''', [aid, num, like, like, like]),
      models: await Db.i.q(
          'SELECT * FROM modeles WHERE atelier_id=? AND (nom LIKE ? OR categorie LIKE ? OR description LIKE ?) LIMIT 30',
          [aid, like, like, like]),
    );
  }
}

// =====================================================================
// Menu "Plus"
// =====================================================================
class MorePage extends StatelessWidget {
  const MorePage({super.key});

  @override
  Widget build(BuildContext context) {
    Widget item(IconData i, String t, Widget page) => Card(
          child: ListTile(
            leading: Icon(i, color: kViolet),
            title: Text(tr(t)),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => page)),
          ),
        );
    return ListView(padding: const EdgeInsets.all(12), children: [
      item(Icons.chat, 'Messagerie', const MessagesPage()),
      item(Icons.receipt_long, 'Reçus d\'achat', const ReceiptsPage()),
      item(Icons.style, 'Catalogue des modèles', const ModelsPage()),
      item(Icons.photo_library, 'Galerie des créations', const GalleryPage()),
      if (context.read<AppState>().isAdmin)
        item(Icons.bar_chart, 'Rapports et statistiques', const ReportsPage()),
      item(Icons.settings, 'Paramètres et sauvegarde', const SettingsPage()),
    ]);
  }
}
