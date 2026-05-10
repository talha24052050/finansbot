import 'dart:convert';
import 'dart:math';
import 'package:flutter/foundation.dart' show defaultTargetPlatform, TargetPlatform;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:speech_to_text/speech_to_text.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';

const _apiKey = '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';
const _orModel = 'google/gemini-2.0-flash-001';

// ── Design Tokens ─────────────────────────────────────────────────────────────

const _bg         = Color(0xFF080C14);
const _surface    = Color(0xFF131E2E);
const _surface2   = Color(0xFF0E1626);
const _aiBg       = Color(0xFF141E2C);
const _border     = Color(0xFF1E2D45);
const _borderSoft = Color(0xFF16243A);
const _gold       = Color(0xFFCBAA35);
const _textHi     = Color(0xFFDDE6F5);
const _textMid    = Color(0xFF6B7FA3);
const _text3      = Color(0xFF4A5C7A);
const _userBg     = Color(0xFF0F1D10);
const _userBdr    = Color(0xFF1A3820);
const _green      = Color(0xFF6FCB8B);

const _goldGradient = LinearGradient(
  begin: Alignment.topCenter,
  end: Alignment.bottomCenter,
  colors: [Color(0xFFD9B845), Color(0xFFB89324)],
);

// ── Storage ───────────────────────────────────────────────────────────────────

class Storage {
  static SharedPreferences? _p;
  static Future<SharedPreferences> get _prefs async {
    _p ??= await SharedPreferences.getInstance();
    return _p!;
  }

  static Future<String?> getUserName() async => (await _prefs).getString('user_name');
  static Future<void> setUserName(String v) async => (await _prefs).setString('user_name', v);
  static Future<void> clearUserName() async => (await _prefs).remove('user_name');
  static Future<String> getMemory() async => (await _prefs).getString('user_memory') ?? '';
  static Future<void> setMemory(String v) async => (await _prefs).setString('user_memory', v);

  static Future<Map<String, String?>> getStats() async {
    final raw = (await _prefs).getString('financial_stats');
    if (raw == null) return {};
    return (jsonDecode(raw) as Map<String, dynamic>).map((k, v) => MapEntry(k, v as String?));
  }

  static Future<void> setStats(Map<String, String?> stats) async =>
      (await _prefs).setString('financial_stats', jsonEncode(stats));

  static Future<bool> getScreenshotProtection() async =>
      (await _prefs).getBool('screenshot_protection') ?? false;
  static Future<void> setScreenshotProtection(bool v) async =>
      (await _prefs).setBool('screenshot_protection', v);

  static Future<List<String>> getConvIds() async {
    final raw = (await _prefs).getString('conv_ids');
    if (raw == null) return [];
    return List<String>.from(jsonDecode(raw));
  }

  static Future<void> _saveIds(List<String> ids) async =>
      (await _prefs).setString('conv_ids', jsonEncode(ids));

  static Future<void> addConvId(String id) async {
    final ids = await getConvIds();
    ids.insert(0, id);
    await _saveIds(ids);
  }

  static Future<String> getTitle(String id) async =>
      (await _prefs).getString('conv_title_$id') ?? 'Yeni Sohbet';
  static Future<void> setTitle(String id, String title) async =>
      (await _prefs).setString('conv_title_$id', title);

  static Future<List<Map<String, dynamic>>> getMessages(String id) async {
    final raw = (await _prefs).getString('conv_msgs_$id');
    if (raw == null) return [];
    return List<Map<String, dynamic>>.from(jsonDecode(raw));
  }

  static Future<void> saveMessages(String id, List<Map<String, dynamic>> msgs) async =>
      (await _prefs).setString('conv_msgs_$id', jsonEncode(msgs));

  static Future<void> deleteConv(String id) async {
    final ids = await getConvIds();
    ids.remove(id);
    await _saveIds(ids);
    final p = await _prefs;
    await p.remove('conv_title_$id');
    await p.remove('conv_msgs_$id');
  }
}

// ── Models ────────────────────────────────────────────────────────────────────

class ChatMessage {
  final String text;
  final bool isUser;
  final String time;
  const ChatMessage({required this.text, required this.isUser, this.time = ''});
  Map<String, dynamic> toJson() => {'text': text, 'isUser': isUser, 'time': time};
  factory ChatMessage.fromJson(Map<String, dynamic> j) => ChatMessage(
        text: j['text'] as String,
        isUser: j['isUser'] as bool,
        time: j['time'] as String? ?? '',
      );
}

class ConvMeta {
  final String id;
  final String title;
  const ConvMeta({required this.id, required this.title});
}

// ── App ───────────────────────────────────────────────────────────────────────

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.light,
    systemNavigationBarColor: _bg,
  ));
  runApp(const MainApp());
}

class MainApp extends StatelessWidget {
  const MainApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Finans Asistanı',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        scaffoldBackgroundColor: _bg,
        colorScheme: const ColorScheme.dark(
          primary: _gold,
          onPrimary: Color(0xFF1A1200),
          surface: _surface,
          onSurface: _textHi,
          surfaceContainerHighest: _aiBg,
        ),
        appBarTheme: const AppBarTheme(
          backgroundColor: _bg,
          foregroundColor: _textHi,
          elevation: 0,
          surfaceTintColor: Colors.transparent,
          systemOverlayStyle: SystemUiOverlayStyle(
            statusBarColor: Colors.transparent,
            statusBarIconBrightness: Brightness.light,
          ),
        ),
        drawerTheme: const DrawerThemeData(
          backgroundColor: _surface2,
          surfaceTintColor: Colors.transparent,
        ),
        dividerColor: _border,
        textButtonTheme: TextButtonThemeData(
          style: TextButton.styleFrom(foregroundColor: _gold),
        ),
        dialogTheme: const DialogThemeData(
          backgroundColor: _aiBg,
          surfaceTintColor: Colors.transparent,
          titleTextStyle: TextStyle(color: _textHi, fontSize: 18, fontWeight: FontWeight.w600),
          contentTextStyle: TextStyle(color: _textMid, fontSize: 14, height: 1.6),
        ),
      ),
      home: const SplashPage(),
    );
  }
}

// ── Splash ────────────────────────────────────────────────────────────────────

class SplashPage extends StatefulWidget {
  const SplashPage({super.key});
  @override
  State<SplashPage> createState() => _SplashPageState();
}

class _SplashPageState extends State<SplashPage> {
  @override
  void initState() {
    super.initState();
    _route();
  }

  Future<void> _route() async {
    final name = await Storage.getUserName();
    if (!mounted) return;
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (_) => (name == null || name.isEmpty)
            ? const OnboardingPage()
            : MainPage(userName: name),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Center(child: CircularProgressIndicator(color: _gold, strokeWidth: 2)),
    );
  }
}

// ── Shared Orb Widgets ────────────────────────────────────────────────────────

