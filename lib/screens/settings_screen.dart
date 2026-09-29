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

  @override
  Widget build(BuildContext context) {
    // Rebuild when locale changes so "Пристапност" / High Contrast / Large Text labels update immediately.
    final locale = context.locale;

    return GameScreenChrome(
      accent: AppStyle.brandTeal,
      title: 'settings.title'.tr(),
      titleFontSize: 26,
      child: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            key: ValueKey(locale.toString()),
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _buildSectionTitle(context, 'settings.language'.tr()),
              _buildLanguageSelector(context),
              const SizedBox(height: 24),
              _buildSectionTitle(context, 'settings.accessibility'.tr()),
              _buildAccessibilitySettings(context),
              const SizedBox(height: 24),
              _buildSectionTitle(context, 'settings.audio'.tr()),
              _buildAudioSettings(context),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSectionTitle(BuildContext context, String title) {
    final contrastColor = AccessibilityUtils.getContrastColor(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Text(
        title,
        style: TextStyle(
          fontSize: 24,
          fontWeight: FontWeight.bold,
          color: contrastColor,
        ),
      ),
    );
  }

  Widget _buildLanguageSelector(BuildContext context) {
    final cardColor = AccessibilityUtils.getCardBackgroundColor(context);
    final contrastColor = AccessibilityUtils.getContrastColor(context);
    return Consumer<AppStateProvider>(
      builder: (context, appState, _) {
        return Card(
          elevation: AccessibilityUtils.isHighContrast(context) ? 0 : 4,
          color: cardColor,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: AccessibilityUtils.getCardBorder(context, fallbackColor: contrastColor),
          ),
          child: Column(
            children: [
              _buildLanguageOption(context, 'Македонски', 'mk', appState.currentLanguage),
              _buildLanguageOption(context, 'English', 'en', appState.currentLanguage),
              _buildLanguageOption(context, 'Shqip', 'sq', appState.currentLanguage),
            ],
          ),
        );
      },
    );
  }

  Widget _buildLanguageOption(BuildContext context, String name, String code, String current) {
    final isSelected = current == code;
    final contrastColor = AccessibilityUtils.getContrastColor(context);

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

    return ListTile(
      title: Text(
        name,
        style: TextStyle(
          fontSize: 20,
          fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
          color: contrastColor,
        ),
      ),
      trailing: isSelected
          ? Icon(Icons.check_circle, color: AccessibilityUtils.getAccentColor(context), size: 28)
          : null,
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
    );
  }

  Widget _buildAccessibilitySettings(BuildContext context) {
    final cardColor = AccessibilityUtils.getCardBackgroundColor(context);
    final contrastColor = AccessibilityUtils.getContrastColor(context);
    return Consumer<AccessibilityProvider>(
      builder: (context, accessibility, _) {
        return Card(
          elevation: AccessibilityUtils.isHighContrast(context) ? 0 : 4,
          color: cardColor,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: AccessibilityUtils.getCardBorder(context, fallbackColor: contrastColor),
          ),
          child: Column(
            children: [
              SwitchListTile(
                title: Text(
                  'settings.high_contrast'.tr(),
                  style: TextStyle(
                    fontSize: 20,
                    color: contrastColor,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                value: accessibility.highContrastMode,
                onChanged: (value) {
                  accessibility.toggleHighContrast();
                  AccessibilityUtils.provideFeedback(context: context);
                },
              ),
              SwitchListTile(
                title: Text(
                  'settings.large_text'.tr(),
                  style: TextStyle(
                    fontSize: 20,
                    color: contrastColor,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                value: accessibility.largeTextMode,
                onChanged: (value) {
                  accessibility.toggleLargeText();
                  AccessibilityUtils.provideFeedback(context: context);
                },
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildAudioSettings(BuildContext context) {
    final cardColor = AccessibilityUtils.getCardBackgroundColor(context);
    final contrastColor = AccessibilityUtils.getContrastColor(context);
    return Consumer<AppStateProvider>(
      builder: (context, appState, _) {
        return Card(
          elevation: AccessibilityUtils.isHighContrast(context) ? 0 : 4,
          color: cardColor,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: AccessibilityUtils.getCardBorder(context, fallbackColor: contrastColor),
          ),
          child: Column(
            children: [
              SwitchListTile(
                title: Text(
                  'settings.voice_assistant'.tr(),
                  style: TextStyle(
                    fontSize: 20,
                    color: contrastColor,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                value: appState.isVoiceAssistantEnabled,
                onChanged: (value) {
                  appState.toggleVoiceAssistant();
                  AccessibilityUtils.provideFeedback(context: context);
                },
              ),
              SwitchListTile(
                title: Text(
                  'settings.vibration'.tr(),
                  style: TextStyle(
                    fontSize: 20,
                    color: contrastColor,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                value: appState.vibrationEnabled,
                onChanged: (value) {
                  appState.toggleVibration();
                  AccessibilityUtils.provideFeedback(context: context);
                },
              ),
              ListTile(
                title: Text(
                  'settings.volume'.tr(),
                  style: TextStyle(
                    fontSize: 20,
                    color: contrastColor,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                subtitle: Slider(
                  value: appState.volume,
                  onChanged: (value) {
                    appState.setVolume(value);
                    AccessibilityUtils.provideFeedback(context: context);
                  },
                  min: 0.0,
                  max: 1.0,
                  divisions: 10,
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}