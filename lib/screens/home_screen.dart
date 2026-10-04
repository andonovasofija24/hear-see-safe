import 'dart:async';
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
import 'package:hear_and_see_safe/theme/app_style.dart';
import 'package:hear_and_see_safe/widgets/ambient_background.dart';
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

class _HomeScreenState extends State<HomeScreen> with SingleTickerProviderStateMixin {
  late VoiceAssistantService _voiceAssistant;
  /// За однапред снимени имиња на игри (assets/audio/home/<јазик>/<audioKey>.mp3).
  final AudioPlayer _featureNamePlayer = AudioPlayer();
  bool _isListening = false;
  /// Сите икони се заклучени додека не заврши пораката за добредојде.
  bool _welcomeLocked = true;
  late AnimationController _fabPulse;
  late Animation<double> _fabScale;

  static const List<_HomeFeature> _learnFeatures = [
    _HomeFeature(
      icon: Icons.grid_view_rounded,
      titleKey: 'features.braille',
      descKey: 'features.braille_desc',
      accent: Color(0xFF4F46E5),
      screen: const BrailleLearningScreen(),
      audioKey: 'braille_alphabet',
    ),
    _HomeFeature(
      icon: Icons.auto_stories_rounded,
      titleKey: 'features.picture_book',
      descKey: 'features.picture_book_desc',
      accent: Color(0xFF6366F1),
      screen: const PictureBookScreen(),
      audioKey: 'picture_book',
    ),
    _HomeFeature(
      icon: Icons.calculate_rounded,
      titleKey: 'features.number_games',
      descKey: 'features.number_games_desc',
      accent: Color(0xFF059669),
      screen: const NumberGamesScreen(),
      audioKey: 'number_games',
    ),
    _HomeFeature(
      icon: Icons.photo_camera_rounded,
      titleKey: 'features.camera_recognition',
      descKey: 'features.camera_recognition_desc',
      accent: Color(0xFFEA580C),
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
      accent: Color(0xFF0D9488),
      screen: const SoundIdentificationScreen(),
      audioKey: 'sound_identification',
    ),
    _HomeFeature(
      icon: Icons.psychology_rounded,
      titleKey: 'features.sound_memory',
      descKey: 'features.sound_memory_desc',
      accent: Color(0xFFDB2777),
      screen: const SoundMemoryScreen(),
      audioKey: 'sound_memory',
    ),
    _HomeFeature(
      icon: Icons.sports_esports_rounded,
      titleKey: 'features.voice_pong',
      descKey: 'features.voice_pong_desc',
      accent: Color(0xFFD97706),
      screen: const VoicePongScreen(),
      audioKey: 'voice_pong',
    ),
    _HomeFeature(
      icon: Icons.piano_rounded,
      titleKey: 'features.melody_memory',
      descKey: 'features.melody_memory_desc',
      accent: Color(0xFF9333EA),
      screen: const MelodyMemoryScreen(),
      audioKey: 'melody_memory',
    ),
    _HomeFeature(
      icon: Icons.graphic_eq_rounded,
      titleKey: 'features.rhythm_tap',
      descKey: 'features.rhythm_tap_desc',
      accent: Color(0xFFE11D48),
      screen: const RhythmTapScreen(),
      audioKey: 'rhythm_tap',
    ),
    _HomeFeature(
      icon: Icons.menu_book_rounded,
      titleKey: 'features.story_choices',
      descKey: 'features.story_choices_desc',
      accent: Color(0xFF0F766E),
      screen: const StoryChoicesScreen(),
      audioKey: 'story_choices',
    ),
  ];

  static const List<_HomeFeature> _safeFeatures = [
    _HomeFeature(
      icon: Icons.verified_user_rounded,
      titleKey: 'features.cyber_safety',
      descKey: 'features.cyber_safety_desc',
      accent: Color(0xFFDC2626),
      screen: const CyberSafetyScreen(),
      audioKey: 'cyber_security',
    ),
  ];