class _GoldOrb extends StatelessWidget {
  final double size;
  final double iconSize;
  const _GoldOrb({required this.size, required this.iconSize});

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: const RadialGradient(
              center: Alignment(-0.4, -0.5),
              radius: 1.0,
              colors: [
                Color(0xFFF4DC8A),
                Color(0xFFE5C459),
                Color(0xFFCBAA35),
                Color(0xFF8E6F1B),
              ],
              stops: [0.0, 0.24, 0.55, 1.0],
            ),
            boxShadow: const [
              BoxShadow(color: Color(0x40CBAA35), blurRadius: 28, offset: Offset(0, 8)),
            ],
          ),
          child: Icon(Icons.account_balance, size: iconSize, color: const Color(0xFF1A1305)),
        ),
        Positioned.fill(
          child: DecoratedBox(
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: const Alignment(0, 0.4),
                colors: [
                  Colors.white.withValues(alpha: 0.18),
                  Colors.white.withValues(alpha: 0.0),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _GoldOrbFlat extends StatelessWidget {
  final double size;
  final double iconSize;
  const _GoldOrbFlat({required this.size, required this.iconSize});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: _goldGradient,
        boxShadow: const [
          BoxShadow(color: Color(0x4D000000), blurRadius: 6, offset: Offset(0, 2)),
        ],
      ),
      child: Icon(Icons.account_balance, size: iconSize, color: const Color(0xFF1A1305)),
    );
  }
}

// ── Onboarding ────────────────────────────────────────────────────────────────

class OnboardingPage extends StatefulWidget {
  const OnboardingPage({super.key});
  @override
  State<OnboardingPage> createState() => _OnboardingPageState();
}

class _OnboardingPageState extends State<OnboardingPage> {
  final _controller = TextEditingController();
  bool _focused = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final name = _controller.text.trim();
    if (name.isEmpty) return;
    await Storage.setUserName(name);
    if (!mounted) return;
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (_) => MainPage(userName: name)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          Container(color: _bg),
          Positioned(
            top: -80,
            left: 0,
            right: 0,
            child: Container(
              height: 420,
              decoration: BoxDecoration(
                gradient: RadialGradient(
                  center: Alignment.topCenter,
                  radius: 0.9,
                  colors: [_gold.withValues(alpha: 0.10), _gold.withValues(alpha: 0.0)],
                ),
              ),
            ),
          ),
          SafeArea(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 12, 24, 0),
                  child: Row(
                    children: [
                      _GoldOrbFlat(size: 22, iconSize: 12),
                      const SizedBox(width: 8),
                      const Text(
                        'FA',
                        style: TextStyle(
                          color: _text3,
                          fontSize: 9.5,
                          fontWeight: FontWeight.w600,
                          letterSpacing: 2.0,
                        ),
                      ),
                      const Spacer(),
                      const Text(
                        'Türkiye · TR',
                        style: TextStyle(
                          color: _text3,
                          fontSize: 10.5,
                          fontWeight: FontWeight.w600,
                          letterSpacing: 1.4,
                        ),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.symmetric(horizontal: 28),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        const SizedBox(height: 40),
                        _GoldOrb(size: 88, iconSize: 40),
                        const SizedBox(height: 20),
                        const Text(
                          'Finans Asistanı',
                          style: TextStyle(
                            fontSize: 28,
                            fontWeight: FontWeight.w600,
                            color: _textHi,
                            letterSpacing: -0.5,
                          ),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 8),
                        const Text(
                          'Kişisel finansal danışmanınız.\nAnlar, hatırlar, planlar.',
                          style: TextStyle(color: _textMid, fontSize: 14.5, height: 1.5),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 18),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: const [
                            _DotPill('Sizi hatırlar'),
                            SizedBox(width: 8),
                            _DotPill('Akıllı analiz'),
                          ],
                        ),
                        const SizedBox(height: 30),
                        Container(
                          height: 1,
                          decoration: const BoxDecoration(
                            gradient: LinearGradient(
                              colors: [Colors.transparent, _border, Colors.transparent],
                            ),
                          ),
                        ),
                        const SizedBox(height: 26),
                        const Align(
                          alignment: Alignment.centerLeft,
                          child: Text(
                            'ADINIZ',
                            style: TextStyle(
                              color: _textMid,
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              letterSpacing: 1.4,
                            ),
                          ),
                        ),
                        const SizedBox(height: 8),
                        Focus(
                          onFocusChange: (v) => setState(() => _focused = v),
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 150),
                            decoration: BoxDecoration(
                              color: _surface,
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(
                                color: _focused ? _gold.withValues(alpha: 0.7) : _border,
                              ),
                              boxShadow: _focused
                                  ? [
                                      BoxShadow(
                                        color: _gold.withValues(alpha: 0.12),
                                        blurRadius: 0,
                                        spreadRadius: 3,
                                      )
                                    ]
                                  : null,
                            ),
                            child: TextField(
                              controller: _controller,
                              textInputAction: TextInputAction.done,
                              onSubmitted: (_) => _submit(),
                              autofocus: true,
                              style: const TextStyle(color: _textHi, fontSize: 15),
                              decoration: InputDecoration(
                                hintText: 'Örn. Mehmet',
                                hintStyle: const TextStyle(color: _text3),
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(14),
                                  borderSide: BorderSide.none,
                                ),
                                enabledBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(14),
                                  borderSide: BorderSide.none,
                                ),
                                focusedBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(14),
                                  borderSide: BorderSide.none,
                                ),
                                filled: true,
                                fillColor: Colors.transparent,
                                contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 16, vertical: 14,
                                ),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 8),
                        const Align(
                          alignment: Alignment.centerLeft,
                          child: Text(
                            'Bu cihazda saklanır. Verileriniz hiçbir yere gönderilmez.',
                            style: TextStyle(color: _text3, fontSize: 11.5, height: 1.5),
                          ),
                        ),
                        const SizedBox(height: 24),
                        SizedBox(
                          width: double.infinity,
                          height: 52,
                          child: GestureDetector(
                            onTap: _submit,
                            child: Container(
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(14),
                                gradient: _goldGradient,
                                boxShadow: const [
                                  BoxShadow(
                                    color: Color(0x33CBAA35),
                                    blurRadius: 24,
                                    offset: Offset(0, 8),
                                  ),
                                ],
                              ),
                              child: const Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Text(
                                    'Başla',
                                    style: TextStyle(
                                      color: Color(0xFF15110A),
                                      fontSize: 16,
                                      fontWeight: FontWeight.w600,
                                      letterSpacing: 0.2,
                                    ),
                                  ),
                                  SizedBox(width: 8),
                                  Icon(Icons.arrow_forward, size: 16, color: Color(0xFF15110A)),
                                ],
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 16),
                        RichText(
                          textAlign: TextAlign.center,
                          text: const TextSpan(
                            style: TextStyle(color: _text3, fontSize: 11, height: 1.6),
                            children: [
                              TextSpan(text: 'Devam ederek '),
                              TextSpan(
                                text: 'Kullanım Koşulları',
                                style: TextStyle(
                                  color: _textMid,
                                  decoration: TextDecoration.underline,
                                  decorationColor: _textMid,
                                ),
                              ),
                              TextSpan(text: ' ve '),
                              TextSpan(
                                text: 'Gizlilik Politikası',
                                style: TextStyle(
                                  color: _textMid,
                                  decoration: TextDecoration.underline,
                                  decorationColor: _textMid,
                                ),
                              ),
                              TextSpan(text: '\'nı kabul etmiş olursunuz.'),
                            ],
                          ),
                        ),
                        const SizedBox(height: 24),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _DotPill extends StatelessWidget {
  final String label;
  const _DotPill(this.label);

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 6),
      decoration: BoxDecoration(
        color: _surface,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: _border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 5,
            height: 5,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: _gold,
              boxShadow: [BoxShadow(color: _gold.withValues(alpha: 0.7), blurRadius: 6)],
            ),
          ),
          const SizedBox(width: 6),
          Text(
            label,
            style: const TextStyle(
              color: _textMid, fontSize: 12, fontWeight: FontWeight.w500, letterSpacing: 0.2,
            ),
          ),
        ],
      ),
    );
  }
}

