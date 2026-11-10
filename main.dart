import 'dart:convert';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:just_audio/just_audio.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

const _ch = MethodChannel('dsf/media');
const cLine = Color(0xFFB5611F);
const cCream = Color(0xFFF6DCB4);
const cDim = Color(0xFFD9AC76);
const cOr = Color(0xFFFF8A1F);
const cGold = Color(0xFFFFB52E);
const cDark = Color(0xFF2A1308);

void main() => runApp(MaterialApp(
      title: 'Disco Soul Funk',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
          brightness: Brightness.dark,
          useMaterial3: true,
          colorScheme: const ColorScheme.dark(primary: cOr)),
      home: const Home(),
    ));

class Track {
  final int id;
  final String title;
  final String artist;
  final String low;
  Track(this.id, this.title, this.artist) : low = ('$title $artist').toLowerCase();
  String get label => artist.isEmpty ? title : '$artist - $title';
}

class Home extends StatefulWidget {
  const Home({super.key});
  @override
  State<Home> createState() => _HomeState();
}

class _HomeState extends State<Home> with SingleTickerProviderStateMixin {
  final _p = AudioPlayer();
  final _pv = AudioPlayer();
  late final AnimationController _ac;
  List<Track> _all = [];
  List<int> _res = [];
  int _cur = -1;
  Uint8List? _art;
  final _qc = TextEditingController();
  String _token = '';
  String _found = '';
  String _foundTitle = '';
  String _radarMsg = '';
  bool _listening = false;
  final _cc = TextEditingController();
  List<Map<String, dynamic>> _cat = [];
  bool _catLoading = false;
  String _catMsg = '';
  String? _previewArt;
  String _previewTitle = '';
  String _q = '';
  String _msg = '';
  bool _loading = true, _open = false, _shuffle = false, _denied = false;

  @override
  void initState() {
    super.initState();
    _ac = AnimationController(vsync: this, duration: const Duration(seconds: 4));
    _p.playerStateStream.listen((s) {
      if (s.playing) {
        if (!_ac.isAnimating) _ac.repeat();
      } else if (!_listening && !_pv.playing) {
        _ac.stop();
      }
      if (s.processingState == ProcessingState.completed) _next();
      if (mounted) setState(() {});
    });
    _pv.playerStateStream.listen((s) {
      if (s.playing) {
        if (!_ac.isAnimating) _ac.repeat();
      } else if (!_listening && !_p.playing) {
        _ac.stop();
      }
      if (mounted) setState(() {});
    });
    SharedPreferences.getInstance().then((sp) {
      if (mounted) setState(() => _token = sp.getString('audd') ?? '');
    });
    _load();
  }

