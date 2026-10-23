import 'dart:async';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:photo_manager/photo_manager.dart';
import 'package:photo_manager_image_provider/photo_manager_image_provider.dart';
import 'package:video_player/video_player.dart';

void main() => runApp(const MaterialApp(debugShowCheckedModeBanner: false, home: Albumes()));

const _dias = ['lunes', 'martes', 'miércoles', 'jueves', 'viernes', 'sábado', 'domingo'];
const _meses = ['enero', 'febrero', 'marzo', 'abril', 'mayo', 'junio', 'julio', 'agosto', 'septiembre', 'octubre', 'noviembre', 'diciembre'];

String fecha(DateTime t) => '${_dias[t.weekday - 1]} ${t.day} de ${_meses[t.month - 1]}';
int clave(DateTime t) => t.year * 10000 + t.month * 100 + t.day;
const _blanco = TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w600);

Widget cristal(Widget child) => ClipRRect(
      borderRadius: BorderRadius.circular(22),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight,
                colors: [Colors.white.withOpacity(.38), Colors.white.withOpacity(.08)]),
            border: Border.all(color: Colors.white.withOpacity(.45)),
            borderRadius: BorderRadius.circular(22),
          ),
          child: child,
        ),
      ),
    );

// Fondo de pantalla del teléfono (o degradado) con desenfoque.
Widget fondoW(Uint8List? b) => Stack(fit: StackFit.expand, children: [
      b != null
          ? Image.memory(b, fit: BoxFit.cover)
          : Container(
              decoration: const BoxDecoration(
                  gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight,
                      colors: [Color(0xFF1B2A49), Color(0xFF6A3D9A)]))),
      BackdropFilter(filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10), child: Container(color: Colors.black26)),
    ]);

Future<Uint8List?> leerFondo() async {
  try {
    return await const MethodChannel('wallpaper').invokeMethod<Uint8List>('get');
  } catch (_) {
    return null;
  }
}

ImageProvider mini(AssetEntity a, [int s = 300]) =>
    AssetEntityImageProvider(a, isOriginal: false, thumbnailSize: ThumbnailSize.square(s));

// ───────────── Pantalla de álbumes (una portada por carpeta) ─────────────
class Albumes extends StatefulWidget {
  const Albumes({super.key});
  @override
  State<Albumes> createState() => _A();
}

class _A extends State<Albumes> {
  List<AssetPathEntity> paths = [];
  final cuenta = <String, int>{};
  final portada = <String, AssetEntity?>{};
  Uint8List? fondo;
  bool permiso = true;

  @override
  void initState() {
    super.initState();
    _init();
  }

  @override
  void dispose() {
    PhotoManager.removeChangeCallback(_cb);
    super.dispose();
  }

  void _cb(MethodCall c) => _cargar();

  Future<void> _init() async {
    leerFondo().then((b) => mounted ? setState(() => fondo = b) : null);
    final p = await PhotoManager.requestPermissionExtend();
    if (!p.hasAccess) {
      setState(() => permiso = false);
      return;
    }
    PhotoManager.addChangeCallback(_cb); // fotos nuevas aparecen solas
    PhotoManager.startChangeNotify();
    _cargar();
  }

  Future<void> _cargar() async {
    final l = await PhotoManager.getAssetPathList(
      filterOption: FilterOptionGroup(orders: [const OrderOption(type: OrderOptionType.createDate, asc: false)]),
    );
    for (final x in l) {
      cuenta[x.id] = await x.assetCountAsync;
      final r = await x.getAssetListRange(start: 0, end: 1);
      portada[x.id] = r.isEmpty ? null : r.first;
    }
    l.removeWhere((x) => cuenta[x.id] == 0);
    l.sort((a, b) => a.isAll ? -1 : (b.isAll ? 1 : cuenta[b.id]!.compareTo(cuenta[a.id]!)));
    if (mounted) setState(() => paths = l);
  }

