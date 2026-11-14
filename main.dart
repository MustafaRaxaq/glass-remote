import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';
import 'dart:ui';
import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:speech_to_text/speech_to_text.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setSystemUIOverlayStyle(SystemUiOverlayStyle.light.copyWith(statusBarColor: Colors.transparent));
  runApp(MaterialApp(debugShowCheckedModeBanner: false, theme: ThemeData.dark(useMaterial3: true), home: const RemotePage()));
}

// ---------- TV protocol (UDP 7899) ----------
class Tv {
  RawDatagramSocket? s;
  String? ip;
  String me = '';
  String name = '';
  final status = ValueNotifier<String>('Searching for TV…');
  final ok = ValueNotifier<bool>(false);
  final apps = ValueNotifier<List<Map>>([]);
  final _bc = InternetAddress('255.255.255.255');

  Future<void> start() async {
    for (final i in await NetworkInterface.list(type: InternetAddressType.IPv4)) {
      if (!i.name.startsWith('lo') && i.addresses.isNotEmpty) {
        me = i.addresses.first.address;
        if (i.name.startsWith('wlan')) break;
      }
    }
    if (s == null) {
      final sock = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 7899, reuseAddress: true);
      sock.broadcastEnabled = true;
      sock.listen((e) {
        if (e != RawSocketEvent.read) return;
        final p = sock.receive();
        if (p == null || p.address.address == me) return;
        _on(utf8.decode(p.data, allowMalformed: true));
      });
      s = sock;
    }
    scan();
  }

  void scan() {
    ip = null;
    ok.value = false;
    apps.value = [];
    status.value = 'Searching for TV…';
    s?.send(utf8.encode('POSTIP'), _bc, 7899);
    Timer(const Duration(seconds: 4), () {
      if (ip == null) status.value = 'No TV found. Tap to retry';
    });
  }

  void _on(String t) {
    final m = RegExp(r'IP\*:\s*([\d.]+)').firstMatch(t);
    if (m != null && ip == null) {
      name = t.split('IP*')[0].trim();
      ip = m.group(1);
      s!.send(utf8.encode('$me&TVIP=$ip&Android Phone'), _bc, 7899);
      ok.value = true;
      status.value = 'Connected  ·  $ip';
    }
    if (t.contains('apps=')) {
      try {
        var j = t.substring(t.indexOf('apps=') + 5);
        j = j.substring(0, j.lastIndexOf(']') + 1);
        apps.value = List<Map>.from(jsonDecode(j));
      } catch (_) {}
    }
  }

  bool send(String msg) {
    if (ip == null) return false;
    s!.send(utf8.encode('$me&$msg'), InternetAddress(ip!), 7899);
    return true;
  }

  bool key(int code) => send('key=action;$code&');
  Future<void> typeText(String t) async {
    for (final c in t.runes) {
      send('key=editText;${String.fromCharCode(c)}');
      await Future.delayed(const Duration(milliseconds: 30));
    }
  }
}

// ---------- tick sound (generated, no asset needed) ----------
Uint8List tickWav() {
  const sr = 22050;
  final n = (sr * 0.035).toInt();
  final d = ByteData(44 + n * 2);
  void w(int o, String t) {
    for (var i = 0; i < t.length; i++) d.setUint8(o + i, t.codeUnitAt(i));
  }
  const le = Endian.little;
  w(0, 'RIFF'); d.setUint32(4, 36 + n * 2, le); w(8, 'WAVEfmt ');
  d.setUint32(16, 16, le); d.setUint16(20, 1, le); d.setUint16(22, 1, le);
  d.setUint32(24, sr, le); d.setUint32(28, sr * 2, le); d.setUint16(32, 2, le); d.setUint16(34, 16, le);
  w(36, 'data'); d.setUint32(40, n * 2, le);
  for (var i = 0; i < n; i++) {
    final t = i / sr;
    final v = (sin(2 * pi * 2200 * t) * .6 + sin(2 * pi * 900 * t) * .4) * exp(-t * 170);
    d.setInt16(44 + i * 2, (v * 26000).toInt(), le);
  }
  return d.buffer.asUint8List();
}

