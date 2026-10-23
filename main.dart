import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:photo_manager/photo_manager.dart';
import 'package:photo_manager_image_provider/photo_manager_image_provider.dart';
import 'package:video_player/video_player.dart';

void main() => runApp(const MaterialApp(debugShowCheckedModeBanner: false, home: Galeria()));

const _dias = ['lunes', 'martes', 'miércoles', 'jueves', 'viernes', 'sábado', 'domingo'];
const _meses = ['enero', 'febrero', 'marzo', 'abril', 'mayo', 'junio', 'julio', 'agosto', 'septiembre', 'octubre', 'noviembre', 'diciembre'];

String fecha(DateTime t) => '${_dias[t.weekday - 1]} ${t.day} de ${_meses[t.month - 1]}';
int clave(DateTime t) => t.year * 10000 + t.month * 100 + t.day;

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

class Galeria extends StatefulWidget {
  const Galeria({super.key});
  @override
  State<Galeria> createState() => _G();
}

class _G extends State<Galeria> {
  static const _ch = MethodChannel('wallpaper');
  static const tamanos = [2, 3, 4, 6, 9];
  final sc = ScrollController();
  List<AssetEntity> items = [];
  Uint8List? fondo;
  bool permiso = true;
  int cols = 4;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    _leerFondo();
    final p = await PhotoManager.requestPermissionExtend();
    if (!p.hasAccess) {
      setState(() => permiso = false);
      return;
    }
    // Cada foto nueva o borrada dispara esto: la galería se actualiza sola.
    PhotoManager.addChangeCallback((_) => _cargar());
    PhotoManager.startChangeNotify();
    _cargar();
  }

  Future<void> _leerFondo() async {
    try {
      final b = await _ch.invokeMethod<Uint8List>('get');
      if (mounted) setState(() => fondo = b);
    } catch (_) {}
  }

  Future<void> _cargar() async {
    final paths = await PhotoManager.getAssetPathList(
      onlyAll: true,
      filterOption: FilterOptionGroup(orders: [const OrderOption(type: OrderOptionType.createDate, asc: false)]),
    );
    if (paths.isEmpty) return;
    final l = await paths.first.getAssetListRange(start: 0, end: 5000);
    if (mounted) setState(() => items = l);
  }

  // Salta a la primera foto de ese día (o a la más cercana anterior).
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
        Widget btn(IconData i, int m) => IconButton(
            icon: Icon(i, color: Colors.white),
            onPressed: (m < 0 || puede(m)) ? () => mover(m) : null);
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
        fondo != null
            ? Image.memory(fondo!, fit: BoxFit.cover)
            : Container(
                decoration: const BoxDecoration(
                    gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight,
                        colors: [Color(0xFF1B2A49), Color(0xFF6A3D9A)]))),
        BackdropFilter(filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10), child: Container(color: Colors.black26)),
        SafeArea(
          child: Column(children: [
            Padding(
              padding: const EdgeInsets.all(12),
              child: cristal(Row(children: [
                Expanded(
                    child: GestureDetector(
                        onTap: () => calendario(c),
                        child: Text(fecha(DateTime.now()),
                            style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w600)))),
                IconButton(
                    icon: const Icon(Icons.calendar_month, color: Colors.white), onPressed: () => calendario(c)),
                IconButton(
                    icon: const Icon(Icons.grid_view, color: Colors.white),
                    onPressed: () => setState(() => cols = tamanos[(tamanos.indexOf(cols) + 1) % tamanos.length])),
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
                      controller: sc,
                      padding: const EdgeInsets.all(6),
                      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: cols, mainAxisSpacing: 6, crossAxisSpacing: 6),
                      itemCount: items.length,
                      itemBuilder: (_, n) {
                        final a = items[n];
                        return GestureDetector(
                          onTap: () => Navigator.push(c, MaterialPageRoute(builder: (_) => Visor(items, n))),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(14),
                            child: Stack(fit: StackFit.expand, children: [
                              Image(
                                  image: AssetEntityImageProvider(a,
                                      isOriginal: false, thumbnailSize: const ThumbnailSize.square(300)),
                                  fit: BoxFit.cover),
                              DecoratedBox(
                                  decoration: BoxDecoration(
                                      gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.center,
                                          colors: [Colors.white.withOpacity(.3), Colors.transparent]),
                                      border: Border.all(color: Colors.white.withOpacity(.35)),
                                      borderRadius: BorderRadius.circular(14))),
                              if (a.type == AssetType.video)
                                const Positioned(
                                    right: 6, bottom: 6, child: Icon(Icons.play_circle, color: Colors.white, size: 22)),
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

class Visor extends StatefulWidget {
  final List<AssetEntity> items;
  final int i;
  const Visor(this.items, this.i, {super.key});
  @override
  State<Visor> createState() => _V();
}

class _V extends State<Visor> {
  late final PageController pc = PageController(initialPage: widget.i);
  late int cur = widget.i;

  @override
  Widget build(BuildContext c) {
    final a = widget.items[cur];
    final t = a.createDateTime;
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(fit: StackFit.expand, children: [
        // La misma foto, borrosa, como fondo.
        ImageFiltered(
          imageFilter: ImageFilter.blur(sigmaX: 40, sigmaY: 40),
          child: Image(
              image: AssetEntityImageProvider(a, isOriginal: false, thumbnailSize: const ThumbnailSize.square(200)),
              fit: BoxFit.cover),
        ),
        Container(color: Colors.black26),
        PageView.builder(
          controller: pc,
          itemCount: widget.items.length,
          onPageChanged: (n) => setState(() => cur = n),
          itemBuilder: (_, n) {
            final x = widget.items[n];
            return x.type == AssetType.video
                ? VideoPag(x)
                : InteractiveViewer(
                    minScale: 0.3, // se puede hacer muy pequeña
                    maxScale: 8, // y muy grande
                    child: Center(child: Image(image: AssetEntityImageProvider(x, isOriginal: true), fit: BoxFit.contain)));
          },
        ),
        SafeArea(
          child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            IconButton(icon: const Icon(Icons.close, color: Colors.white), onPressed: () => Navigator.pop(c)),
            IconButton(
                icon: const Icon(Icons.delete_outline, color: Colors.white),
                onPressed: () async {
                  // Papelera del sistema (Android 11+): pide confirmación y se puede restaurar desde la galería del teléfono.
                  await PhotoManager.editor.android.moveToTrash([a]);
                  if (mounted) Navigator.pop(c);
                }),
          ]),
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
    );
  }
}

class VideoPag extends StatefulWidget {
  final AssetEntity a;
  const VideoPag(this.a, {super.key});
  @override
  State<VideoPag> createState() => _VP();
}

class _VP extends State<VideoPag> {
  VideoPlayerController? v;

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
    super.dispose();
  }

  @override
  Widget build(BuildContext c) {
    final p = v;
    if (p == null || !p.value.isInitialized) return const Center(child: CircularProgressIndicator());
    return GestureDetector(
      onTap: () => setState(() => p.value.isPlaying ? p.pause() : p.play()),
      child: Stack(alignment: Alignment.center, children: [
        AspectRatio(aspectRatio: p.value.aspectRatio, child: VideoPlayer(p)),
        if (!p.value.isPlaying) const Icon(Icons.play_circle_fill, color: Colors.white70, size: 72),
      ]),
    );
  }
}