  @override
  Widget build(BuildContext c) {
    return Scaffold(
      body: Stack(fit: StackFit.expand, children: [
        fondoW(fondo),
        SafeArea(
          child: Column(children: [
            Padding(
              padding: const EdgeInsets.all(12),
              child: cristal(Row(children: [
                Expanded(child: Text(fecha(DateTime.now()), style: _blanco)),
                Text('${paths.length} álbumes', style: const TextStyle(color: Colors.white70)),
              ])),
            ),
            Expanded(
              child: !permiso
                  ? Center(
                      child: GestureDetector(
                          onTap: PhotoManager.openSetting,
                          child: cristal(const Text('Da permiso de galería (toca aquí)',
                              style: TextStyle(color: Colors.white)))))
                  : GridView.builder(
                      padding: const EdgeInsets.all(12),
                      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 3, mainAxisSpacing: 14, crossAxisSpacing: 12, childAspectRatio: .72),
                      itemCount: paths.length,
                      itemBuilder: (_, n) {
                        final x = paths[n];
                        final pa = portada[x.id];
                        return GestureDetector(
                          onTap: () => Navigator.push(c, MaterialPageRoute(builder: (_) => Album(x, fondo))),
                          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Expanded(
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(20),
                                child: Stack(fit: StackFit.expand, children: [
                                  pa != null
                                      ? Image(image: mini(pa, 400), fit: BoxFit.cover)
                                      : Container(color: Colors.white12),
                                  DecoratedBox(
                                      decoration: BoxDecoration(
                                          gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.center,
                                              colors: [Colors.white.withOpacity(.3), Colors.transparent]),
                                          border: Border.all(color: Colors.white.withOpacity(.35)),
                                          borderRadius: BorderRadius.circular(20))),
                                ]),
                              ),
                            ),
                            const SizedBox(height: 6),
                            Text(x.isAll ? 'Todo' : x.name,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w600)),
                            Text('${cuenta[x.id]}', style: const TextStyle(color: Colors.white70)),
                          ]),
                        );
                      },
                    ),
            ),
          ]),
        ),
      ]),
    );
  }
}

// ───────────── Dentro de un álbum: cuadrícula + calendario ─────────────
class Album extends StatefulWidget {
  final AssetPathEntity path;
  final Uint8List? fondo;
  const Album(this.path, this.fondo, {super.key});
  @override
  State<Album> createState() => _Al();
}

class _Al extends State<Album> {
  static const tamanos = [2, 3, 4, 6, 9];
  final sc = ScrollController();
  List<AssetEntity> todos = [];
  List<AssetEntity> items = [];
  int filtro = 0;
  int cols = 4;
  final sel = <String>{};

  Future<void> borrarSel() async {
    await PhotoManager.editor.android.moveToTrash(items.where((x) => sel.contains(x.id)).toList());
    if (mounted) setState(sel.clear);
  }

  @override
  void initState() {
    super.initState();
    PhotoManager.addChangeCallback(_cb);
    _cargar();
  }

  @override
  void dispose() {
    PhotoManager.removeChangeCallback(_cb);
    sc.dispose();
    super.dispose();
  }

  void _cb(MethodCall c) => _cargar();

  Future<void> _cargar() async {
    final l = await widget.path.getAssetListRange(start: 0, end: 5000);
    todos = l;
    if (mounted) setState(aplicar);
  }

  void aplicar() => items = todos
      .where((x) => filtro == 0 || (filtro == 1 && x.type == AssetType.image) || (filtro == 2 && x.type == AssetType.video))
      .toList();

  void irA(DateTime dia, double ancho) {
    final fin = DateTime(dia.year, dia.month, dia.day, 23, 59, 59);
    final idx = items.indexWhere((a) => !a.createDateTime.isAfter(fin));
    if (idx < 0 || !sc.hasClients) return;
    final celda = (ancho - 12 - 6 * (cols - 1)) / cols;
    final off = ((idx ~/ cols) * (celda + 6)).clamp(0.0, sc.position.maxScrollExtent).toDouble();
    sc.animateTo(off, duration: const Duration(milliseconds: 450), curve: Curves.easeOut);
  }