// ---------- glass widgets ----------
class Glass extends StatelessWidget {
  final Widget? child;
  final double r;
  final Color? tint;
  final EdgeInsets pad;
  const Glass({super.key, this.child, this.r = 28, this.tint, this.pad = EdgeInsets.zero});
  @override
  Widget build(BuildContext context) {
    final c = tint ?? Colors.white;
    final br = BorderRadius.circular(r);
    return ClipRRect(
      borderRadius: br,
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 26, sigmaY: 26),
        child: Container(
          padding: pad,
          decoration: BoxDecoration(
            borderRadius: br,
            gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [c.withValues(alpha: .26), c.withValues(alpha: .07)]),
            border: Border.all(color: Colors.white.withValues(alpha: .30), width: 1),
          ),
          child: child,
        ),
      ),
    );
  }
}

class Press extends StatefulWidget {
  final Widget child;
  final VoidCallback onTap;
  final bool repeat;
  const Press({super.key, required this.child, required this.onTap, this.repeat = false});
  @override
  State<Press> createState() => _PressState();
}

class _PressState extends State<Press> {
  bool down = false;
  Timer? t;
  void up() {
    t?.cancel();
    if (mounted) setState(() => down = false);
  }
  @override
  void dispose() { t?.cancel(); super.dispose(); }
  @override
  Widget build(BuildContext context) => GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: (_) {
          setState(() => down = true);
          widget.onTap();
          if (widget.repeat) {
            t = Timer(const Duration(milliseconds: 400), () {
              t = Timer.periodic(const Duration(milliseconds: 110), (_) => widget.onTap());
            });
          }
        },
        onTapUp: (_) => up(),
        onTapCancel: up,
        child: AnimatedScale(scale: down ? .91 : 1, duration: const Duration(milliseconds: 80), child: widget.child),
      );
}

class GBtn extends StatelessWidget {
  final Widget child;
  final VoidCallback onTap;
  final double w, h, r;
  final Color? tint;
  final bool repeat;
  const GBtn({super.key, required this.child, required this.onTap, this.w = 72, this.h = 64, this.r = 24, this.tint, this.repeat = false});
  @override
  Widget build(BuildContext context) => Press(
        onTap: onTap,
        repeat: repeat,
        child: SizedBox(width: w, height: h, child: Glass(r: r, tint: tint, child: Center(child: child))),
      );
}

// ---------- page ----------
class RemotePage extends StatefulWidget {
  const RemotePage({super.key});
  @override
  State<RemotePage> createState() => _RemotePageState();
}

class _RemotePageState extends State<RemotePage> {
  final tv = Tv();
  final player = AudioPlayer();
  final wav = tickWav();
  final stt = SpeechToText();
  final txt = TextEditingController();
  String? listening;
  String heard = '';

  @override
  void initState() {
    super.initState();
    tv.start();
  }

  void tick() {
    HapticFeedback.selectionClick();
    player.stop();
    player.play(BytesSource(wav), volume: .7);
  }

  void key(int code) {
    tick();
    if (!tv.key(code)) toast('TV not connected yet');
  }

