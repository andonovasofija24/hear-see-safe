import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:hear_and_see_safe/providers/accessibility_provider.dart';
import 'package:hear_and_see_safe/providers/app_state_provider.dart';
import 'package:hear_and_see_safe/services/voice_assistant_service.dart';
import 'package:hear_and_see_safe/utils/vibration_utils.dart';

/// Цветови за режим висок контраст (темна позадина, максимална читливост)
class _HighContrastColors {
  static const Color background = Color(0xFF000000);
  static const Color text = Color(0xFFFFFFFF);
  static const Color accent = Color(0xFFFFFF00);   // светло жолта за акценти
  static const Color cardBackground = Color(0xFF0D0D0D);
  static const Color border = Color(0xFFFFFFFF);
  static const Color buttonBackground = Color(0xFF1A1A1A);
  static const Color buttonForeground = Color(0xFFFFFFFF);
  static const Color disabled = Color(0xFFB0B0B0);
}

class AccessibilityUtils {
  static bool isHighContrast(BuildContext context) {
    return Provider.of<AccessibilityProvider>(context, listen: false).highContrastMode;
  }

  static double getTextScale(BuildContext context) {
    final accessibilityProvider = Provider.of<AccessibilityProvider>(context);
    return accessibilityProvider.textScale;
  }

  static Color getContrastColor(BuildContext context, {Color? lightColor, Color? darkColor}) {
    final accessibilityProvider = Provider.of<AccessibilityProvider>(context);
    final isHighContrast = accessibilityProvider.highContrastMode;

    if (isHighContrast) {
      return lightColor ?? _HighContrastColors.text;
    }
    return darkColor ?? const Color(0xFF0F172A);
  }

  static Color getBackgroundColor(BuildContext context) {
    final accessibilityProvider = Provider.of<AccessibilityProvider>(context);
    final isHighContrast = accessibilityProvider.highContrastMode;

    if (isHighContrast) {
      return _HighContrastColors.background;
    }
    return const Color(0xFFF1F5F9);
  }

  /// Позадина за AppBar – црна во режим висок контраст
  static Color getAppBarBackgroundColor(BuildContext context) {
    return isHighContrast(context) ? _HighContrastColors.background : const Color(0xFF0F766E);
  }

  /// Боја за акценти (чекмарки, икони) – жолта во HC за максимална видливост
  static Color getAccentColor(BuildContext context) {
    return isHighContrast(context) ? _HighContrastColors.accent : const Color(0xFF0D9488);
  }

  /// Позадина за карти – црна со бели рабови во HC
  static Color getCardBackgroundColor(BuildContext context) {
    return isHighContrast(context) ? _HighContrastColors.cardBackground : Colors.white;
  }

  /// Раб за карти – бел 2px во HC, во нормално contrastColor 3px
  static BorderSide getCardBorder(BuildContext context, {Color? fallbackColor, double? fallbackWidth}) {
    if (isHighContrast(context)) {
      return const BorderSide(color: _HighContrastColors.border, width: 2);
    }
    final c = fallbackColor ?? getContrastColor(context);
    return BorderSide(color: c, width: fallbackWidth ?? 3);
  }

  /// Секундарен текст (опис) – чисто бел во HC
  static Color getSecondaryTextColor(BuildContext context) {
    return isHighContrast(context)
        ? _HighContrastColors.text
        : const Color(0xFF475569);
  }

  /// Позадина за примарни копчиња
  static Color getPrimaryButtonBackground(BuildContext context) {
    return isHighContrast(context) ? _HighContrastColors.buttonBackground : const Color(0xFF0F766E);
  }

  /// Текст/икони на примарни копчиња
  static Color getPrimaryButtonForeground(BuildContext context) {
    return isHighContrast(context) ? _HighContrastColors.buttonForeground : Colors.white;
  }

  /// Боја за исклучено/неактивно – читлива на црна
  static Color getDisabledColor(BuildContext context) {
    return isHighContrast(context) ? _HighContrastColors.disabled : Colors.grey;
  }

  /// Opacity за секундарен текст (0.7 нормално, 1.0 HC)
  static double getSecondaryTextOpacity(BuildContext context) {
    return isHighContrast(context) ? 1.0 : 0.7;
  }

  static double getButtonSize(BuildContext context) {
    final accessibilityProvider = Provider.of<AccessibilityProvider>(context);
    return accessibilityProvider.buttonSize;
  }