  void calendario(BuildContext c) {
    final dias = items.map((a) => clave(a.createDateTime)).toSet();
    final hoy = DateTime.now();
    var mes = DateTime(hoy.year, hoy.month);
    showModalBottomSheet(
      context: c,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => StatefulBuilder(builder: (ctx, set) {
        final n = DateTime(mes.year, mes.month + 1, 0).day;
        final desfase = mes.weekday - 1;
        bool puede(int m) => DateTime(mes.year, mes.month + m).isBefore(DateTime(hoy.year, hoy.month + 1));
        void mover(int m) => set(() => mes = DateTime(mes.year, mes.month + m));
        Widget btn(IconData i, int m) =>
            IconButton(icon: Icon(i, color: Colors.white), onPressed: (m < 0 || puede(m)) ? () => mover(m) : null);
        return Padding(
          padding: const EdgeInsets.all(12),
          child: cristal(Column(mainAxisSize: MainAxisSize.min, children: [
            Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
              btn(Icons.keyboard_double_arrow_left, -12),
              btn(Icons.chevron_left, -1),
              Text('${_meses[mes.month - 1]} ${mes.year}',
                  style: const TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.w600)),
              btn(Icons.chevron_right, 1),
              btn(Icons.keyboard_double_arrow_right, 12),
            ]),
            GridView.count(
              crossAxisCount: 7,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              children: [
                for (final l in ['L', 'M', 'X', 'J', 'V', 'S', 'D'])
                  Center(child: Text(l, style: const TextStyle(color: Colors.white70))),
                for (var i = 0; i < desfase; i++) const SizedBox(),
                for (var d = 1; d <= n; d++)
                  Builder(builder: (_) {
                    final f = DateTime(mes.year, mes.month, d);
                    final hay = dias.contains(clave(f));
                    final futuro = f.isAfter(hoy);
                    return GestureDetector(
                      onTap: futuro
                          ? null
                          : () {
                              Navigator.pop(ctx);
                              irA(f, MediaQuery.of(c).size.width);
                            },
                      child: Container(
                        margin: const EdgeInsets.all(3),
                        decoration: BoxDecoration(shape: BoxShape.circle, color: hay ? Colors.white.withOpacity(.35) : null),
                        child: Center(
                            child: Text('$d',
                                style: TextStyle(
                                    color: futuro ? Colors.white24 : Colors.white,
                                    fontWeight: hay ? FontWeight.bold : FontWeight.normal))),
                      ),
                    );
                  }),
              ],
            ),
          ])),
        );
      }),
    );
  }

  @override
  Widget build(BuildContext c) {
    return Scaffold(
      body: Stack(fit: StackFit.expand, children: [
        fondoW(widget.fondo),
        SafeArea(
          child: Column(children: [
            Padding(
              padding: const EdgeInsets.all(12),
              child: sel.isNotEmpty
                  ? cristal(Row(children: [
                      IconButton(icon: const Icon(Icons.close, color: Colors.white), onPressed: () => setState(sel.clear)),
                      Expanded(child: Text('${sel.length} seleccionadas', style: _blanco)),
                      IconButton(icon: const Icon(Icons.delete_outline, color: Colors.white), onPressed: borrarSel),
                    ]))
                  : cristal(Row(children: [
                GestureDetector(onTap: () => Navigator.pop(c), child: const Icon(Icons.arrow_back, color: Colors.white)),
                const SizedBox(width: 10),
                Expanded(
                  child: GestureDetector(
                    onTap: () => calendario(c),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(widget.path.isAll ? 'Todo' : widget.path.name, style: _blanco, maxLines: 1, overflow: TextOverflow.ellipsis),
                      Text(fecha(DateTime.now()), style: const TextStyle(color: Colors.white70, fontSize: 12)),
                    ]),
                  ),
                ),
                IconButton(icon: const Icon(Icons.calendar_month, color: Colors.white), onPressed: () => calendario(c)),
                IconButton(
                    icon: const Icon(Icons.grid_view, color: Colors.white),
                    onPressed: () => setState(() => cols = tamanos[(tamanos.indexOf(cols) + 1) % tamanos.length])),
              ])),
            ),
            Row(children: [
              const SizedBox(width: 12),
              for (final e in ['Todo', 'Fotos', 'Vídeos'].asMap().entries)
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ChoiceChip(
                    label: Text(e.value),
                    selected: filtro == e.key,
                    onSelected: (_) => setState(() {
                      filtro = e.key;
                      aplicar();
                    }),
                  ),
                ),
            ]),
            Expanded(
              child: GridView.builder(
                controller: sc,
                padding: const EdgeInsets.all(6),
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: cols, mainAxisSpacing: 6, crossAxisSpacing: 6),
                itemCount: items.length,
                itemBuilder: (_, n) {
                  final a = items[n];
                  return GestureDetector(
                    onTap: () {
                      if (sel.isNotEmpty) {
                        setState(() {
                          if (!sel.remove(a.id)) sel.add(a.id);
                        });
                      } else {
                        Navigator.push(c, MaterialPageRoute(builder: (_) => Visor(items, n)));
                      }
                    },
                    onLongPress: () => setState(() => sel.add(a.id)),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(14),
                      child: Stack(fit: StackFit.expand, children: [
                        Image(image: mini(a), fit: BoxFit.cover),
                        DecoratedBox(
                            decoration: BoxDecoration(
                                gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.center,
                                    colors: [Colors.white.withOpacity(.3), Colors.transparent]),
                                border: Border.all(color: Colors.white.withOpacity(.35)),
                                borderRadius: BorderRadius.circular(14))),
                        if (sel.contains(a.id))
                          Container(
                              color: Colors.blue.withOpacity(.45),
                              child: const Icon(Icons.check_circle, color: Colors.white, size: 30)),
                        if (a.type == AssetType.video)
                          const Positioned(right: 6, bottom: 6, child: Icon(Icons.play_circle, color: Colors.white, size: 22)),
                      ]),
                    ),
                  );
                },
              ),
            ),
          ]),
        ),
      ]),
    );
  }
}

