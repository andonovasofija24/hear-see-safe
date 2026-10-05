import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:provider/provider.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:hear_and_see_safe/services/voice_assistant_service.dart';
import 'package:hear_and_see_safe/providers/app_state_provider.dart';
import 'package:hear_and_see_safe/voice_system/application/language_manager.dart';
import 'package:hear_and_see_safe/voice_system/application/voice_command_orchestrator.dart';
import 'package:hear_and_see_safe/voice_system/application/voice_ui_strings.dart';
import 'package:hear_and_see_safe/voice_system/presentation/voice_intent_dispatcher.dart';
import 'package:hear_and_see_safe/utils/accessibility_utils.dart';
import 'package:hear_and_see_safe/utils/voice_hotkey.dart';
import 'package:hear_and_see_safe/utils/voice_level.dart';
import 'package:hear_and_see_safe/widgets/playful_ui.dart';
import 'package:hear_and_see_safe/screens/braille_learning_screen.dart';
import 'package:hear_and_see_safe/screens/picture_book_screen.dart';
import 'package:hear_and_see_safe/screens/number_games_screen.dart';
import 'package:hear_and_see_safe/screens/camera_recognition_screen.dart';
import 'package:hear_and_see_safe/screens/spatial_orientation_screen.dart';
import 'package:hear_and_see_safe/screens/sound_identification_screen.dart';
import 'package:hear_and_see_safe/screens/cyber_safety_screen.dart';
import 'package:hear_and_see_safe/screens/sound_memory_screen.dart';
import 'package:hear_and_see_safe/screens/voice_pong_screen.dart';
import 'package:hear_and_see_safe/screens/melody_memory_screen.dart';
import 'package:hear_and_see_safe/screens/rhythm_tap_screen.dart';
import 'package:hear_and_see_safe/screens/story_choices_screen.dart';
import 'package:hear_and_see_safe/screens/settings_screen.dart';
import 'package:hear_and_see_safe/screens/language_selection_screen.dart';

class _HomeFeature {
  const _HomeFeature({
    required this.icon,
    required this.titleKey,
    required this.descKey,
    required this.accent,
    required this.screen,
    this.audioKey,
  });

  final IconData icon;
  final String titleKey;
  final String descKey;
  final Color accent;
  final Widget screen;
  /// Клуч за однапред снимено име на играта (assets/audio/home/<јазик>/<audioKey>.mp3).
  /// Null = играта сè уште не е преуредена - користи го стариот TTS начин.
  final String? audioKey;
}

class _HomeSection {
  const _HomeSection({
    required this.titleKey,
    required this.hintKey,
    required this.icon,
    required this.tint,
    required this.features,
  });

  final String titleKey;
  final String hintKey;
  final IconData icon;
  final Color tint;
  final List<_HomeFeature> features;
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  late VoiceAssistantService _voiceAssistant;
  /// За однапред снимени имиња на игри (assets/audio/home/<јазик>/<audioKey>.mp3).
  final AudioPlayer _featureNamePlayer = AudioPlayer();
  bool _isListening = false;
  /// Сите икони се заклучени додека не заврши пораката за добредојде.
  bool _welcomeLocked = true;

  /// Колку од пораката за добредојде е изговорено (0..1) - за караоке
  /// текстот што светнува збор по збор.
  final ValueNotifier<double> _welcomeProgress = ValueNotifier<double>(0);

  static const List<_HomeFeature> _learnFeatures = [
    _HomeFeature(
      icon: Icons.grid_view_rounded,
      titleKey: 'features.braille',
      descKey: 'features.braille_desc',
      accent: Color(0xFF3730A3),
      screen: const BrailleLearningScreen(),
      audioKey: 'braille_alphabet',
    ),
    _HomeFeature(
      icon: Icons.auto_stories_rounded,
      titleKey: 'features.picture_book',
      descKey: 'features.picture_book_desc',
      accent: Color(0xFF4F46E5),
      screen: const PictureBookScreen(),
      audioKey: 'picture_book',
    ),
    _HomeFeature(
      icon: Icons.calculate_rounded,
      titleKey: 'features.number_games',
      descKey: 'features.number_games_desc',
      accent: Color(0xFF047857),
      screen: const NumberGamesScreen(),
      audioKey: 'number_games',
    ),
    _HomeFeature(
      icon: Icons.photo_camera_rounded,
      titleKey: 'features.camera_recognition',
      descKey: 'features.camera_recognition_desc',
      accent: Color(0xFFC2410C),
      screen: const CameraRecognitionScreen(),
      audioKey: 'camera_recognition',
    ),
    _HomeFeature(
      icon: Icons.explore_rounded,
      titleKey: 'features.spatial_orientation',
      descKey: 'features.spatial_orientation_desc',
      accent: Color(0xFF7C3AED),
      screen: const SpatialOrientationScreen(),
      audioKey: 'spatial_orientation',
    ),
  ];

