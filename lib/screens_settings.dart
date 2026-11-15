import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'db.dart';
import 'i18n.dart';
import 'services.dart';
import 'state.dart';
import 'sync.dart';
import 'updater.dart';
import 'ui.dart';

class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key});

  Future<String?> _ask(BuildContext c, String title, {String initial = ''}) {
    final ctl = TextEditingController(text: initial);
    return showDialog<String>(
      context: c,
      builder: (ctx) => AlertDialog(
        title: Text(tr(title)),
        content: field(ctl, 'Nom', icon: Icons.store),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text(tr('Annuler'))),
          FilledButton(onPressed: () => Navigator.pop(ctx, ctl.text), child: Text(tr('Enregistrer'))),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final st = context.watch<AppState>();
    final aid = st.atelierId!;
    return AppScaffold(
      appBar: AppBar(title: Text(tr('Paramètres et sauvegarde'))),
      body: ListView(padding: const EdgeInsets.all(12), children: [
        ListTile(
          leading: const Icon(Icons.account_circle, color: kViolet, size: 40),
          title: Text(st.userName),
          subtitle: Text(st.isAdmin ? tr('Propriétaire') : tr('Employé')),
        ),
        sectionTitle('Ateliers'),
        for (final a in st.ateliers)
          RadioListTile<int>(
            value: a['id'] as int,
            groupValue: st.atelierId,
            title: Text(s(a['name'])),
            secondary: st.isAdmin
                ? IconButton(
                    icon: const Icon(Icons.edit),
                    onPressed: () async {
                      final n = await _ask(context, 'Renommer l\'atelier', initial: s(a['name']));
                      if (n != null && n.trim().isNotEmpty) await st.renameAtelier(a['id'] as int, n);
                    },
                  )
                : null,
            onChanged: (v) => st.switchAtelier(v!),
          ),
        if (st.isAdmin) ...[
          ListTile(
            leading: const Icon(Icons.add_business, color: kViolet),
            title: Text(tr('Ajouter un atelier')),
            onTap: () async {
              final n = await _ask(context, 'Nouvel atelier');
              if (n != null && n.trim().isNotEmpty) await st.addAtelier(n);
            },
          ),
          ListTile(
            leading: const Icon(Icons.group_add, color: kViolet),
            title: Text(tr('Ajouter un employé à cet atelier')),
            onTap: () => showDialog(context: context, builder: (_) => _EmployeeDialog(st)),
          ),
        ],
        sectionTitle('Apparence et langue'),
        SwitchListTile(
          secondary: const Icon(Icons.dark_mode),
          title: Text(tr('Mode sombre')),
          value: st.dark,
          onChanged: st.setDark,
        ),
        SwitchListTile(
          secondary: const Icon(Icons.record_voice_over),
          title: Text(tr('Voix de bienvenue')),
          subtitle: Text(tr('Dit « Bienvenue chez Madame ZANA Couture, votre élégance notre priorité » à l\'ouverture')),
          value: st.voice,
          onChanged: st.setVoice,
        ),
        ListTile(
          leading: const Icon(Icons.language),
          title: Text(tr('Langue')),
          trailing: SegmentedButton<String>(
            segments: const [
              ButtonSegment(value: 'fr', label: Text('Français')),
              ButtonSegment(value: 'mo', label: Text('Mooré')),
            ],
            selected: {st.lang},
            onSelectionChanged: (v) => st.setLang(v.first),
          ),
        ),
        if (st.lang == 'mo')
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Text(
                'Le mooré est préparé mais peu de textes sont traduits : complétez le dictionnaire dans lib/i18n.dart.',
                style: const TextStyle(fontSize: 12)),
          ),
        sectionTitle('Sécurité'),
        SwitchListTile(
          secondary: const Icon(Icons.fingerprint),
          title: Text(tr('Connexion par empreinte digitale')),
          value: st.bioEnabled,
          onChanged: (v) async {
            if (v) {
              if (!await Bio.available()) {
                if (context.mounted) toast(context, tr('Aucune empreinte enregistrée sur ce téléphone'));
                return;
              }
              if (!await Bio.auth()) return;
            }
            await st.setBio(v);
          },
        ),
        SwitchListTile(
          secondary: const Icon(Icons.lock_clock),
          title: Text(tr('Verrouillage automatique')),
          subtitle: Text(tr('Après 2 minutes en arrière-plan')),
          value: st.autoLock,
          onChanged: st.setAutoLock,
        ),
        if (st.isAdmin) ...[
          sectionTitle('Sauvegarde des données'),
          ListTile(
            leading: const Icon(Icons.backup, color: kViolet),
            title: Text(tr('Sauvegarder (base SQLite + photos)')),
            subtitle: Text(tr('Crée un fichier .zip à enregistrer ou envoyer')),
            onTap: () => Exports.backup(),
          ),
          ListTile(
            leading: const Icon(Icons.restore, color: kViolet),
            title: Text(tr('Restaurer une sauvegarde')),
            onTap: () async {
              if (!await confirm(context, tr('Remplacer toutes les données actuelles par la sauvegarde ?'))) return;
              final ok = await Exports.restore();
              if (!context.mounted) return;
              if (ok) {
                st.logout();
                toast(context, tr('Sauvegarde restaurée. Reconnectez-vous.'));
              } else {
                toast(context, tr('Fichier de sauvegarde invalide'));
              }
            },
          ),
          ListTile(
            leading: const Icon(Icons.table_chart, color: kViolet),
            title: Text(tr('Exporter en Excel')),
            onTap: () => Exports.excel(aid),
          ),
          ListTile(
            leading: const Icon(Icons.picture_as_pdf, color: kViolet),
            title: Text(tr('Exporter les commandes en PDF')),
            onTap: () async => Pdfs.print(await Pdfs.ordersReport(aid), 'commandes.pdf'),
          ),
        ],
        const Divider(),
        sectionTitle('Catalogue partagé'),
        ValueListenableBuilder<String>(
          valueListenable: CatalogSync.status,
          builder: (c, v, _) => ListTile(
            leading: const Icon(Icons.cloud_sync, color: kViolet),
            title: Text(tr('Synchroniser le catalogue maintenant')),
            subtitle: Text(v),
            isThreeLine: v.length > 50,
            onTap: () => CatalogSync.syncNow(),
          ),
        ),
        const Divider(),
        sectionTitle('Mise à jour de l\'application'),
        ValueListenableBuilder<String>(
          valueListenable: Updater.status,
          builder: (c, v, _) => ListTile(
            leading: const Icon(Icons.system_update, color: kViolet),
            title: Text(tr('Vérifier les mises à jour')),
            subtitle: Text('$kAppVersion - $v'),
            onTap: () => Updater.checkAndPrompt(context, manual: true),
          ),
        ),
        const Divider(),
        ListTile(
          leading: const Icon(Icons.logout, color: Colors.red),
          title: Text(tr('Se déconnecter')),
          onTap: st.logout,
        ),
        const SizedBox(height: 8),
        const Divider(),
        const ListTile(
          leading: Icon(Icons.info_outline, color: kViolet),
          title: Text(kAtelierName),
          subtitle: Text('WhatsApp : $kWhatsappShow\n$kQuartier\nDéveloppeur : $kDevName - Tél : $kDevPhone'),
          isThreeLine: true,
        ),
        const Center(child: Text('$kAtelierName $kAppVersion', style: TextStyle(fontSize: 12))),
      ]),
    );
  }
}

class _EmployeeDialog extends StatefulWidget {
  final AppState st;
  const _EmployeeDialog(this.st);
  @override
  State<_EmployeeDialog> createState() => _EmployeeDialogState();
}

class _EmployeeDialogState extends State<_EmployeeDialog> {
  final name = TextEditingController();
  final email = TextEditingController();
  final pw = TextEditingController();
  final rec = TextEditingController();
  String? error;

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: Text(tr('Nouvel employé')),
        content: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            field(name, 'Nom complet', icon: Icons.person),
            field(email, 'Email', type: TextInputType.emailAddress, icon: Icons.email),
            field(pw, 'Mot de passe', icon: Icons.lock, obscure: true),
            field(rec, 'Code de récupération', icon: Icons.key),
            if (error != null) Text(tr(error!), style: const TextStyle(color: Colors.red)),
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: Text(tr('Annuler'))),
          FilledButton(
            onPressed: () async {
              final e = await widget.st.addEmployee(name.text, email.text, pw.text, rec.text);
              if (!mounted) return;
              if (e != null) {
                setState(() => error = e);
              } else {
                Navigator.pop(context);
                toast(context, tr('Employé ajouté'));
              }
            },
            child: Text(tr('Créer')),
          ),
        ],
      );
}
