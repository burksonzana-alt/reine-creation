import 'package:flutter_tts/flutter_tts.dart';

/// Voix de bienvenue (synthèse vocale du téléphone, fonctionne sans internet
/// si une voix française est installée : Paramètres Android > Synthèse vocale).
class Voice {
  static const welcome = 'Bienvenue chez Madame ZANA Couture. Votre élégance, notre priorité.';

  static final FlutterTts _tts = FlutterTts();
  static bool _ready = false;

  /// Vrai une fois que la bienvenue a été dite depuis le lancement de l'appli
  /// (évite de la répéter à chaque déverrouillage ou changement d'atelier).
  static bool greeted = false;

  static Future<void> _init() async {
    if (_ready) return;
    await _tts.setLanguage('fr-FR');
    await _tts.setSpeechRate(0.45);
    await _tts.setPitch(1.0);
    await _tts.setVolume(1.0);
    _ready = true;
  }

  static Future<void> speakWelcome() async {
    try {
      await _init();
      await _tts.stop();
      await _tts.speak(welcome);
    } catch (_) {
      // Pas de voix disponible : on ignore, l'appli continue normalement.
    }
  }

  static Future<void> stop() async {
    try {
      await _tts.stop();
    } catch (_) {}
  }
}
