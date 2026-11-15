import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'i18n.dart';
import 'services.dart';
import 'state.dart';
import 'ui.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});
  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final email = TextEditingController();
  final pw = TextEditingController();
  bool hide = true, busy = false, bioOk = false;
  String? error;

  @override
  void initState() {
    super.initState();
    final st = context.read<AppState>();
    email.text = st.prefs.getString('last_email') ?? '';
    if (st.bioEnabled) Bio.available().then((v) => mounted ? setState(() => bioOk = v) : null);
  }

  Future<void> _login() async {
    setState(() {
      busy = true;
      error = null;
    });
    final e = await context.read<AppState>().login(email.text, pw.text);
    if (mounted) setState(() {
      busy = false;
      error = e;
    });
  }

  Future<void> _bio() async {
    final e = await context.read<AppState>().bioLogin();
    if (mounted && e != null) setState(() => error = e);
  }

  @override
  Widget build(BuildContext context) {
    return AppScaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(children: [
              const Logo(size: 150),
              const SizedBox(height: 12),
              const Text(kAtelierName,
                  style: TextStyle(fontSize: 26, fontWeight: FontWeight.bold, color: kViolet)),
              Text(tr('Votre atelier de couture numérique'), style: const TextStyle(color: kGold)),
              const SizedBox(height: 28),
              field(email, 'Email', type: TextInputType.emailAddress, icon: Icons.email),
              field(pw, 'Mot de passe',
                  icon: Icons.lock,
                  obscure: hide,
                  suffix: IconButton(
                    icon: Icon(hide ? Icons.visibility : Icons.visibility_off),
                    onPressed: () => setState(() => hide = !hide),
                  )),
              if (error != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Text(tr(error!), style: const TextStyle(color: Colors.red)),
                ),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  style: FilledButton.styleFrom(backgroundColor: kViolet, padding: const EdgeInsets.all(14)),
                  onPressed: busy ? null : _login,
                  child: Text(tr('Connexion')),
                ),
              ),
              if (bioOk)
                TextButton.icon(
                  onPressed: _bio,
                  icon: const Icon(Icons.fingerprint, size: 32, color: kGold),
                  label: Text(tr('Connexion par empreinte')),
                ),
              TextButton(
                onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const ResetScreen())),
                child: Text(tr('Mot de passe oublié ?')),
              ),
              TextButton(
                onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const RegisterScreen())),
                child: Text(tr('Créer un compte')),
              ),
              const SizedBox(height: 16),
              const Text('WhatsApp : $kWhatsappShow', style: TextStyle(fontSize: 12)),
              const Text(kQuartier, style: TextStyle(fontSize: 12)),
              const Text('Développeur : $kDevName - $kDevPhone', style: TextStyle(fontSize: 12)),
            ]),
          ),
        ),
      ),
    );
  }
}

class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key});
  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final name = TextEditingController();
  final email = TextEditingController();
  final pw = TextEditingController();
  final rec = TextEditingController();
  String? error;

  Future<void> _go() async {
    final e = await context.read<AppState>().register(name.text, email.text, pw.text, rec.text);
    if (!mounted) return;
    if (e != null) {
      setState(() => error = e);
    } else {
      Navigator.of(context).popUntil((r) => r.isFirst);
    }
  }

  @override
  Widget build(BuildContext context) => AppScaffold(
        appBar: AppBar(title: Text(tr('Créer un compte'))),
        body: ListView(padding: const EdgeInsets.all(20), children: [
          field(name, 'Nom complet', icon: Icons.person),
          field(email, 'Email', type: TextInputType.emailAddress, icon: Icons.email),
          field(pw, 'Mot de passe', icon: Icons.lock, obscure: true),
          field(rec, 'Code de récupération (à retenir)', icon: Icons.key),
          Text(tr('Le code de récupération permet de changer le mot de passe si vous l\'oubliez.'),
              style: const TextStyle(fontSize: 12)),
          if (error != null) Text(tr(error!), style: const TextStyle(color: Colors.red)),
          const SizedBox(height: 16),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: kViolet, padding: const EdgeInsets.all(14)),
            onPressed: _go,
            child: Text(tr('Créer mon compte')),
          ),
        ]),
      );
}

class ResetScreen extends StatefulWidget {
  const ResetScreen({super.key});
  @override
  State<ResetScreen> createState() => _ResetScreenState();
}

class _ResetScreenState extends State<ResetScreen> {
  final email = TextEditingController();
  final code = TextEditingController();
  final pw = TextEditingController();
  String? error;

  Future<void> _go() async {
    final e = await context.read<AppState>().resetPassword(email.text, code.text, pw.text);
    if (!mounted) return;
    if (e != null) {
      setState(() => error = e);
    } else {
      toast(context, tr('Mot de passe modifié'));
      Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) => AppScaffold(
        appBar: AppBar(title: Text(tr('Mot de passe oublié ?'))),
        body: ListView(padding: const EdgeInsets.all(20), children: [
          field(email, 'Email', type: TextInputType.emailAddress, icon: Icons.email),
          field(code, 'Code de récupération', icon: Icons.key),
          field(pw, 'Nouveau mot de passe', icon: Icons.lock, obscure: true),
          if (error != null) Text(tr(error!), style: const TextStyle(color: Colors.red)),
          const SizedBox(height: 16),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: kViolet, padding: const EdgeInsets.all(14)),
            onPressed: _go,
            child: Text(tr('Valider')),
          ),
        ]),
      );
}

/// Écran de verrouillage automatique : empreinte ou mot de passe.
class LockScreen extends StatefulWidget {
  const LockScreen({super.key});
  @override
  State<LockScreen> createState() => _LockScreenState();
}

class _LockScreenState extends State<LockScreen> {
  final pw = TextEditingController();
  String? error;

  @override
  void initState() {
    super.initState();
    final st = context.read<AppState>();
    if (st.bioEnabled) _bio();
  }

  Future<void> _bio() async {
    if (await Bio.auth() && mounted) context.read<AppState>().unlock();
  }

  Future<void> _pw() async {
    final st = context.read<AppState>();
    if (await st.checkPassword(pw.text)) {
      st.unlock();
    } else {
      setState(() => error = 'Mot de passe incorrect');
    }
  }

  @override
  Widget build(BuildContext context) {
    final st = context.read<AppState>();
    return AppScaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(children: [
              const Logo(size: 90),
              const SizedBox(height: 12),
              Text(tr('Application verrouillée'), style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
              const SizedBox(height: 20),
              field(pw, 'Mot de passe', icon: Icons.lock, obscure: true),
              if (error != null) Text(tr(error!), style: const TextStyle(color: Colors.red)),
              FilledButton(
                style: FilledButton.styleFrom(backgroundColor: kViolet),
                onPressed: _pw,
                child: Text(tr('Déverrouiller')),
              ),
              if (st.bioEnabled)
                IconButton(onPressed: _bio, icon: const Icon(Icons.fingerprint, size: 48, color: kGold)),
              TextButton(onPressed: st.logout, child: Text(tr('Se déconnecter'))),
            ]),
          ),
        ),
      ),
    );
  }
}