// ───────────── Visor de foto/vídeo ─────────────
class Visor extends StatefulWidget {
  final List<AssetEntity> items;
  final int i;
  const Visor(this.items, this.i, {super.key});
  @override
  State<Visor> createState() => _V();
}

class _V extends State<Visor> {
  late final PageController pc = PageController(initialPage: widget.i);
  final bloqueo = ValueNotifier<bool>(false); // true = toques bloqueados en vídeo
  late int cur = widget.i;
  Timer? tm;

  @override
  void dispose() {
    tm?.cancel();
    bloqueo.dispose();
    super.dispose();
  }

  // Presentación automática: pasa de foto cada 3 s (espera en los vídeos).
  void toggleShow() {
    if (tm != null) {
      tm!.cancel();
      setState(() => tm = null);
      return;
    }
    setState(() => tm = Timer.periodic(const Duration(seconds: 3), (_) {
          if (cur >= widget.items.length - 1) return toggleShow();
          if (widget.items[cur].type == AssetType.video) return;
          pc.nextPage(duration: const Duration(milliseconds: 400), curve: Curves.easeInOut);
        }));
  }

  // Favoritos del sistema (Android 11+). Se llama de forma dinámica para no romper la compilación.
  bool esFav(AssetEntity a) {
    try {
      return (a as dynamic).isFavorite == true;
    } catch (_) {
      return false;
    }
  }

  Future<void> favorito(AssetEntity a) async {
    try {
      await (PhotoManager.editor.android as dynamic).favoriteAsset(entity: a, favorite: !esFav(a));
      final n = await (a as dynamic).obtainForNewProperties();
      if (n != null) widget.items[cur] = n as AssetEntity;
      if (mounted) setState(() {});
    } catch (_) {}
  }

  @override
  Widget build(BuildContext c) {
    final a = widget.items[cur];
    final t = a.createDateTime;
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(fit: StackFit.expand, children: [
        ImageFiltered(
          imageFilter: ImageFilter.blur(sigmaX: 40, sigmaY: 40),
          child: Image(image: mini(a, 200), fit: BoxFit.cover),
        ),
        Container(color: Colors.black26),
        ValueListenableBuilder<bool>(
          valueListenable: bloqueo,
          builder: (_, b, __) => PageView.builder(
            controller: pc,
            physics: b ? const NeverScrollableScrollPhysics() : null,
            itemCount: widget.items.length,
            onPageChanged: (n) => setState(() => cur = n),
            itemBuilder: (_, n) {
              final x = widget.items[n];
              return x.type == AssetType.video
                  ? VideoPag(x, bloqueo)
                  : InteractiveViewer(
                      minScale: 0.3,
                      maxScale: 8,
                      child: Center(child: Image(image: AssetEntityImageProvider(x, isOriginal: true), fit: BoxFit.contain)));
            },
          ),
        ),
        ValueListenableBuilder<bool>(
          valueListenable: bloqueo,
          builder: (_, b, __) => b
              ? const SizedBox.shrink()
              : Stack(fit: StackFit.expand, children: [
                  SafeArea(
                    child: Align(
                      alignment: Alignment.topCenter,
                      child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                        IconButton(icon: const Icon(Icons.close, color: Colors.white), onPressed: () => Navigator.pop(c)),
                        Row(mainAxisSize: MainAxisSize.min, children: [
                          IconButton(
                              icon: Icon(esFav(a) ? Icons.favorite : Icons.favorite_border, color: Colors.white),
                              onPressed: () => favorito(a)),
                          IconButton(
                              icon: Icon(tm == null ? Icons.slideshow : Icons.stop_circle_outlined, color: Colors.white),
                              onPressed: toggleShow),
                          IconButton(icon: const Icon(Icons.share, color: Colors.white), onPressed: () => compartir(a)),
                          IconButton(icon: const Icon(Icons.info_outline, color: Colors.white), onPressed: () => detalles(c, a)),
                          IconButton(
                              icon: const Icon(Icons.delete_outline, color: Colors.white),
                              onPressed: () async {
                                await PhotoManager.editor.android.moveToTrash([a]);
                                if (mounted) Navigator.pop(c);
                              }),
                        ]),
                      ]),
                    ),
                  ),
                  SafeArea(
                    child: Align(
                      alignment: Alignment.bottomCenter,
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: cristal(Text(
                            '${fecha(t)} ${t.year} · ${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}',
                            style: const TextStyle(color: Colors.white))),
                      ),
                    ),
                  ),
                ]),
        ),
      ]),
    );
  }
}

