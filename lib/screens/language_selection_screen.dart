import 'dart:async';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:google_fonts/google_fonts.dart';

import 'home_screen.dart';
import '../providers/app_state_provider.dart';
import '../providers/accessibility_provider.dart';
import '../services/voice_assistant_service.dart';
import '../voice_system/application/language_manager.dart';
import '../voice_system/application/voice_command_orchestrator.dart';
import '../voice_system/data/repositories/heuristic_voice_intent_repository.dart';
import '../utils/accessibility_utils.dart';
import '../theme/app_style.dart';
import '../widgets/ambient_background.dart';

class LanguageSelectionScreen extends StatefulWidget {
  const LanguageSelectionScreen({super.key});

  @override
  State<LanguageSelectionScreen> createState() => _LanguageSelectionScreenState();
}

class _LanguageSelectionScreenState extends State<LanguageSelectionScreen> {
  bool _listening = false;

  /// Веб прелистувачите (Chrome итн.) НЕ дозволуваат звук ниту микрофон пред
  /// корисникот прво да допре нешто на страницата („autoplay“ правило). Затоа
  /// на веб, при прво отворање, се чека еден допир / копче - тој допир го
  /// „отклучува“ звукот, па веднаш се пушта воведот. На телефон ова не е
  /// потребно и воведот почнува сам.
  static bool _webAudioUnlocked = false;
  late bool _awaitingFirstTap = kIsWeb && !_webAudioUnlocked;
  final FocusNode _unlockFocus = FocusNode();

