import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'i18n.dart';

const kGold = Color(0xFFD4AF37);
const kViolet = Color(0xFF6B1D34); // bordeaux du logo (nom historique conservé)
const kCream = Color(0xFFF7F1E6);
const kGoldSoft = Color(0xFFE8CF8A);

/// Identité de l'atelier et du développeur.
const kAtelierName = 'Madame ZANA Couture';
const kDevName = 'ZANA';
const kDevPhone = '76442614';
const kAppVersion = '1.5.0';
const kWhatsapp = '+22674536284';
const kWhatsappShow = '+226 74536284';
const kQuartier = 'Yagma/Ouagadougou';

const kStatuts = ['En attente', 'En cours', 'Essayage', 'Terminé', 'Livré'];
const kCategories = ['Robe', 'Boubou', 'Chemise', 'Costume', 'Jupe', 'Pantalon', 'Uniforme', 'Tenue enfant'];
const kModesPaiement = ['Espèces', 'Orange Money', 'Moov Money', 'Coris Money', 'Autre'];
const kGalerieTypes = ['Avant', 'Après', 'Modèle', 'Réalisation'];

/// Dossier des photos (renseigné au démarrage). La base ne stocke que le nom du fichier.
late String imagesDir;

/// Incrémenté après chaque écriture en base : les écrans se rechargent.
final ValueNotifier<int> dataTick = ValueNotifier<int>(0);
void bump() => dataTick.value++;

// ---------- Helpers de formatage ----------

String s(Object? v) => (v ?? '').toString();
double d(Object? v) => (v as num?)?.toDouble() ?? 0;

String money(num v) {
  final neg = v < 0;
  final str = v.abs().round().toString();
  final b = StringBuffer();
  for (var i = 0; i < str.length; i++) {
    if (i > 0 && (str.length - i) % 3 == 0) b.write(' ');
    b.write(str[i]);
  }
  return '${neg ? '-' : ''}$b FCFA';
}

/// Numéro de reçu affiché : R-0001, R-0002...
String recuNumero(Object? n) => 'R-${s(n).padLeft(4, '0')}';

String today() => DateFormat('yyyy-MM-dd').format(DateTime.now());

String showDate(String? iso) {
  if (iso == null || iso.length < 10) return '-';
  final dt = DateTime.tryParse(iso.substring(0, 10));
  return dt == null ? '-' : DateFormat('dd/MM/yyyy').format(dt);
}

Future<String?> pickDate(BuildContext c, {String? initial}) async {
  final init = DateTime.tryParse(initial ?? '') ?? DateTime.now();
  final r = await showDatePicker(
    context: c,
    initialDate: init,
    firstDate: DateTime(2020),
    lastDate: DateTime(2100),
  );
  return r == null ? null : DateFormat('yyyy-MM-dd').format(r);
}

// ---------- Photos ----------

Future<String?> _pickImage(ImageSource source) async {
  final x = await ImagePicker().pickImage(source: source, imageQuality: 70, maxWidth: 1200);
  if (x == null) return null;
  final docs = await getApplicationDocumentsDirectory();
  imagesDir = p.join(docs.path, 'images');
  Directory(imagesDir).createSync(recursive: true);
  final name = '${DateTime.now().microsecondsSinceEpoch}${p.extension(x.path)}';
  await File(x.path).copy(p.join(imagesDir, name));
  return name;
}

/// Demande appareil photo / galerie, copie l'image et renvoie son nom de fichier.
Future<String?> choosePhoto(BuildContext c) async {
  final src = await showModalBottomSheet<ImageSource>(
    context: c,
    builder: (ctx) => SafeArea(
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        ListTile(
          leading: const Icon(Icons.photo_camera),
          title: Text(tr('Appareil photo')),
          onTap: () => Navigator.pop(ctx, ImageSource.camera),
        ),
        ListTile(
          leading: const Icon(Icons.photo_library),
          title: Text(tr('Galerie')),
          onTap: () => Navigator.pop(ctx, ImageSource.gallery),
        ),
      ]),
    ),
  );
  if (src == null) return null;
  return _pickImage(src);
}

/// Filmer ou choisir une vidéo (max 2 min en tournage), copiée dans le dossier de l'appli.
Future<String?> chooseVideo(BuildContext c) async {
  final src = await showModalBottomSheet<ImageSource>(
    context: c,
    builder: (ctx) => SafeArea(
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        ListTile(
          leading: const Icon(Icons.videocam),
          title: Text(tr('Filmer')),
          onTap: () => Navigator.pop(ctx, ImageSource.camera),
        ),
        ListTile(
          leading: const Icon(Icons.video_library),
          title: Text(tr('Choisir dans la galerie')),
          onTap: () => Navigator.pop(ctx, ImageSource.gallery),
        ),
      ]),
    ),
  );
  if (src == null) return null;
  final x = await ImagePicker().pickVideo(source: src, maxDuration: const Duration(minutes: 2));
  if (x == null) return null;
  final docs = await getApplicationDocumentsDirectory();
  imagesDir = p.join(docs.path, 'images');
  Directory(imagesDir).createSync(recursive: true);
  final ext = p.extension(x.path).isEmpty ? '.mp4' : p.extension(x.path);
  final name = '${DateTime.now().microsecondsSinceEpoch}$ext';
  await File(x.path).copy(p.join(imagesDir, name));
  return name;
}

File? imageFile(String? name) {
  if (name == null || name.isEmpty) return null;
  final f = File(p.join(imagesDir, name));
  return f.existsSync() ? f : null;
}

