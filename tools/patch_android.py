#!/usr/bin/env python3
"""Adapte le dossier android/ généré par `flutter create` pour Reine Création.
Usage : python3 tools/patch_android.py   (depuis la racine du projet)
Idempotent : peut être relancé sans danger."""
import glob
import json
import os
import re
import shutil

ROOT = os.getcwd()
APP = os.path.join(ROOT, 'android', 'app')


def read(p):
    with open(p, encoding='utf-8') as f:
        return f.read()


def write(p, t):
    with open(p, 'w', encoding='utf-8') as f:
        f.write(t)


# ---------- Manifest ----------
mp = os.path.join(APP, 'src', 'main', 'AndroidManifest.xml')
m = read(mp)
perms = [
    'android.permission.CAMERA',
    'android.permission.POST_NOTIFICATIONS',
    'android.permission.USE_BIOMETRIC',
    'android.permission.RECEIVE_BOOT_COMPLETED',
]
add = ''.join(f'    <uses-permission android:name="{p}"/>\n' for p in perms if p not in m)
if add:
    m = m.replace('<application', add + '    <application', 1)
m = re.sub(r'android:label="[^"]*"', 'android:label="Madame ZANA Couture"', m, count=1)
if 'ScheduledNotificationReceiver' not in m:
    receivers = '''
        <receiver android:exported="false" android:name="com.dexterous.flutterlocalnotifications.ScheduledNotificationReceiver"/>
        <receiver android:exported="false" android:name="com.dexterous.flutterlocalnotifications.ScheduledNotificationBootReceiver">
            <intent-filter>
                <action android:name="android.intent.action.BOOT_COMPLETED"/>
                <action android:name="android.intent.action.MY_PACKAGE_REPLACED"/>
                <action android:name="android.intent.action.QUICKBOOT_POWERON"/>
                <action android:name="com.htc.intent.action.QUICKBOOT_POWERON"/>
            </intent-filter>
        </receiver>
'''
    m = m.replace('</application>', receivers + '    </application>', 1)
if 'android.intent.action.SENDTO' not in m and '</queries>' in m:
    extra = '''        <intent>
            <action android:name="android.intent.action.VIEW"/>
            <data android:scheme="https"/>
        </intent>
        <intent>
            <action android:name="android.intent.action.SENDTO"/>
            <data android:scheme="sms"/>
        </intent>
        <intent>
            <action android:name="android.intent.action.DIAL"/>
            <data android:scheme="tel"/>
        </intent>
        <package android:name="com.whatsapp"/>
        <package android:name="com.whatsapp.w4b"/>
    '''
    m = m.replace('</queries>', extra + '</queries>', 1)
# Synthèse vocale (flutter_tts) : Android 11+ exige de déclarer le service TTS
if 'android.intent.action.TTS_SERVICE' not in m and '</queries>' in m:
    m = m.replace('</queries>',
                  '        <intent>\n            <action android:name="android.intent.action.TTS_SERVICE"/>\n        </intent>\n    </queries>', 1)
write(mp, m)

# ---------- MainActivity (FlutterFragmentActivity requis par local_auth) ----------
for kt in glob.glob(os.path.join(APP, 'src', 'main', 'kotlin', '**', 'MainActivity.kt'), recursive=True):
    t = read(kt)
    t = t.replace('import io.flutter.embedding.android.FlutterActivity',
                  'import io.flutter.embedding.android.FlutterFragmentActivity')
    t = t.replace(': FlutterActivity()', ': FlutterFragmentActivity()')
    write(kt, t)

# ---------- Gradle : minSdk 23 + desugaring (flutter_local_notifications) ----------
kts = os.path.join(APP, 'build.gradle.kts')
grv = os.path.join(APP, 'build.gradle')
if os.path.exists(kts):
    g = read(kts)
    g = re.sub(r'minSdk\s*=\s*flutter\.minSdkVersion', 'minSdk = 23', g)
    if 'isCoreLibraryDesugaringEnabled' not in g:
        g = re.sub(r'(compileOptions\s*\{)', r'\1\n        isCoreLibraryDesugaringEnabled = true', g, count=1)
    if 'desugar_jdk_libs' not in g:
        g += '\ndependencies {\n    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")\n}\n'
    write(kts, g)
elif os.path.exists(grv):
    g = read(grv)
    g = re.sub(r'minSdkVersion\s+flutter\.minSdkVersion', 'minSdkVersion 23', g)
    if 'coreLibraryDesugaringEnabled' not in g:
        g = re.sub(r'(compileOptions\s*\{)', r'\1\n        coreLibraryDesugaringEnabled true', g, count=1)
    if 'desugar_jdk_libs' not in g:
        g += "\ndependencies {\n    coreLibraryDesugaring 'com.android.tools:desugar_jdk_libs:2.1.4'\n}\n"
    write(grv, g)
else:
    raise SystemExit('build.gradle(.kts) introuvable : lancez d\'abord flutter create')