  @override
  void initState() {
    super.initState();
    if (!_awaitingFirstTap) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _playExplanation());
    }
  }

  @override
  void dispose() {
    _unlockFocus.dispose();
    super.dispose();
  }

  void _unlockAndStart() {
    if (!_awaitingFirstTap) return;
    _webAudioUnlocked = true;
    setState(() => _awaitingFirstTap = false);
    _playExplanation(delay: Duration.zero);
  }

  /// Цел екран „допри било каде“ - само на веб, пред првиот допир.
  Widget _buildUnlockOverlay() {
    const text = 'Допри било каде за да започнеш\nTap anywhere to start\nPrek kudo për të filluar';
    return Positioned.fill(
      child: Material(
        type: MaterialType.transparency,
        child: Focus(
        focusNode: _unlockFocus,
        autofocus: true,
        onKeyEvent: (node, event) {
          if (event is KeyDownEvent) {
            _unlockAndStart();
            return KeyEventResult.handled;
          }
          return KeyEventResult.ignored;
        },
        child: Semantics(
          button: true,
          label: text,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: _unlockAndStart,
            child: Container(
              color: Colors.black.withValues(alpha: 0.82),
              alignment: Alignment.center,
              padding: const EdgeInsets.all(32),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.touch_app_rounded, color: Colors.white, size: 120),
                  const SizedBox(height: 28),
                  Text(
                    text,
                    textAlign: TextAlign.center,
                    style: GoogleFonts.lexend(
                      fontSize: 26,
                      fontWeight: FontWeight.w700,
                      height: 1.6,
                      color: Colors.white,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
      ),
    );
  }

  /// Тројазичното објаснување - при отворање на екранот, и достапно за
  /// повторување со допир на текстот на картичката. Копчето-микрофон
  /// НИКОГАШ не го повикува ова - тоа служи исклучиво за слушање.
  Future<void> _playExplanation({Duration delay = const Duration(milliseconds: 400)}) async {
    final voiceAssistant = Provider.of<VoiceAssistantService>(context, listen: false);
    if (delay > Duration.zero) await Future.delayed(delay);
    if (!mounted) return;
    await AccessibilityUtils.provideFeedback(
      context: context,
      audioFeedback: 'language.voice_assistant_ready'.tr(),
      voiceAssistant: voiceAssistant,
      clipAssetPath: 'audio/language/voice_explain.mp3',
    );
  }

  @override
  Widget build(BuildContext context) {
    final content = _buildContent(context);
    if (!_awaitingFirstTap) return content;
    return Stack(
      fit: StackFit.expand,
      children: [
        content,
        _buildUnlockOverlay(),
      ],
    );
  }

  Widget _buildContent(BuildContext context) {
    final voiceAssistant = Provider.of<VoiceAssistantService>(context, listen: false);
    final hc = Provider.of<AccessibilityProvider>(context).highContrastMode;

    if (hc) {
      return Scaffold(
        backgroundColor: AccessibilityUtils.getBackgroundColor(context),
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'app.title'.tr(),
                  style: GoogleFonts.lexend(
                    fontSize: 26,
                    fontWeight: FontWeight.w800,
                    color: AccessibilityUtils.getContrastColor(context),
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  'language.welcome'.tr(),
                  style: GoogleFonts.lexend(
                    fontSize: 16,
                    color: AccessibilityUtils.getContrastColor(context),
                  ),
                ),
                const SizedBox(height: 28),
                _voiceAssistantCard(context, voiceAssistant, highContrast: true),
                const SizedBox(height: 24),
                _languageRow(
                  context: context,
                  code: 'MK',
                  name: 'Македонски',
                  locale: const Locale('mk', 'MK'),
                  langCode: 'mk',
                  accent: const Color(0xFFFFC400),
                  voiceAssistant: voiceAssistant,
                  highContrast: true,
                ),
                const SizedBox(height: 18),
                _languageRow(
                  context: context,
                  code: 'EN',
                  name: 'English',
                  locale: const Locale('en', 'US'),
                  langCode: 'en',
                  accent: const Color(0xFF4A90E2),
                  voiceAssistant: voiceAssistant,
                  highContrast: true,
                ),
                const SizedBox(height: 18),
                _languageRow(
                  context: context,
                  code: 'SQ',
                  name: 'Shqip',
                  locale: const Locale('sq', 'AL'),
                  langCode: 'sq',
                  accent: const Color(0xFFFF1E2D),
                  voiceAssistant: voiceAssistant,
                  highContrast: true,
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Scaffold(
      body: Stack(
        fit: StackFit.expand,
        children: [
          Container(
            decoration: const BoxDecoration(gradient: AppStyle.welcomeBackground),
          ),
          const Positioned.fill(
            child: AmbientBackground(variant: AmbientVariant.welcome),
          ),
          SafeArea(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final maxWidth = constraints.maxWidth > 480 ? 480.0 : constraints.maxWidth;
                return Center(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
                    child: ConstrainedBox(
                      constraints: BoxConstraints(maxWidth: maxWidth),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          const SizedBox(height: 12),
                          Text(
                            'app.title'.tr(),
                            textAlign: TextAlign.center,
                            style: GoogleFonts.lexend(
                              fontSize: 32,
                              fontWeight: FontWeight.w800,
                              color: Colors.white,
                              height: 1.15,
                              letterSpacing: -0.8,
                              shadows: [
                                Shadow(
                                  color: Colors.black.withValues(alpha: 0.2),
                                  blurRadius: 12,
                                  offset: const Offset(0, 4),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 12),
                          Text(
                            'language.welcome'.tr(),
                            textAlign: TextAlign.center,
                            style: GoogleFonts.lexend(
                              fontSize: 16,
                              fontWeight: FontWeight.w500,
                              height: 1.4,
                              color: Colors.white.withValues(alpha: 0.92),
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            '👂  ·  👁️  ·  🙌',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 22,
                              color: Colors.white.withValues(alpha: 0.85),
                            ),
                          ),
                          const SizedBox(height: 32),
                          _voiceAssistantCard(context, voiceAssistant, highContrast: false),
                          const SizedBox(height: 28),
                          Text(
                            'language.choose'.tr(),
                            style: GoogleFonts.lexend(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              letterSpacing: 1.2,
                              color: Colors.white.withValues(alpha: 0.8),
                            ),
                          ),
                          const SizedBox(height: 16),
                          _languageRow(
                            context: context,
                            code: 'MK',
                            name: 'Македонски',
                            locale: const Locale('mk', 'MK'),
                            langCode: 'mk',
                            accent: const Color(0xFFFFB800),
                            voiceAssistant: voiceAssistant,
                            highContrast: false,
                          ),
                          const SizedBox(height: 18),
                          _languageRow(
                            context: context,
                            code: 'EN',
                            name: 'English',
                            locale: const Locale('en', 'US'),
                            langCode: 'en',
                            accent: const Color(0xFF38BDF8),
                            voiceAssistant: voiceAssistant,
                            highContrast: false,
                          ),
                          const SizedBox(height: 18),
                          _languageRow(
                            context: context,
                            code: 'SQ',
                            name: 'Shqip',
                            locale: const Locale('sq', 'AL'),
                            langCode: 'sq',
                            accent: const Color(0xFFFB7185),
                            voiceAssistant: voiceAssistant,
                            highContrast: false,
                          ),
                          const SizedBox(height: 32),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  /// Ги препознава клучните зборови за трите јазици (независно од UI-јазик,
  /// бидејќи сè уште не е избран).
  String? _matchLanguage(String transcript) =>
      HeuristicVoiceIntentRepository.namedLanguage(transcript.toLowerCase());


  static const Map<String, (String, Locale)> _langData = {
    'mk': ('Македонски', Locale('mk', 'MK')),
    'en': ('English', Locale('en', 'US')),
    'sq': ('Shqip', Locale('sq', 'AL')),
  };

  Future<void> _selectLanguage(BuildContext context, String langCode, VoiceAssistantService voiceAssistant) async {
    // Ако сè уште свири објаснувањето (или нешто друго) кога јазикот ќе се
    // избере, веднаш запри го пред да се премине понатаму.
    await AccessibilityUtils.stopFeedback();
    voiceAssistant.stop();

    final data = _langData[langCode]!;
    await context.setLocale(data.$2);
    if (!context.mounted) return;
    Provider.of<AppStateProvider>(context, listen: false).setLanguage(langCode);
    Provider.of<LanguageManager>(context, listen: false).setUserUiLanguageCode(langCode);
    // Никаков изговор на "јазик: Македонски" тука - директно на почетниот
    // екран, каде ќе проговори пораката за добредојде.
    if (!context.mounted) return;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => const HomeScreen()),
    );
  }

  /// Микрофон-копче: ИСКЛУЧИВО слуша - веднаш почнува, без да го пушта
  /// објаснувањето прво (тоа е одделна функција, погоре).
  Future<void> _startVoiceLanguagePick(BuildContext context, VoiceAssistantService voiceAssistant) async {
    if (_listening) return;
    // Ако објаснувањето (voice_explain) сè уште свири, веднаш прекини го -
    // микрофонот треба веднаш да почне да слуша, не да чека тоа да заврши.
    await AccessibilityUtils.stopFeedback();
    voiceAssistant.stop();

    setState(() => _listening = true);

    final orchestrator = Provider.of<VoiceCommandOrchestrator>(context, listen: false);

    try {
      final transcript = await orchestrator.listenOnce(
        timeout: const Duration(seconds: 6),
      );
      if (!mounted) return;

      final matched = transcript == null ? null : _matchLanguage(transcript);
      if (matched != null) {
        await _selectLanguage(context, matched, voiceAssistant);
        return; // веќе навигиравме - не враќај _listening на false на стар екран
      }
      // Не е препознаен јазик - кажи го тоа (порано екранот молчеше) и
      // покажи што е чуено, за да се знае што да се повтори.
      final heard = (transcript ?? '').trim();
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        SnackBar(
          duration: const Duration(seconds: 5),
          content: Text(
            heard.isEmpty
                ? 'Не те слушнав - обиди се повторно / I didn\'t hear you - try again / Nuk të dëgjova - provo përsëri'
                : 'Чув / I heard / Dëgjova: „$heard“',
            style: const TextStyle(fontSize: 16),
          ),
        ),
      );
      await AccessibilityUtils.provideFeedback(
        context: context,
        vibrate: true,
        clipAssetPath: 'audio/voice/mk/not_recognized.mp3',
      );
    } finally {
      if (mounted) setState(() => _listening = false);
    }
  }

  Widget _voiceAssistantCard(
    BuildContext context,
    VoiceAssistantService voiceAssistant, {
    required bool highContrast,
  }) {
    final micButton = Semantics(
      label: '${'language.voice_title'.tr()}. ${'language.voice_ready'.tr()}',
      button: true,
      child: Material(
        color: _listening
            ? AccessibilityUtils.getDisabledColor(context)
            : (highContrast ? AccessibilityUtils.getAccentColor(context) : const Color(0xFF6366F1)),
        shape: const CircleBorder(),
        elevation: highContrast ? 0 : 6,
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: _listening ? null : () => _startVoiceLanguagePick(context, voiceAssistant),
          child: Padding(
            padding: const EdgeInsets.all(22),
            child: Icon(
              _listening ? Icons.hearing_rounded : Icons.mic_rounded,
              color: Colors.white,
              size: 36,
            ),
          ),
        ),
      ),
    );

    // Текстуалниот дел е допирлив - повторно го пушта објаснувањето (мп3),
    // одделно од микрофонот кој служи исклучиво за слушање. Визуелно
    // означено како "под-копче" на главното копче со асистентот, со мала
    // икона-звучник која чисто визуелно покажува дека допирот тука изговара
    // нешто.
    final subButtonBg = highContrast
        ? AccessibilityUtils.getAccentColor(context).withOpacity(0.12)
        : const Color(0xFF6366F1).withOpacity(0.08);
    final subButtonBorder = highContrast
        ? AccessibilityUtils.getAccentColor(context).withOpacity(0.5)
        : const Color(0xFF6366F1).withOpacity(0.25);

    final textArea = Semantics(
      label: '${'language.voice_title'.tr()}. ${'language.voice_ready'.tr()}',
      button: true,
      child: Material(
        color: subButtonBg,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          onTap: _playExplanation,
          borderRadius: BorderRadius.circular(14),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: subButtonBorder, width: 1.5),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'language.voice_title'.tr(),
                        style: GoogleFonts.lexend(
                          fontSize: 19,
                          fontWeight: FontWeight.w700,
                          color: highContrast ? AccessibilityUtils.getContrastColor(context) : AppStyle.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        _listening ? 'voice.listening'.tr() : 'language.voice_ready'.tr(),
                        style: GoogleFonts.lexend(
                          fontSize: 15,
                          fontWeight: FontWeight.w500,
                          color: highContrast ? AccessibilityUtils.getContrastColor(context) : AppStyle.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Icon(
                  Icons.volume_up_rounded,
                  size: 22,
                  color: highContrast ? AccessibilityUtils.getAccentColor(context) : const Color(0xFF6366F1),
                ),
              ],
            ),
          ),
        ),
      ),
    );

    if (highContrast) {
      return Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: AccessibilityUtils.getCardBackgroundColor(context),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: AccessibilityUtils.getAccentColor(context), width: 2),
        ),
        child: Row(
          children: [
            micButton,
            const SizedBox(width: 18),
            Expanded(child: textArea),
          ],
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(26),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.12),
            blurRadius: 24,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: Row(
        children: [
          micButton,
          const SizedBox(width: 18),
          Expanded(child: textArea),
        ],
      ),
    );
  }

  Widget _languageRow({
    required BuildContext context,
    required String code,
    required String name,
    required Locale locale,
    required String langCode,
    required Color accent,
    required VoiceAssistantService voiceAssistant,
    required bool highContrast,
  }) {
    Future<void> select() => _selectLanguage(context, langCode, voiceAssistant);

    Future<void> preview() async {
      await AccessibilityUtils.provideFeedback(
        context: context,
        audioFeedback: name,
        voiceAssistant: voiceAssistant,
        clipAssetPath: 'audio/language/$langCode/name.mp3',
      );
    }

    if (highContrast) {
      return Semantics(
        button: true,
        label: '$name. ${'language.choose'.tr()}',
        child: Row(
          children: [
            Expanded(
              child: Material(
                color: AccessibilityUtils.getCardBackgroundColor(context),
                borderRadius: BorderRadius.circular(20),
                child: InkWell(
                  borderRadius: BorderRadius.circular(20),
                  onTap: select,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 26, vertical: 30),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: AccessibilityUtils.getAccentColor(context), width: 2),
                    ),
                    child: Row(
                      children: [
                        Text(
                          code,
                          style: GoogleFonts.lexend(
                            fontSize: 36,
                            fontWeight: FontWeight.w800,
                            color: AccessibilityUtils.getAccentColor(context),
                          ),
                        ),
                        const SizedBox(width: 20),
                        Expanded(
                          child: Text(
                            name,
                            style: GoogleFonts.lexend(
                              fontSize: 27,
                              fontWeight: FontWeight.w700,
                              color: AccessibilityUtils.getContrastColor(context),
                            ),
                          ),
                        ),
                        Icon(Icons.arrow_forward_rounded, color: AccessibilityUtils.getContrastColor(context), size: 30),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 12),
            IconButton.filled(
              iconSize: 36,
              padding: const EdgeInsets.all(20),
              style: IconButton.styleFrom(
                backgroundColor: AccessibilityUtils.getPrimaryButtonBackground(context),
                foregroundColor: AccessibilityUtils.getPrimaryButtonForeground(context),
              ),
              onPressed: preview,
              icon: const Icon(Icons.volume_up_rounded),
            ),
          ],
        ),
      );
    }

    return Semantics(
      button: true,
      label: '$name. ${'language.choose'.tr()}',
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Material(
              color: Colors.white,
              elevation: 6,
              shadowColor: Colors.black.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(24),
              child: InkWell(
                borderRadius: BorderRadius.circular(24),
                onTap: select,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 26, vertical: 30),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(24),
                    border: Border(
                      left: BorderSide(color: accent, width: 6),
                    ),
                  ),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                        decoration: BoxDecoration(
                          color: accent.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: Text(
                          code,
                          style: GoogleFonts.lexend(
                            fontSize: 22,
                            fontWeight: FontWeight.w800,
                            color: accent,
                          ),
                        ),
                      ),
                      const SizedBox(width: 20),
                      Expanded(
                        child: Text(
                          name,
                          style: GoogleFonts.lexend(
                            fontSize: 27,
                            fontWeight: FontWeight.w700,
                            color: AppStyle.textPrimary,
                          ),
                        ),
                      ),
                      Icon(Icons.arrow_forward_rounded, color: accent, size: 28),
                    ],
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Material(
            color: Colors.white,
            elevation: 4,
            borderRadius: BorderRadius.circular(20),
            child: InkWell(
              borderRadius: BorderRadius.circular(20),
              onTap: preview,
              child: Container(
                padding: const EdgeInsets.all(22),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: accent.withValues(alpha: 0.4), width: 2),
                ),
                child: Icon(Icons.volume_up_rounded, color: accent, size: 34),
              ),
            ),
          ),
        ],
      ),
    );
  }
}