  void toast(String m) {
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m), duration: const Duration(seconds: 2), behavior: SnackBarBehavior.floating));
  }

  Future<void> voice(bool search) async {
    tick();
    if (tv.ip == null) { toast('TV not connected yet'); return; }
    final okInit = await stt.initialize(onError: (e) => toast(e.errorMsg));
    if (!okInit) { toast('Allow microphone access in Settings'); return; }
    setState(() { listening = search ? 'Say what to search' : 'Say what to type'; heard = ''; });
    await stt.listen(
      listenFor: const Duration(seconds: 15),
      pauseFor: const Duration(seconds: 3),
      onResult: (r) {
        setState(() => heard = r.recognizedWords);
        if (r.finalResult) {
          final text = r.recognizedWords;
          setState(() => listening = null);
          if (text.isEmpty) return;
          if (search) { tv.send('key=search=$text'); } else { tv.typeText(text); }
        }
      },
    );
  }

  void sendText() {
    final t = txt.text;
    if (t.isEmpty) { key(66); return; }
    tick();
    tv.typeText(t).then((_) => tv.key(66));
    txt.clear();
  }

  void openApps() {
    tick();
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => Padding(
        padding: const EdgeInsets.all(12),
        child: Glass(
          r: 32,
          pad: const EdgeInsets.all(16),
          child: ValueListenableBuilder<List<Map>>(
            valueListenable: tv.apps,
            builder: (_, list, __) => list.isEmpty
                ? const SizedBox(height: 120, child: Center(child: Text('No apps received yet')))
                : GridView.count(
                    crossAxisCount: 3,
                    shrinkWrap: true,
                    children: [
                      for (final a in list)
                        Press(
                          onTap: () { tick(); tv.send('key=open;${a['pkg']}&'); Navigator.pop(context); },
                          child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                            CircleAvatar(radius: 24, backgroundColor: Colors.white24, child: Text('${a['name']}'.isEmpty ? '?' : '${a['name']}'[0].toUpperCase(), style: const TextStyle(fontSize: 20))),
                            const SizedBox(height: 6),
                            Text('${a['name']}', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12)),
                          ]),
                        ),
                    ],
                  ),
          ),
        ),
      ),
    );
  }

  Widget orb(Color c, double size, {double? top, double? left, double? right, double? bottom}) => Positioned(
        top: top, left: left, right: right, bottom: bottom,
        child: Container(width: size, height: size, decoration: BoxDecoration(shape: BoxShape.circle, gradient: RadialGradient(colors: [c.withValues(alpha: .8), c.withValues(alpha: 0)]))),
      );

  Widget arrow(IconData i, int code, Alignment a) => Align(
        alignment: a,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Press(repeat: true, onTap: () => key(code), child: Container(width: 64, height: 64, color: Colors.transparent, child: Icon(i, size: 38, color: Colors.white.withValues(alpha: .92)))),
        ),
      );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      resizeToAvoidBottomInset: true,
      body: Stack(children: [
        Container(decoration: const BoxDecoration(gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [Color(0xFF060A22), Color(0xFF1A0F3D), Color(0xFF0A2848)]))),
        orb(const Color(0xFF0A84FF), 380, top: -120, left: -140),
        orb(const Color(0xFFBF5AF1), 340, top: 260, right: -170),
        orb(const Color(0xFFFF375F), 300, bottom: -100, left: -80),
        orb(const Color(0xFF64D2FF), 220, bottom: 120, right: -60),
        SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(18, 10, 18, 18),
            child: Column(children: [
              Row(children: [
                GBtn(w: 58, h: 58, r: 29, tint: const Color(0xFFFF453A), onTap: () => key(26), child: const Icon(Icons.power_settings_new, size: 26)),
                const SizedBox(width: 12),
                Expanded(
                  child: Press(
                    onTap: () { tick(); tv.scan(); },
                    child: Glass(
                      r: 29,
                      pad: const EdgeInsets.symmetric(horizontal: 16, vertical: 17),
                      child: ValueListenableBuilder<String>(
                        valueListenable: tv.status,
                        builder: (_, s, __) => Row(children: [
                          ValueListenableBuilder<bool>(valueListenable: tv.ok, builder: (_, o, __) => Container(width: 9, height: 9, decoration: BoxDecoration(shape: BoxShape.circle, color: o ? const Color(0xFF30D158) : const Color(0xFFFF9F0A)))),
                          const SizedBox(width: 10),
                          Expanded(child: Text(s, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500))),
                        ]),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                GBtn(w: 58, h: 58, r: 29, onTap: () => key(164), child: const Icon(Icons.volume_off_rounded, size: 24)),
              ]),
              const SizedBox(height: 26),
              SizedBox(
                width: 280, height: 280,
                child: Stack(alignment: Alignment.center, children: [
                  const Glass(r: 140, child: SizedBox.expand()),
                  arrow(Icons.keyboard_arrow_up_rounded, 19, Alignment.topCenter),
                  arrow(Icons.keyboard_arrow_down_rounded, 20, Alignment.bottomCenter),
                  arrow(Icons.keyboard_arrow_left_rounded, 21, Alignment.centerLeft),
                  arrow(Icons.keyboard_arrow_right_rounded, 22, Alignment.centerRight),
                  GBtn(w: 104, h: 104, r: 52, tint: const Color(0xFF0A84FF), onTap: () => key(23), child: const Text('OK', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w600))),
                ]),
              ),
              const SizedBox(height: 22),
              Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                GBtn(onTap: () => key(4), child: const Icon(Icons.arrow_back_ios_new_rounded, size: 22)),
                GBtn(onTap: () => key(3), child: const Icon(Icons.home_rounded, size: 28)),
                GBtn(onTap: openApps, child: const Icon(Icons.apps_rounded, size: 26)),
              ]),
              const SizedBox(height: 16),
              Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                SizedBox(
                  width: 78, height: 164,
                  child: Glass(r: 39, child: Column(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
                    Press(repeat: true, onTap: () => key(24), child: Container(width: 78, height: 70, color: Colors.transparent, child: const Icon(Icons.add_rounded, size: 32))),
                    Press(repeat: true, onTap: () => key(25), child: Container(width: 78, height: 70, color: Colors.transparent, child: const Icon(Icons.remove_rounded, size: 32))),
                  ])),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(children: [
                    Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                      GBtn(w: 62, h: 62, r: 22, onTap: () => key(89), child: const Icon(Icons.fast_rewind_rounded)),
                      GBtn(w: 62, h: 62, r: 22, onTap: () => key(85), child: const Icon(Icons.play_arrow_rounded, size: 30)),
                      GBtn(w: 62, h: 62, r: 22, onTap: () => key(90), child: const Icon(Icons.fast_forward_rounded)),
                    ]),
                    const SizedBox(height: 14),
                    Row(children: [
                      Expanded(child: GBtn(w: double.infinity, h: 52, r: 20, onTap: () => voice(true), child: const Row(mainAxisAlignment: MainAxisAlignment.center, children: [Icon(Icons.mic_rounded, size: 20), SizedBox(width: 6), Text('Search')]))),
                      const SizedBox(width: 10),
                      Expanded(child: GBtn(w: double.infinity, h: 52, r: 20, onTap: () => voice(false), child: const Row(mainAxisAlignment: MainAxisAlignment.center, children: [Icon(Icons.keyboard_voice_rounded, size: 20), SizedBox(width: 6), Text('Dictate')]))),
                    ]),
                  ]),
                ),
              ]),
              const SizedBox(height: 16),
              Glass(
                r: 30,
                pad: const EdgeInsets.fromLTRB(20, 2, 8, 2),
                child: Row(children: [
                  Expanded(child: TextField(controller: txt, onSubmitted: (_) => sendText(), decoration: const InputDecoration(hintText: 'Type on TV', border: InputBorder.none))),
                  Press(repeat: true, onTap: () => key(67), child: const Padding(padding: EdgeInsets.all(10), child: Icon(Icons.backspace_outlined, size: 22))),
                  Press(onTap: sendText, child: const Padding(padding: EdgeInsets.all(10), child: Icon(Icons.send_rounded, size: 22, color: Color(0xFF64D2FF)))),
                ]),
              ),
            ]),
          ),
        ),
        if (listening != null)
          Positioned(
            left: 24, right: 24, bottom: 40,
            child: Press(
              onTap: () { stt.stop(); setState(() => listening = null); },
              child: Glass(r: 32, tint: const Color(0xFF0A84FF), pad: const EdgeInsets.all(22), child: Column(mainAxisSize: MainAxisSize.min, children: [
                const Icon(Icons.mic_rounded, size: 34),
                const SizedBox(height: 8),
                Text(heard.isEmpty ? listening! : heard, textAlign: TextAlign.center, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w500)),
                const SizedBox(height: 6),
                const Text('Tap to cancel', style: TextStyle(fontSize: 12, color: Colors.white70)),
              ])),
            ),
          ),
      ]),
    );
  }
}