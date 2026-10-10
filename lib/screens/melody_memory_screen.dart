import 'dart:async';

import 'dart:math';

import 'package:flutter/material.dart';

import 'package:provider/provider.dart';

import 'package:easy_localization/easy_localization.dart';

import 'package:audioplayers/audioplayers.dart';

import 'package:hear_and_see_safe/services/voice_assistant_service.dart';

import 'package:hear_and_see_safe/utils/accessibility_utils.dart';

import 'package:hear_and_see_safe/utils/vibration_utils.dart';

import 'package:hear_and_see_safe/widgets/game_screen_chrome.dart';

import 'package:hear_and_see_safe/widgets/playful_ui.dart';



/// Колку пати е поголем текстот на екранот за мелодиска меморија.

const double _kMelText = 1.6;



/// Мемorија на звуци: детето слуша НИЗА звуци по ред (пр. мачка, мачка,

/// куче, автомобил) - никогаш автоматски, само по притискање на Почни да

/// слушаш. Потоа треба да ги тапне истите звуци, во истиот редослед.

/// Должината на низата расте од 2 до 7 звуци низ 20-те вкупни рунди. На

/// крајот се прикажува колку рунди се погодени, а колку промашени.

class MelodyMemoryScreen extends StatefulWidget {

  const MelodyMemoryScreen({super.key});



  @override

  State<MelodyMemoryScreen> createState() => _MelodyMemoryScreenState();

}



class _MelodyMemoryScreenState extends State<MelodyMemoryScreen> {

  static const Color _moduleAccent = Color(0xFF9333EA);

  static const int _totalRounds = 20;



  late VoiceAssistantService _voiceAssistant;

  final AudioPlayer _audioPlayer = AudioPlayer();
  // Посебен плеер за ефектите, за да не го прекинуваат звукот на низата.
  final AudioPlayer _effectsPlayer = AudioPlayer();
  static const Duration _minimumSoundTime = Duration(milliseconds: 1100);
  static const Duration _gapBetweenSounds = Duration(milliseconds: 240);
  int _playbackGeneration = 0;

  final Random _random = Random();



  static const List<String> _soundIds = ['cat', 'dog', 'car', 'rain'];



  static const Map<String, String> _soundAssets = {

    'cat': 'assets/sounds/sound_identification/meow.mp3',

    'dog': 'assets/sounds/sound_identification/bark.mp3',

    'car': 'assets/sounds/sound_identification/car.mp3',

    'rain': 'assets/sounds/sound_identification/rain.mp3',

  };



  static const Map<String, IconData> _soundIcons = {

    'cat': Icons.pets_rounded,

    'dog': Icons.cruelty_free_rounded,

    'car': Icons.directions_car_filled_rounded,

    'rain': Icons.water_drop_rounded,

  };



  static const Map<String, String> _soundLabelKeys = {

    'cat': 'melody.sound1',

    'dog': 'melody.sound2',

    'car': 'melody.sound3',

    'rain': 'melody.sound4',

  };



  static const Map<String, Color> _soundColors = {

    'cat': Color(0xFF9333EA),

    'dog': Color(0xFFD97706),

    'car': Color(0xFF2563EB),

    'rain': Color(0xFF0D9488),

  };



  /// Должина на низата по рунда: 2,3,4,5,6,7, па се повторува пак од 2 - за

  /// вкупно 20 рунди.

  late final List<int> _lengthPerRound =

      List.generate(_totalRounds, (i) => 2 + (i % 6));



  List<String> _sequence = [];

  int _userIndex = 0;

  bool _revealed = false;

  bool _isPlaying = false;

  String? _flashingId;

  int _round = 0;

  int _hits = 0;

  bool _gameOver = false;

  bool _explanationOpen = false;



  /// Рундата е одговорена (точно или погрешно) и се чека преминот кон

  /// следната. Блокира секој дополнителен допир/копче до `_prepareRound`.

  bool _answered = false;



  String get _langCode => context.locale.languageCode;



  @override

  void initState() {

    super.initState();

    _voiceAssistant = Provider.of<VoiceAssistantService>(context, listen: false);

    _voiceAssistant.initialize();

    _prepareRound();

  }



  @override

