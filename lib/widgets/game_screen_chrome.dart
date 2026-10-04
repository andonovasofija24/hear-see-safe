import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:hear_and_see_safe/theme/app_style.dart';
import 'package:hear_and_see_safe/utils/accessibility_utils.dart';
import 'package:hear_and_see_safe/widgets/category_voice_command_button.dart';

/// Shared shell for game / activity screens: accent-tinted gradient, soft blobs,
/// Lexend titles — high contrast stays flat and semantic-friendly.
class GameScreenChrome extends StatelessWidget {
  const GameScreenChrome({
    super.key,
    required this.accent,
    required this.title,
    required this.child,
    this.actions,
    this.leading,
    this.titleFontSize = 22,
    this.voiceCommand = true,
    this.voiceOptions = const [],
    this.onVoiceBack,
  });

  /// Копче за гласовна команда горе десно (и копчето Г), во секоја игра:
  /// „назад“, имињата на другите игри / „поставки“ / „главно мени“ и
  /// `voiceOptions` (категориите/режимите на самата игра). Се исклучува кај
  /// екраните што веќе имаат свое копче на секој поглед (Брајова азбука).
  final bool voiceCommand;
  final List<VoiceCategoryOption> voiceOptions;

  /// Што значи „назад“ (стандардно: затвори го екранот).
  final VoidCallback? onVoiceBack;

  final Color accent;
  final String title;
  final Widget child;
  final List<Widget>? actions;
  final Widget? leading;
  final double titleFontSize;

  List<Widget>? _actions(BuildContext context, Color fg) {
    if (!voiceCommand) return actions;
    return [
      ...?actions,
      CategoryVoiceCommandButton(
        options: voiceOptions,
        onBack: onVoiceBack ?? () => Navigator.of(context).maybePop(),
        iconOnly: true,
        foreground: fg,
        respondToHotkey: true,
        hotkeyPriority: 0,
      ),
      const SizedBox(width: 6),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final hc = AccessibilityUtils.isHighContrast(context);
    final bg = AccessibilityUtils.getBackgroundColor(context);
    final contrast = AccessibilityUtils.getContrastColor(context);
    final appBarBg = AccessibilityUtils.getAppBarBackgroundColor(context);
    final buttonSize = AccessibilityUtils.getButtonSize(context);
    final scaledTitleSize = titleFontSize * buttonSize;

    final titleStyle = hc
        ? TextStyle(
            fontSize: scaledTitleSize,
            fontWeight: FontWeight.bold,
            color: contrast,
          )
        : GoogleFonts.lexend(
            fontSize: scaledTitleSize,
            fontWeight: FontWeight.w800,
            color: Colors.white,
            height: 1.2,
          );

    if (hc) {
      return Scaffold(
        backgroundColor: bg,
        appBar: AppBar(
          title: Text(title, style: titleStyle),
          backgroundColor: appBarBg,
          foregroundColor: contrast,
          iconTheme: IconThemeData(color: contrast),
          actionsIconTheme: IconThemeData(color: contrast),
          actions: _actions(context, contrast),
          leading: leading,
        ),
        body: child,
      );
    }

    final bodyTop = Color.lerp(const Color(0xFFECFEFF), accent, 0.14)!;
    final bodyBottom = Color.lerp(const Color(0xFFF8FAFC), accent, 0.06)!;

    return Scaffold(
      backgroundColor: bodyTop,
      appBar: AppBar(
        title: Text(title, style: titleStyle),
        flexibleSpace: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                Color.lerp(accent, const Color(0xFF0F172A), 0.22)!,
                accent,
                Color.lerp(accent, const Color(0xFF5EEAD4), 0.35)!,
              ],
            ),
          ),
        ),
        backgroundColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        foregroundColor: Colors.white,
        iconTheme: const IconThemeData(color: Colors.white),
        actionsIconTheme: const IconThemeData(color: Colors.white),
        actions: _actions(context, Colors.white),
        leading: leading,
      ),
      body: Stack(
        fit: StackFit.expand,
        children: [
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [bodyTop, bodyBottom],
              ),
            ),
          ),
          IgnorePointer(
            child: ExcludeSemantics(
              child: SizedBox.expand(
                child: CustomPaint(
                  painter: _GameBlobsPainter(accent: accent),
                ),
              ),
            ),
          ),
          child,
        ],
      ),
    );
  }
}

/// Lexend helpers for in-body copy on themed screens (no logic impact).
abstract final class GameTypography {
  static TextStyle heading(BuildContext context, Color contrast, double size) {
    if (AccessibilityUtils.isHighContrast(context)) {
      return TextStyle(
        fontSize: size,
        fontWeight: FontWeight.bold,
        color: contrast,
      );
    }
    return GoogleFonts.lexend(
      fontSize: size,
      fontWeight: FontWeight.w800,
      color: contrast,
      height: 1.25,
    );
  }

  static TextStyle body(BuildContext context, Color contrast, double size) {
    if (AccessibilityUtils.isHighContrast(context)) {
      return TextStyle(fontSize: size, color: contrast);
    }
    return GoogleFonts.lexend(
      fontSize: size,
      fontWeight: FontWeight.w600,
      color: contrast,
      height: 1.35,
    );
  }
}

class _GameBlobsPainter extends CustomPainter {
  _GameBlobsPainter({required this.accent});

  final Color accent;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;

    void blob(Offset c, double r, Color color) {
      canvas.drawCircle(c, r, Paint()..color = color);
    }

    final a1 = accent.withValues(alpha: 0.14);
    final a2 = Color.lerp(accent, const Color(0xFFA78BFA), 0.4)!.withValues(alpha: 0.12);
    final a3 = Color.lerp(accent, const Color(0xFF38BDF8), 0.5)!.withValues(alpha: 0.1);

    blob(Offset(size.width * 0.9, size.height * 0.05), size.width * 0.26, a1);
    blob(Offset(size.width * -0.04, size.height * 0.16), size.width * 0.22, a2);
    blob(Offset(size.width * 0.68, size.height * 0.4), size.width * 0.32, a3);
    blob(Offset(size.width * 0.1, size.height * 0.76), size.width * 0.24,
        accent.withValues(alpha: 0.08));
    blob(Offset(size.width * 0.86, size.height * 0.9), size.width * 0.18,
        const Color(0xFFF472B6).withValues(alpha: 0.08));
  }

  @override
  bool shouldRepaint(covariant _GameBlobsPainter oldDelegate) =>
      oldDelegate.accent != accent;
}

/// Optional soft card for hints / stats — skipped in high contrast (plain text).
class GameSoftPanel extends StatelessWidget {
  const GameSoftPanel({
    super.key,
    required this.accent,
    required this.child,
    this.padding = const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
  });

  final Color accent;
  final Widget child;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    if (AccessibilityUtils.isHighContrast(context)) {
      return Padding(padding: padding, child: child);
    }
    return Padding(
      padding: padding,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.92),
          borderRadius: BorderRadius.circular(18),
          border: Border(
            left: BorderSide(color: accent, width: 5),
          ),
          boxShadow: AppStyle.cardShadow(false),
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 14, 12),
          child: child,
        ),
      ),
    );
  }
}