  static const List<_HomeFeature> _soundFeatures = [
    _HomeFeature(
      icon: Icons.hearing_rounded,
      titleKey: 'features.sound_identification',
      descKey: 'features.sound_identification_desc',
      accent: Color(0xFF0F766E),
      screen: const SoundIdentificationScreen(),
      audioKey: 'sound_identification',
    ),
    _HomeFeature(
      icon: Icons.psychology_rounded,
      titleKey: 'features.sound_memory',
      descKey: 'features.sound_memory_desc',
      accent: Color(0xFFBE185D),
      screen: const SoundMemoryScreen(),
      audioKey: 'sound_memory',
    ),
    _HomeFeature(
      icon: Icons.sports_esports_rounded,
      titleKey: 'features.voice_pong',
      descKey: 'features.voice_pong_desc',
      accent: Color(0xFFB45309),
      screen: const VoicePongScreen(),
      audioKey: 'voice_pong',
    ),
    _HomeFeature(
      icon: Icons.piano_rounded,
      titleKey: 'features.melody_memory',
      descKey: 'features.melody_memory_desc',
      accent: Color(0xFF7E22CE),
      screen: const MelodyMemoryScreen(),
      audioKey: 'melody_memory',
    ),
    _HomeFeature(
      icon: Icons.graphic_eq_rounded,
      titleKey: 'features.rhythm_tap',
      descKey: 'features.rhythm_tap_desc',
      accent: Color(0xFFBE123C),
      screen: const RhythmTapScreen(),
      audioKey: 'rhythm_tap',
    ),
    _HomeFeature(
      icon: Icons.menu_book_rounded,
      titleKey: 'features.story_choices',
      descKey: 'features.story_choices_desc',
      accent: Color(0xFF1D4ED8),
      screen: const StoryChoicesScreen(),
      audioKey: 'story_choices',
    ),
  ];

  static const List<_HomeFeature> _safeFeatures = [
    _HomeFeature(
      icon: Icons.verified_user_rounded,
      titleKey: 'features.cyber_safety',
      descKey: 'features.cyber_safety_desc',
      accent: Color(0xFFB91C1C),
      screen: const CyberSafetyScreen(),
      audioKey: 'cyber_security',
    ),
  ];

  static const List<_HomeSection> _sections = [
    _HomeSection(
      titleKey: 'home.section_learn',
      hintKey: 'home.section_learn_hint',
      icon: Icons.school_rounded,
      tint: Color(0xFFA5B4FC),
      features: _learnFeatures,
    ),
    _HomeSection(
      titleKey: 'home.section_sound',
      hintKey: 'home.section_sound_hint',
      icon: Icons.headphones_rounded,
      tint: Color(0xFF5EEAD4),
      features: _soundFeatures,
    ),
    _HomeSection(
      titleKey: 'home.section_safe',
      hintKey: 'home.section_safe_hint',
      icon: Icons.shield_rounded,
      tint: Color(0xFFFDA4AF),
      features: _safeFeatures,
    ),
  ];

  @override
  void initState() {
    super.initState();
    _voiceAssistant = Provider.of<VoiceAssistantService>(context, listen: false);
    _voiceAssistant.initialize();
    _updateVoiceAssistantSettings();
    _announceHomeScreen();

    VoiceHotkey.pressed.addListener(_onVoiceHotkey);
  }

  /// Г на тастатура = копчето за гласовна команда (само кога менито е
  /// најгоре и пораката за добредојде е завршена).
  void _onVoiceHotkey() {
    if (!mounted || _welcomeLocked || _isListening) return;
    final route = ModalRoute.of(context);
    if (route != null && !route.isCurrent) return;
    _startVoiceCommand();
  }

  @override
  void dispose() {
    VoiceHotkey.pressed.removeListener(_onVoiceHotkey);
    _voiceAssistant.stop();
    _featureNamePlayer.dispose();
    _welcomeProgress.dispose();
    VoiceLevel.speaking.value = false;
    super.dispose();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final code = context.locale.languageCode;
    final lm = Provider.of<LanguageManager>(context, listen: false);
    if (lm.userUiLanguageCode != code) {
      lm.setUserUiLanguageCode(code);
    }
  }

