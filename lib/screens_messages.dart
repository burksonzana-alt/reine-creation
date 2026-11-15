import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import 'db.dart';
import 'i18n.dart';
import 'state.dart';
import 'ui.dart';

// =====================================================================
// Outils : numéros, WhatsApp, SMS, appel
// =====================================================================

/// Numéro au format international sans « + » (8 chiffres => Burkina Faso +226).
String waDigits(String raw) {
  var n = raw.replaceAll(RegExp(r'[^0-9]'), '');
  if (n.startsWith('00')) n = n.substring(2);
  if (n.length == 8) n = '226$n';
  return n;
}

String _clean(String raw) => raw.replaceAll(RegExp(r'[^0-9+]'), '');

Future<bool> _open(Uri u) async {
  try {
    return await launchUrl(u, mode: LaunchMode.externalApplication);
  } catch (_) {
    return false;
  }
}

Future<bool> openWhatsApp(String phone, String text) =>
    _open(Uri.parse('https://wa.me/${waDigits(phone)}?text=${Uri.encodeComponent(text)}'));

Future<bool> openSms(String phone, String text) =>
    _open(Uri.parse('sms:${_clean(phone)}?body=${Uri.encodeComponent(text)}'));

Future<bool> openCall(String phone) => _open(Uri.parse('tel:${_clean(phone)}'));

// =====================================================================
// Liste des conversations (un client = une conversation)
// =====================================================================
class MessagesPage extends StatefulWidget {
  const MessagesPage({super.key});
  @override
  State<MessagesPage> createState() => _MessagesPageState();
}

class _MessagesPageState extends State<MessagesPage> {
  String q = '';

  @override
  Widget build(BuildContext context) {
    final aid = context.read<AppState>().atelierId!;
    return AppScaffold(
      appBar: AppBar(title: Text(tr('Messagerie'))),
      body: Column(children: [
        Padding(
          padding: const EdgeInsets.all(8),
          child: TextField(
            decoration: InputDecoration(
              prefixIcon: const Icon(Icons.search),
              hintText: tr('Rechercher un client'),
              border: const OutlineInputBorder(),
            ),
            onChanged: (v) => setState(() => q = v.trim().toLowerCase()),
          ),
        ),
        Expanded(
          child: DbBuilder<List<Map<String, Object?>>>(
            load: () => Db.i.q('''
              SELECT * FROM (
                SELECT cl.id, cl.nom, cl.telephone, cl.photo,
                  (SELECT texte FROM messages m WHERE m.client_id=cl.id ORDER BY m.id DESC LIMIT 1) AS dernier,
                  (SELECT date FROM messages m WHERE m.client_id=cl.id ORDER BY m.id DESC LIMIT 1) AS ddate
                FROM clients cl WHERE cl.atelier_id=?
              ) ORDER BY (ddate IS NULL), ddate DESC, nom COLLATE NOCASE''', [aid]),
            builder: (c, all) {
              final rows = all
                  .where((r) => q.isEmpty || s(r['nom']).toLowerCase().contains(q) || s(r['telephone']).contains(q))
                  .toList();
              if (rows.isEmpty) return emptyState('Aucun client.', Icons.chat_bubble_outline);
              return ListView.builder(
                padding: const EdgeInsets.all(8),
                itemCount: rows.length,
                itemBuilder: (c, i) {
                  final r = rows[i];
                  final last = s(r['dernier']);
                  return Card(
                    child: ListTile(
                      leading: photoBox(s(r['photo']), size: 46),
                      title: Text(s(r['nom'])),
                      subtitle: Text(
                        last.isEmpty ? (s(r['telephone']).isEmpty ? tr('Pas de numéro') : s(r['telephone'])) : last,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      trailing: s(r['ddate']).length >= 10
                          ? Text(showDate(s(r['ddate'])), style: const TextStyle(fontSize: 11))
                          : null,
                      onTap: () => Navigator.push(
                          c, MaterialPageRoute(builder: (_) => ChatPage(r['id'] as int))),
                    ),
                  );
                },
              );
            },
          ),
        ),
      ]),
    );
  }
}

// =====================================================================
// Discussion avec un client
// =====================================================================
class ChatPage extends StatefulWidget {
  final int clientId;
  const ChatPage(this.clientId, {super.key});
  @override
  State<ChatPage> createState() => _ChatPageState();
}

class _ChatPageState extends State<ChatPage> {
  final ctl = TextEditingController();
  Map<String, Object?>? client;
  List<Map<String, Object?>> msgs = [];

  @override
  void initState() {
    super.initState();
    dataTick.addListener(_load);
    _load();
  }

  @override
  void dispose() {
    dataTick.removeListener(_load);
    ctl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final c = await Db.i.q('SELECT * FROM clients WHERE id=?', [widget.clientId]);
    final m = await Db.i.q('SELECT * FROM messages WHERE client_id=? ORDER BY id', [widget.clientId]);
    if (!mounted) return;
    setState(() {
      client = c.isEmpty ? null : c.first;
      msgs = m;
    });
  }

  String _now() => DateFormat('yyyy-MM-dd HH:mm').format(DateTime.now());