// ───────────── Reproductor: progreso, ±10 s, velocidad, volumen y bloqueo ─────────────
class VideoPag extends StatefulWidget {
  final AssetEntity a;
  final ValueNotifier<bool> bloqueo;
  const VideoPag(this.a, this.bloqueo, {super.key});
  @override
  State<VideoPag> createState() => _VP();
}

class _VP extends State<VideoPag> {
  static const vels = [0.5, 1.0, 1.5, 2.0];
  VideoPlayerController? v;
  double vol = 1, tx = 0;
  int vel = 1;
  bool loop = false, horiz = false;

  @override
  void initState() {
    super.initState();
    widget.a.file.then((f) {
      if (f == null) return;
      v = VideoPlayerController.file(f)..initialize().then((_) => mounted ? setState(() {}) : null);
    });
  }

  @override
  void dispose() {
    v?.dispose();
    SystemChrome.setPreferredOrientations(DeviceOrientation.values);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    super.dispose();
  }

  void saltar(int s) {
    final p = v!;
    final n = p.value.position + Duration(seconds: s);
    final max = p.value.duration;
    p.seekTo(n < Duration.zero ? Duration.zero : (n > max ? max : n));
  }

  String hms(Duration d) => '${d.inMinutes}:${(d.inSeconds % 60).toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext c) {
    final p = v;
    if (p == null || !p.value.isInitialized) return const Center(child: CircularProgressIndicator());
    const b70 = TextStyle(color: Colors.white70, fontSize: 12);
    return ValueListenableBuilder<bool>(
      valueListenable: widget.bloqueo,
      builder: (_, bloq, __) => Stack(alignment: Alignment.center, children: [
        GestureDetector(
          onTap: bloq ? null : () => setState(() => p.value.isPlaying ? p.pause() : p.play()),
          onDoubleTapDown: bloq ? null : (d) => tx = d.globalPosition.dx,
          // Doble toque a la izquierda: -10 s. A la derecha: +10 s.
          onDoubleTap: bloq ? null : () => saltar(tx < MediaQuery.of(c).size.width / 2 ? -10 : 10),
          child: AspectRatio(aspectRatio: p.value.aspectRatio, child: VideoPlayer(p)),
        ),
        if (!p.value.isPlaying && !bloq) const IgnorePointer(child: Icon(Icons.play_circle_fill, color: Colors.white70, size: 72)),
        if (bloq)
          Align(
            alignment: Alignment.centerRight,
            child: GestureDetector(
              onLongPress: () => widget.bloqueo.value = false,
              child: Container(
                margin: const EdgeInsets.only(right: 12),
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(color: Colors.black45, borderRadius: BorderRadius.circular(16)),
                child: const Column(mainAxisSize: MainAxisSize.min, children: [
                  Icon(Icons.lock, color: Colors.white, size: 30),
                  SizedBox(height: 4),
                  Text('Mantén\npulsado', textAlign: TextAlign.center, style: TextStyle(color: Colors.white70, fontSize: 11)),
                ]),
              ),
            ),
          )
        else
          Align(
            alignment: Alignment.bottomCenter,
            child: Padding(
              padding: const EdgeInsets.only(left: 12, right: 12, bottom: 84),
              child: cristal(ValueListenableBuilder<VideoPlayerValue>(
                valueListenable: p,
                builder: (_, val, __) => Column(mainAxisSize: MainAxisSize.min, children: [
                  Row(children: [
                    Text(hms(val.position), style: b70),
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        child: VideoProgressIndicator(p,
                            allowScrubbing: true,
                            padding: const EdgeInsets.symmetric(vertical: 10),
                            colors: const VideoProgressColors(
                                playedColor: Colors.white, bufferedColor: Colors.white38, backgroundColor: Colors.white24)),
                      ),
                    ),
                    Text(hms(val.duration), style: b70),
                  ]),
                  Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                    IconButton(icon: const Icon(Icons.replay_10, color: Colors.white), onPressed: () => saltar(-10)),
                    IconButton(
                        iconSize: 34,
                        icon: Icon(val.isPlaying ? Icons.pause : Icons.play_arrow, color: Colors.white),
                        onPressed: () => val.isPlaying ? p.pause() : p.play()),
                    IconButton(icon: const Icon(Icons.forward_10, color: Colors.white), onPressed: () => saltar(10)),
                    TextButton(
                        onPressed: () {
                          vel = (vel + 1) % vels.length;
                          p.setPlaybackSpeed(vels[vel]);
                          setState(() {});
                        },
                        child: Text('${vels[vel]}x', style: const TextStyle(color: Colors.white))),
                    IconButton(icon: const Icon(Icons.lock_open, color: Colors.white), onPressed: () => widget.bloqueo.value = true),
                  ]),
                  Row(children: [
                    Icon(vol == 0 ? Icons.volume_off : (vol < .5 ? Icons.volume_down : Icons.volume_up), color: Colors.white),
                    Expanded(
                      child: Slider(
                        value: vol,
                        activeColor: Colors.white,
                        inactiveColor: Colors.white30,
                        onChanged: (x) {
                          setState(() => vol = x);
                          p.setVolume(x);
                        },
                      ),
                    ),
                    IconButton(
                        icon: Icon(Icons.repeat, color: loop ? Colors.white : Colors.white38),
                        onPressed: () {
                          loop = !loop;
                          p.setLooping(loop);
                          setState(() {});
                        }),
                    IconButton(
                        icon: const Icon(Icons.screen_rotation, color: Colors.white),
                        onPressed: () {
                          horiz = !horiz;
                          SystemChrome.setPreferredOrientations(
                              horiz ? [DeviceOrientation.landscapeLeft, DeviceOrientation.landscapeRight] : DeviceOrientation.values);
                          SystemChrome.setEnabledSystemUIMode(horiz ? SystemUiMode.immersiveSticky : SystemUiMode.edgeToEdge);
                          setState(() {});
                        }),
                  ]),
                ]),
              )),
            ),
          ),
      ]),
    );
  }
}

