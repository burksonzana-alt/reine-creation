/// Langue courante : 'fr' (français) ou 'mo' (mooré).
String currentLang = 'fr';

/// Traductions mooré. La clé est le texte français tel qu'il apparaît dans l'app.
/// Toute clé absente s'affiche en français.
/// À COMPLÉTER et faire relire par un locuteur natif du mooré :
/// ajoutez simplement des lignes  'Texte français': 'Traduction mooré',
const Map<String, String> _mo = {
  'Merci': 'Barka',
  'Bonjour': 'Ne y windga',
  // 'Clients': '...',
  // 'Commandes': '...',
  // 'Modèles': '...',
  // 'Mesures': '...',
};

String tr(String fr) => currentLang == 'mo' ? (_mo[fr] ?? fr) : fr;
