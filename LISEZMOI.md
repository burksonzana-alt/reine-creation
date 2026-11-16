# Madame ZANA Couture (v1.7.0)

Développeur : ZANA - 76442614

Application Flutter (Android) de gestion d'atelier de couture.

## Contenu
- `lib/` : code Dart (clients, mesures, modèles, commandes, paiements, galerie, agenda, rapports, sauvegarde, facture PDF, QR code, signature, multi-ateliers, mode sombre, français / mooré)
- `tools/patch_android.py` : adapte le dossier Android (permissions, notifications, empreinte, icônes)
- `build_local.sh` : compile l'APK sur une machine où Flutter fonctionne
- `.github/workflows/build.yml` : compile l'APK dans le cloud (GitHub Actions)

## Limites connues
- Non compilé avant livraison : Flutter n'était pas disponible là où le projet a été écrit. Si `flutter build` signale une erreur, envoyez-la pour correction.
- Firebase (Auth, Firestore, Storage) n'est pas branché : il exige VOTRE fichier `google-services.json`. L'authentification et les données sont locales (SQLite). La sauvegarde se fait en fichier .zip (base + photos).
- Mooré : seulement quelques mots dans `lib/i18n.dart`, à faire compléter par un locuteur.
- Impression Bluetooth : via la boîte d'impression Android (service d'impression Bluetooth à installer).

## Nouveautés 1.1.0
- Atelier : « Madame ZANA Couture » (les ateliers nommés par défaut sont renommés à la mise à jour).
- Chiffre d'affaires, paiements en attente, rapports, export Excel / PDF des commandes, sauvegarde et restauration : réservés à l'administrateur (compte propriétaire). Les employés ne voient pas ces écrans.
- Nouvelle icône : couturière à sa machine à coudre.
- Développeur ZANA affiché sur l'écran de connexion et dans les paramètres.

## Nouveautés 1.2.0
- Contact WhatsApp +226 74 53 62 84 et quartier Yagma, Ouagadougou (connexion, paramètres, factures).
- Messagerie : une conversation par client, envoi par WhatsApp ou SMS, messages modèles, historique.
- Accueil : les cartes « Chiffre d'affaires du mois » et « Paiements en attente » sont supprimées.
- Modèles : jusqu'à 5 photos et 1 vidéo par modèle.

## Nouveautés 1.3.0
- Nom de l'application : « Madame ZANA Couture ».
- Barre du haut : boîte de messages à gauche, logo au centre, « Madame ZANA Couture / Yagma/Ouagadougou / WhatsApp +226 74536284 » à droite.
- Le logo est l'icône de l'application (classique et adaptative) et le fond de tous les écrans.
- Couleurs de l'application : bordeaux et or, comme le logo.
- Nouvelle partie « Reçus d'achat » (Accueil et menu Plus) : articles, quantités, prix, mode de paiement (espèces, Orange/Moov/Coris Money), montant payé et reste, PDF A5 avec logo, impression, partage et envoi WhatsApp. Numérotation R-0001, R-0002...
- Les factures, fiches de mesures et rapports PDF portent maintenant le logo.

## Nouveautés 1.4.0
- Catalogue partagé automatiquement entre tous les téléphones (Firebase Firestore, sans Storage donc sans carte bancaire) : modèles, prix, descriptions et photos. Suppressions et modifications comprises. Les vidéos restent locales.
- Suivre `GUIDE_FIREBASE.txt` pour créer le projet Firebase, puis mettre `google-services.json` à la racine du projet avant de compiler. Sans ce fichier, l'application fonctionne comme avant (catalogue local).
- Plus > Paramètres : état de la synchronisation et bouton « Synchroniser le catalogue maintenant ».
- Photos prises à 1200 px (plus légères) pour passer dans la base en ligne.

## Nouveautés 1.5.0
- Mise à jour automatique sur tous les téléphones : à l'ouverture, l'application compare sa version à la dernière publiée sur GitHub (Releases) et propose « Mettre à jour ». Vérification manuelle dans Paramètres. `[OBLIGATOIRE]` dans `RELEASE_NOTES.md` rend la mise à jour impossible à ignorer.
- Signature fixe de l'APK (`tools/zana-release.jks`) : indispensable pour que les mises à jour s'installent par-dessus l'ancienne version sans perdre les données. Les versions <= 1.4 avaient une clé différente : sauvegarder, désinstaller, installer la 1.5.0, restaurer (une seule fois).
- Le workflow GitHub publie automatiquement l'APK en « Release » à chaque envoi. Le dépôt doit être public.
- Pour chaque nouvelle version : augmenter `version:` dans `pubspec.yaml` et `kAppVersion` dans `lib/ui.dart`.
- Limites : non compilé ici (pas de Flutter disponible) ; le téléchargement passe par le navigateur du téléphone.

## Nouveautés 1.7.0
- Vignette de la vidéo comme une photo ; appui long sur la vidéo pour la supprimer (avec confirmation).
- Page de consultation d'un modèle : on balaie pour voir toutes les photos puis la vidéo ; galerie plein écran avec loupe.
