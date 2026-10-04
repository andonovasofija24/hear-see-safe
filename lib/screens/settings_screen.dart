import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:hear_and_see_safe/providers/app_state_provider.dart';
import 'package:hear_and_see_safe/voice_system/application/language_manager.dart';
import 'package:hear_and_see_safe/providers/accessibility_provider.dart';
import 'package:hear_and_see_safe/services/voice_assistant_service.dart';
import 'package:hear_and_see_safe/theme/app_style.dart';
import 'package:hear_and_see_safe/utils/accessibility_utils.dart';
import 'package:hear_and_see_safe/widgets/game_screen_chrome.dart';
import 'package:hear_and_see_safe/widgets/playful_ui.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  late VoiceAssistantService _voiceAssistant;

  @override
  void initState() {
    super.initState();
    _voiceAssistant = Provider.of<VoiceAssistantService>(context, listen: false);
  }

  @override
  void dispose() {
    _voiceAssistant.stop();
    super.dispose();
  }

  static const Color _accent = AppStyle.brandTeal;

  bool get _hc => AccessibilityUtils.isHighContrast(context);
  Color get _fg => _hc ? AccessibilityUtils.getContrastColor(context) : Colors.white;

  @override
  Widget build(BuildContext context) {
    // Rebuild when locale changes so "Пристапност" / High Contrast / Large Text labels update immediately.
    final locale = context.locale;

    return GameScreenChrome(
      accent: _accent,
      title: 'settings.title'.tr(),
      titleFontSize: 26,
      bodyBackground: const EmojiBackdrop(
        emojis: ['⚙️', '🌐', '🔊', '👁️', '📳', '🔆'],
        tint: _accent,
      ),
      child: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final side = ((constraints.maxWidth - 760) / 2).clamp(16.0, double.infinity);
            final wide = constraints.maxWidth - side * 2 >= 520;
            return ListView(
              key: ValueKey(locale.toString()),
              padding: EdgeInsets.fromLTRB(side, 16, side, 32),
              children: [
                PopIn(
                  child: _section(
                    icon: Icons.translate_rounded,
                    color: const Color(0xFF2563EB),
                    title: 'settings.language'.tr(),
                    child: _buildLanguageSelector(context, wide),
                  ),
                ),
                const SizedBox(height: 20),
                PopIn(
                  index: 1,
                  child: _section(
                    icon: Icons.visibility_rounded,
                    color: const Color(0xFF9333EA),
                    title: 'settings.accessibility'.tr(),
                    child: _buildAccessibilitySettings(context),
                  ),
                ),
                const SizedBox(height: 20),
                PopIn(
                  index: 2,
                  child: _section(
                    icon: Icons.volume_up_rounded,
                    color: const Color(0xFFDB2777),
                    title: 'settings.audio'.tr(),
                    child: _buildAudioSettings(context),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  /// Темна плоча за еден дел: икона во обоен круг + наслов, па содржината.
  Widget _section({required IconData icon, required Color color, required String title, required Widget child}) {
    final hc = _hc;
    return Container(
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 18),
      decoration: BoxDecoration(
        color: hc ? Colors.black : Playful.nightRaised.withValues(alpha: 0.9),
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: hc ? Colors.white : Colors.white.withValues(alpha: 0.35), width: hc ? 2 : 2),
        boxShadow: hc ? null : [BoxShadow(color: color.withValues(alpha: 0.3), blurRadius: 22)],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Semantics(
            header: true,
            label: title,
            child: ExcludeSemantics(
              child: Row(
                children: [
                  _iconBubble(icon, color, 52),
                  const SizedBox(width: 14),
                  Expanded(child: Text(title, style: Playful.display(25, color: _fg))),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          child,
        ],
      ),
    );
  }

  Widget _iconBubble(IconData icon, Color color, double size) {
    final hc = _hc;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: hc ? Colors.black : null,
        gradient: hc
            ? null
            : LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [Color.lerp(color, Colors.white, 0.15)!, Color.lerp(color, Colors.black, 0.3)!],
              ),
        border: Border.all(color: Colors.white, width: hc ? 2 : 2.5),
      ),
      child: Icon(icon, color: Colors.white, size: size * 0.52),
    );
  }

  Widget _buildLanguageSelector(BuildContext context, bool wide) {
    return Consumer<AppStateProvider>(
      builder: (context, appState, _) {
        final options = [
          _buildLanguageOption(context, 'Македонски', 'mk', 'МК', appState.currentLanguage),
          _buildLanguageOption(context, 'English', 'en', 'EN', appState.currentLanguage),
          _buildLanguageOption(context, 'Shqip', 'sq', 'SQ', appState.currentLanguage),
        ];
        if (wide) {
          return Row(
            children: [
              for (var i = 0; i < options.length; i++) ...[
                if (i > 0) const SizedBox(width: 12),
                Expanded(child: options[i]),
              ],
            ],
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (var i = 0; i < options.length; i++) ...[
              if (i > 0) const SizedBox(height: 10),
              options[i],
            ],
          ],
        );
      },
    );
  }

  Widget _buildLanguageOption(BuildContext context, String name, String code, String badge, String current) {
    final isSelected = current == code;
    final hc = _hc;

    Locale _localeForCode(String langCode) {
      switch (langCode) {
        case 'mk':
          return const Locale('mk', 'MK');
        case 'sq':
          return const Locale('sq', 'AL');
        case 'en':
        default:
          return const Locale('en', 'US');
      }
    }

    final bg = isSelected
        ? (hc ? const Color(0xFFFFFF00) : Playful.sun)
        : (hc ? Colors.black : Colors.white.withValues(alpha: 0.1));
    final fg = isSelected ? (hc ? Colors.black : Playful.ink) : _fg;

    return Semantics(
      label: name,
      button: true,
      selected: isSelected,
      child: ExcludeSemantics(
        child: PressableScale(
          child: Material(
            color: bg,
            borderRadius: BorderRadius.circular(20),
            child: InkWell(
              borderRadius: BorderRadius.circular(20),
              onTap: () async {
                // Wait so UI text + translations update immediately.
                await context.setLocale(_localeForCode(code));
                Provider.of<AppStateProvider>(context, listen: false).setLanguage(code);
                Provider.of<LanguageManager>(context, listen: false).setUserUiLanguageCode(code);
                await AccessibilityUtils.provideFeedback(
                  context: context,
                  audioFeedback: 'settings.language_changed'.tr(),
                  voiceAssistant: _voiceAssistant,
                );
              },
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 220),
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: hc ? Colors.white : (isSelected ? Colors.white : Colors.white.withValues(alpha: 0.5)),
                    width: isSelected ? 3 : 2,
                  ),
                  boxShadow: isSelected && !hc ? [BoxShadow(color: Playful.sun.withValues(alpha: 0.45), blurRadius: 18)] : null,
                ),
                child: Row(
                  children: [
                    Container(
                      width: 44,
                      height: 44,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: isSelected ? (hc ? Colors.black : Playful.ink) : (hc ? Colors.black : Colors.white.withValues(alpha: 0.15)),
                        border: Border.all(color: isSelected ? Colors.white : _fg.withValues(alpha: 0.6), width: 2),
                      ),
                      child: Text(
                        badge,
                        style: Playful.title(15, color: isSelected ? (hc ? Colors.white : Playful.sun) : _fg),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        name,
                        overflow: TextOverflow.ellipsis,
                        style: Playful.title(19, color: fg),
                      ),
                    ),
                    AnimatedSwitcher(
                      duration: const Duration(milliseconds: 200),
                      child: isSelected
                          ? Icon(Icons.check_circle_rounded, key: const ValueKey('on'), size: 28, color: fg)
                          : const SizedBox(key: ValueKey('off'), width: 28, height: 28),
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

  /// Ред со икона, наслов и прекинувач - целиот ред може да се допре.
  Widget _toggleRow({
    required IconData icon,
    required Color color,
    required String label,
    required bool value,
    required VoidCallback onToggle,
  }) {
    final hc = _hc;
    return MergeSemantics(
      child: Material(
        color: hc ? Colors.black : (value ? Colors.white.withValues(alpha: 0.12) : Colors.white.withValues(alpha: 0.05)),
        borderRadius: BorderRadius.circular(20),
        child: InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: onToggle,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: hc ? Colors.white : (value ? Playful.sun.withValues(alpha: 0.8) : Colors.white.withValues(alpha: 0.25)),
                width: 2,
              ),
            ),
            child: Row(
              children: [
                _iconBubble(icon, color, 44),
                const SizedBox(width: 12),
                Expanded(child: Text(label, style: Playful.title(19, color: _fg))),
                const SizedBox(width: 8),
                Switch(
                  value: value,
                  onChanged: (_) => onToggle(),
                  thumbColor: WidgetStateProperty.resolveWith(
                    (states) => states.contains(WidgetState.selected) ? (hc ? Colors.black : Playful.ink) : Colors.white,
                  ),
                  trackColor: WidgetStateProperty.resolveWith(
                    (states) => states.contains(WidgetState.selected)
                        ? (hc ? const Color(0xFFFFFF00) : Playful.sun)
                        : (hc ? Colors.black : Colors.white.withValues(alpha: 0.2)),
                  ),
                  trackOutlineColor: WidgetStatePropertyAll(hc ? Colors.white : Colors.white.withValues(alpha: 0.6)),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildAccessibilitySettings(BuildContext context) {
    return Consumer<AccessibilityProvider>(
      builder: (context, accessibility, _) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _toggleRow(
              icon: Icons.contrast_rounded,
              color: const Color(0xFF475569),
              label: 'settings.high_contrast'.tr(),
              value: accessibility.highContrastMode,
              onToggle: () {
                accessibility.toggleHighContrast();
                AccessibilityUtils.provideFeedback(context: context);
              },
            ),
            const SizedBox(height: 10),
            _toggleRow(
              icon: Icons.text_fields_rounded,
              color: const Color(0xFF0D9488),
              label: 'settings.large_text'.tr(),
              value: accessibility.largeTextMode,
              onToggle: () {
                accessibility.toggleLargeText();
                AccessibilityUtils.provideFeedback(context: context);
              },
            ),
          ],
        );
      },
    );
  }

  Widget _buildAudioSettings(BuildContext context) {
    return Consumer<AppStateProvider>(
      builder: (context, appState, _) {
        final hc = _hc;
        final percent = (appState.volume * 100).round();
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _toggleRow(
              icon: Icons.record_voice_over_rounded,
              color: const Color(0xFF2563EB),
              label: 'settings.voice_assistant'.tr(),
              value: appState.isVoiceAssistantEnabled,
              onToggle: () {
                appState.toggleVoiceAssistant();
                AccessibilityUtils.provideFeedback(context: context);
              },
            ),
            const SizedBox(height: 10),
            _toggleRow(
              icon: Icons.vibration_rounded,
              color: const Color(0xFFD97706),
              label: 'settings.vibration'.tr(),
              value: appState.vibrationEnabled,
              onToggle: () {
                appState.toggleVibration();
                AccessibilityUtils.provideFeedback(context: context);
              },
            ),
            const SizedBox(height: 10),
            // Јачина на звукот: икона, наслов, процент и лизгач.
            Container(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 6),
              decoration: BoxDecoration(
                color: hc ? Colors.black : Colors.white.withValues(alpha: 0.05),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: hc ? Colors.white : Colors.white.withValues(alpha: 0.25), width: 2),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      _iconBubble(Icons.graphic_eq_rounded, const Color(0xFFDB2777), 44),
                      const SizedBox(width: 12),
                      Expanded(child: Text('settings.volume'.tr(), style: Playful.title(19, color: _fg))),
                      ExcludeSemantics(
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                          decoration: BoxDecoration(
                            color: hc ? Colors.black : Playful.sun,
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(color: Colors.white, width: 2),
                          ),
                          child: Text('$percent%', style: Playful.title(16, color: hc ? Colors.white : Playful.ink)),
                        ),
                      ),
                    ],
                  ),
                  Row(
                    children: [
                      Icon(Icons.volume_mute_rounded, color: _fg.withValues(alpha: 0.8)),
                      Expanded(
                        child: SliderTheme(
                          data: SliderTheme.of(context).copyWith(
                            trackHeight: 10,
                            activeTrackColor: hc ? const Color(0xFFFFFF00) : Playful.sun,
                            inactiveTrackColor: hc ? Colors.white38 : Colors.white.withValues(alpha: 0.2),
                            thumbColor: Colors.white,
                            overlayColor: (hc ? Colors.white : Playful.sun).withValues(alpha: 0.2),
                            activeTickMarkColor: hc ? Colors.black : Playful.ink.withValues(alpha: 0.4),
                            inactiveTickMarkColor: Colors.white.withValues(alpha: 0.4),
                            thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 14),
                          ),
                          child: Slider(
                            value: appState.volume,
                            onChanged: (value) {
                              appState.setVolume(value);
                              AccessibilityUtils.provideFeedback(context: context);
                            },
                            min: 0.0,
                            max: 1.0,
                            divisions: 10,
                            label: '$percent%',
                          ),
                        ),
                      ),
                      Icon(Icons.volume_up_rounded, color: _fg.withValues(alpha: 0.8)),
                    ],
                  ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}