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

// =====================================================================
// Photos et vidéo : vignettes et défilement
// =====================================================================

/// Un élément du catalogue : une photo ou la vidéo.
class MediaItem {
  final String name;
  final bool video;
  const MediaItem(this.name, this.video);
}

/// Vignette d'une vidéo (première image, sans avoir à cliquer), comme une photo.
class VideoThumb extends StatefulWidget {
  final String name;
  final bool playIcon;
  const VideoThumb(this.name, {super.key, this.playIcon = true});
  @override
  State<VideoThumb> createState() => _VideoThumbState();
}

class _VideoThumbState extends State<VideoThumb> {
  VideoPlayerController? c;
  bool ready = false;

  @override
  void initState() {
    super.initState();
    final f = imageFile(widget.name);
    if (f == null) return;
    final ctl = VideoPlayerController.file(f, videoPlayerOptions: VideoPlayerOptions(mixWithOthers: true));
    c = ctl;
    ctl.initialize().then((_) async {
      await ctl.setVolume(0);
      await ctl.seekTo(const Duration(milliseconds: 300));
      if (mounted) setState(() => ready = true);
    }).catchError((_) {});
  }

  @override
  void dispose() {
    c?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ctl = c;
    return Stack(fit: StackFit.expand, children: [
      Container(color: Colors.black87),
      if (ready && ctl != null && ctl.value.size.width > 0)
        FittedBox(
          fit: BoxFit.cover,
          clipBehavior: Clip.hardEdge,
          child: SizedBox(
            width: ctl.value.size.width,
            height: ctl.value.size.height,
            child: VideoPlayer(ctl),
          ),
        ),
      if (widget.playIcon)
        const Center(child: Icon(Icons.play_circle_fill, color: Colors.white70, size: 38)),
    ]);
  }
}

/// Défilement (balayage gauche/droite) des photos puis de la vidéo.
class MediaPager extends StatefulWidget {
  final List<MediaItem> items;
  final int initial;
  final bool fullscreen;
  final ValueChanged<int>? onIndex;
  const MediaPager(this.items, {super.key, this.initial = 0, this.fullscreen = false, this.onIndex});
  @override
  State<MediaPager> createState() => _MediaPagerState();
}

class _MediaPagerState extends State<MediaPager> {
  late final PageController pc = PageController(initialPage: widget.initial);
  late int index = widget.initial;

  @override
  void dispose() {
    pc.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final items = widget.items;
    return Stack(children: [
      PageView.builder(
        controller: pc,
        itemCount: items.length,
        onPageChanged: (i) {
          setState(() => index = i);
          widget.onIndex?.call(i);
        },
        itemBuilder: (c, i) {
          final it = items[i];
          if (it.video) {
            return _VideoSlide(it.name, active: index == i, autoplay: widget.fullscreen);
          }
          final f = imageFile(it.name);
          return GestureDetector(
            onTap: widget.fullscreen
                ? null
                : () => Navigator.push(
                    c, MaterialPageRoute(builder: (_) => MediaGalleryPage(items, initial: i))),
            child: Container(
              color: widget.fullscreen ? Colors.black : Colors.black12,
              alignment: Alignment.center,
              child: f == null
                  ? const Icon(Icons.broken_image, color: Colors.white54, size: 48)
                  : Image.file(f, fit: BoxFit.contain, width: double.infinity, height: double.infinity),
            ),
          );
        },
      ),
      if (items.length > 1)
        Positioned(
          left: 0,
          right: 0,
          bottom: 8,
          child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            for (var i = 0; i < items.length; i++)
              Container(
                margin: const EdgeInsets.symmetric(horizontal: 3),
                width: i == index ? 10 : 7,
                height: i == index ? 10 : 7,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: i == index ? kGold : Colors.white70,
                  border: Border.all(color: Colors.black26),
                ),
              ),
          ]),
        ),
    ]);
  }
}

class _VideoSlide extends StatefulWidget {
  final String name;
  final bool active;
  final bool autoplay;
  const _VideoSlide(this.name, {required this.active, required this.autoplay});
  @override
  State<_VideoSlide> createState() => _VideoSlideState();
}

class _VideoSlideState extends State<_VideoSlide> {
  VideoPlayerController? c;
  bool failed = false;

  @override
  void initState() {
    super.initState();
    final f = imageFile(widget.name);
    if (f == null) {
      failed = true;
      return;
    }
    final ctl = VideoPlayerController.file(f);
    c = ctl;
    ctl.addListener(() {
      if (mounted) setState(() {});
    });
    ctl.initialize().then((_) {
      if (!mounted) return;
      setState(() {});
      if (widget.autoplay && widget.active) ctl.play();
    }).catchError((_) {
      if (mounted) setState(() => failed = true);
    });
  }

  @override
  void didUpdateWidget(covariant _VideoSlide old) {
    super.didUpdateWidget(old);
    final ctl = c;
    if (ctl != null && ctl.value.isInitialized && old.active != widget.active && !widget.active) {
      ctl.pause();
    }
  }

  @override
  void dispose() {
    c?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ctl = c;
    final ready = ctl != null && ctl.value.isInitialized;
    return Container(
      color: Colors.black,
      alignment: Alignment.center,
      child: failed
          ? Text(tr('Vidéo introuvable'), style: const TextStyle(color: Colors.white))
          : !ready
              ? const CircularProgressIndicator()
              : GestureDetector(
                  onTap: () => ctl.value.isPlaying ? ctl.pause() : ctl.play(),
                  child: AspectRatio(
                    aspectRatio: ctl.value.aspectRatio,
                    child: Stack(alignment: Alignment.center, children: [
                      VideoPlayer(ctl),
                      if (!ctl.value.isPlaying)
                        const Icon(Icons.play_circle_fill, color: Colors.white70, size: 64),
                      Positioned(
                        left: 0,
                        right: 0,
                        bottom: 0,
                        child: VideoProgressIndicator(ctl, allowScrubbing: true),
                      ),
                    ]),
                  ),
                ),
    );
  }
}

/// Galerie plein écran : on balaie pour voir toutes les photos et la vidéo.
class MediaGalleryPage extends StatefulWidget {
  final List<MediaItem> items;
  final int initial;
  const MediaGalleryPage(this.items, {super.key, this.initial = 0});
  @override
  State<MediaGalleryPage> createState() => _MediaGalleryPageState();
}

class _MediaGalleryPageState extends State<MediaGalleryPage> {
  late int index = widget.initial;

  @override
  Widget build(BuildContext context) {
    final it = widget.items[index];
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        title: Text('${index + 1} / ${widget.items.length}'),
        actions: [
          if (!it.video)
            IconButton(
              tooltip: tr('Zoom'),
              icon: const Icon(Icons.zoom_in),
              onPressed: () => showPhoto(context, it.name),
            ),
        ],
      ),
      body: MediaPager(widget.items, initial: widget.initial, fullscreen: true, onIndex: (i) => setState(() => index = i)),
    );
  }
}