  @override
  void dispose() {
    _p.dispose();
    _ac.dispose();
    _qc.dispose();
    _cc.dispose();
    _pv.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _msg = '';
      _denied = false;
    });
    final st = await [Permission.audio, Permission.storage].request();
    final ok = (st[Permission.audio]?.isGranted ?? false) ||
        (st[Permission.storage]?.isGranted ?? false);
    if (!ok) {
      setState(() {
        _loading = false;
        _denied = true;
        _msg = 'Autorisez l’accès à la musique pour afficher vos MP3.';
      });
      return;
    }
    try {
      final List<dynamic> raw = await _ch.invokeMethod('list');
      final list = <Track>[];
      for (final e in raw) {
        final m = Map<String, dynamic>.from(e as Map);
        var title = ((m['title'] ?? '') as String).trim();
        var artist = ((m['artist'] ?? '') as String).trim();
        if (artist == '<unknown>') artist = '';
        if (title.isEmpty) {
          title = ((m['name'] ?? '') as String).replaceAll(RegExp(r'\.[^.]+$'), '');
        }
        list.add(Track((m['id'] as num).toInt(), title, artist));
      }
      list.sort((a, b) => a.label.toLowerCase().compareTo(b.label.toLowerCase()));
      _all = list;
      _cur = -1;
      _art = null;
      _filter(_q);
      setState(() {
        _loading = false;
        if (list.isEmpty) {
          _msg = 'Aucun MP3 trouvé. Touchez Actualiser, ou redémarrez la tablette si vous venez de copier des fichiers.';
        }
      });
    } catch (e) {
      setState(() {
        _loading = false;
        _msg = 'Impossible de lire la bibliothèque : $e';
      });
    }
  }

  void _filter(String v) {
    final q = v.trim().toLowerCase();
    final r = <int>[];
    for (var i = 0; i < _all.length; i++) {
      if (q.isEmpty || _all[i].low.contains(q)) r.add(i);
    }
    setState(() {
      _q = v.trim();
      _res = r;
    });
  }

  Future<void> _play(int idx) async {
    if (idx < 0 || idx >= _all.length) return;
    FocusScope.of(context).unfocus();
    setState(() {
      _cur = idx;
      _art = null;
      _found = '';
      _previewArt = null;
      _open = false;
    });
    _pv.pause();
    _loadArt(idx);
    try {
      await _p.setAudioSource(AudioSource.uri(
          Uri.parse('content://media/external/audio/media/${_all[idx].id}')));
      _p.play();
    } catch (e) {
      setState(() => _msg = 'Impossible de lire ce fichier.');
    }
  }

  Future<void> _loadArt(int idx) async {
    try {
      final b = await _ch.invokeMethod<Uint8List>('art', {'id': _all[idx].id});
      if (mounted && _cur == idx) setState(() => _art = b);
    } catch (e) {
      // pas de pochette
    }
  }

  void _next() {
    if (_all.isEmpty) return;
    _play(_shuffle ? math.Random().nextInt(_all.length) : (_cur + 1) % _all.length);
  }

  void _prev() {
    if (_all.isEmpty) return;
    if (_p.position.inSeconds > 3) {
      _p.seek(Duration.zero);
    } else {
      _play((_cur - 1 + _all.length) % _all.length);
    }
  }

  void _toggle() {
    if (_pv.playing) {
      _pv.pause();
      return;
    }
    if (_cur < 0) {
      if (_all.isNotEmpty) _play(0);
    } else if (_p.playing) {
      _p.pause();
    } else {
      _p.play();
    }
  }

  Future<void> _catSearch() async {
    final t = _cc.text.trim();
    if (t.isEmpty) return;
    FocusScope.of(context).unfocus();
    setState(() {
      _catLoading = true;
      _catMsg = '';
      _cat = [];
    });
    try {
      final r = await http
          .get(Uri.parse('https://itunes.apple.com/search?media=music&entity=song&limit=25&term=${Uri.encodeQueryComponent(t)}'))
          .timeout(const Duration(seconds: 20));
      final j = jsonDecode(utf8.decode(r.bodyBytes)) as Map<String, dynamic>;
      final list = (j['results'] as List).map((e) => Map<String, dynamic>.from(e as Map)).toList();
      setState(() {
        _catLoading = false;
        _cat = list;
        _catMsg = list.isEmpty ? 'Aucun résultat.' : '';
      });
    } catch (e) {
      setState(() {
        _catLoading = false;
        _catMsg = 'Impossible de joindre le catalogue en ligne. Vérifiez la connexion internet.';
      });
    }
  }

  Future<void> _preview(Map<String, dynamic> x) async {
    final u = (x['previewUrl'] ?? '').toString();
    if (u.isEmpty) return;
    await _p.pause();
    setState(() {
      _previewArt = (x['artworkUrl100'] ?? '').toString().replaceAll('100x100', '300x300');
      final a = (x['artistName'] ?? '').toString();
      _previewTitle = a.isEmpty ? (x['trackName'] ?? '').toString() : '$a - ${x['trackName'] ?? ''}';
    });
    try {
      await _pv.setUrl(u);
      _pv.play();
    } catch (e) {
      _snack('Impossible de lire cet extrait.');
    }
  }

  void _elsewhere(Map<String, dynamic> x) {
    final a = (x['artistName'] ?? '').toString();
    final t = (x['trackName'] ?? '').toString();
    setState(() {
      _foundTitle = t;
      _found = a.isEmpty ? t : '$a - $t';
      _radarMsg = '';
    });
    _snack('Touchez un bouton de la passerelle (plus bas) pour chercher ce titre.');
  }

  Widget _catTile(Map<String, dynamic> x) {
    final art = (x['artworkUrl100'] ?? '').toString();
    const blank = SizedBox(width: 56, height: 56);
    final sub = '${x['artistName'] ?? ''}${(x['collectionName'] ?? '').toString().isEmpty ? '' : ' · ${x['collectionName']}'}';
    return Container(
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.only(bottom: 6),
      decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: Color(0x59B5611F)))),
      child: Row(children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: art.isEmpty
              ? blank
              : Image.network(art, width: 56, height: 56, fit: BoxFit.cover, errorBuilder: (c, e, s) => blank),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text((x['trackName'] ?? '').toString(),
                maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700)),
            Text(sub, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(color: cDim, fontSize: 13)),
          ]),
        ),
        Column(children: [
          IconButton(
              onPressed: () => _preview(x),
              tooltip: 'Écouter 30 s',
              icon: const Icon(Icons.play_circle_fill, color: cOr, size: 36)),
          TextButton(
              onPressed: () => _elsewhere(x),
              child: const Text('Chercher ailleurs', style: TextStyle(fontSize: 12))),
        ]),
      ]),
    );
  }

  Widget _catPanel() => _panel(
        'Catalogue en ligne (extraits 30 s)',
        Column(children: [
          Row(children: [
            Expanded(
              child: TextField(
                controller: _cc,
                textInputAction: TextInputAction.search,
                onSubmitted: (_) => _catSearch(),
                style: const TextStyle(color: cGold, fontWeight: FontWeight.w700, fontSize: 17),
                decoration: InputDecoration(
                  prefixIcon: const Icon(Icons.public, color: cOr),
                  hintText: 'Chercher n’importe quel titre',
                  filled: true,
                  fillColor: const Color(0x59000000),
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(color: cLine, width: 1.5)),
                  enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(color: cLine, width: 1.5)),
                ),
              ),
            ),
            const SizedBox(width: 8),
            ElevatedButton(
              onPressed: _catSearch,
              style: ElevatedButton.styleFrom(
                backgroundColor: cOr,
                foregroundColor: cDark,
                minimumSize: const Size(0, 52),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              child: const Text('Chercher', style: TextStyle(fontWeight: FontWeight.w800)),
            ),
          ]),
          if (_catLoading)
            const Padding(padding: EdgeInsets.all(14), child: CircularProgressIndicator(color: cOr)),
          if (_catMsg.isNotEmpty)
            Padding(
                padding: const EdgeInsets.only(top: 10),
                child: Text(_catMsg, textAlign: TextAlign.center, style: const TextStyle(color: cDim))),
          for (final x in _cat) _catTile(x),
        ]),
      );

  void _snack(String m) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));

  Future<void> _askToken() async {
    final c = TextEditingController(text: _token);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Clé AudD'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          const Text('Créez un compte sur audd.io, copiez votre « api_token » et collez-le ici. Il reste sur cette tablette.'),
          const SizedBox(height: 12),
          TextField(controller: c, decoration: const InputDecoration(hintText: 'api_token')),
        ]),
        actions: [
          TextButton(
              onPressed: () => launchUrl(Uri.parse('https://dashboard.audd.io/'), mode: LaunchMode.externalApplication),
              child: const Text('Ouvrir audd.io')),
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Annuler')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Enregistrer')),
        ],
      ),
    );
    if (ok == true) {
      final t = c.text.trim();
      final sp = await SharedPreferences.getInstance();
      await sp.setString('audd', t);
      if (mounted) setState(() => _token = t);
    }
  }

  Future<void> _radar() async {
    if (_listening) return;
    if (_token.isEmpty) {
      await _askToken();
      if (_token.isEmpty) return;
    }
    final st = await Permission.microphone.request();
    if (!st.isGranted) {
      _snack('Autorisez le micro dans les réglages pour utiliser le radar.');
      return;
    }
    await _p.pause();
    setState(() {
      _listening = true;
      _found = '';
      _radarMsg = 'Le radar écoute… gardez la tablette près de la musique (10 secondes).';
    });
    _ac.repeat();
    String? path;
    try {
      path = await _ch.invokeMethod<String>('recStart');
      await Future.delayed(const Duration(seconds: 10));
      await _ch.invokeMethod('recStop');
    } catch (e) {
      try {
        await _ch.invokeMethod('recStop');
      } catch (_) {}
      path = null;
      if (mounted) setState(() => _radarMsg = 'Impossible d’enregistrer avec le micro.');
    }
    if (path != null) {
      if (mounted) setState(() => _radarMsg = 'Identification en cours…');
      await _identify(path);
    }
    if (!mounted) return;
    setState(() => _listening = false);
    if (!_p.playing) _ac.stop();
  }

  Future<void> _identify(String path) async {
    try {
      final req = http.MultipartRequest('POST', Uri.parse('https://api.audd.io/'))
        ..fields['api_token'] = _token
        ..files.add(await http.MultipartFile.fromPath('file', path));
      final res = await http.Response.fromStream(await req.send().timeout(const Duration(seconds: 45)));
      final j = jsonDecode(res.body) as Map<String, dynamic>;
      if (j['status'] == 'success' && j['result'] != null) {
        final r = j['result'] as Map<String, dynamic>;
        final t = (r['title'] ?? '').toString();
        final a = (r['artist'] ?? '').toString();
        setState(() {
          _foundTitle = t;
          _found = a.isEmpty ? t : '$a - $t';
          _radarMsg = '';
        });
      } else if (j['status'] == 'success') {
        setState(() => _radarMsg = 'Titre non reconnu. Rapprochez la tablette de la source et réessayez.');
      } else {
        final e = j['error'];
        final m = e is Map ? (e['error_message'] ?? '').toString() : '';
        setState(() => _radarMsg = 'Erreur du service : $m');
      }
    } catch (e) {
      setState(() => _radarMsg = 'Impossible de contacter le service. Vérifiez la connexion internet.');
    }
  }

  void _searchMine() {
    _qc.text = _foundTitle;
    setState(() => _open = true);
    _filter(_foundTitle);
  }

  void _go(String? base, String home) {
    final q = _found.isNotEmpty ? _found : (_cur >= 0 ? _all[_cur].label : _q);
    final url = (q.isNotEmpty && base != null) ? base + Uri.encodeComponent(q) : home;
    launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
  }

  String _fmt(Duration d) {
    final s = d.inSeconds % 60;
    return '${d.inMinutes}:${s < 10 ? '0$s' : '$s'}';
  }

  Widget _outlined(String t, double size) {
    final base = TextStyle(fontSize: size, fontWeight: FontWeight.w900, height: .9);
    return Stack(children: [
      Text(t,
          style: base.copyWith(
              foreground: Paint()
                ..style = PaintingStyle.stroke
                ..strokeWidth = size * .16
                ..strokeJoin = StrokeJoin.round
                ..color = const Color(0xFF4A1C07))),
      Text(t, style: base.copyWith(color: cGold)),
    ]);
  }

  Widget _vinyl(double s, {Uint8List? art, String? artUrl}) {
    final hasArt = art != null || (artUrl != null && artUrl.isNotEmpty);
    final fallback = Container(width: s * .64, height: s * .64, color: const Color(0xFFE8892A));
    return Container(
      width: s,
      height: s,
      alignment: Alignment.center,
      decoration: const BoxDecoration(
        shape: BoxShape.circle,
        gradient: RadialGradient(
            colors: [Color(0xFF222222), Color(0xFF0D0D0D), Color(0xFF222222), Color(0xFF0D0D0D)],
            stops: [.3, .5, .75, 1]),
        boxShadow: [BoxShadow(color: Color(0x73FF8A1F), blurRadius: 30, spreadRadius: 6)],
      ),
      child: hasArt
          ? Stack(alignment: Alignment.center, children: [
              ClipOval(
                child: art != null
                    ? Image.memory(art,
                        width: s * .64,
                        height: s * .64,
                        fit: BoxFit.cover,
                        gaplessPlayback: true,
                        errorBuilder: (c, e, st) => fallback)
                    : Image.network(artUrl!,
                        width: s * .64,
                        height: s * .64,
                        fit: BoxFit.cover,
                        gaplessPlayback: true,
                        errorBuilder: (c, e, st) => fallback),
              ),
              Container(
                  width: s * .06,
                  height: s * .06,
                  decoration: const BoxDecoration(shape: BoxShape.circle, color: Colors.black)),
            ])
          : Container(
              width: s * .42,
              height: s * .42,
              alignment: Alignment.center,
              decoration: const BoxDecoration(shape: BoxShape.circle, color: Color(0xFFE8892A)),
              child: s > 100
                  ? Text('STUDIO\nGROOVE',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: s * .06, fontWeight: FontWeight.w800, color: const Color(0xFF3A1706), height: 1.1))
                  : Container(
                      width: s * .1,
                      height: s * .1,
                      decoration: const BoxDecoration(shape: BoxShape.circle, color: Colors.black)),
            ),
    );
  }

  Widget _logo() => Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          _outlined('DISCO', 52),
          Padding(padding: const EdgeInsets.symmetric(horizontal: 4), child: _vinyl(46)),
          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            _outlined('SOUL', 34),
            _outlined('FUNK', 34),
          ]),
        ]),
      );

  Widget _panel(String title, Widget child) => Container(
        margin: const EdgeInsets.only(bottom: 14),
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
        decoration: BoxDecoration(
          color: const Color(0x2E000000),
          border: Border.all(color: const Color(0x99B5611F), width: 1.5),
          borderRadius: BorderRadius.circular(18),
        ),
        child: Column(children: [
          Text(title.toUpperCase(),
              textAlign: TextAlign.center,
              style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14, color: cCream)),
          const SizedBox(height: 10),
          child,
        ]),
      );

  Widget _searchPanel() => _panel(
        'Recherche locale (${_all.length} MP3)',
        Column(children: [
          Row(children: [
            Expanded(
              child: TextField(
                controller: _qc,
                onTap: () => setState(() => _open = true),
                onChanged: (v) {
                  _open = true;
                  _found = '';
                  _filter(v);
                },
                style: const TextStyle(color: cGold, fontWeight: FontWeight.w700, fontSize: 17),
                decoration: InputDecoration(
                  prefixIcon: const Icon(Icons.search, color: cOr),
                  suffixIcon: _open
                      ? IconButton(
                          icon: const Icon(Icons.close),
                          onPressed: () {
                            FocusScope.of(context).unfocus();
                            setState(() => _open = false);
                          })
                      : null,
                  hintText: 'Chercher un titre ou un artiste',
                  filled: true,
                  fillColor: const Color(0x59000000),
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(color: cLine, width: 1.5)),
                  enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(color: cLine, width: 1.5)),
                ),
              ),
            ),
            IconButton(onPressed: _load, tooltip: 'Actualiser', icon: const Icon(Icons.refresh, color: cOr)),
          ]),
          if (_loading)
            const Padding(
                padding: EdgeInsets.all(14), child: CircularProgressIndicator(color: cOr)),
          if (_msg.isNotEmpty)
            Padding(
                padding: const EdgeInsets.only(top: 10),
                child: Text(_msg, textAlign: TextAlign.center, style: const TextStyle(color: cDim))),
          if (_denied)
            Wrap(children: [
              TextButton(onPressed: _load, child: const Text('Réessayer')),
              TextButton(onPressed: () => openAppSettings(), child: const Text('Réglages')),
            ]),
          if (_open && _all.isNotEmpty)
            Container(
              height: 240,
              margin: const EdgeInsets.only(top: 10),
              decoration: BoxDecoration(
                color: const Color(0x59000000),
                border: Border.all(color: cLine, width: 1.5),
                borderRadius: BorderRadius.circular(12),
              ),
              child: _res.isEmpty
                  ? const Center(child: Text('Aucun résultat', style: TextStyle(color: cDim)))
                  : ListView.builder(
                      itemCount: _res.length,
                      itemBuilder: (c, i) {
                        final idx = _res[i];
                        return ListTile(
                          dense: true,
                          selected: idx == _cur,
                          selectedColor: cGold,
                          title: Text(_all[idx].label, maxLines: 2, overflow: TextOverflow.ellipsis),
                          onTap: () => _play(idx),
                        );
                      }),
            ),
        ]),
      );

  Widget _seek() => StreamBuilder<Duration?>(
        stream: _p.durationStream,
        builder: (c, ds) {
          final d = ds.data ?? Duration.zero;
          final mx = d.inMilliseconds.toDouble();
          return StreamBuilder<Duration>(
            stream: _p.positionStream,
            builder: (c, ps) {
              final pos = ps.data ?? Duration.zero;
              final v = pos.inMilliseconds.toDouble().clamp(0.0, mx > 0 ? mx : 1.0).toDouble();
              return Row(children: [
                Text(_fmt(pos), style: const TextStyle(color: cDim, fontSize: 13)),
                Expanded(
                  child: Slider(
                    value: v,
                    max: mx > 0 ? mx : 1.0,
                    activeColor: cOr,
                    onChanged: mx > 0 ? (x) => _p.seek(Duration(milliseconds: x.toInt())) : null,
                  ),
                ),
                Text(_fmt(d), style: const TextStyle(color: cDim, fontSize: 13)),
              ]);
            },
          );
        },
      );

  Widget _cb(IconData i, VoidCallback f, {bool on = false, bool big = false}) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6),
        child: Material(
          color: big ? cOr : (on ? cGold : const Color(0x59000000)),
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(big ? 36 : 14),
              side: const BorderSide(color: cLine, width: 1.5)),
          child: InkWell(
            customBorder:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(big ? 36 : 14)),
            onTap: f,
            child: SizedBox(
                width: big ? 72 : 56,
                height: big ? 72 : 52,
                child: Icon(i, size: big ? 36 : 26, color: (big || on) ? cDark : cCream)),
          ),
        ),
      );

  Widget _playerPanel() => _panel(
        'Mode d’écoute / reconnaissance',
        Column(children: [
          SizedBox(
            height: 210,
            child: Stack(alignment: Alignment.center, children: [
              Positioned.fill(
                child: AnimatedBuilder(
                  animation: _ac,
                  builder: (c, _) => CustomPaint(painter: Waves(_ac.value, _p.playing || _pv.playing || _listening)),
                ),
              ),
              RotationTransition(turns: _ac, child: _vinyl(190, art: _art, artUrl: _pv.playing ? _previewArt : null)),
            ]),
          ),
          Text(_pv.playing && _previewTitle.isNotEmpty ? _previewTitle : (_cur >= 0 ? _all[_cur].label : 'Choisissez un morceau'),
              textAlign: TextAlign.center,
              style: const TextStyle(color: cGold, fontWeight: FontWeight.w800, fontSize: 18)),
          _seek(),
          Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            _cb(Icons.shuffle, () => setState(() => _shuffle = !_shuffle), on: _shuffle),
            _cb(Icons.skip_previous, _prev),
            _cb(_p.playing ? Icons.pause : Icons.play_arrow, _toggle, big: true),
            _cb(Icons.skip_next, _next),
          ]),
          const SizedBox(height: 14),
          OutlinedButton.icon(
            onPressed: _listening ? null : _radar,
            icon: const Icon(Icons.mic),
            label: Text(_listening ? 'LE RADAR ÉCOUTE…' : 'ACTIVER LE RADAR'),
            style: OutlinedButton.styleFrom(
              foregroundColor: const Color(0xFFFFD9A0),
              side: const BorderSide(color: cOr, width: 2.5),
              shape: const StadiumBorder(),
              padding: const EdgeInsets.symmetric(horizontal: 30, vertical: 16),
              textStyle: const TextStyle(fontWeight: FontWeight.w800, fontSize: 17),
            ),
          ),
          if (_listening)
            const Padding(padding: EdgeInsets.only(top: 12), child: LinearProgressIndicator(color: cOr)),
          if (_radarMsg.isNotEmpty)
            Padding(
                padding: const EdgeInsets.only(top: 10),
                child: Text(_radarMsg, textAlign: TextAlign.center, style: const TextStyle(color: cDim))),
          if (_found.isNotEmpty)
            Container(
              margin: const EdgeInsets.only(top: 10),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0x59000000),
                border: Border.all(color: cOr, width: 1.5),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(children: [
                Text(_found,
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: cGold, fontWeight: FontWeight.w800, fontSize: 18)),
                const Text('Les boutons de la passerelle cherchent ce titre.',
                    textAlign: TextAlign.center, style: TextStyle(color: cDim, fontSize: 13)),
                TextButton(onPressed: _searchMine, child: const Text('Chercher dans mes MP3')),
              ]),
            ),
          TextButton(onPressed: _askToken, child: const Text('Clé AudD')),
        ]),
      );

  Widget _circle(Color c, Widget child) => Container(
      width: 44, height: 44, alignment: Alignment.center,
      decoration: BoxDecoration(shape: BoxShape.circle, color: c), child: child);

  Widget _bar(double h, Color c) =>
      Container(width: 7, height: h, margin: const EdgeInsets.symmetric(horizontal: 1.5), color: c);

  Widget _tile(String label, Widget icon, String? base, String home) => InkWell(
        onTap: () => _go(base, home),
        child: SizedBox(
          width: 84,
          child: Column(children: [
            Container(
              width: 76,
              height: 64,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: const Color(0xFFF6E6C8),
                border: Border.all(color: cLine, width: 2.5),
                borderRadius: BorderRadius.circular(14),
              ),
              child: icon,
            ),
            const SizedBox(height: 6),
            Text(label,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: cCream)),
          ]),
        ),
      );

  Widget _gatePanel() => _panel(
        'Passerelle universelle',
        Wrap(alignment: WrapAlignment.spaceEvenly, spacing: 8, runSpacing: 12, children: [
          _tile('CDandLP', const Icon(Icons.album, size: 42, color: Color(0xFFE2B23C)),
              'https://www.cdandlp.com/fr/search/?q=', 'https://www.cdandlp.com/'),
          _tile('Discogs',
              _circle(Colors.black, const Text('Discogs', style: TextStyle(fontSize: 9, fontWeight: FontWeight.w800, color: Color(0xFFFFD23F)))),
              'https://www.discogs.com/search/?type=all&q=', 'https://www.discogs.com/'),
          _tile('Deezer',
              Row(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.end, children: [
                _bar(10, const Color(0xFF40C4A8)),
                _bar(18, const Color(0xFF8A4FD6)),
                _bar(26, const Color(0xFFFF5A3C)),
                _bar(34, cGold),
              ]),
              'https://www.deezer.com/search/', 'https://www.deezer.com/'),
          _tile('Spotify', _circle(const Color(0xFF1DB954), const Icon(Icons.graphic_eq, color: Colors.white)),
              'https://open.spotify.com/search/', 'https://open.spotify.com/'),
          _tile('YouTube',
              Container(
                  width: 46, height: 32, alignment: Alignment.center,
                  decoration: BoxDecoration(color: const Color(0xFFE62117), borderRadius: BorderRadius.circular(9)),
                  child: const Icon(Icons.play_arrow, color: Colors.white)),
              'https://www.youtube.com/results?search_query=', 'https://www.youtube.com/'),
          _tile('Shazam',
              _circle(const Color(0xFF0F8CFF), const Text('S', style: TextStyle(fontSize: 26, fontWeight: FontWeight.w900, color: Colors.white))),
              null, 'https://www.shazam.com/'),
          _tile('SoundHound',
              _circle(const Color(0xFFFF7A1A),
                  Container(width: 22, height: 22,
                      decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: const Color(0xFF3A1706), width: 5)))),
              null, 'https://www.soundhound.com/'),
        ]),
      );

  @override
  Widget build(BuildContext context) => Scaffold(
        body: Container(
          decoration: const BoxDecoration(
              gradient: RadialGradient(
                  center: Alignment(0, -1), radius: 1.4, colors: [Color(0xFF4B2511), Color(0xFF2A1308)])),
          child: SafeArea(
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 920),
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                  children: [_logo(), _searchPanel(), _catPanel(), _playerPanel(), _gatePanel()],
                ),
              ),
            ),
          ),
        ),
      );
}

class Waves extends CustomPainter {
  final double t;
  final bool on;
  Waves(this.t, this.on);
  @override
  void paint(Canvas c, Size s) {
    final mid = s.width / 2;
    const r = 110.0;
    final n = ((s.width / 2 - r - 10) / 9).floor().clamp(4, 30).toInt();
    final p = Paint()..color = cOr;
    for (var i = 0; i < n; i++) {
      final fade = 1 - i / n;
      final v = on
          ? (.25 + .6 * math.sin(t * 4 * math.pi + i * .9).abs() * (1 - i / n * .5))
          : (.14 + .2 * math.sin(i * 1.7).abs() * fade);
      final h = math.max(5.0, v * s.height * .85);
      final x = r + i * 9.0;
      c.drawRect(Rect.fromLTWH(mid + x, (s.height - h) / 2, 4, h), p);
      c.drawRect(Rect.fromLTWH(mid - x - 4, (s.height - h) / 2, 4, h), p);
    }
  }

  @override
  bool shouldRepaint(Waves o) => o.t != t || o.on != on;
}