// ── Main Page ─────────────────────────────────────────────────────────────────

class MainPage extends StatefulWidget {
  final String userName;
  const MainPage({super.key, required this.userName});
  @override
  State<MainPage> createState() => _MainPageState();
}

class _MainPageState extends State<MainPage> {
  List<ConvMeta> _conversations = [];
  String? _currentId;
  bool _screenshotProtected = false;

  static const _screenshotChannel = MethodChannel('com.example.chatbot/screenshot');

  @override
  void initState() {
    super.initState();
    _loadConversations();
    _loadScreenshotPref();
  }

  Future<void> _loadConversations() async {
    final ids = await Storage.getConvIds();
    final metas = await Future.wait(
      ids.map((id) async => ConvMeta(id: id, title: await Storage.getTitle(id))),
    );
    setState(() {
      _conversations = metas;
      _currentId = null;
    });
  }

  void _newChat() {
    setState(() => _currentId = null);
    Navigator.pop(context);
  }

  void _selectConv(String id) {
    setState(() => _currentId = id);
    Navigator.pop(context);
  }

  void _onConvCreated(String id, String title) {
    setState(() {
      _conversations.insert(0, ConvMeta(id: id, title: title));
      // _currentId is intentionally NOT updated here — ChatArea manages its own
      // _convId and must not be recreated mid-conversation via a key change.
    });
  }

  void _onTitleUpdated(String id, String title) {
    setState(() {
      _conversations = _conversations
          .map((c) => c.id == id ? ConvMeta(id: id, title: title) : c)
          .toList();
    });
    // Persist is handled inside ChatArea before this callback is fired.
  }

  Future<void> _deleteConv(String id) async {
    await Storage.deleteConv(id);
    setState(() {
      _conversations.removeWhere((c) => c.id == id);
      if (_currentId == id) {
        _currentId = _conversations.isNotEmpty ? _conversations.first.id : null;
      }
    });
  }