  static const List<_HomeSection> _sections = [
    _HomeSection(
      titleKey: 'home.section_learn',
      hintKey: 'home.section_learn_hint',
      icon: Icons.school_rounded,
      tint: Color(0xFF4F46E5),
      features: _learnFeatures,
    ),
    _HomeSection(
      titleKey: 'home.section_sound',
      hintKey: 'home.section_sound_hint',
      icon: Icons.headphones_rounded,
      tint: Color(0xFF0D9488),
      features: _soundFeatures,
    ),
    _HomeSection(
      titleKey: 'home.section_safe',
      hintKey: 'home.section_safe_hint',
      icon: Icons.shield_rounded,
      tint: Color(0xFFE11D48),
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

    _fabPulse = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2200),
    )..repeat(reverse: true);
    _fabScale = Tween<double>(begin: 1.0, end: 1.06).animate(
      CurvedAnimation(parent: _fabPulse, curve: Curves.easeInOut),
    );
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
    _fabPulse.dispose();
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
        await finishedCompleter.future.timeout(const Duration(seconds: 30), onTimeout: () {});
      }
    }
    await stateSub.cancel();

    if (!mounted) return;
    if (!(playCallSucceeded && reachedPlaying)) {
      await _voiceAssistant.speakWithLanguage('home.welcome'.tr(), langCode, vibrate: false);
    }

    if (!mounted) return;
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
                    fontSize: 16 * buttonSize,
                    fontWeight: FontWeight.w700,
                    height: 1.4,
                    color: contrastColor,
                  ),
                ),
                SizedBox(height: 8 * buttonSize),
                Text(
                  sub,
                  style: GoogleFonts.lexend(
                    fontSize: 14 * buttonSize,
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
        child: Container(
          margin: const EdgeInsets.only(bottom: 22, top: 4),
          padding: EdgeInsets.all(20 * buttonSize),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(26),
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                Color(0xFF0F766E),
                Color(0xFF0D9488),
                Color(0xFF2DD4BF),
              ],
            ),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF0F766E).withValues(alpha: 0.35),
                blurRadius: 24,
                offset: const Offset(0, 12),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  _heroChip(Icons.school_rounded),
                  SizedBox(width: 8 * buttonSize),
                  _heroChip(Icons.graphic_eq_rounded),
                  SizedBox(width: 8 * buttonSize),
                  _heroChip(Icons.shield_rounded),
                  SizedBox(width: 8 * buttonSize),
                  _heroChip(Icons.favorite_rounded),
                ],
              ),
              SizedBox(height: 16 * buttonSize),
              Text(
                welcome,
                style: GoogleFonts.lexend(
                  fontSize: 16 * buttonSize,
                  fontWeight: FontWeight.w600,
                  height: 1.45,
                  color: Colors.white,
                ),
              ),
              SizedBox(height: 8 * buttonSize),
              Text(
                sub,
                style: GoogleFonts.lexend(
                  fontSize: 13 * buttonSize,
                  fontWeight: FontWeight.w500,
                  height: 1.4,
                  color: Colors.white.withValues(alpha: 0.92),
                ),
              ),
            ],
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
    final lines = <(IconData, String)>[
      (Icons.keyboard_return_rounded, 'home.guide_esc'.tr()),
      (Icons.mic_rounded, 'home.guide_g'.tr()),
      (Icons.record_voice_over_rounded, 'home.guide_home'.tr(args: [gameNames])),
      (Icons.sports_esports_rounded, 'home.guide_games'.tr()),
      (Icons.menu_book_rounded, 'home.guide_books'.tr(args: ['features.braille'.tr(), 'features.picture_book'.tr()])),
    ];
    final accent = hc ? AccessibilityUtils.getAccentColor(context) : AppStyle.brandTeal;
    final title = 'home.guide_title'.tr();

    return Semantics(
      container: true,
      label: '$title. ${lines.map((l) => l.$2).join(' ')}',
      child: ExcludeSemantics(
        child: Container(
          margin: EdgeInsets.only(bottom: 8 * buttonSize),
          padding: EdgeInsets.all(16 * buttonSize),
          decoration: BoxDecoration(
            color: hc ? AccessibilityUtils.getCardBackgroundColor(context) : Colors.white,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: hc ? contrastColor : accent.withValues(alpha: 0.35), width: hc ? 2 : 1.5),
            boxShadow: AppStyle.cardShadow(hc),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.info_outline_rounded, color: accent, size: 24 * buttonSize),
                  SizedBox(width: 8 * buttonSize),
                  Expanded(
                    child: Text(
                      title,
                      style: GoogleFonts.lexend(
                        fontSize: 17 * buttonSize,
                        fontWeight: FontWeight.w800,
                        color: contrastColor,
                      ),
                    ),
                  ),
                ],
              ),
              SizedBox(height: 10 * buttonSize),
              for (final (icon, text) in lines)
                Padding(
                  padding: EdgeInsets.only(bottom: 8 * buttonSize),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(icon, size: 18 * buttonSize, color: accent),
                      SizedBox(width: 8 * buttonSize),
                      Expanded(
                        child: Text(
                          text,
                          style: GoogleFonts.lexend(
                            fontSize: 13.5 * buttonSize,
                            fontWeight: FontWeight.w500,
                            height: 1.4,
                            color: secondaryColor,
                          ),
                        ),
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

  Widget _heroChip(IconData icon) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.22),
        shape: BoxShape.circle,
        border: Border.all(color: Colors.white.withValues(alpha: 0.35)),
      ),
      child: Icon(icon, color: Colors.white, size: 20),
    );
  }

  Widget _buildSectionHeader({
    required _HomeSection section,
    required bool hc,
    required double buttonSize,
    required Color contrastColor,
  }) {
    final title = section.titleKey.tr();
    final hint = section.hintKey.tr();

    if (hc) {
      return Semantics(
        header: true,
        label: '$title. $hint',
        child: Padding(
          padding: EdgeInsets.only(top: 22 * buttonSize, bottom: 12 * buttonSize),
          child: Row(
            children: [
              Icon(section.icon, color: section.tint, size: 28 * buttonSize),
              SizedBox(width: 12 * buttonSize),
              Expanded(
                child: Text(
                  title,
                  style: GoogleFonts.lexend(
                    fontSize: 20 * buttonSize,
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
        child: Padding(
          padding: EdgeInsets.only(top: 22 * buttonSize, bottom: 12 * buttonSize),
          child: Container(
            padding: EdgeInsets.symmetric(horizontal: 18 * buttonSize, vertical: 14 * buttonSize),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(20),
              gradient: LinearGradient(
                colors: [
                  section.tint.withValues(alpha: 0.2),
                  section.tint.withValues(alpha: 0.06),
                ],
              ),
              border: Border.all(color: section.tint.withValues(alpha: 0.35), width: 1.5),
              boxShadow: [
                BoxShadow(
                  color: section.tint.withValues(alpha: 0.12),
                  blurRadius: 16,
                  offset: const Offset(0, 6),
                ),
              ],
            ),
            child: Row(
              children: [
                Container(
                  padding: EdgeInsets.all(12 * buttonSize),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: LinearGradient(
                      colors: [
                        section.tint.withValues(alpha: 0.45),
                        section.tint.withValues(alpha: 0.2),
                      ],
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: section.tint.withValues(alpha: 0.25),
                        blurRadius: 8,
                        offset: const Offset(0, 3),
                      ),
                    ],
                  ),
                  child: Icon(section.icon, color: Colors.white, size: 24 * buttonSize),
                ),
                SizedBox(width: 16 * buttonSize),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: GoogleFonts.lexend(
                          fontSize: 18 * buttonSize,
                          fontWeight: FontWeight.w800,
                          color: AppStyle.textPrimary,
                          letterSpacing: -0.3,
                        ),
                      ),
                      SizedBox(height: 4 * buttonSize),
                      Text(
                        hint,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.lexend(
                          fontSize: 12 * buttonSize,
                          fontWeight: FontWeight.w500,
                          color: AppStyle.textSecondary,
                          height: 1.3,
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

  @override
  Widget build(BuildContext context) {
    final hc = AccessibilityUtils.isHighContrast(context);
    final backgroundColor = AccessibilityUtils.getBackgroundColor(context);
    final contrastColor = AccessibilityUtils.getContrastColor(context);
    final secondaryColor = AccessibilityUtils.getSecondaryTextColor(context);
    final buttonSize = AccessibilityUtils.getButtonSize(context);
    final fabBg = _isListening
        ? AccessibilityUtils.getDisabledColor(context)
        : (hc ? AccessibilityUtils.getPrimaryButtonBackground(context) : const Color(0xFF115E59));
    final fabFg = AccessibilityUtils.getPrimaryButtonForeground(context);
    final pulseOn = !hc && !_isListening;

    return Scaffold(
      backgroundColor: hc ? backgroundColor : Colors.transparent,
      extendBody: false,
      appBar: AppBar(
        centerTitle: false,
        elevation: 0,
        scrolledUnderElevation: 0,
        backgroundColor: hc ? AccessibilityUtils.getAppBarBackgroundColor(context) : Colors.transparent,
        flexibleSpace: hc
            ? null
            : Container(
                decoration: const BoxDecoration(gradient: AppStyle.appBarGradient),
              ),
        title: Text(
          'app.title'.tr(),
          style: GoogleFonts.lexend(
            fontSize: 22 * buttonSize,
            fontWeight: FontWeight.w700,
            color: hc ? contrastColor : Colors.white,
            letterSpacing: -0.5,
          ),
        ),
        actions: [
          IconButton(
            icon: Icon(Icons.language_rounded, size: 28 * buttonSize),
            color: hc ? contrastColor : Colors.white,
            style: IconButton.styleFrom(
              backgroundColor: hc ? null : Colors.white.withValues(alpha: 0.18),
            ),
            onPressed: _welcomeLocked ? null : _goToLanguageSelection,
            tooltip: 'language.change'.tr(),
          ),
          const SizedBox(width: 8),
          IconButton(
            icon: Icon(Icons.settings_rounded, size: 28 * buttonSize),
            color: hc ? contrastColor : Colors.white,
            style: IconButton.styleFrom(
              backgroundColor: hc ? null : Colors.white.withValues(alpha: 0.18),
            ),
            onPressed: _welcomeLocked
                ? null
                : () {
                    _navigateToScreen(
                      const SettingsScreen(),
                      'settings.opening'.tr(),
                    );
                  },
            tooltip: 'settings.title'.tr(),
          ),
          const SizedBox(width: 8),
        ],
      ),
      floatingActionButton: Semantics(
        button: true,
        label: 'home.fab_semantics'.tr(),
        child: AnimatedBuilder(
          animation: _fabPulse,
          builder: (context, child) {
            final scale = pulseOn ? _fabScale.value : 1.0;
            return Transform.scale(
              scale: scale,
              child: child,
            );
          },
          child: Material(
            elevation: hc ? 0 : 10,
            shadowColor: const Color(0xFF115E59).withValues(alpha: 0.5),
            borderRadius: BorderRadius.circular(22),
            child: InkWell(
              onTap: (_isListening || _welcomeLocked) ? null : _startVoiceCommand,
              borderRadius: BorderRadius.circular(22),
              child: Ink(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(22),
                  gradient: _isListening || hc
                      ? null
                      : const LinearGradient(
                          colors: [Color(0xFF115E59), Color(0xFF14B8A6), Color(0xFF5EEAD4)],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                  color: (_isListening || hc) ? fabBg : null,
                  border: hc ? Border.all(color: contrastColor, width: 2) : null,
                ),
                child: Padding(
                  padding: EdgeInsets.symmetric(
                    horizontal: 22 * buttonSize,
                    vertical: 16 * buttonSize,
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        _isListening ? Icons.mic_rounded : Icons.record_voice_over_rounded,
                        color: fabFg,
                        size: 28 * buttonSize,
                      ),
                      SizedBox(width: 10 * buttonSize),
                      Text(
                        _isListening ? 'voice.listening'.tr() : 'voice.tap_to_speak'.tr(),
                        style: GoogleFonts.lexend(
                          fontSize: 16 * buttonSize,
                          fontWeight: FontWeight.w800,
                          color: fabFg,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
      body: Stack(
        children: [
          Positioned.fill(
            child: Container(
              decoration: hc
                  ? BoxDecoration(color: backgroundColor)
                  : const BoxDecoration(gradient: AppStyle.homeBodyGradient),
            ),
          ),
          if (!hc) const Positioned.fill(child: AmbientBackground(variant: AmbientVariant.home)),
          Positioned.fill(
            child: SafeArea(
              top: false,
              child: ListView(
                padding: EdgeInsets.fromLTRB(20, 8, 20, 110),
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
                    ),
                    for (final f in section.features) ...[
                      Padding(
                        padding: EdgeInsets.only(bottom: 12 * buttonSize),
                        child: AbsorbPointer(
                          absorbing: _welcomeLocked,
                          child: Opacity(
                            opacity: _welcomeLocked ? 0.4 : 1.0,
                            child: _buildFeatureCard(
                              context,
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
                    ],
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFeatureCard(
    BuildContext context, {
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
    final cardBg = AccessibilityUtils.getCardBackgroundColor(context);
    final borderSide = AccessibilityUtils.getCardBorder(context, fallbackColor: contrastColor);
    final borderColor = highContrast ? borderSide.color : const Color(0xFFE2E8F0);
    final borderW = highContrast ? borderSide.width : 1.0;

    return Semantics(
      label: semanticLabel,
      button: true,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(22),
          child: Ink(
            decoration: BoxDecoration(
              color: cardBg,
              borderRadius: BorderRadius.circular(22),
              border: Border.all(
                color: borderColor,
                width: borderW,
              ),
              boxShadow: AppStyle.cardShadow(highContrast),
            ),
            child: IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Container(
                    width: 6,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [accent, accent.withValues(alpha: 0.65)],
                      ),
                      borderRadius: const BorderRadius.horizontal(left: Radius.circular(20)),
                    ),
                  ),
                  Expanded(
                    child: Padding(
                      padding: EdgeInsets.all(16 * buttonSize),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          Container(
                            padding: EdgeInsets.all(14 * buttonSize),
                            decoration: BoxDecoration(
                              color: highContrast
                                  ? AccessibilityUtils.getPrimaryButtonBackground(context)
                                  : accent.withValues(alpha: 0.13),
                              borderRadius: BorderRadius.circular(18),
                              border: Border.all(
                                color: highContrast
                                    ? contrastColor
                                    : accent.withValues(alpha: 0.25),
                              ),
                            ),
                            child: Icon(
                              icon,
                              size: 34 * buttonSize,
                              color: highContrast
                                  ? AccessibilityUtils.getPrimaryButtonForeground(context)
                                  : accent,
                            ),
                          ),
                          SizedBox(width: 16 * buttonSize),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Text(
                                  title,
                                  style: GoogleFonts.lexend(
                                    fontSize: 18 * buttonSize,
                                    fontWeight: FontWeight.w800,
                                    height: 1.2,
                                    color: contrastColor,
                                  ),
                                ),
                                SizedBox(height: 6 * buttonSize),
                                Text(
                                  description,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: GoogleFonts.lexend(
                                    fontSize: 14 * buttonSize,
                                    fontWeight: FontWeight.w500,
                                    height: 1.35,
                                    color: secondaryColor.withValues(
                                      alpha: highContrast ? 1.0 : 0.95,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          ExcludeSemantics(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(Icons.touch_app_rounded, color: accent.withValues(alpha: 0.85), size: 22 * buttonSize),
                                SizedBox(height: 4 * buttonSize),
                                Icon(Icons.arrow_forward_ios_rounded, color: accent, size: 16 * buttonSize),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}