  Future<void> _send(String canal) async {
    final text = ctl.text.trim();
    final tel = s(client?['telephone']);
    if (text.isEmpty) return;
    if (tel.isEmpty) {
      toast(context, tr('Ce client n\'a pas de numéro de téléphone.'));
      return;
    }
    final aid = context.read<AppState>().atelierId;
    await Db.i.ins('messages', {
      'atelier_id': aid,
      'client_id': widget.clientId,
      'texte': text,
      'canal': canal,
      'sens': 'out',
      'date': _now(),
    });
    ctl.clear();
    bump();
    final ok = canal == 'whatsapp' ? await openWhatsApp(tel, text) : await openSms(tel, text);
    if (!ok && mounted) {
      toast(context, tr(canal == 'whatsapp' ? 'WhatsApp introuvable sur ce téléphone.' : 'Impossible d\'ouvrir les SMS.'));
    }
  }

  Future<void> _noteReply() async {
    final t = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(tr('Noter la réponse du client')),
        content: TextField(controller: t, maxLines: 3, autofocus: true),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(tr('Annuler'))),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(tr('Enregistrer'))),
        ],
      ),
    );
    final text = t.text.trim();
    if (ok == true && text.isNotEmpty) {
      await Db.i.ins('messages', {
        'atelier_id': context.read<AppState>().atelierId,
        'client_id': widget.clientId,
        'texte': text,
        'canal': 'note',
        'sens': 'in',
        'date': _now(),
      });
      bump();
    }
  }

  Widget _bubble(Map<String, Object?> m) {
    final out = s(m['sens']) != 'in';
    final canal = s(m['canal']);
    final label = canal == 'whatsapp' ? 'WhatsApp' : (canal == 'sms' ? 'SMS' : tr('Réponse du client'));
    final date = s(m['date']);
    final hour = date.length >= 16 ? date.substring(11, 16) : '';
    return Align(
      alignment: out ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * .78),
        margin: const EdgeInsets.symmetric(vertical: 3),
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: out ? kViolet.withAlpha(45) : Colors.grey.withAlpha(60),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
          Align(alignment: Alignment.centerLeft, child: Text(s(m['texte']))),
          const SizedBox(height: 4),
          Text('${showDate(date)} $hour - $label', style: const TextStyle(fontSize: 10)),
        ]),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cl = client;
    if (cl == null) return AppScaffold(appBar: AppBar(), body: const SizedBox());
    final nom = s(cl['nom']);
    final tel = s(cl['telephone']);
    final list = msgs.reversed.toList();
    final templates = <String, String>{
      'Tenue prête':
          'Bonjour $nom, votre tenue est prête. Vous pouvez passer la récupérer à l\'atelier $kAtelierName ($kQuartier). Merci !',
      'Essayage': 'Bonjour $nom, merci de passer à l\'atelier $kAtelierName pour l\'essayage de votre tenue.',
      'Merci': 'Bonjour $nom, merci pour votre confiance ! $kAtelierName.',
    };
    return AppScaffold(
      appBar: AppBar(
        title: Row(children: [
          photoBox(s(cl['photo']), size: 36),
          const SizedBox(width: 10),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(nom, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 16)),
              Text(tel.isEmpty ? tr('Pas de numéro') : tel, style: const TextStyle(fontSize: 12)),
            ]),
          ),
        ]),
        actions: [
          if (tel.isNotEmpty)
            IconButton(
              tooltip: tr('Appeler'),
              icon: const Icon(Icons.call),
              onPressed: () => openCall(tel),
            ),
          PopupMenuButton<String>(
            onSelected: (v) {
              if (v == 'note') _noteReply();
            },
            itemBuilder: (_) => [
              PopupMenuItem(value: 'note', child: Text(tr('Noter la réponse du client'))),
            ],
          ),
        ],
      ),
      body: Column(children: [
        Expanded(
          child: list.isEmpty
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(tr('Aucun message. Écrivez le premier ci-dessous.'), textAlign: TextAlign.center),
                  ),
                )
              : ListView.builder(
                  reverse: true,
                  padding: const EdgeInsets.all(10),
                  itemCount: list.length,
                  itemBuilder: (_, i) => _bubble(list[i]),
                ),
        ),
        SafeArea(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            SizedBox(
              height: 40,
              child: ListView(scrollDirection: Axis.horizontal, padding: const EdgeInsets.symmetric(horizontal: 8), children: [
                for (final e in templates.entries)
                  Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: ActionChip(label: Text(tr(e.key)), onPressed: () => setState(() => ctl.text = e.value)),
                  ),
              ]),
            ),
            Padding(
              padding: const EdgeInsets.all(8),
              child: Row(children: [
                Expanded(
                  child: TextField(
                    controller: ctl,
                    minLines: 1,
                    maxLines: 4,
                    decoration: InputDecoration(hintText: tr('Votre message'), border: const OutlineInputBorder()),
                  ),
                ),
                IconButton(
                  tooltip: 'SMS',
                  icon: const Icon(Icons.sms, color: kViolet),
                  onPressed: () => _send('sms'),
                ),
                IconButton(
                  tooltip: 'WhatsApp',
                  icon: const Icon(Icons.send, color: Color(0xFF25D366)),
                  onPressed: () => _send('whatsapp'),
                ),
              ]),
            ),
          ]),
        ),
      ]),
    );
  }
}