  Future<void> _showMemory() async {
    final memory = await Storage.getMemory();
    if (!mounted) return;
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.psychology_outlined, color: _gold, size: 20),
            SizedBox(width: 8),
            Text('Hafıza'),
          ],
        ),
        content: SingleChildScrollView(
          child: Text(memory.isEmpty ? 'Henüz bilgi kaydedilmedi.' : memory),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Kapat')),
        ],
      ),
    );
  }

  Future<void> _handleLogout() async {
    await Storage.clearUserName();
    if (!mounted) return;
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (_) => const OnboardingPage()),
    );
  }

  Future<void> _handleRename(String newName) async {
    if (!mounted) return;
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (_) => MainPage(userName: newName)),
    );
  }

  Future<void> _handleClearAll() async {
    final ids = await Storage.getConvIds();
    for (final id in ids) { await Storage.deleteConv(id); }
    if (!mounted) return;
    setState(() { _conversations = []; _currentId = null; });
  }

  Future<void> _loadScreenshotPref() async {
    final protected = await Storage.getScreenshotProtection();
    if (!mounted) return;
    setState(() => _screenshotProtected = protected);
    await _applyScreenshotProtection(protected);
  }

  Future<void> _applyScreenshotProtection(bool protect) async {
    if (defaultTargetPlatform != TargetPlatform.android) return;
    try {
      await _screenshotChannel.invokeMethod(protect ? 'enable' : 'disable');
    } catch (_) {}
  }

  Future<void> _handleScreenshotToggle(bool protect) async {
    await Storage.setScreenshotProtection(protect);
    if (!mounted) return;
    setState(() => _screenshotProtected = protect);
    await _applyScreenshotProtection(protect);
  }

  void _showPrivacyAndAbout() {
    const sectionStyle = TextStyle(
      color: _text3, fontSize: 10.5, fontWeight: FontWeight.w600, letterSpacing: 1.5,
    );
    const commands = [
      ('"adımı [isim] yap"', 'İsminizi değiştirir'),
      ('"hafızamı sil"', 'Öğrenilen bilgileri temizler'),
      ('"tüm sohbetleri sil"', 'Sohbet geçmişini temizler'),
      ('"ekran görüntüsü korumasını aç"', 'Ekran alıntısını engeller'),
      ('"ekran görüntüsü korumasını kapat"', 'Ekran alıntısına izin verir'),
      ('"çıkış yap"', 'Uygulamadan çıkar'),
    ];
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.shield_outlined, color: _gold, size: 20),
            SizedBox(width: 8),
            Text('Gizlilik ve Hakkımda'),
          ],
        ),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('GİZLİLİK', style: sectionStyle),
              const SizedBox(height: 6),
              const Text(
                'Tüm verileriniz yalnızca bu cihazda saklanır. '
                'Sohbet geçmişi, hafıza ve finansal bilgileriniz '
                'hiçbir harici sunucuya gönderilmez.',
              ),
              const SizedBox(height: 16),
              Container(height: 1, color: _border),
              const SizedBox(height: 16),
              const Text('HAKKINDA', style: sectionStyle),
              const SizedBox(height: 6),
              const Text(
                'Finans Asistanı — v0.1.0\n'
                'Kişisel yapay zeka destekli finansal danışmanınız.\n'
                'OpenRouter · Gemini 2.0 Flash',
              ),
              const SizedBox(height: 16),
              Container(height: 1, color: _border),
              const SizedBox(height: 16),
              const Text('CHATBOT KOMUTLARI', style: sectionStyle),
              const SizedBox(height: 6),
              const Text(
                'Asistana yazarak aşağıdaki ayarları değiştirebilirsiniz:',
                style: TextStyle(color: _textMid, fontSize: 12.5),
              ),
              const SizedBox(height: 10),
              ...commands.map(
                (e) => Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        width: 5, height: 5,
                        margin: const EdgeInsets.only(top: 5),
                        decoration: const BoxDecoration(shape: BoxShape.circle, color: _gold),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: RichText(
                          text: TextSpan(
                            style: const TextStyle(fontSize: 13, height: 1.4),
                            children: [
                              TextSpan(
                                text: '${e.$1}  ',
                                style: const TextStyle(color: _textHi, fontWeight: FontWeight.w500),
                              ),
                              TextSpan(
                                text: e.$2,
                                style: const TextStyle(color: _textMid),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Kapat'),
          ),
        ],
      ),
    );
  }

  String get _initials {
    final parts = widget.userName.trim().split(' ');
    if (parts.length >= 2) return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
    return widget.userName.substring(0, min(2, widget.userName.length)).toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: _bg,
        surfaceTintColor: Colors.transparent,
        leading: Builder(
          builder: (ctx) => IconButton(
            icon: const Icon(Icons.menu, color: _textMid),
            onPressed: () => Scaffold.of(ctx).openDrawer(),
          ),
        ),
        title: Row(
          children: [
            _GoldOrbFlat(size: 32, iconSize: 17),
            const SizedBox(width: 10),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'Finans Asistanı',
                  style: TextStyle(
                    fontWeight: FontWeight.w600, fontSize: 16, color: _textHi, letterSpacing: -0.1,
                  ),
                ),
                Row(
                  children: [
                    Container(
                      width: 5,
                      height: 5,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: _green,
                        boxShadow: [BoxShadow(color: _green.withValues(alpha: 0.7), blurRadius: 6)],
                      ),
                    ),
                    const SizedBox(width: 5),
                    const Text(
                      'ÇEVRİMİÇİ · BAĞLAMLI',
                      style: TextStyle(
                        color: _gold, fontSize: 9, fontWeight: FontWeight.w600, letterSpacing: 0.8,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.psychology_outlined, color: _gold),
            onPressed: _showMemory,
            tooltip: 'Hafıza',
          ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(height: 1, color: _borderSoft),
        ),
      ),
      drawer: _buildDrawer(),
      body: ChatArea(
        key: ValueKey(_currentId),
        userName: widget.userName,
        conversationId: _currentId,
        screenshotProtected: _screenshotProtected,
        onConvCreated: _onConvCreated,
        onTitleUpdated: _onTitleUpdated,
        onScreenshotToggle: _handleScreenshotToggle,
        onLogout: _handleLogout,
        onRename: _handleRename,
        onClearAll: _handleClearAll,
      ),
    );
  }

  Widget _buildDrawer() {
    return Theme(
      data: Theme.of(context).copyWith(
        drawerTheme: DrawerThemeData(
          backgroundColor: _surface2,
          surfaceTintColor: Colors.transparent,
          width: MediaQuery.of(context).size.width * 0.84,
        ),
      ),
      child: Drawer(
        child: Column(
          children: [
            Container(
              width: double.infinity,
              padding: EdgeInsets.only(
                top: MediaQuery.of(context).padding.top + 20,
                left: 18,
                right: 18,
                bottom: 18,
              ),
              decoration: const BoxDecoration(
                border: Border(bottom: BorderSide(color: _borderSoft)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 44,
                        height: 44,
                        decoration: const BoxDecoration(
                          shape: BoxShape.circle,
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [Color(0xFFE5C459), Color(0xFFB89324)],
                          ),
                        ),
                        child: Center(
                          child: Text(
                            _initials,
                            style: const TextStyle(
                              color: Color(0xFF1A1305),
                              fontWeight: FontWeight.w600,
                              fontSize: 15,
                              letterSpacing: 0.5,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              widget.userName,
                              style: const TextStyle(
                                color: _textHi, fontWeight: FontWeight.w600, fontSize: 15,
                              ),
                            ),
                            Text(
                              _conversations.isEmpty
                                  ? 'Yeni kullanıcı'
                                  : '${_conversations.length} sohbet',
                              style: const TextStyle(color: _textMid, fontSize: 12),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  GestureDetector(
                    onTap: _newChat,
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 14),
                      decoration: BoxDecoration(
                        color: Colors.transparent,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: _gold.withValues(alpha: 0.45)),
                      ),
                      child: const Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.add, color: _gold, size: 16),
                          SizedBox(width: 8),
                          Text(
                            'Yeni Sohbet',
                            style: TextStyle(
                              color: _gold, fontWeight: FontWeight.w500, fontSize: 14,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 18, 18, 10),
              child: Row(
                children: [
                  const Text(
                    'GEÇMİŞ',
                    style: TextStyle(
                      color: _text3, fontSize: 10.5, fontWeight: FontWeight.w600, letterSpacing: 2.0,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Container(
                      height: 1,
                      decoration: const BoxDecoration(
                        gradient: LinearGradient(colors: [_border, Colors.transparent]),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: _conversations.isEmpty
                  ? const Center(
                      child: Text(
                        'Henüz sohbet yok',
                        style: TextStyle(color: _textMid, fontSize: 13),
                      ),
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      itemCount: _conversations.length,
                      itemBuilder: (_, i) {
                        final conv = _conversations[i];
                        final selected = conv.id == _currentId;
                        return Container(
                          margin: const EdgeInsets.symmetric(vertical: 2),
                          decoration: selected
                              ? BoxDecoration(
                                  borderRadius: BorderRadius.circular(12),
                                  gradient: const LinearGradient(
                                    colors: [Color(0x1ACBAA35), Color(0x05CBAA35)],
                                  ),
                                  border: Border.all(color: _gold.withValues(alpha: 0.25)),
                                )
                              : null,
                          child: InkWell(
                            borderRadius: BorderRadius.circular(12),
                            onTap: () => _selectConv(conv.id),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
                              child: Row(
                                children: [
                                  Container(
                                    width: 32,
                                    height: 32,
                                    decoration: BoxDecoration(
                                      color: _surface,
                                      borderRadius: BorderRadius.circular(9),
                                      border: Border.all(
                                        color: selected ? _gold.withValues(alpha: 0.25) : _border,
                                      ),
                                    ),
                                    child: Icon(
                                      Icons.chat_bubble_outline,
                                      size: 15,
                                      color: selected ? _gold : _textMid,
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Text(
                                      conv.title,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        color: selected ? _gold : _textHi,
                                        fontSize: 13.5,
                                        fontWeight: selected ? FontWeight.w500 : FontWeight.normal,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 4),
                                  GestureDetector(
                                    onTap: () => _deleteConv(conv.id),
                                    child: const Icon(Icons.delete_outline, size: 15, color: _text3),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        );
                      },
                    ),
            ),
            Container(
              decoration: const BoxDecoration(
                border: Border(top: BorderSide(color: _borderSoft)),
              ),
              child: InkWell(
                onTap: () {
                  Navigator.pop(context);
                  _showPrivacyAndAbout();
                },
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
                  child: Row(
                    children: [
                      const Icon(Icons.shield_outlined, color: _textMid, size: 18),
                      const SizedBox(width: 12),
                      const Text(
                        'Gizlilik ve Hakkımda',
                        style: TextStyle(color: _textMid, fontSize: 13.5),
                      ),
                      const Spacer(),
                      const Icon(Icons.chevron_right, color: _text3, size: 16),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Chat Area ─────────────────────────────────────────────────────────────────

class ChatArea extends StatefulWidget {
  final String userName;
  final String? conversationId;
  final bool screenshotProtected;
  final void Function(String id, String title) onConvCreated;
  final void Function(String id, String title)? onTitleUpdated;
  final void Function(bool)? onScreenshotToggle;
  final VoidCallback? onLogout;
  final void Function(String newName)? onRename;
  final VoidCallback? onClearAll;

  const ChatArea({
    super.key,
    required this.userName,
    required this.conversationId,
    this.screenshotProtected = false,
    required this.onConvCreated,
    this.onTitleUpdated,
    this.onScreenshotToggle,
    this.onLogout,
    this.onRename,
    this.onClearAll,
  });

  @override
  State<ChatArea> createState() => _ChatAreaState();
}

class _ChatAreaState extends State<ChatArea> {
  final _textController = TextEditingController();
  final _scrollController = ScrollController();
  final _speech = SpeechToText();
  List<ChatMessage> _messages = [];
  bool _isLoading = false;
  bool _isListening = false;
  List<Map<String, dynamic>> _chatHistory = [];
  String _memory = '';
  String? _convId;
  DateTime _lastRender = DateTime.fromMillisecondsSinceEpoch(0);
  Map<String, String?> _stats = {};

  @override
  void initState() {
    super.initState();
    _convId = widget.conversationId;
    _init();
  }

  @override
  void dispose() {
    _textController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _init() async {
    _memory = await Storage.getMemory();
    _stats = await Storage.getStats();
    if (_convId != null) {
      final raw = await Storage.getMessages(_convId!);
      if (mounted) {
        setState(() => _messages = raw.map(ChatMessage.fromJson).toList());
      }
    }
    _buildHistory();
    WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBottom());
  }

  String get _systemPrompt => '''
Sen "Finans Asistanı" adlı bir yapay zeka finansal danışmansın.
Türkçe konuşuyorsun. Kullanıcının adı: ${widget.userName}.

Kullanıcı hakkında bildiklerin:
${_memory.isEmpty ? 'Henüz bilgi yok, konuşurken öğreneceksin.' : _memory}

Görevin:
- Bütçe yönetimi, yatırım, tasarruf, borç, emeklilik planlaması gibi finansal konularda uzman tavsiyeler ver.
- Kullanıcıyı tanıyorsun, geçmiş bilgilerini hatırlıyorsun ve konuşmada bunlara atıfta bulun.
- Samimi, teşvik edici ama profesyonel bir ton kullan.
- Finansal kararlar için somut, uygulanabilir öneriler sun.
- Gerektiğinde daha fazla bilgi iste (gelir, gider, hedef vb.).

Mevcut ayarlar:
- Ekran görüntüsü koruması: ${widget.screenshotProtected ? 'aktif ✓' : 'pasif ✗'}

Sistem işlemleri:
Kullanıcı aşağıdaki işlemleri açıkça isterse, yanıtının EN SONUNA (başka hiçbir yere değil) ilgili etiketi ekle:
- Adını değiştirmek isterse (örn. "adımı X yap", "ismimi X olarak değiştir") → [ACTION:rename:YeniAd]
- Hafızayı sıfırlamak isterse (örn. "hafızamı sil", "beni unut") → [ACTION:clear_memory]
- Tüm sohbetleri silmek isterse → [ACTION:clear_all]
- Çıkış yapmak isterse (örn. "çıkış yap", "hesabı sıfırla") → [ACTION:logout]
- Ekran görüntüsü korumasını açmak isterse → [ACTION:screenshot_on]
- Ekran görüntüsü korumasını kapatmak isterse → [ACTION:screenshot_off]
Etiketleri kullanıcıya gösterme, sadece sistem okur. Onay almadan işlem yapma — önce onayla, sonra etiketi ekle.
''';

  void _buildHistory() {
    _chatHistory = [
      {'role': 'system', 'content': _systemPrompt},
    ];
    for (final msg in _messages.where((m) => m.text.isNotEmpty)) {
      _chatHistory.add({'role': msg.isUser ? 'user' : 'assistant', 'content': msg.text});
    }
  }

  Stream<String> _streamCompletion(List<Map<String, dynamic>> messages) async* {
    final client = http.Client();
    try {
      final request = http.Request(
        'POST',
        Uri.parse('https://openrouter.ai/api/v1/chat/completions'),
      );
      request.headers['Authorization'] = 'Bearer $_apiKey';
      request.headers['Content-Type'] = 'application/json';
      request.body = jsonEncode({'model': _orModel, 'messages': messages, 'stream': true});
      final resp = await client.send(request);
      final lines = resp.stream.transform(utf8.decoder).transform(const LineSplitter());
      await for (final line in lines) {
        if (!line.startsWith('data: ')) continue;
        final data = line.substring(6).trim();
        if (data == '[DONE]') break;
        try {
          final parsed = jsonDecode(data) as Map<String, dynamic>;
          final delta = (parsed['choices'] as List?)
              ?.firstOrNull?['delta']?['content'] as String?;
          if (delta != null && delta.isNotEmpty) yield delta;
        } catch (_) {}
      }
    } finally {
      client.close();
    }
  }

  String get _nowTime {
    final now = DateTime.now();
    return '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}';
  }

  Future<void> _sendMessage([String? presetText]) async {
    final text = presetText ?? _textController.text.trim();
    if (text.isEmpty || _isLoading) return;
    _textController.clear();
    final time = _nowTime;

    if (_convId == null) {
      final id = DateTime.now().millisecondsSinceEpoch.toString();
      _convId = id;
      await Storage.addConvId(id);
      await Storage.setTitle(id, 'Yeni Sohbet');
      widget.onConvCreated(id, 'Yeni Sohbet');
    }

    setState(() {
      _messages.add(ChatMessage(text: text, isUser: true, time: time));
      _isLoading = true;
      _messages.add(const ChatMessage(text: '', isUser: false));
    });
    _scrollToBottom();

    _chatHistory.add({'role': 'user', 'content': text});

    try {
      final stream = _streamCompletion(_chatHistory);
      String fullReply = '';
      await for (final delta in stream) {
        if (!mounted) return;
        fullReply += delta;
        final now = DateTime.now();
        if (now.difference(_lastRender).inMilliseconds >= 50) {
          _lastRender = now;
          setState(() {
            _messages[_messages.length - 1] =
                ChatMessage(text: _stripActions(fullReply), isUser: false, time: _nowTime);
          });
          _scrollToBottom();
        }
      }
      final actionMatch = _actionRegex.firstMatch(fullReply);
      final displayReply = _stripActions(fullReply);
      if (mounted) {
        setState(() {
          _messages[_messages.length - 1] =
              ChatMessage(text: displayReply, isUser: false, time: _nowTime);
        });
      }
      _chatHistory.add({'role': 'assistant', 'content': displayReply});
      await _save();
      _updateMemory(userMessage: text, aiReply: displayReply);
      _updateStats(userMessage: text, aiReply: displayReply);
      if (_messages.where((m) => m.isUser).length == 1) {
        _generateTitle(userMessage: text, aiReply: displayReply);
      }
      if (actionMatch != null) _handleAction(actionMatch.group(1)!);
    } catch (e) {
      if (!mounted) return;
      _chatHistory.removeLast();
      setState(() {
        _messages[_messages.length - 1] =
            ChatMessage(text: 'Hata: $e', isUser: false, time: _nowTime);
      });
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
        _scrollToBottom();
      }
    }
  }

  Future<void> _save() async {
    if (_convId == null) return;
    final json = _messages.where((m) => m.text.isNotEmpty).map((m) => m.toJson()).toList();
    await Storage.saveMessages(_convId!, json);
  }

  Future<void> _updateMemory({required String userMessage, required String aiReply}) async {
    try {
      final current = await Storage.getMemory();
      final resp = await http.post(
        Uri.parse('https://openrouter.ai/api/v1/chat/completions'),
        headers: {
          'Authorization': 'Bearer $_apiKey',
          'Content-Type': 'application/json',
        },
        body: jsonEncode({
          'model': _orModel,
          'messages': [
            {
              'role': 'user',
              'content': 'Aşağıdaki konuşmadan kullanıcı (${widget.userName}) hakkında öğrenilen finansal bilgileri çıkar.\n'
                  'Mevcut hafıza ile birleştir ve güncelle. Sadece özet paragraf yaz, başka bir şey yazma.\n\n'
                  'Mevcut hafıza:\n${current.isEmpty ? '(boş)' : current}\n\n'
                  'Yeni konuşma:\nKullanıcı: $userMessage\nAsistan: $aiReply\n\n'
                  'Güncellenmiş özet (Türkçe, kısa ve öz):',
            }
          ],
        }),
      );
      final json = jsonDecode(resp.body) as Map<String, dynamic>;
      final choices = json['choices'] as List?;
      final newMemory = choices?.firstOrNull?['message']?['content'] as String?;
      if (newMemory != null && newMemory.trim().isNotEmpty) {
        _memory = newMemory.trim();
        await Storage.setMemory(_memory);
      }
    } catch (_) {}
  }

  Future<void> _generateTitle({required String userMessage, required String aiReply}) async {
    if (_convId == null) return;
    try {
      final resp = await http.post(
        Uri.parse('https://openrouter.ai/api/v1/chat/completions'),
        headers: {'Authorization': 'Bearer $_apiKey', 'Content-Type': 'application/json'},
        body: jsonEncode({
          'model': _orModel,
          'messages': [
            {
              'role': 'user',
              'content':
                  'Aşağıdaki sohbet için kısa ve açıklayıcı bir başlık üret (en fazla 5-6 kelime, Türkçe). '
                  'Sadece başlığı yaz, başka hiçbir şey ekleme.\n\n'
                  'Kullanıcı: $userMessage\nAsistan: $aiReply',
            }
          ],
        }),
      );
      final decoded = jsonDecode(resp.body) as Map<String, dynamic>;
      final raw = (decoded['choices'] as List?)?.firstOrNull?['message']?['content'] as String?;
      if (raw == null || raw.trim().isEmpty) return;
      final title = raw.trim().replaceAll('"', '').replaceAll("'", '');
      await Storage.setTitle(_convId!, title);
      widget.onTitleUpdated?.call(_convId!, title);
    } catch (_) {}
  }

  static final _actionRegex = RegExp(r'\[ACTION:([^\]]+)\]');

  String _stripActions(String text) =>
      text.replaceAll(_actionRegex, '').trim();

  Future<void> _handleAction(String action) async {
    if (action == 'logout') {
      widget.onLogout?.call();
    } else if (action == 'clear_memory') {
      await Storage.setMemory('');
      if (mounted) setState(() => _memory = '');
      _buildHistory();
    } else if (action == 'clear_all') {
      widget.onClearAll?.call();
    } else if (action.startsWith('rename:')) {
      final newName = action.substring(7).trim();
      if (newName.isNotEmpty) {
        await Storage.setUserName(newName);
        widget.onRename?.call(newName);
      }
    } else if (action == 'screenshot_on') {
      widget.onScreenshotToggle?.call(true);
    } else if (action == 'screenshot_off') {
      widget.onScreenshotToggle?.call(false);
    }
  }

  Future<void> _updateStats({required String userMessage, required String aiReply}) async {
    try {
      final resp = await http.post(
        Uri.parse('https://openrouter.ai/api/v1/chat/completions'),
        headers: {'Authorization': 'Bearer $_apiKey', 'Content-Type': 'application/json'},
        body: jsonEncode({
          'model': _orModel,
          'messages': [
            {
              'role': 'user',
              'content':
                  'Aşağıdaki konuşmadan finansal rakamları çıkar.\n'
                  'Kullanıcı net bakiyesinden, aylık harcamasından veya toplam birikiminden bahsettiyse değerleri döndür.\n'
                  'Mevcut değerler: ${jsonEncode(_stats)}\n'
                  'Konuşma:\nKullanıcı: $userMessage\nAsistan: $aiReply\n\n'
                  'Sadece kesin söylenen rakamları dahil et. Tahmini veya belirsiz değerleri dahil etme.\n'
                  'Yanıtı sadece JSON olarak ver, başka hiçbir şey yazma.\n'
                  'Format: {"balance":"₺ 50.000","spending":"₺ 8.000","savings":"₺ 15.000"}\n'
                  'Bilinen alanı yoksa boş JSON {} döndür.',
            }
          ],
        }),
      );
      final decoded = jsonDecode(resp.body) as Map<String, dynamic>;
      final content =
          (decoded['choices'] as List?)?.firstOrNull?['message']?['content'] as String?;
      if (content == null) return;
      final jsonStr =
          content.trim().replaceAll('```json', '').replaceAll('```', '').trim();
      final extracted = jsonDecode(jsonStr) as Map<String, dynamic>;
      if (extracted.isEmpty) return;
      final newStats = Map<String, String?>.from(_stats);
      extracted.forEach((k, v) {
        if (v != null) newStats[k] = v.toString();
      });
      if (mounted) setState(() => _stats = newStats);
      await Storage.setStats(newStats);
    } catch (_) {}
  }

  Future<void> _toggleMic() async {
    if (_isListening) {
      await _speech.stop();
      setState(() => _isListening = false);
      return;
    }
    final available = await _speech.initialize(
      onError: (_) { if (mounted) setState(() => _isListening = false); },
      onStatus: (s) { if ((s == 'notListening' || s == 'done') && mounted) setState(() => _isListening = false); },
    );
    if (!available || !mounted) return;
    setState(() => _isListening = true);
    await _speech.listen(
      onResult: (r) { if (mounted) setState(() => _textController.text = r.recognizedWords); },
      localeId: 'tr_TR',
    );
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final showChipsRow = _messages.isNotEmpty && _messages.length <= 3 && !_isLoading;
    return Column(
      children: [
        _StatsRow(stats: _stats),
        Expanded(
          child: _messages.isEmpty
              ? _EmptyState(userName: widget.userName, memory: _memory, onChipTap: (t) => _sendMessage(t))
              : ListView.builder(
                  controller: _scrollController,
                  padding: const EdgeInsets.fromLTRB(14, 18, 14, 14),
                  itemCount: _messages.length + 1,
                  itemBuilder: (_, i) {
                    if (i == 0) return const _DateSeparator();
                    return _MessageBubble(message: _messages[i - 1]);
                  },
                ),
        ),
        if (showChipsRow) _SuggestionChipsRow(onTap: (t) => _sendMessage(t)),
        _InputBar(
          controller: _textController,
          onSend: () => _sendMessage(),
          onMic: _toggleMic,
          isLoading: _isLoading,
          isListening: _isListening,
        ),
      ],
    );
  }
}

// ── Stats Row ─────────────────────────────────────────────────────────────────

class _StatsRow extends StatelessWidget {
  final Map<String, String?> stats;
  const _StatsRow({required this.stats});

  @override
  Widget build(BuildContext context) {
    final entries = <({String label, String value, bool isUp})>[];
    if (stats['balance'] != null) entries.add((label: 'Bakiye', value: stats['balance']!, isUp: true));
    if (stats['spending'] != null) entries.add((label: 'Harcama', value: stats['spending']!, isUp: false));
    if (stats['savings'] != null) entries.add((label: 'Birikim', value: stats['savings']!, isUp: true));

    if (entries.isEmpty) return const SizedBox.shrink();

    final children = <Widget>[];
    for (var i = 0; i < entries.length; i++) {
      if (i > 0) children.add(const SizedBox(width: 8));
      children.add(Expanded(
        child: _StatCard(label: entries[i].label, value: entries[i].value, isUp: entries[i].isUp),
      ));
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 0),
      child: Row(children: children),
    );
  }
}

class _StatCard extends StatelessWidget {
  final String label;
  final String value;
  final bool isUp;
  const _StatCard({required this.label, required this.value, required this.isUp});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: _surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label.toUpperCase(),
            style: const TextStyle(
              color: _text3, fontSize: 9.5, fontWeight: FontWeight.w600, letterSpacing: 1.4,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: const TextStyle(color: _textHi, fontSize: 13, fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }
}

// ── Date Separator ────────────────────────────────────────────────────────────

class _DateSeparator extends StatelessWidget {
  const _DateSeparator();

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final t = '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}';
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Expanded(child: Container(height: 1, color: _borderSoft)),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Text(
              'Bugün · $t',
              style: const TextStyle(
                color: _text3, fontSize: 10.5, fontWeight: FontWeight.w500, letterSpacing: 1.4,
              ),
            ),
          ),
          Expanded(child: Container(height: 1, color: _borderSoft)),
        ],
      ),
    );
  }
}

// ── Empty State ───────────────────────────────────────────────────────────────

class _EmptyState extends StatelessWidget {
  final String userName;
  final String memory;
  final void Function(String) onChipTap;
  const _EmptyState({required this.userName, required this.memory, required this.onChipTap});

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 20),
            _GoldOrb(size: 72, iconSize: 34),
            const SizedBox(height: 20),
            Text(
              memory.isEmpty ? 'Merhaba, $userName' : 'Tekrar hoş geldin, $userName',
              style: const TextStyle(
                fontSize: 22, fontWeight: FontWeight.w700, color: _textHi, letterSpacing: -0.3,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              memory.isEmpty
                  ? 'Finansal hedeflerinize ulaşmanıza\nyardımcı olmaya hazırım.'
                  : 'Finansal durumunuzu takip ediyorum.\nSize nasıl yardımcı olabilirim?',
              textAlign: TextAlign.center,
              style: const TextStyle(color: _textMid, fontSize: 14, height: 1.6),
            ),
            const SizedBox(height: 28),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              alignment: WrapAlignment.center,
              children: memory.isEmpty ? [
                _SuggChip('Bütçe planı oluştur', Icons.pie_chart_outline, onChipTap),
                _SuggChip('Birikim için öneri ver', Icons.trending_up, onChipTap),
                _SuggChip('Finansal hedef belirle', Icons.flag_outlined, onChipTap),
                _SuggChip('Emeklilik planı yap', Icons.savings_outlined, onChipTap),
              ] : [
                _SuggChip('Bu ay harcama durumum', Icons.pie_chart_outline, onChipTap),
                _SuggChip('Birikim önerileri', Icons.trending_up, onChipTap),
                _SuggChip('Finansal özet ver', Icons.summarize_outlined, onChipTap),
                _SuggChip('Hedeflerime ne kadar kaldı?', Icons.flag_outlined, onChipTap),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _SuggChip extends StatelessWidget {
  final String label;
  final IconData icon;
  final void Function(String) onTap;
  const _SuggChip(this.label, this.icon, this.onTap);

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => onTap(label),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: _surface,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: _border),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 13, color: _gold),
            const SizedBox(width: 6),
            Text(label, style: const TextStyle(color: _textHi, fontSize: 12.5, letterSpacing: 0.1)),
          ],
        ),
      ),
    );
  }
}

// ── Chips Row ─────────────────────────────────────────────────────────────────

class _SuggestionChipsRow extends StatelessWidget {
  final void Function(String) onTap;
  const _SuggestionChipsRow({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 42,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 14),
        children: [
          _InlineChip('Bu ay harcamam', Icons.pie_chart_outline, onTap),
          const SizedBox(width: 8),
          _InlineChip('Birikim önerisi', Icons.trending_up, onTap),
          const SizedBox(width: 8),
          _InlineChip('Kart borcu', Icons.credit_card_outlined, onTap),
        ],
      ),
    );
  }
}

class _InlineChip extends StatelessWidget {
  final String label;
  final IconData icon;
  final void Function(String) onTap;
  const _InlineChip(this.label, this.icon, this.onTap);

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => onTap(label),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: _surface,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: _border),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 13, color: _gold),
            const SizedBox(width: 6),
            Text(label, style: const TextStyle(color: _textHi, fontSize: 12.5)),
          ],
        ),
      ),
    );
  }
}

// ── Message Bubble ────────────────────────────────────────────────────────────

class _MessageBubble extends StatelessWidget {
  final ChatMessage message;
  const _MessageBubble({required this.message});

  @override
  Widget build(BuildContext context) {
    if (!message.isUser && message.text.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            _GoldOrbFlat(size: 28, iconSize: 13),
            const SizedBox(width: 10),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: _aiBg,
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(18),
                  topRight: Radius.circular(18),
                  bottomLeft: Radius.circular(6),
                  bottomRight: Radius.circular(18),
                ),
                border: Border.all(color: _border),
              ),
              child: const _TypingDots(),
            ),
          ],
        ),
      );
    }

    if (message.isUser) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.end,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Flexible(
              child: Container(
                constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.72),
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                decoration: BoxDecoration(
                  color: _userBg,
                  borderRadius: const BorderRadius.only(
                    topLeft: Radius.circular(18),
                    topRight: Radius.circular(18),
                    bottomLeft: Radius.circular(18),
                    bottomRight: Radius.circular(6),
                  ),
                  border: Border.all(color: _userBdr),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      message.text,
                      style: const TextStyle(color: _textHi, fontSize: 14.5, height: 1.5),
                    ),
                    if (message.time.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        '${message.time} · okundu',
                        style: const TextStyle(color: _text3, fontSize: 10.5, letterSpacing: 0.3),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          _GoldOrbFlat(size: 28, iconSize: 13),
          const SizedBox(width: 10),
          Flexible(
            child: Container(
              constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.78),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                color: _aiBg,
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(18),
                  topRight: Radius.circular(18),
                  bottomLeft: Radius.circular(6),
                  bottomRight: Radius.circular(18),
                ),
                border: Border.all(color: _border),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  MarkdownBody(
                    data: message.text,
                    selectable: true,
                    styleSheet: MarkdownStyleSheet(
                      p: const TextStyle(color: _textHi, fontSize: 14.5, height: 1.6),
                      strong: const TextStyle(color: _textHi, fontSize: 14.5, fontWeight: FontWeight.bold),
                      em: const TextStyle(color: _textHi, fontSize: 14.5, fontStyle: FontStyle.italic),
                      h1: const TextStyle(color: _textHi, fontSize: 20, fontWeight: FontWeight.bold, height: 1.4),
                      h2: const TextStyle(color: _textHi, fontSize: 17.5, fontWeight: FontWeight.bold, height: 1.4),
                      h3: const TextStyle(color: _textHi, fontSize: 15.5, fontWeight: FontWeight.w600, height: 1.4),
                      code: const TextStyle(color: _gold, fontSize: 13, fontFamily: 'monospace'),
                      codeblockDecoration: BoxDecoration(
                        color: Color(0xFF1A1A2E),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: _border),
                      ),
                      blockquoteDecoration: const BoxDecoration(
                        border: Border(left: BorderSide(color: _gold, width: 3)),
                        color: Color(0x11D4AF37),
                      ),
                      listBullet: const TextStyle(color: _gold, fontSize: 14.5),
                    ),
                  ),
                  if (message.time.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      message.time,
                      style: const TextStyle(color: _text3, fontSize: 10.5, letterSpacing: 0.3),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Typing Dots ───────────────────────────────────────────────────────────────

class _TypingDots extends StatefulWidget {
  const _TypingDots();
  @override
  State<_TypingDots> createState() => _TypingDotsState();
}

class _TypingDotsState extends State<_TypingDots> with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 1200))
      ..repeat();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (_, _) {
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: List.generate(3, (i) {
            final phase = (_ctrl.value * 3 - i).clamp(0.0, 1.0);
            final dy = sin(phase * pi) * -4.0;
            final opacity = 0.35 + sin(phase * pi) * 0.65;
            return Transform.translate(
              offset: Offset(0, dy),
              child: Container(
                margin: const EdgeInsets.symmetric(horizontal: 3),
                width: 6,
                height: 6,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: _gold.withValues(alpha: opacity),
                ),
              ),
            );
          }),
        );
      },
    );
  }
}