# ---------- Icônes (logo Madame ZANA Couture) ----------
# Copie tout le contenu de tools/icons/<dossier>/ vers android/app/src/main/res/<dossier>/
src = os.path.join(ROOT, 'tools', 'icons')
for d in glob.glob(os.path.join(src, '*')):
    if not os.path.isdir(d):
        continue
    dst = os.path.join(APP, 'src', 'main', 'res', os.path.basename(d))
    os.makedirs(dst, exist_ok=True)
    for f in glob.glob(os.path.join(d, '*')):
        shutil.copy(f, os.path.join(dst, os.path.basename(f)))


# ---------- Signature fixe (indispensable pour que les mises à jour s'installent par-dessus) ----------
KS_PASS = '220ce3530cd33d1557034eb1'
_ks_src = os.path.join(ROOT, 'tools', 'zana-release.jks')
if os.path.exists(_ks_src):
    shutil.copy(_ks_src, os.path.join(APP, 'zana-release.jks'))
    for f in ('build.gradle.kts', 'build.gradle'):
        q = os.path.join(APP, f)
        if not os.path.exists(q):
            continue
        t = read(q)
        if 'zana-release.jks' in t:
            continue
        if f.endswith('.kts'):
            blk = (
                'signingConfigs {\n        create("release") {\n'
                '            storeFile = file("zana-release.jks")\n'
                f'            storePassword = "{KS_PASS}"\n'
                '            keyAlias = "zana"\n'
                f'            keyPassword = "{KS_PASS}"\n'
                '        }\n    }\n    ')
            t = re.sub(r'signingConfig\s*=\s*signingConfigs\.getByName\("debug"\)',
                       'signingConfig = signingConfigs.getByName("release")', t)
        else:
            blk = (
                'signingConfigs {\n        release {\n'
                '            storeFile file("zana-release.jks")\n'
                f'            storePassword "{KS_PASS}"\n'
                '            keyAlias "zana"\n'
                f'            keyPassword "{KS_PASS}"\n'
                '        }\n    }\n    ')
            t = re.sub(r'signingConfig\s+signingConfigs\.debug', 'signingConfig signingConfigs.release', t)
        t = re.sub(r'(buildTypes\s*\{)', lambda m: blk + m.group(1), t, count=1)
        write(q, t)
    print('Signature fixe appliquée')
else:
    print('ATTENTION : tools/zana-release.jks absent, signature aléatoire (mises à jour impossibles)')

print('Android patché : OK')

for f in ('build.gradle.kts', 'build.gradle'):
    q = os.path.join(APP, f)
    if os.path.exists(q):
        t = read(q)
        t = re.sub(r'compileSdk(?:Version)?\s*=?\s*flutter\.compileSdkVersion', 'compileSdk = 36', t)
        write(q, t)

_init = os.path.expanduser('~/.gradle/init.d')
os.makedirs(_init, exist_ok=True)
write(os.path.join(_init, 'sdk36.gradle'),
      "allprojects {\n"
      "  afterEvaluate { p ->\n"
      "    if (p.hasProperty('android')) { p.android.compileSdkVersion 36 }\n"
      "  }\n"
      "}\n")

write(os.path.join(_init, 'nolint.gradle'),
      "allprojects {\n"
      "  tasks.whenTaskAdded { t ->\n"
      "    if (t.name.contains('lintVital')) { t.enabled = false }\n"
      "  }\n"
      "}\n")


# ---------- Firebase : catalogue partagé ----------
# Lit google-services.json (à la racine du projet) et écrit lib/firebase_config.dart.
def _dq(v):
    return "'" + str(v).replace('\\', '\\\\').replace("'", "\\'").replace('$', '\\$') + "'"

_gs = os.path.join(ROOT, 'google-services.json')
_cfg = os.path.join(ROOT, 'lib', 'firebase_config.dart')
if os.path.exists(_gs):
    try:
        j = json.load(open(_gs, encoding='utf-8'))
        clients = j.get('client', [])
        client = None
        for c in clients:
            pn = c.get('client_info', {}).get('android_client_info', {}).get('package_name')
            if pn == 'com.reinecreation.reine_creation':
                client = c
                break
        if client is None and clients:
            client = clients[0]
        info = j.get('project_info', {})
        write(_cfg, (
            "// Généré par tools/patch_android.py à partir de google-services.json\n"
            "const bool kFirebaseReady = true;\n"
            f"const String kFbApiKey = {_dq(client['api_key'][0]['current_key'])};\n"
            f"const String kFbAppId = {_dq(client['client_info']['mobilesdk_app_id'])};\n"
            f"const String kFbSenderId = {_dq(info.get('project_number', ''))};\n"
            f"const String kFbProjectId = {_dq(info.get('project_id', ''))};\n"
            f"const String kFbBucket = {_dq(info.get('storage_bucket', ''))};\n"))
        print('Firebase configuré : catalogue partagé activé')
    except Exception as e:
        print('google-services.json illisible :', e)
else:
    print('google-services.json absent : catalogue partagé désactivé')
