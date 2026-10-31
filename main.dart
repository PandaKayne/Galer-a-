import 'dart:async';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:photo_manager/photo_manager.dart';
import 'package:photo_manager_image_provider/photo_manager_image_provider.dart';
import 'package:video_player/video_player.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  PaintingBinding.instance.imageCache.maximumSize = 600;
  PaintingBinding.instance.imageCache.maximumSizeBytes = 150 << 20;
  runApp(const MaterialApp(debugShowCheckedModeBanner: false, home: Albumes()));
}

const _dias = ['lunes', 'martes', 'miércoles', 'jueves', 'viernes', 'sábado', 'domingo'];
const _meses = ['enero', 'febrero', 'marzo', 'abril', 'mayo', 'junio', 'julio', 'agosto', 'septiembre', 'octubre', 'noviembre', 'diciembre'];

String fecha(DateTime t) => '${_dias[t.weekday - 1]} ${t.day} de ${_meses[t.month - 1]}';
int clave(DateTime t) => t.year * 10000 + t.month * 100 + t.day;
const _blanco = TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w600);
int visores = 0; // visores de foto abiertos: mientras haya uno, no se recarga la galería

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

class _A extends State<Albumes> with WidgetsBindingObserver {
  List<AssetPathEntity> paths = [];
  final cuenta = <String, int>{};
  final portada = <String, AssetEntity?>{};
  Uint8List? fondo;
  bool permiso = true;
  bool pedir = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _init();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _deb?.cancel();
    PhotoManager.removeChangeCallback(_cb);
    super.dispose();
  }

  Timer? _deb;
  void _cb(MethodCall c) {
    if (visores > 0) return; // con una foto abierta no se recarga nada
    _deb?.cancel();
    _deb = Timer(const Duration(milliseconds: 700), _cargar);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState s) {
    if (s == AppLifecycleState.resumed) _fondo();
  }

  Future<void> _fondo() async {
    final b = await leerFondo();
    var n = false;
    try {
      n = await const MethodChannel('wallpaper').invokeMethod<bool>('necesita') ?? false;
    } catch (_) {}
    if (mounted) {
      setState(() {
        fondo = b;
        pedir = n;
      });
    }
  }

  final _pidiendo = <String>{};

  // Pide la cantidad y la portada de un álbum solo cuando su casilla aparece en pantalla.
  Future<void> _dato(AssetPathEntity x) async {
    if (cuenta.containsKey(x.id) || !_pidiendo.add(x.id)) return;
    try {
      final n = await x.assetCountAsync;
      final r = n == 0 ? <AssetEntity>[] : await x.getAssetListRange(start: 0, end: 1);
      cuenta[x.id] = n;
      portada[x.id] = r.isEmpty ? null : r.first;
    } catch (_) {}
    _pidiendo.remove(x.id);
    if (mounted) setState(() {});
  }

  Future<void> _init() async {
    _fondo();
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
    cuenta.clear();
    portada.clear();
    if (mounted) setState(() => paths = [...l.where((x) => x.isAll), ...l.where((x) => !x.isAll)]);
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
                IconButton(
                    icon: const Icon(Icons.delete_outline, color: Colors.white),
                    onPressed: () => Navigator.push(c, MaterialPageRoute(builder: (_) => Papelera(fondo)))),
              ])),
            ),
            if (pedir)
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
                child: GestureDetector(
                  onTap: () => const MethodChannel('wallpaper').invokeMethod('pedir'),
                  child: cristal(const Text('Toca aquí para activar el fondo de pantalla (Android 13 o superior)',
                      style: TextStyle(color: Colors.white))),
                ),
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
                        _dato(x);
                        return GestureDetector(
                          onTap: () => Navigator.push(c, MaterialPageRoute(builder: (_) => Album(x, fondo))).then((_) => _cargar()),
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
                            Text('${cuenta[x.id] ?? ''}', style: const TextStyle(color: Colors.white70)),
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
  bool nuevasPrimero = true;
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
    sc.addListener(() {
      if (sc.hasClients && sc.position.pixels > sc.position.maxScrollExtent - 2500) _mas();
    });
    _cargar();
  }

  @override
  void dispose() {
    _deb?.cancel();
    PhotoManager.removeChangeCallback(_cb);
    sc.dispose();
    super.dispose();
  }

  Timer? _deb;
  void _cb(MethodCall c) {
    if (visores > 0) return; // con una foto abierta no se recarga nada
    _deb?.cancel();
    _deb = Timer(const Duration(milliseconds: 700), () => _cargar(mantener: true));
  }

  // ── Carga por páginas: así una carpeta de miles de fotos abre al instante ──
  static const pag = 240;
  int total = 0, cargados = 0, gen = 0;
  bool nativoDesc = true, dirOk = false, cargando = false, recargando = false;

  // Pide `n` elementos a partir de la posición `p0` en el orden elegido (nuevas o viejas primero).
  Future<List<AssetEntity>> trozo(int p0, int n) async {
    if (n <= 0) return [];
    final mismo = nuevasPrimero == nativoDesc;
    final ini = mismo ? p0 : total - p0 - n;
    final l = await widget.path.getAssetListRange(start: ini, end: ini + n);
    return mismo ? l : l.reversed.toList();
  }

  Future<void> _cargar({bool mantener = false}) async {
    final g = ++gen;
    recargando = true;
    try {
      final pedir = mantener && cargados > pag ? (cargados > 1500 ? 1500 : cargados) : pag;
      total = await widget.path.assetCountAsync;
      if (!dirOk && total > 1) {
        // Detecta en qué sentido devuelve Android las fotos, para pedir primero las que corresponden.
        final a = await widget.path.getAssetListRange(start: 0, end: 1);
        final b = await widget.path.getAssetListRange(start: total - 1, end: total);
        if (a.isNotEmpty && b.isNotEmpty) {
          nativoDesc = !a.first.createDateTime.isBefore(b.first.createDateTime);
          dirOk = true;
        }
      }
      final l = await trozo(0, pedir > total ? total : pedir);
      if (g != gen || !mounted) return;
      todos = l;
      cargados = l.length;
      cargando = false;
      setState(aplicar);
    } finally {
      if (g == gen) recargando = false;
    }
    if (g == gen) _llenar();
  }

  Future<void> _mas() async {
    if (cargando || recargando || cargados >= total) return;
    cargando = true;
    final g = gen;
    final n = (total - cargados) < pag ? (total - cargados) : pag;
    final l = await trozo(cargados, n);
    cargando = false;
    if (g != gen || !mounted) return;
    cargados += l.isEmpty ? total : l.length;
    todos = [...todos, ...l];
    setState(aplicar);
  }

  // Si el filtro deja pocas fotos en pantalla, sigue cargando hasta llenar.
  Future<void> _llenar() async {
    while (mounted && cargados < total && items.length < 60) {
      if (cargando || recargando) {
        await Future.delayed(const Duration(milliseconds: 80));
        continue;
      }
      final antes = cargados;
      await _mas();
      if (cargados == antes) break;
    }
  }

  void aplicar() {
    final f = todos
        .where((x) => filtro == 0 || (filtro == 1 && x.type == AssetType.image) || (filtro == 2 && x.type == AssetType.video))
        .toList();
    items = f;
  }

  Future<void> irA(DateTime dia, double ancho) async {
    final fin = DateTime(dia.year, dia.month, dia.day, 23, 59, 59);
    final inicio = DateTime(dia.year, dia.month, dia.day);
    int buscar() => nuevasPrimero
        ? items.indexWhere((a) => !a.createDateTime.isAfter(fin))
        : items.indexWhere((a) => !a.createDateTime.isBefore(inicio));
    var idx = buscar();
    // Si ese día aún no está cargado, sigue cargando hasta llegar a él.
    while (idx < 0 && mounted && cargados < total) {
      if (cargando || recargando) {
        await Future.delayed(const Duration(milliseconds: 80));
        continue;
      }
      final antes = cargados;
      await _mas();
      if (cargados == antes) break;
      idx = buscar();
    }
    await WidgetsBinding.instance.endOfFrame;
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
                      Text('${fecha(DateTime.now())} · ${nuevasPrimero ? 'nuevas primero' : 'viejas primero'}',
                          style: const TextStyle(color: Colors.white70, fontSize: 12)),
                    ]),
                  ),
                ),
                IconButton(icon: const Icon(Icons.calendar_month, color: Colors.white), onPressed: () => calendario(c)),
                IconButton(
                    icon: const Icon(Icons.swap_vert, color: Colors.white),
                    onPressed: () {
                      setState(() => nuevasPrimero = !nuevasPrimero);
                      _cargar();
                    }),
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
                    onSelected: (_) {
                      setState(() {
                        filtro = e.key;
                        aplicar();
                      });
                      _llenar();
                    },
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
                        Navigator.push(c, MaterialPageRoute(builder: (_) => Visor(items, n))).then((_) => _cargar(mantener: true));
                      }
                    },
                    onLongPress: () => setState(() => sel.add(a.id)),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(14),
                      child: Stack(fit: StackFit.expand, children: [
                        Image(image: mini(a, cols >= 6 ? 160 : 300), fit: BoxFit.cover),
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
        Positioned(
          right: 12,
          bottom: 24,
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            FloatingActionButton.small(
              heroTag: null,
              backgroundColor: Colors.white30,
              elevation: 0,
              onPressed: () {
                if (sc.hasClients) sc.animateTo(0, duration: const Duration(milliseconds: 500), curve: Curves.easeOut);
              },
              child: const Icon(Icons.keyboard_double_arrow_up, color: Colors.white),
            ),
            const SizedBox(height: 8),
            FloatingActionButton.small(
              heroTag: null,
              backgroundColor: Colors.white30,
              elevation: 0,
              onPressed: () async {
                // Carga todo lo que falta para poder llegar hasta el final.
                while (mounted && cargados < total) {
                  if (cargando || recargando) {
                    await Future.delayed(const Duration(milliseconds: 80));
                    continue;
                  }
                  final antes = cargados;
                  await _mas();
                  if (cargados == antes) break;
                }
                await WidgetsBinding.instance.endOfFrame;
                if (sc.hasClients) {
                  sc.animateTo(sc.position.maxScrollExtent, duration: const Duration(milliseconds: 500), curve: Curves.easeOut);
                }
              },
              child: const Icon(Icons.keyboard_double_arrow_down, color: Colors.white),
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
  final ui = ValueNotifier<bool>(true); // false = interfaz oculta mientras se ve un vídeo
  final zoom = ValueNotifier<bool>(false); // true = foto ampliada
  late int cur = widget.i;
  Timer? tm;

  @override
  void initState() {
    super.initState();
    visores++;
  }

  @override
  void dispose() {
    visores--;
    tm?.cancel();
    bloqueo.dispose();
    ui.dispose();
    zoom.dispose();
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
        AnimatedBuilder(
          animation: Listenable.merge([bloqueo, zoom]),
          builder: (_, __) => PageView.builder(
            controller: pc,
            physics: (bloqueo.value || zoom.value) ? const NeverScrollableScrollPhysics() : null,
            itemCount: widget.items.length,
            onPageChanged: (n) {
              ui.value = true;
              zoom.value = false;
              setState(() => cur = n);
            },
            itemBuilder: (_, n) {
              final x = widget.items[n];
              return x.type == AssetType.video
                  ? VideoPag(x, bloqueo, ui)
                  : FotoPag(x, zoom, key: ValueKey(x.id));
            },
          ),
        ),
        AnimatedBuilder(
          animation: Listenable.merge([bloqueo, ui]),
          builder: (_, __) => (bloqueo.value || !ui.value)
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
  final ValueNotifier<bool> bloqueo, ui;
  const VideoPag(this.a, this.bloqueo, this.ui, {super.key});
  @override
  State<VideoPag> createState() => _VP();
}

class _VP extends State<VideoPag> {
  static const vels = [0.5, 1.0, 1.5, 2.0];
  VideoPlayerController? v;
  double vol = 1, tx = 0;
  int vel = 1;
  bool loop = false, horiz = false;
  Timer? t;

  void _r() {
    if (mounted) setState(() {});
  }

  bool _despierta = false;

  // Mantiene la pantalla encendida solo mientras el vídeo se está reproduciendo.
  Future<void> _pantalla() async {
    final on = v?.value.isPlaying == true;
    if (on == _despierta) return;
    _despierta = on;
    try {
      await const MethodChannel('wallpaper').invokeMethod('pantalla', {'on': on});
    } catch (_) {}
  }

  // Muestra los controles y los oculta solos a los 3 s si el vídeo se está reproduciendo.
  void mostrar() {
    t?.cancel();
    widget.ui.value = true;
    t = Timer(const Duration(seconds: 3), () {
      if (mounted && v?.value.isPlaying == true) widget.ui.value = false;
    });
  }

  @override
  void initState() {
    super.initState();
    widget.ui.addListener(_r);
    widget.a.file.then((f) {
      if (f == null) return;
      v = VideoPlayerController.file(f)
        ..initialize().then((_) {
          if (!mounted) return;
          setState(() {});
          v?.addListener(_pantalla);
        });
    });
  }

  @override
  void dispose() {
    t?.cancel();
    widget.ui.removeListener(_r);
    const MethodChannel('wallpaper').invokeMethod('pantalla', {'on': false});
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
    final ver = widget.ui.value;
    return ValueListenableBuilder<bool>(
      valueListenable: widget.bloqueo,
      builder: (_, bloq, __) => Stack(alignment: Alignment.center, children: [
        GestureDetector(
          onTap: bloq
              ? null
              : () {
                  if (ver) {
                    t?.cancel();
                    widget.ui.value = false;
                  } else {
                    mostrar();
                  }
                },
          onDoubleTapDown: bloq ? null : (d) => tx = d.globalPosition.dx,
          // Doble toque a la izquierda: -10 s. A la derecha: +10 s.
          onDoubleTap: bloq ? null : () => saltar(tx < MediaQuery.of(c).size.width / 2 ? -10 : 10),
          child: AspectRatio(aspectRatio: p.value.aspectRatio, child: VideoPlayer(p)),
        ),
        ValueListenableBuilder<VideoPlayerValue>(
          valueListenable: p,
          builder: (_, val, __) => (val.isPlaying || bloq)
              ? const SizedBox.shrink()
              : IconButton(
                  iconSize: 84,
                  icon: const Icon(Icons.play_circle_fill, color: Colors.white70),
                  onPressed: () {
                    p.play();
                    mostrar();
                  }),
        ),
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
        else if (ver)
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
                    IconButton(icon: const Icon(Icons.replay_10, color: Colors.white), onPressed: () {
                      saltar(-10);
                      mostrar();
                    }),
                    IconButton(
                        iconSize: 34,
                        icon: Icon(val.isPlaying ? Icons.pause : Icons.play_arrow, color: Colors.white),
                        onPressed: () {
                          if (val.isPlaying) {
                            p.pause();
                          } else {
                            p.play();
                          }
                          mostrar();
                        }),
                    IconButton(icon: const Icon(Icons.forward_10, color: Colors.white), onPressed: () {
                      saltar(10);
                      mostrar();
                    }),
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
                          mostrar();
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

// ───────────── Papelera: ver, restaurar y borrar definitivamente ─────────────
class Papelera extends StatefulWidget {
  final Uint8List? fondo;
  const Papelera(this.fondo, {super.key});
  @override
  State<Papelera> createState() => _P();
}

class _P extends State<Papelera> with WidgetsBindingObserver {
  static const _ch = MethodChannel('wallpaper');
  List<Map> items = [];
  final sel = <int>{};
  bool cargando = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _cargar();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  // Al volver del cuadro de confirmación del sistema, se actualiza la lista.
  @override
  void didChangeAppLifecycleState(AppLifecycleState s) {
    if (s == AppLifecycleState.resumed) _cargar();
  }

  Future<void> _cargar() async {
    List l = [];
    try {
      l = await _ch.invokeMethod<List>('papelera') ?? [];
    } catch (_) {}
    if (!mounted) return;
    setState(() {
      items = l.map((e) => Map.from(e as Map)).toList();
      sel.removeWhere((id) => !items.any((x) => x['id'] == id));
      cargando = false;
    });
  }

  Future<void> _accion(bool borrar) async {
    final pick = items.where((x) => sel.contains(x['id'])).toList();
    try {
      await _ch.invokeMethod('accion', {
        'ids': pick.map((x) => x['id']).toList(),
        'videos': pick.map((x) => x['video']).toList(),
        'borrar': borrar,
      });
    } catch (_) {}
  }

  @override
  Widget build(BuildContext c) {
    final ahora = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    return Scaffold(
      body: Stack(fit: StackFit.expand, children: [
        fondoW(widget.fondo),
        SafeArea(
          child: Column(children: [
            Padding(
              padding: const EdgeInsets.all(12),
              child: cristal(Row(children: [
                IconButton(icon: const Icon(Icons.arrow_back, color: Colors.white), onPressed: () => Navigator.pop(c)),
                Expanded(child: Text(sel.isEmpty ? 'Papelera' : '${sel.length} seleccionadas', style: _blanco)),
                if (sel.isNotEmpty) ...[
                  IconButton(icon: const Icon(Icons.restore_from_trash, color: Colors.white), onPressed: () => _accion(false)),
                  IconButton(icon: const Icon(Icons.delete_forever, color: Colors.white), onPressed: () => _accion(true)),
                ],
              ])),
            ),
            Expanded(
              child: items.isEmpty
                  ? Center(
                      child: Text(cargando ? 'Cargando…' : 'La papelera está vacía',
                          style: const TextStyle(color: Colors.white70)))
                  : GridView.builder(
                      padding: const EdgeInsets.all(6),
                      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 3, mainAxisSpacing: 6, crossAxisSpacing: 6),
                      itemCount: items.length,
                      itemBuilder: (_, n) {
                        final x = items[n];
                        final id = x['id'] as int;
                        final t = x['thumb'] as Uint8List?;
                        final exp = x['expira'] as int;
                        final dias = exp == 0 ? null : (exp - ahora) ~/ 86400;
                        return GestureDetector(
                          onTap: () => setState(() {
                            if (!sel.remove(id)) sel.add(id);
                          }),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(14),
                            child: Stack(fit: StackFit.expand, children: [
                              t != null ? Image.memory(t, fit: BoxFit.cover) : Container(color: Colors.white12),
                              if (x['video'] == true)
                                const Positioned(right: 6, bottom: 6, child: Icon(Icons.play_circle, color: Colors.white, size: 22)),
                              if (dias != null)
                                Positioned(
                                  left: 6,
                                  top: 6,
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                    decoration: BoxDecoration(color: Colors.black54, borderRadius: BorderRadius.circular(8)),
                                    child: Text('${dias < 0 ? 0 : dias} d', style: const TextStyle(color: Colors.white, fontSize: 11)),
                                  ),
                                ),
                              if (sel.contains(id))
                                Container(
                                    color: Colors.blue.withOpacity(.45),
                                    child: const Icon(Icons.check_circle, color: Colors.white, size: 30)),
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

// ───────────── Foto con zoom: pellizco, doble toque y movimiento libre ─────────────
class FotoPag extends StatefulWidget {
  final AssetEntity a;
  final ValueNotifier<bool> zoom;
  const FotoPag(this.a, this.zoom, {super.key});
  @override
  State<FotoPag> createState() => _FP();
}

class _FP extends State<FotoPag> with SingleTickerProviderStateMixin {
  final tc = TransformationController();
  late final AnimationController ac = AnimationController(vsync: this, duration: const Duration(milliseconds: 220));
  Animation<Matrix4>? anim;
  Offset toque = Offset.zero;
  late final ImageProvider orig = ResizeImage(AssetEntityImageProvider(widget.a, isOriginal: true), width: 2400);

  @override
  void initState() {
    super.initState();
    tc.addListener(() {
      final z = tc.value.getMaxScaleOnAxis() > 1.02;
      if (widget.zoom.value != z) widget.zoom.value = z;
    });
    ac.addListener(() {
      if (anim != null) tc.value = anim!.value;
    });
  }

  @override
  void dispose() {
    ac.dispose();
    tc.dispose();
    super.dispose();
  }

  // Doble toque: acerca a 2.5x justo donde tocaste; otro doble toque vuelve al tamaño normal.
  void doble() {
    final m = tc.value;
    final Matrix4 fin;
    if (m.getMaxScaleOnAxis() > 1.02) {
      fin = Matrix4.identity();
    } else {
      const s = 2.5;
      fin = Matrix4.identity()
        ..setEntry(0, 0, s)
        ..setEntry(1, 1, s)
        ..setEntry(0, 3, toque.dx * (1 - s))
        ..setEntry(1, 3, toque.dy * (1 - s));
    }
    anim = Matrix4Tween(begin: m, end: fin).animate(CurvedAnimation(parent: ac, curve: Curves.easeOut));
    ac.forward(from: 0);
  }

  @override
  Widget build(BuildContext c) {
    return GestureDetector(
      onDoubleTapDown: (d) => toque = d.localPosition,
      onDoubleTap: doble,
      // Con la foto ampliada se mueve libre en las cuatro direcciones; sin ampliar, el deslizar cambia de foto.
      child: InteractiveViewer(
        transformationController: tc,
        minScale: 0.3,
        maxScale: 8,
        child: Center(
          // La miniatura sale al instante y la foto completa la reemplaza cuando termina de cargar.
          child: Stack(fit: StackFit.expand, children: [
            Image(image: mini(widget.a, 500), fit: BoxFit.contain),
            Image(image: orig, fit: BoxFit.contain, gaplessPlayback: true),
          ]),
        ),
      ),
    );
  }
}