  Future<void> _startVoiceCommand() async {
    if (_isListening) return;
    setState(() => _isListening = true);
    final langCode = context.locale.languageCode;
    final orchestrator = Provider.of<VoiceCommandOrchestrator>(context, listen: false);
    final strings = VoiceUiStrings(
      commandHint: 'voice.speak_command'.tr(),
      notRecognized: 'voice.not_recognized'.tr(),
      confirmWifiDisable: 'voice.confirm_wifi_disable'.tr(),
      sessionCancelled: 'voice.session_cancelled'.tr(),
      systemWifiUnavailable: 'voice.system_wifi_unavailable'.tr(),
    );

    final intent = await orchestrator.runCommand(
      strings,
      langCode,
      playClip: (key) => _tryPlayVoiceClip(key, langCode),
    );
    if (!mounted) return;
    setState(() => _isListening = false);
    if (intent == null) return;

    await dispatchVoiceIntent(
      context: context,
      intent: intent,
      voiceAssistant: _voiceAssistant,
      systemWifiUnavailableMessage: strings.systemWifiUnavailable,
    );
  }

  /// Пробува однапред снимен клип за гласовниот тек (assets/audio/voice/<јазик>/<клуч>.mp3).
  /// Враќа true ако успешно пуштил, false ако не постои (тогаш се користи TTS).
  Future<bool> _tryPlayVoiceClip(String key, String langCode) async {
    try {
      await _featureNamePlayer.stop();
      await _featureNamePlayer.play(AssetSource('audio/voice/$langCode/$key.mp3'));
      return true;
    } catch (_) {
      return false;
    }
  }

  void _updateVoiceAssistantSettings() {
    final appState = Provider.of<AppStateProvider>(context, listen: false);
    _voiceAssistant.setVoiceAssistantEnabled(appState.isVoiceAssistantEnabled);
    _voiceAssistant.setVibrationEnabled(appState.vibrationEnabled);
  }

  Future<void> _announceHomeScreen() async {
    await Future.delayed(const Duration(milliseconds: 500));
    if (!mounted) return;
    final langCode = context.locale.languageCode;

    // Иста робустна проверка како и на другите екрани: некои платформи
    // тивко ја голтаат формат-грешката без да фрлат исклучок, па не се
    // потпираме само на тоа дали .play() не фрлил грешка.
    bool reachedPlaying = false;
    final startedCompleter = Completer<void>();
    final finishedCompleter = Completer<void>();
    late final StreamSubscription<PlayerState> stateSub;
    stateSub = _featureNamePlayer.onPlayerStateChanged.listen((state) {
      if (state == PlayerState.playing) {
        reachedPlaying = true;
        if (!startedCompleter.isCompleted) startedCompleter.complete();
      }
      if (state == PlayerState.completed || state == PlayerState.stopped) {
        if (!startedCompleter.isCompleted) startedCompleter.complete();
        if (!finishedCompleter.isCompleted) finishedCompleter.complete();
      }
    });

    // Караоке: позицијата на снимката / нејзината должина.
    Duration? total;
    final posSub = _featureNamePlayer.onPositionChanged.listen((pos) async {
      total ??= await _featureNamePlayer.getDuration();
      final ms = total?.inMilliseconds ?? 0;
      if (ms > 0 && mounted) _welcomeProgress.value = (pos.inMilliseconds / ms).clamp(0.0, 1.0);
    });

    bool playCallSucceeded = false;
    try {
      await _featureNamePlayer.stop();
      await _featureNamePlayer.play(AssetSource('audio/home/$langCode/welcome.mp3'));
      playCallSucceeded = true;
    } catch (_) {
      playCallSucceeded = false;
    }

    if (playCallSucceeded) {
      await startedCompleter.future.timeout(const Duration(seconds: 4), onTimeout: () {});
      if (reachedPlaying) {
        VoiceLevel.speaking.value = true;
        await finishedCompleter.future.timeout(const Duration(seconds: 30), onTimeout: () {});
      }
    }
    await stateSub.cancel();
    await posSub.cancel();
    VoiceLevel.speaking.value = false;

    if (!mounted) return;
    if (!(playCallSucceeded && reachedPlaying)) {
      // Без снимка: системски глас, а текстот светнува според проценето
      // време (околу 65 ms по буква).
      final text = 'home.welcome'.tr();
      final estimate = Duration(milliseconds: 65 * text.length);
      final sw = Stopwatch()..start();
      VoiceLevel.speaking.value = true;
      final ticker = Timer.periodic(const Duration(milliseconds: 80), (t) {
        if (!mounted) return t.cancel();
        _welcomeProgress.value = (sw.elapsedMilliseconds / estimate.inMilliseconds).clamp(0.0, 1.0);
      });
      await _voiceAssistant.speakWithLanguage(text, langCode, vibrate: false);
      ticker.cancel();
      VoiceLevel.speaking.value = false;
    }

    if (!mounted) return;
    _welcomeProgress.value = 1;
    setState(() => _welcomeLocked = false);
  }