  /// Заеднички плеер за сите кратки "фидбек" клипови (гласовен асистент,
  /// избор на јазик итн.) низ целата апликација.
  static final AudioPlayer _feedbackPlayer = AudioPlayer();

  /// Го запира било кој звук/клип што моментално свири преку споделениот
  /// фидбек-плеер (пр. кога веќе е избран јазик и се преминува понатаму).
  static Future<void> stopFeedback() async {
    try {
      await _feedbackPlayer.stop();
    } catch (_) {}
  }

  static Future<void> provideFeedback({
    required BuildContext context,
    bool vibrate = true,
    String? audioFeedback,
    VoiceAssistantService? voiceAssistant,
    /// Патека (релативна на assets/, пр. 'audio/language/mk/selected.mp3')
    /// до однапред снимен говорен клип. Се пробува ПРВО; само ако не постои
    /// (или падне) се паѓа назад на `audioFeedback` преку системскиот TTS.
    String? clipAssetPath,
  }) async {
    final appState = Provider.of<AppStateProvider>(context, listen: false);

    if (vibrate && appState.vibrationEnabled) {
      if (await VibrationUtils.hasVibrator()) {
        await VibrationUtils.vibrate(duration: 100);
      }
    }

    if (!appState.isVoiceAssistantEnabled) return;

    if (clipAssetPath != null) {
      // ВАЖНО: некои платформи (веб) тивко "голтаат" формат-грешка без да
      // фрлат исклучок од .play() - плеерот никогаш не влегува во состојба
      // "playing". Затоа не се потпираме само на тоа дали .play() фрлил
      // грешка - експлицитно чекаме потврда дека звукот НАВИСТИНА почнал,
      // инаку функцијата излегува со return; пред TTS-резервата да стигне
      // на ред, и корисникот не слуша ништо.
      bool reachedPlaying = false;
      final startedCompleter = Completer<void>();
      late final StreamSubscription<PlayerState> stateSub;
      stateSub = _feedbackPlayer.onPlayerStateChanged.listen((state) {
        if (state == PlayerState.playing) {
          reachedPlaying = true;
          if (!startedCompleter.isCompleted) startedCompleter.complete();
        }
        if ((state == PlayerState.completed || state == PlayerState.stopped) &&
            !startedCompleter.isCompleted) {
          startedCompleter.complete();
        }
      });

      bool playCallSucceeded = false;
      try {
        await _feedbackPlayer.stop();
        await _feedbackPlayer.play(AssetSource(clipAssetPath));
        playCallSucceeded = true;
      } catch (_) {
        playCallSucceeded = false;
      }

      if (playCallSucceeded) {
        await startedCompleter.future.timeout(const Duration(seconds: 4), onTimeout: () {});
      }
      await stateSub.cancel();

      if (playCallSucceeded && reachedPlaying) return; // навистина проработи - готово.
      // инаку продолжи кон TTS-резервата подолу.
    }

    if (audioFeedback != null && voiceAssistant != null) {
      final langCode = context.locale.languageCode;
      await voiceAssistant.speakWithLanguage(audioFeedback, langCode, vibrate: false);
    }
  }

  static Widget buildAccessibleButton({
    required BuildContext context,
    required String text,
    required VoidCallback onPressed,
    IconData? icon,
    Color? backgroundColor,
    Color? textColor,
    double? width,
    double? height,
  }) {
    final buttonSize = getButtonSize(context);
    final contrastColor = getContrastColor(context, darkColor: textColor);
    final bgColor = backgroundColor ?? getPrimaryButtonBackground(context);
    final fgColor = textColor ?? getPrimaryButtonForeground(context);
    final borderWidth = isHighContrast(context) ? 3 : 2;

    return SizedBox(
      width: width != null ? width * buttonSize : 200 * buttonSize,
      height: height != null ? height * buttonSize : 60 * buttonSize,
      child: ElevatedButton(
        onPressed: onPressed,
        style: ElevatedButton.styleFrom(
          backgroundColor: bgColor,
          foregroundColor: fgColor,
          textStyle: TextStyle(
            fontSize: 20 * buttonSize,
            fontWeight: FontWeight.bold,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: BorderSide(
              color: contrastColor,
              width: borderWidth.toDouble(),
            ),
          ),
          elevation: isHighContrast(context) ? 0 : 4,
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (icon != null) ...[
              Icon(icon, size:  buttonSize),
              const SizedBox(width: 8),
            ],
            Text(text),
          ],
        ),
      ),
    );
  }
}