  void dispose() {

    // Го запира говорот/звукот веднаш штом се напушта екранот - без разлика

    // дали објаснувањето било отворено или не.

    _voiceAssistant.stop();

    _audioPlayer.dispose();
    _effectsPlayer.dispose();
    _playbackGeneration++;

    super.dispose();

  }



  void _prepareRound() {
    _playbackGeneration++;

    final length = _lengthPerRound[_round];

    setState(() {

      _sequence = List.generate(length, (_) => _soundIds[_random.nextInt(_soundIds.length)]);

      _userIndex = 0;

      _revealed = false;

      _isPlaying = false;

      _answered = false;

      _flashingId = null;

    });

  }



  /// Важно: на веб, некои формат-грешки НЕ фрлаат исклучок од .play() -

  /// плеерот тивко "голта" грешка и никогаш не влегува во состојба

  /// "playing". Затоа експлицитно чекаме потврда дека звукот НАВИСТИНА

  /// почнал, инаку TTS-резервата погрешно никогаш не се активира.

  Future<void> _playClip(String key, String fallbackText) async {

    if (!mounted) return;

    final relativePath = 'audio/melody_memory/$_langCode/$key.mp3';

    try {

      await _audioPlayer.stop();

    } catch (_) {}



    bool reachedPlaying = false;

    final startedCompleter = Completer<void>();

    final finishedCompleter = Completer<void>();

    late final StreamSubscription<PlayerState> stateSub;

    stateSub = _audioPlayer.onPlayerStateChanged.listen((state) {

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

      await _audioPlayer.play(AssetSource(relativePath));

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

      await _voiceAssistant.speakWithLanguage(fallbackText, _langCode, vibrate: false);

    }

  }



  /// Секој звук се слуша до крај, со ИСТО минимално време во сите рунди.
  /// onPlayerComplete се слуша пред play(), за да не се пропушти настанот.
  Future<void> _playSoundEffect(String id) async {
    final path = _soundAssets[id];
    if (path == null) return;
    final relative = path.startsWith('assets/') ? path.substring(7) : path;
    final startedAt = DateTime.now();
    final completed = Completer<void>();
    final subscription = _effectsPlayer.onPlayerComplete.listen((_) {
      if (!completed.isCompleted) completed.complete();
    });
    try {
      await _effectsPlayer.stop();
      await _effectsPlayer.setReleaseMode(ReleaseMode.stop);
      await _effectsPlayer.play(AssetSource(relative));
      // Без фиксно кратење на 550 ms: чекај вистински крај на MP3.
      await completed.future.timeout(const Duration(seconds: 12));
    } catch (_) {
      // Ако звукот не може да се пушти, сепак задржи ист ритам.
    } finally {
      await subscription.cancel();
      final elapsed = DateTime.now().difference(startedAt);
      if (elapsed < _minimumSoundTime) {
        await Future.delayed(_minimumSoundTime - elapsed);
      }
    }
  }

  Future<void> _playSequence() async {
    if (_isPlaying || _answered || _gameOver) return;
    final generation = ++_playbackGeneration;
    setState(() {
      _isPlaying = true;
      _revealed = true;
      _userIndex = 0;
    });
    try {
      for (final id in _sequence) {
        if (!mounted || generation != _playbackGeneration) return;
        setState(() => _flashingId = id);
        await _playSoundEffect(id);
        if (!mounted || generation != _playbackGeneration) return;
        if (await VibrationUtils.hasVibrator()) {
          await VibrationUtils.vibrate(duration: 50);
        }
        setState(() => _flashingId = null);
        await Future.delayed(_gapBetweenSounds);
      }
    } finally {
      if (mounted && generation == _playbackGeneration) {
        setState(() {
          _flashingId = null;
          _isPlaying = false;
        });
      }
    }
  }

  Future<void> _onTapIcon(String id) async {

    if (_isPlaying || !_revealed || _gameOver || _answered) return;

    // Низата е веќе погодена (се чека следната рунда) - вишок допир.

    if (_userIndex >= _sequence.length) return;



    // ВАЖНО: одговорот се проценува и состојбата се менува СИНХРОНО, пред

    // секое `await`. Порано проверката се правеше дури по звукот/вибрацијата,

    // па втор допир (двоен тап, тастатура + глувче, нетрпеливо дете по

    // грешка) влегуваше повторно и `_nextRound` се викаше двапати -> рунда

    // 15 скокаше на 17.

    final roundAtTap = _round;

    final isCorrectStep = id == _sequence[_userIndex];

    final finishesRound = !isCorrectStep || _userIndex + 1 >= _sequence.length;



    setState(() {

      _flashingId = id;

      if (isCorrectStep) _userIndex++;

      if (finishesRound) _answered = true;

      if (isCorrectStep && finishesRound) _hits++;

    });



    await _playSoundEffect(id);

    if (await VibrationUtils.hasVibrator()) {

      await VibrationUtils.vibrate(duration: 60);

    }

    await Future.delayed(const Duration(milliseconds: 150));

    if (!mounted) return;

    if (_flashingId == id) setState(() => _flashingId = null);



    if (!finishesRound) return;



    if (isCorrectStep) {

      await _playClip('correct', 'melody.correct'.tr());

    } else {

      await _playClip('incorrect', 'melody.incorrect'.tr());

    }

    await Future.delayed(const Duration(milliseconds: 900));

    if (!mounted) return;

    _advanceFrom(roundAtTap);

  }



  /// Единствено место каде што `_round` се зголемува: точно еднаш по

  /// одговорена рунда (точно или погрешно). Ако рундата веќе е сменета

  /// (пр. рестарт во меѓувреме), повикот се игнорира.

  void _advanceFrom(int answeredRound) {

    if (!_answered || _round != answeredRound || _gameOver) return;

    final newRound = _round + 1;

    if (newRound >= _totalRounds) {

      setState(() {

        _round = _totalRounds - 1;

        _gameOver = true;

        _answered = false;

      });

    } else {

      setState(() => _round = newRound);

      _prepareRound();

    }

  }



  void _restart() {
    _playbackGeneration++;
    _effectsPlayer.stop();

    setState(() {

      _round = 0;

      _hits = 0;

      _gameOver = false;

    });

    _prepareRound();

  }



  void _toggleExplanation() {

    final opening = !_explanationOpen;

    setState(() => _explanationOpen = opening);

    if (opening) {

      _playClip('explanation', 'melody.explanation_text'.tr());

    } else {

      // Враќање кон играта: веднаш запри го говорот на објаснувањето.

      _voiceAssistant.stop();

      _audioPlayer.stop();

    }

  }



  @override

  Widget build(BuildContext context) {

    final hc = AccessibilityUtils.isHighContrast(context);

    final fg = hc ? AccessibilityUtils.getContrastColor(context) : Colors.white;



    return GameScreenChrome(

      accent: _moduleAccent,

      title: 'features.melody_memory'.tr(),

      bodyBackground: const EmojiBackdrop(

        emojis: ['🎹', '🎵', '🎶', '🐱', '🐶', '🌧️'],

        tint: _moduleAccent,

      ),

      child: SafeArea(

        child: LayoutBuilder(

          builder: (context, constraints) {

            final side = ((constraints.maxWidth - 980) / 2).clamp(16.0, double.infinity);

            final header = <Widget>[

              PlayfulExplainButton(

                open: _explanationOpen,

                label: _explanationOpen

                    ? 'melody.explanation_toggle_close'.tr()

                    : 'melody.explanation_toggle_open'.tr(),

                onTap: _toggleExplanation,

              ),

              if (_explanationOpen)

                PlayfulExplainPanel(

                  icon: Icons.volume_up_rounded,

                  title: 'melody.explanation_title'.tr(),

                  text: 'melody.explanation_text'.tr(),

                  accent: _moduleAccent,

                ),

              const SizedBox(height: 16),

            ];



            if (_gameOver) {

              final misses = _totalRounds - _hits;

              return Column(

                crossAxisAlignment: CrossAxisAlignment.stretch,

                children: [

                  Flexible(

                    child: SingleChildScrollView(

                      padding: EdgeInsets.fromLTRB(side, 12, side, 0),

                      child: Column(

                        crossAxisAlignment: CrossAxisAlignment.stretch,

                        children: [

                          ...header,

                          Text(

                            'melody.game_over_title'.tr(),

                            textAlign: TextAlign.center,

                            style: Playful.display(26 * _kMelText, color: fg),

                          ),

                        ],

                      ),

                    ),

                  ),

                  Expanded(

                    child: PlayfulResult(

                      text: 'melody.final_summary'.tr(args: [

                        _hits.toString(),

                        misses.toString(),

                        _totalRounds.toString(),

                      ]),

                      buttonLabel: 'melody.play_again'.tr(),

                      onAgain: _restart,

                      stars: _hits,

                      total: _totalRounds,

                    ),

                  ),

                ],

              );

            }



            return ListView(

              padding: EdgeInsets.fromLTRB(side, 12, side, 28),

              children: [

                ...header,

                RoundProgress(

                  label: 'melody.rounds_progress'.tr(args: [

                    (_round + 1).toString(),

                    _totalRounds.toString(),

                  ]),

                  current: _round,

                  total: _totalRounds,

                  extra: 'melody.score'.tr(args: [_hits.toString()]),

                ),

                const SizedBox(height: 20),

                _buildSequenceNotes(hc),

                const SizedBox(height: 18),

                if (!_revealed)

                  Center(

                    child: SoundOrb(

                      icon: Icons.play_arrow_rounded,

                      label: 'melody.start_listening'.tr(),

                      onTap: _playSequence,

                      active: _isPlaying,

                      size: 150,

                    ),

                  )

                else ...[

                  PlayfulHint('melody.choose_prompt'.tr()),

                  const SizedBox(height: 12),

                  Center(

                    child: PlayfulGhostButton(

                      icon: Icons.replay_rounded,

                      label: 'melody.listen_again'.tr(),

                      onTap: (_isPlaying || _answered) ? null : _playSequence,

                    ),

                  ),

                ],

                const SizedBox(height: 20),

                _buildIconGrid(constraints.maxWidth - side * 2),

              ],

            );

          },

        ),

      ),

    );

  }



  /// Ноти за низата: колку звуци има во рундата и колку се веќе погодени

  /// (злато). Додека низата свири, тековната нота пулсира.

  Widget _buildSequenceNotes(bool hc) {

    final done = hc ? const Color(0xFFFFFF00) : Playful.sun;

    final idle = hc ? Colors.white38 : Colors.white.withValues(alpha: 0.35);

    return ExcludeSemantics(

      child: Wrap(

        alignment: WrapAlignment.center,

        spacing: 10,

        runSpacing: 8,

        children: [

          for (var i = 0; i < _sequence.length; i++)

            AnimatedContainer(

              duration: const Duration(milliseconds: 250),

              curve: Curves.easeOutBack,

              width: 56,

              height: 56,

              decoration: BoxDecoration(

                shape: BoxShape.circle,

                color: i < _userIndex ? done : (hc ? Colors.black : Playful.nightRaised.withValues(alpha: 0.85)),

                border: Border.all(color: i < _userIndex ? Colors.white : idle, width: 2),

                boxShadow: i < _userIndex && !hc ? [BoxShadow(color: Playful.sun.withValues(alpha: 0.5), blurRadius: 12)] : null,

              ),

              child: Icon(

                Icons.music_note_rounded,

                size: 31,

                color: i < _userIndex ? (hc ? Colors.black : Playful.ink) : (hc ? Colors.white : Colors.white.withValues(alpha: 0.7)),

              ),

            ),

        ],

      ),

    );

  }



  Widget _buildIconGrid(double width) {

    final interactive = _revealed && !_isPlaying && !_gameOver && !_answered;

    return PlayfulGrid(

      columns: 2,

      aspectRatio: width < 420 ? 1.08 : 1.30,

      children: [

        for (var i = 0; i < _soundIds.length; i++)

          PopIn(

            index: i,

            child: SoundTile(

              icon: _soundIcons[_soundIds[i]]!,

              label: _soundLabelKeys[_soundIds[i]]!.tr(),

              color: _soundColors[_soundIds[i]]!,

              onTap: interactive ? () => _onTapIcon(_soundIds[i]) : null,

              enabled: interactive,

              flash: _flashingId == _soundIds[i],

            ),

          ),

      ],

    );

  }

}