// ───────────── Herramientas: compartir y detalles ─────────────
Future<void> compartir(AssetEntity a) async {
  try {
    await const MethodChannel('wallpaper')
        .invokeMethod('share', {'id': a.id, 'video': a.type == AssetType.video});
  } catch (_) {}
}

Future<void> detalles(BuildContext c, AssetEntity a) async {
  final nombre = '${await a.titleAsync}';
  final f = await a.originFile;
  final bytes = f == null ? 0 : await f.length();
  var ubic = '';
  try {
    final ll = await a.latlngAsync();
    final la = ll?.latitude;
    final lo = ll?.longitude;
    if (la != null && lo != null && la != 0) ubic = '$la, $lo';
  } catch (_) {}
  final t = a.createDateTime;
  final filas = <String>[
    nombre,
    '${fecha(t)} ${t.year} · ${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}',
    '${a.width} × ${a.height}',
    '${(bytes / 1048576).toStringAsFixed(1)} MB',
    if (a.type == AssetType.video) 'Duración: ${a.videoDuration.inSeconds} s',
    if (a.relativePath != null) 'Carpeta: ${a.relativePath}',
    if (ubic.isNotEmpty) 'Ubicación: $ubic',
  ];
  if (!c.mounted) return;
  showModalBottomSheet(
    context: c,
    backgroundColor: Colors.transparent,
    builder: (_) => Padding(
      padding: const EdgeInsets.all(12),
      child: cristal(Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        for (final s in filas)
          Padding(padding: const EdgeInsets.symmetric(vertical: 3), child: Text(s, style: const TextStyle(color: Colors.white))),
      ])),
    ),
  );
}