Widget photoBox(String? name, {double size = 56, IconData icon = Icons.person}) {
  final f = imageFile(name);
  return ClipRRect(
    borderRadius: BorderRadius.circular(size / 4),
    child: Container(
      width: size,
      height: size,
      color: kViolet.withAlpha(30),
      child: f != null ? Image.file(f, fit: BoxFit.cover) : Icon(icon, color: kViolet, size: size / 2),
    ),
  );
}

// ---------- Widgets communs ----------

void toast(BuildContext c, String m) =>
    ScaffoldMessenger.of(c).showSnackBar(SnackBar(content: Text(m)));

Future<bool> confirm(BuildContext c, String msg) async =>
    (await showDialog<bool>(
      context: c,
      builder: (ctx) => AlertDialog(
        content: Text(msg),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(tr('Annuler'))),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(tr('Confirmer'))),
        ],
      ),
    )) ??
    false;

Widget field(
  TextEditingController c,
  String label, {
  TextInputType? type,
  int lines = 1,
  IconData? icon,
  bool obscure = false,
  bool required = false,
  Widget? suffix,
}) =>
    Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextFormField(
        controller: c,
        keyboardType: type,
        maxLines: obscure ? 1 : lines,
        obscureText: obscure,
        decoration: InputDecoration(
          labelText: tr(label),
          prefixIcon: icon == null ? null : Icon(icon),
          suffixIcon: suffix,
          border: const OutlineInputBorder(),
        ),
        validator: required ? (v) => (v == null || v.trim().isEmpty) ? tr('Champ obligatoire') : null : null,
      ),
    );

Widget dateTile(BuildContext c, String label, String? value, ValueChanged<String> onPick) => ListTile(
      contentPadding: EdgeInsets.zero,
      leading: const Icon(Icons.event, color: kViolet),
      title: Text(tr(label)),
      subtitle: Text(showDate(value)),
      onTap: () async {
        final r = await pickDate(c, initial: value);
        if (r != null) onPick(r);
      },
    );

Widget sectionTitle(String t) => Padding(
      padding: const EdgeInsets.fromLTRB(4, 16, 4, 8),
      child: Text(tr(t), style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: kViolet)),
    );

Color statutColor(String st) {
  switch (st) {
    case 'En attente':
      return Colors.orange;
    case 'En cours':
      return Colors.blue;
    case 'Essayage':
      return Colors.purple;
    case 'Terminé':
      return Colors.green;
    case 'Livré':
      return Colors.teal;
    default:
      return Colors.grey;
  }
}

class StatutChip extends StatelessWidget {
  final String statut;
  const StatutChip(this.statut, {super.key});
  @override
  Widget build(BuildContext context) {
    final col = statutColor(statut);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
      decoration: BoxDecoration(color: col.withAlpha(40), borderRadius: BorderRadius.circular(12)),
      child: Text(tr(statut), style: TextStyle(color: col, fontSize: 12, fontWeight: FontWeight.w600)),
    );
  }
}

/// Recharge automatiquement quand [dataTick] change.
class DbBuilder<T> extends StatelessWidget {
  final Future<T> Function() load;
  final Widget Function(BuildContext, T) builder;
  const DbBuilder({super.key, required this.load, required this.builder});

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<int>(
        valueListenable: dataTick,
        builder: (c, _, __) => FutureBuilder<T>(
          future: load(),
          builder: (c, snap) {
            if (snap.hasError) return Center(child: Text('Erreur : ${snap.error}'));
            if (!snap.hasData) return const Center(child: CircularProgressIndicator());
            return builder(c, snap.data as T);
          },
        ),
      );
}

Widget emptyState(String text, IconData icon) => Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 64, color: kGold),
          const SizedBox(height: 12),
          Text(tr(text), textAlign: TextAlign.center),
        ]),
      ),
    );

// ---------- Logo et fond d'écran ----------

class Logo extends StatelessWidget {
  final double size;
  const Logo({super.key, this.size = 96});
  @override
  Widget build(BuildContext context) => ClipOval(
        child: Image.asset('assets/logo.png', width: size, height: size, fit: BoxFit.cover),
      );
}

/// Remplace Scaffold : le logo de Madame ZANA Couture sert de fond à tous les écrans.
class AppScaffold extends StatelessWidget {
  final PreferredSizeWidget? appBar;
  final Widget? body;
  final Widget? floatingActionButton;
  final FloatingActionButtonLocation? floatingActionButtonLocation;
  final Widget? bottomNavigationBar;
  const AppScaffold({
    super.key,
    this.appBar,
    this.body,
    this.floatingActionButton,
    this.floatingActionButtonLocation,
    this.bottomNavigationBar,
  });

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Scaffold(
      appBar: appBar,
      backgroundColor: dark ? const Color(0xFF1B1216) : kCream,
      floatingActionButton: floatingActionButton,
      floatingActionButtonLocation: floatingActionButtonLocation,
      bottomNavigationBar: bottomNavigationBar,
      body: Stack(
        fit: StackFit.expand,
        children: [
          Positioned.fill(
            child: IgnorePointer(
              child: Opacity(
                opacity: dark ? 0.10 : 0.22,
                child: Padding(
                  padding: const EdgeInsets.all(4),
                  child: Image.asset('assets/logo.png', fit: BoxFit.contain),
                ),
              ),
            ),
          ),
          if (body != null) body!,
        ],
      ),
    );
  }
}
