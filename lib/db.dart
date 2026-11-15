import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

/// Accès SQLite (base locale unique, données séparées par atelier_id).
class Db {
  Db._();
  static final Db i = Db._();

  Database? _db;

  static const _mediaSql = '''CREATE TABLE IF NOT EXISTS modele_media(
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          modele_id INTEGER NOT NULL,
          type TEXT,
          fichier TEXT,
          FOREIGN KEY(modele_id) REFERENCES modeles(id) ON DELETE CASCADE)''';

  static const _messagesSql = '''CREATE TABLE IF NOT EXISTS messages(
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          atelier_id INTEGER NOT NULL,
          client_id INTEGER NOT NULL,
          texte TEXT,
          canal TEXT,
          sens TEXT DEFAULT 'out',
          date TEXT,
          FOREIGN KEY(client_id) REFERENCES clients(id) ON DELETE CASCADE)''';

  static const _recusSql = '''CREATE TABLE IF NOT EXISTS recus(
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          atelier_id INTEGER NOT NULL,
          numero INTEGER,
          client_id INTEGER,
          client_nom TEXT,
          client_tel TEXT,
          date TEXT,
          mode TEXT,
          paye REAL DEFAULT 0,
          note TEXT)''';

  static const _recuLignesSql = '''CREATE TABLE IF NOT EXISTS recu_lignes(
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          recu_id INTEGER NOT NULL,
          designation TEXT,
          qte REAL DEFAULT 1,
          prix REAL DEFAULT 0,
          FOREIGN KEY(recu_id) REFERENCES recus(id) ON DELETE CASCADE)''';

  /// Synchronisation du catalogue : suppressions à répercuter sur le serveur.
  static const _syncDeletedSql = 'CREATE TABLE IF NOT EXISTS sync_deleted(remote_id TEXT PRIMARY KEY)';
  static const _syncTriggerSql = '''CREATE TRIGGER IF NOT EXISTS modeles_sync_del AFTER DELETE ON modeles
        WHEN old.remote_id IS NOT NULL AND old.remote_id != ''
        BEGIN
          INSERT OR REPLACE INTO sync_deleted(remote_id) VALUES (old.remote_id);
        END''';

  Future<String> path() async => p.join(await getDatabasesPath(), 'reine_creation.db');

  Future<Database> get db async => _db ??= await _open();

  Future<Database> _open() async {
    return openDatabase(
      await path(),
      version: 5,
      onConfigure: (d) async {
        await d.execute('PRAGMA foreign_keys = ON');
      },
      onUpgrade: (d, oldV, newV) async {
        if (oldV < 2) {
          await d.execute(
              "UPDATE ateliers SET name='Madame ZANA Couture' WHERE name LIKE 'Atelier de %' OR name='Mon atelier'");
        }
        if (oldV < 3) {
          await d.execute(_mediaSql);
          await d.execute(_messagesSql);
          await d.execute(
              "INSERT INTO modele_media(modele_id,type,fichier) SELECT id,'photo',image FROM modeles WHERE image IS NOT NULL AND image!=''");
        }
        if (oldV < 4) {
          await d.execute(_recusSql);
          await d.execute(_recuLignesSql);
        }
        if (oldV < 5) {
          await d.execute('ALTER TABLE modeles ADD COLUMN remote_id TEXT');
          await d.execute('ALTER TABLE modeles ADD COLUMN sync_hash TEXT');
          await d.execute('ALTER TABLE modeles ADD COLUMN remote_hash TEXT');
          await d.execute('ALTER TABLE modeles ADD COLUMN synced_at INTEGER DEFAULT 0');
          await d.execute(_syncDeletedSql);
          await d.execute(_syncTriggerSql);
        }
      },
      onCreate: (d, v) async {
        await d.execute('''CREATE TABLE users(
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          email TEXT UNIQUE NOT NULL,
          name TEXT,
          salt TEXT,
          pass_hash TEXT,
          recovery_hash TEXT,
          role TEXT DEFAULT 'admin',
          atelier_id INTEGER)''');
        await d.execute('''CREATE TABLE ateliers(
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          name TEXT NOT NULL,
          owner_id INTEGER)''');
        await d.execute('''CREATE TABLE clients(
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          atelier_id INTEGER NOT NULL,
          nom TEXT NOT NULL,
          telephone TEXT,
          adresse TEXT,
          ville TEXT,
          date_inscription TEXT,
          photo TEXT,
          notes TEXT,
          code TEXT)''');
        await d.execute('''CREATE TABLE mesures(
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          client_id INTEGER NOT NULL,
          type TEXT,
          data TEXT,
          date TEXT,
          FOREIGN KEY(client_id) REFERENCES clients(id) ON DELETE CASCADE)''');
        await d.execute('''CREATE TABLE modeles(
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          atelier_id INTEGER NOT NULL,
          nom TEXT NOT NULL,
          image TEXT,
          categorie TEXT,
          description TEXT,
          prix REAL DEFAULT 0,
          remote_id TEXT,
          sync_hash TEXT,
          remote_hash TEXT,
          synced_at INTEGER DEFAULT 0)''');
        await d.execute('''CREATE TABLE commandes(
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          atelier_id INTEGER NOT NULL,
          client_id INTEGER NOT NULL,
          modele_id INTEGER,
          description TEXT,
          prix REAL DEFAULT 0,
          statut TEXT DEFAULT 'En attente',
          date_commande TEXT,
          date_essayage TEXT,
          date_livraison TEXT,
          signature TEXT,
          FOREIGN KEY(client_id) REFERENCES clients(id) ON DELETE CASCADE)''');
        await d.execute('''CREATE TABLE paiements(
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          commande_id INTEGER NOT NULL,
          montant REAL NOT NULL,
          date TEXT,
          note TEXT,
          FOREIGN KEY(commande_id) REFERENCES commandes(id) ON DELETE CASCADE)''');
        await d.execute('''CREATE TABLE galerie(
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          atelier_id INTEGER NOT NULL,
          image TEXT,
          type TEXT,
          legende TEXT,
          date TEXT)''');
        await d.execute('''CREATE TABLE rdv(
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          atelier_id INTEGER NOT NULL,
          client_id INTEGER,
          titre TEXT,
          date TEXT,
          heure TEXT,
          note TEXT)''');
        await d.execute(_mediaSql);
        await d.execute(_messagesSql);
        await d.execute(_recusSql);
        await d.execute(_recuLignesSql);
        await d.execute(_syncDeletedSql);
        await d.execute(_syncTriggerSql);
      },
    );
  }

  Future<List<Map<String, Object?>>> q(String sql, [List<Object?> args = const []]) async =>
      (await db).rawQuery(sql, args);

  Future<int> ins(String table, Map<String, Object?> values) async => (await db).insert(table, values);

  Future<int> upd(String table, Map<String, Object?> values, int id) async =>
      (await db).update(table, values, where: 'id=?', whereArgs: [id]);

  Future<int> del(String table, int id) async =>
      (await db).delete(table, where: 'id=?', whereArgs: [id]);

  Future<int> delWhere(String table, String where, List<Object?> args) async =>
      (await db).delete(table, where: where, whereArgs: args);

  Future<void> close() async {
    await _db?.close();
    _db = null;
  }

  /// Hash SHA-256 salé (mot de passe / code de récupération).
  static String hash(String value, String salt) =>
      sha256.convert(utf8.encode('$salt:$value')).toString();
}
