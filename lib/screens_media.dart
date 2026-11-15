import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

import 'i18n.dart';
import 'ui.dart';

/// Affiche une photo en plein écran (zoom avec deux doigts).
void showPhoto(BuildContext c, String name) {
  final f = imageFile(name);
  if (f == null) return;
  Navigator.push(
    c,
    MaterialPageRoute(
      builder: (_) => Scaffold(
        backgroundColor: Colors.black,
        appBar: AppBar(backgroundColor: Colors.black),
        body: Center(child: InteractiveViewer(child: Image.file(f))),
      ),
    ),
  );
}

/// Lecteur vidéo (fichier enregistré dans le dossier des photos de l'appli).
class VideoPage extends StatefulWidget {
  final String name;
  const VideoPage(this.name, {super.key});
  @override
  State<VideoPage> createState() => _VideoPageState();
}

class _VideoPageState extends State<VideoPage> {
  VideoPlayerController? ctl;
  bool failed = false;

  @override
  void initState() {
    super.initState();
    final f = imageFile(widget.name);
    if (f == null) {
      failed = true;
      return;
    }
    final c = VideoPlayerController.file(f);
    ctl = c;
    c.addListener(() {
      if (mounted) setState(() {});
    });
    c.initialize().then((_) {
      if (mounted) {
        setState(() {});
        c.play();
      }
    }).catchError((_) {
      if (mounted) setState(() => failed = true);
    });
  }

  @override
  void dispose() {
    ctl?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = ctl;
    final ready = c != null && c.value.isInitialized;
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(title: Text(tr('Vidéo'))),
      body: Center(
        child: failed
            ? Text(tr('Vidéo introuvable'), style: const TextStyle(color: Colors.white))
            : ready
                ? AspectRatio(aspectRatio: c!.value.aspectRatio, child: VideoPlayer(c))
                : const CircularProgressIndicator(),
      ),
      floatingActionButton: ready
          ? FloatingActionButton(
              onPressed: () => c!.value.isPlaying ? c.pause() : c.play(),
              child: Icon(c!.value.isPlaying ? Icons.pause : Icons.play_arrow),
            )
          : null,
    );
  }
}