// ── Input Bar ─────────────────────────────────────────────────────────────────

class _InputBar extends StatelessWidget {
  final TextEditingController controller;
  final VoidCallback onSend;
  final VoidCallback onMic;
  final bool isLoading;
  final bool isListening;

  const _InputBar({
    required this.controller,
    required this.onSend,
    required this.onMic,
    required this.isLoading,
    required this.isListening,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: _bg,
        border: Border(top: BorderSide(color: _borderSoft, width: 1)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 14),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: Container(
                  constraints: const BoxConstraints(minHeight: 44),
                  decoration: BoxDecoration(
                    color: _surface,
                    borderRadius: BorderRadius.circular(22),
                    border: Border.all(color: _border),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Expanded(
                        child: TextField(
                          controller: controller,
                          textInputAction: TextInputAction.send,
                          onSubmitted: (_) => onSend(),
                          maxLines: null,
                          style: const TextStyle(color: _textHi, fontSize: 14.5),
                          decoration: InputDecoration(
                            hintText: 'Asistana yazın…',
                            hintStyle: const TextStyle(color: _text3, fontSize: 14.5),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(22),
                              borderSide: BorderSide.none,
                            ),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(22),
                              borderSide: BorderSide.none,
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(22),
                              borderSide: BorderSide.none,
                            ),
                            filled: true,
                            fillColor: Colors.transparent,
                            contentPadding: const EdgeInsets.symmetric(horizontal: 4, vertical: 12),
                          ),
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.only(right: 4, bottom: 4),
                        child: _IconBtn(
                          icon: isListening ? Icons.mic : Icons.mic_none,
                          size: 18,
                          onTap: onMic,
                          color: isListening ? _gold : _textMid,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 10),
              GestureDetector(
                onTap: isLoading ? null : onSend,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: isLoading ? null : _goldGradient,
                    color: isLoading ? _surface : null,
                    boxShadow: isLoading
                        ? null
                        : const [
                            BoxShadow(
                              color: Color(0x40CBAA35), blurRadius: 8, offset: Offset(0, 2),
                            ),
                          ],
                  ),
                  child: Icon(
                    Icons.arrow_upward,
                    color: isLoading ? _textMid : const Color(0xFF15110A),
                    size: 18,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _IconBtn extends StatelessWidget {
  final IconData icon;
  final double size;
  final VoidCallback onTap;
  final Color color;
  const _IconBtn({required this.icon, required this.size, required this.onTap, this.color = _textMid});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: SizedBox(
        width: 36,
        height: 36,
        child: Icon(icon, size: size, color: color),
      ),
    );
  }
}