  void _goToLanguageSelection() {
    _voiceAssistant.stop();
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => const LanguageSelectionScreen()),
    );
  }

  void _navigateToScreen(Widget screen, String announcement) {
    AccessibilityUtils.provideFeedback(
      context: context,
      audioFeedback: announcement,
      voiceAssistant: _voiceAssistant,
    );
    Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => screen),
    );
  }

  /// За игри со подготвена снимка на името (f.audioKey != null), се пушта
  /// таа снимка наместо системскиот TTS. За другите игри (audioKey == null)
  /// однесувањето останува исто како порано.
  Future<void> _navigateToFeature(_HomeFeature f) async {
    if (f.audioKey == null) {
      _navigateToScreen(f.screen, f.titleKey.tr());
      return;
    }

    AccessibilityUtils.provideFeedback(context: context);
    final langCode = context.locale.languageCode;
    final relativePath = 'audio/home/$langCode/${f.audioKey}.mp3';
    try {
      await _featureNamePlayer.stop();
      await _featureNamePlayer.play(AssetSource(relativePath));
    } catch (_) {
      await _voiceAssistant.speakWithLanguage(f.titleKey.tr(), langCode, vibrate: false);
    }

    if (!mounted) return;
    Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => f.screen),
    );
  }

  // =====================================================================
  // Изглед. Нормален режим: темна „ноќна“ позадина со лебдечки брајови
  // точки, бел текст и полно обоени картички (контраст >= 4.5:1). Режимот со
  // висок контраст останува рамен и едноставен.
  // =====================================================================

  Widget _buildHero({
    required bool hc,
    required double buttonSize,
    required Color contrastColor,
    required Color secondaryColor,
  }) {
    final welcome = 'home.welcome'.tr();
    final sub = 'home.hero_subtitle'.tr();

    if (hc) {
      return Semantics(
        container: true,
        label: '$welcome $sub',
        child: ExcludeSemantics(
          child: Padding(
            padding: const EdgeInsets.only(bottom: 20, top: 4),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  welcome,
                  style: GoogleFonts.lexend(
                    fontSize: 20 * buttonSize,
                    fontWeight: FontWeight.w700,
                    height: 1.4,
                    color: contrastColor,
                  ),
                ),
                SizedBox(height: 8 * buttonSize),
                Text(
                  sub,
                  style: GoogleFonts.lexend(
                    fontSize: 17 * buttonSize,
                    fontWeight: FontWeight.w500,
                    color: secondaryColor,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Semantics(
      container: true,
      label: '$welcome $sub',
      child: ExcludeSemantics(
        child: PopIn(
          index: 0,
          child: Padding(
            padding: EdgeInsets.only(top: 10 * buttonSize, bottom: 22 * buttonSize),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Името на апликацијата „напишано“ на Брајово писмо, со
                // печатените букви под точките.
                BrailleWordReveal(
                  text: 'app.title'.tr(),
                  lang: brailleLangFor(context.locale.languageCode),
                  cellSize: 30 * buttonSize,
                ),
                SizedBox(height: 22 * buttonSize),
                // Пораката за добредојде светнува збор по збор додека се слуша.
                KaraokeText(
                  text: welcome,
                  progress: _welcomeProgress,
                  style: Playful.title(24 * buttonSize),
                ),
                SizedBox(height: 10 * buttonSize),
                Text(sub, style: Playful.body(17 * buttonSize, color: Playful.mist)),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// Кратко техничко упатство пред менито со игри: ESC, Г, гласовни команди
  /// во менито и во игрите, листање на сликовниците со < и >.
  Widget _buildGuide({
    required bool hc,
    required double buttonSize,
    required Color contrastColor,
    required Color secondaryColor,
  }) {
    final gameNames = [
      for (final section in _sections)
        for (final f in section.features) f.titleKey.tr(),
    ].join(', ');
    // (тастер или null, икона, текст)
    final lines = <(String?, IconData, String)>[
      ('ESC', Icons.keyboard_return_rounded, 'home.guide_esc'.tr()),
      (context.locale.languageCode == 'mk' ? 'Г' : 'G', Icons.mic_rounded, 'home.guide_g'.tr()),
      (null, Icons.record_voice_over_rounded, 'home.guide_home'.tr(args: [gameNames])),
      (null, Icons.sports_esports_rounded, 'home.guide_games'.tr()),
      ('< >', Icons.menu_book_rounded, 'home.guide_books'.tr(args: ['features.braille'.tr(), 'features.picture_book'.tr()])),
      ('↑ ↓', Icons.swap_vert_rounded, 'home.guide_scroll'.tr()),
      (context.locale.languageCode == 'mk' ? 'Е' : 'E', Icons.menu_book_rounded, 'home.guide_e'.tr()),
      ('8 4 6 2', Icons.dialpad_rounded, 'home.guide_numpad'.tr()),
      ('← →', Icons.grid_3x3_rounded, 'home.guide_sudoku'.tr()),
    ];
    final title = 'home.guide_title'.tr();

    /// „ESC – враќање...“ → без „ESC – “ кога тастерот е веќе нацртан.
    String stripKey(String? key, String text) {
      if (key == null) return text;
      final dash = text.indexOf(' – ');
      if (dash > 0 && dash <= 4) return text.substring(dash + 3);
      return text;
    }

    if (hc) {
      final accent = AccessibilityUtils.getAccentColor(context);
      return Semantics(
        container: true,
        label: '$title. ${lines.map((l) => l.$3).join(' ')}',
        child: ExcludeSemantics(
          child: Container(
            margin: EdgeInsets.only(bottom: 8 * buttonSize),
            padding: EdgeInsets.all(16 * buttonSize),
            decoration: BoxDecoration(
              color: AccessibilityUtils.getCardBackgroundColor(context),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: contrastColor, width: 2),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: GoogleFonts.lexend(fontSize: 21 * buttonSize, fontWeight: FontWeight.w800, color: contrastColor)),
                SizedBox(height: 10 * buttonSize),
                for (final (_, icon, text) in lines)
                  Padding(
                    padding: EdgeInsets.only(bottom: 10 * buttonSize),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(icon, size: 24 * buttonSize, color: accent),
                        SizedBox(width: 10 * buttonSize),
                        Expanded(
                          child: Text(text, style: GoogleFonts.lexend(fontSize: 17 * buttonSize, fontWeight: FontWeight.w500, height: 1.4, color: contrastColor)),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ),
      );
    }

    return Semantics(
      container: true,
      label: '$title. ${lines.map((l) => l.$3).join(' ')}',
      child: ExcludeSemantics(
        child: PopIn(
          index: 1,
          child: Container(
            margin: EdgeInsets.only(bottom: 8 * buttonSize),
            padding: EdgeInsets.all(20 * buttonSize),
            decoration: BoxDecoration(
              color: Playful.nightRaised.withValues(alpha: 0.92),
              borderRadius: BorderRadius.circular(26),
              border: Border.all(color: Colors.white.withValues(alpha: 0.18), width: 1.5),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.lightbulb_rounded, color: Playful.sun, size: 30 * buttonSize),
                    SizedBox(width: 10 * buttonSize),
                    Expanded(child: Text(title, style: Playful.title(22 * buttonSize))),
                  ],
                ),
                SizedBox(height: 16 * buttonSize),
                for (final (key, icon, text) in lines)
                  Padding(
                    padding: EdgeInsets.only(bottom: 14 * buttonSize),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SizedBox(
                          width: 64 * buttonSize,
                          child: Align(
                            alignment: Alignment.topLeft,
                            child: key != null
                                ? KeyCap(key, size: 0.9 * buttonSize)
                                : Container(
                                    width: 44 * buttonSize,
                                    height: 44 * buttonSize,
                                    decoration: BoxDecoration(
                                      shape: BoxShape.circle,
                                      color: Colors.white.withValues(alpha: 0.12),
                                    ),
                                    child: Icon(icon, size: 24 * buttonSize, color: Playful.sun),
                                  ),
                          ),
                        ),
                        SizedBox(width: 6 * buttonSize),
                        Expanded(
                          child: Padding(
                            padding: EdgeInsets.only(top: 8 * buttonSize),
                            child: Text(stripKey(key, text), style: Playful.body(16.5 * buttonSize)),
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSectionHeader({
    required _HomeSection section,
    required bool hc,
    required double buttonSize,
    required Color contrastColor,
    int index = 0,
  }) {
    final title = section.titleKey.tr();
    final hint = section.hintKey.tr();

    if (hc) {
      return Semantics(
        header: true,
        label: '$title. $hint',
        child: Padding(
          padding: EdgeInsets.only(top: 24 * buttonSize, bottom: 12 * buttonSize),
          child: Row(
            children: [
              Icon(section.icon, color: AccessibilityUtils.getAccentColor(context), size: 32 * buttonSize),
              SizedBox(width: 12 * buttonSize),
              Expanded(
                child: Text(
                  title,
                  style: GoogleFonts.lexend(
                    fontSize: 24 * buttonSize,
                    fontWeight: FontWeight.w800,
                    color: contrastColor,
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }

    return Semantics(
      header: true,
      label: '$title. $hint',
      child: ExcludeSemantics(
        child: PopIn(
          index: index,
          child: Padding(
            padding: EdgeInsets.only(top: 30 * buttonSize, bottom: 14 * buttonSize),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Container(
                  width: 58 * buttonSize,
                  height: 58 * buttonSize,
                  decoration: BoxDecoration(
                    color: section.tint,
                    borderRadius: BorderRadius.circular(18),
                  ),
                  child: Icon(section.icon, color: Playful.ink, size: 32 * buttonSize),
                ),
                SizedBox(width: 16 * buttonSize),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title, style: Playful.display(26 * buttonSize)),
                      SizedBox(height: 4 * buttonSize),
                      Text(hint, style: Playful.body(16 * buttonSize, color: section.tint)),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final hc = AccessibilityUtils.isHighContrast(context);
    final backgroundColor = AccessibilityUtils.getBackgroundColor(context);
    final contrastColor = AccessibilityUtils.getContrastColor(context);
    final secondaryColor = AccessibilityUtils.getSecondaryTextColor(context);
    final buttonSize = AccessibilityUtils.getButtonSize(context);
    final topIconColor = hc ? contrastColor : Playful.paper;

    // Редоследот на појавување (скок) на елементите.
    var popIndex = 2;

    Widget topButton({required IconData icon, required String tooltip, required VoidCallback? onPressed}) {
      return Padding(
        padding: const EdgeInsets.only(right: 10),
        child: IconButton(
          icon: Icon(icon, size: 30 * buttonSize),
          color: topIconColor,
          tooltip: tooltip,
          padding: EdgeInsets.all(10 * buttonSize),
          style: IconButton.styleFrom(
            backgroundColor: hc ? null : Colors.white.withValues(alpha: 0.12),
            side: hc ? null : BorderSide(color: Colors.white.withValues(alpha: 0.35), width: 1.5),
          ),
          onPressed: onPressed,
        ),
      );
    }

    return Scaffold(
      backgroundColor: hc ? backgroundColor : Playful.night,
      appBar: AppBar(
        centerTitle: false,
        elevation: 0,
        scrolledUnderElevation: 0,
        toolbarHeight: 72 * buttonSize.clamp(1.0, 1.4),
        // Иста боја како горниот дел од позадината - без шев.
        backgroundColor: hc ? AccessibilityUtils.getAppBarBackgroundColor(context) : Playful.background.colors.first,
        title: Text(
          'app.title'.tr(),
          style: hc
              ? GoogleFonts.lexend(fontSize: 24 * buttonSize, fontWeight: FontWeight.w800, color: contrastColor)
              : Playful.display(26 * buttonSize),
        ),
        actions: [
          topButton(
            icon: Icons.language_rounded,
            tooltip: 'language.change'.tr(),
            onPressed: _welcomeLocked ? null : _goToLanguageSelection,
          ),
          topButton(
            icon: Icons.settings_rounded,
            tooltip: 'settings.title'.tr(),
            onPressed: _welcomeLocked
                ? null
                : () => _navigateToScreen(const SettingsScreen(), 'settings.opening'.tr()),
          ),
        ],
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
      floatingActionButton: _buildVoiceFab(hc: hc, buttonSize: buttonSize, contrastColor: contrastColor),
      body: Stack(
        children: [
          Positioned.fill(
            child: hc ? ColoredBox(color: backgroundColor) : const BrailleBackdrop(),
          ),
          Positioned.fill(
            child: SafeArea(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  // Низ целиот екран: листата е широка колку екранот (лизгачот
                  // е скроз десно), а картичките се во 1 / 2 / 3 колони.
                  final width = constraints.maxWidth;
                  final side = width >= 1200 ? 40.0 : (width >= 760 ? 28.0 : 20.0);
                  final columns = width >= 1300 ? 3 : (width >= 760 ? 2 : 1);
                  const gap = 16.0;
                  final innerWidth = width - side * 2;
                  final cardWidth = (innerWidth - gap * (columns - 1)) / columns - 0.5;
                  return SizedBox(
                      width: width,
                      child: ListView(
                        padding: EdgeInsets.fromLTRB(side, 8, side, 140),
                        children: [
                          _buildHero(
                            hc: hc,
                            buttonSize: buttonSize,
                            contrastColor: contrastColor,
                            secondaryColor: secondaryColor,
                          ),
                          _buildGuide(
                            hc: hc,
                            buttonSize: buttonSize,
                            contrastColor: contrastColor,
                            secondaryColor: secondaryColor,
                          ),
                          for (final section in _sections) ...[
                            _buildSectionHeader(
                              section: section,
                              hc: hc,
                              buttonSize: buttonSize,
                              contrastColor: contrastColor,
                              index: popIndex++,
                            ),
                            Wrap(
                              spacing: gap,
                              runSpacing: gap,
                              children: [
                                for (final f in section.features)
                                  SizedBox(
                                    width: cardWidth,
                                    child: AbsorbPointer(
                                      absorbing: _welcomeLocked,
                                      child: AnimatedOpacity(
                                        duration: const Duration(milliseconds: 400),
                                        opacity: _welcomeLocked ? 0.45 : 1.0,
                                        child: PopIn(
                                          index: popIndex++,
                                          child: _buildFeatureCard(
                                            context,
                                            brailleDelayMs: 500 + math.min(popIndex, 12) * 90,
                                            icon: f.icon,
                                            title: f.titleKey.tr(),
                                            description: f.descKey.tr(),
                                            accent: f.accent,
                                            buttonSize: buttonSize,
                                            contrastColor: contrastColor,
                                            secondaryColor: secondaryColor,
                                            highContrast: hc,
                                            semanticLabel:
                                                '${f.titleKey.tr()}. ${f.descKey.tr()}. ${'features.tap_to_open'.tr()}',
                                            onTap: () => _navigateToFeature(f),
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                          ],
                        ],
                      ),
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Големото копче за гласовна команда долу во средина: жолто, со звучни
  /// бранови околу него (побрзи додека се слуша).
  Widget _buildVoiceFab({required bool hc, required double buttonSize, required Color contrastColor}) {
    final label = _isListening ? 'voice.listening'.tr() : 'voice.tap_to_speak'.tr();
    final enabled = !(_isListening || _welcomeLocked);

    if (hc) {
      return Semantics(
        button: true,
        label: 'home.fab_semantics'.tr(),
        child: Material(
          color: _isListening ? AccessibilityUtils.getDisabledColor(context) : AccessibilityUtils.getPrimaryButtonBackground(context),
          borderRadius: BorderRadius.circular(22),
          child: InkWell(
            onTap: enabled ? _startVoiceCommand : null,
            borderRadius: BorderRadius.circular(22),
            child: Container(
              padding: EdgeInsets.symmetric(horizontal: 26 * buttonSize, vertical: 18 * buttonSize),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(22),
                border: Border.all(color: contrastColor, width: 2),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(_isListening ? Icons.mic_rounded : Icons.record_voice_over_rounded,
                      color: AccessibilityUtils.getPrimaryButtonForeground(context), size: 30 * buttonSize),
                  SizedBox(width: 12 * buttonSize),
                  Text(label,
                      style: GoogleFonts.lexend(
                          fontSize: 19 * buttonSize,
                          fontWeight: FontWeight.w800,
                          color: AccessibilityUtils.getPrimaryButtonForeground(context))),
                ],
              ),
            ),
          ),
        ),
      );
    }

    final bg = _isListening ? Colors.white : Playful.sun;
    return Semantics(
      button: true,
      label: 'home.fab_semantics'.tr(),
      child: Opacity(
        opacity: _welcomeLocked ? 0.6 : 1,
        child: RippleRings(
          color: _isListening ? Colors.white : Playful.sun,
          active: _isListening,
          spread: 22,
          child: PressableScale(
            enabled: enabled,
            child: Material(
              color: bg,
              elevation: 12,
              shadowColor: Colors.black.withValues(alpha: 0.5),
              borderRadius: BorderRadius.circular(40),
              child: InkWell(
                onTap: enabled ? _startVoiceCommand : null,
                borderRadius: BorderRadius.circular(40),
                child: Padding(
                  padding: EdgeInsets.symmetric(horizontal: 28 * buttonSize, vertical: 18 * buttonSize),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (_isListening)
                        // Гласот се гледа: столбчињата скокаат додека се зборува.
                        SoundWave(color: Playful.ink, bars: 7, height: 34 * buttonSize, barWidth: 5 * buttonSize)
                      else
                        Container(
                          padding: EdgeInsets.all(8 * buttonSize),
                          decoration: const BoxDecoration(color: Playful.ink, shape: BoxShape.circle),
                          child: Icon(Icons.record_voice_over_rounded, color: bg, size: 26 * buttonSize),
                        ),
                      SizedBox(width: 14 * buttonSize),
                      Text(label, style: Playful.display(20 * buttonSize, color: Playful.ink)),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildFeatureCard(
    BuildContext context, {
    int brailleDelayMs = 500,
    required IconData icon,
    required String title,
    required String description,
    required Color accent,
    required double buttonSize,
    required Color contrastColor,
    required Color secondaryColor,
    required bool highContrast,
    required String semanticLabel,
    required VoidCallback onTap,
  }) {
    if (highContrast) {
      final borderSide = AccessibilityUtils.getCardBorder(context, fallbackColor: contrastColor);
      return Semantics(
        label: semanticLabel,
        button: true,
        child: Material(
          color: AccessibilityUtils.getCardBackgroundColor(context),
          borderRadius: BorderRadius.circular(22),
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(22),
            child: Container(
              padding: EdgeInsets.all(18 * buttonSize),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(22),
                border: Border.all(color: borderSide.color, width: math.max(borderSide.width, 2)),
              ),
              child: Row(
                children: [
                  Container(
                    padding: EdgeInsets.all(14 * buttonSize),
                    decoration: BoxDecoration(
                      color: AccessibilityUtils.getPrimaryButtonBackground(context),
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(color: contrastColor),
                    ),
                    child: Icon(icon, size: 38 * buttonSize, color: AccessibilityUtils.getPrimaryButtonForeground(context)),
                  ),
                  SizedBox(width: 16 * buttonSize),
                  Expanded(
                    child: ExcludeSemantics(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(title,
                              style: GoogleFonts.lexend(fontSize: 22 * buttonSize, fontWeight: FontWeight.w800, height: 1.2, color: contrastColor)),
                          SizedBox(height: 6 * buttonSize),
                          Text(description,
                              maxLines: 3,
                              overflow: TextOverflow.ellipsis,
                              style: GoogleFonts.lexend(fontSize: 17 * buttonSize, fontWeight: FontWeight.w500, height: 1.35, color: secondaryColor)),
                        ],
                      ),
                    ),
                  ),
                  Icon(Icons.arrow_forward_rounded, color: contrastColor, size: 30 * buttonSize),
                ],
              ),
            ),
          ),
        ),
      );
    }

    // Полна боја на играта; белиот текст и иконата се секогаш читливи.
    final deep = Color.lerp(accent, Colors.black, 0.28)!;
    final cells = brailleCellsFor(title, brailleLangFor(context.locale.languageCode));
    final firstCell = cells.isEmpty ? null : cells.first;
    return Semantics(
      label: semanticLabel,
      button: true,
      child: PressableScale(
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(26),
            child: Ink(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(26),
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [accent, deep],
                ),
                border: Border.all(color: Colors.white.withValues(alpha: 0.22), width: 1.5),
                boxShadow: [
                  BoxShadow(color: deep.withValues(alpha: 0.55), blurRadius: 18, offset: const Offset(0, 8)),
                ],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(26),
                child: Stack(
                children: [
                  // Голема бледа икона во аголот - само украс.
                  Positioned(
                    right: -14,
                    bottom: -18,
                    child: ExcludeSemantics(
                      child: Icon(icon, size: 120 * buttonSize, color: Colors.white.withValues(alpha: 0.10)),
                    ),
                  ),
                  Padding(
                    padding: EdgeInsets.all(18 * buttonSize),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Container(
                          width: 68 * buttonSize,
                          height: 68 * buttonSize,
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Icon(icon, size: 38 * buttonSize, color: deep),
                        ),
                        SizedBox(width: 18 * buttonSize),
                        Expanded(
                          child: ExcludeSemantics(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Text(title, style: Playful.display(22 * buttonSize)),
                                SizedBox(height: 6 * buttonSize),
                                Text(
                                  description,
                                  maxLines: 3,
                                  overflow: TextOverflow.ellipsis,
                                  style: Playful.body(16 * buttonSize, color: Colors.white.withValues(alpha: 0.95)),
                                ),
                              ],
                            ),
                          ),
                        ),
                        SizedBox(width: 12 * buttonSize),
                        // Првата буква од името на Брајово писмо (испакната).
                        if (firstCell != null)
                          EmbossedBrailleCell(
                            dots: firstCell.$2,
                            letter: firstCell.$1,
                            size: 40 * buttonSize,
                            plateColor: Color.lerp(accent, Colors.black, 0.5)!,
                            delayMs: brailleDelayMs,
                          ),
                      ],
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
}