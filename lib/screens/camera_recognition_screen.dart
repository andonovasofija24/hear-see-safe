import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:provider/provider.dart';
import 'package:easy_localization/easy_localization.dart';

import 'package:hear_and_see_safe/models/recognition_result.dart';
import 'package:hear_and_see_safe/services/image_recognition_service.dart';
import 'package:hear_and_see_safe/services/voice_assistant_service.dart';
import 'package:hear_and_see_safe/utils/accessibility_utils.dart';
import 'package:hear_and_see_safe/widgets/game_screen_chrome.dart';
import 'package:hear_and_see_safe/widgets/playful_ui.dart';
import 'package:hear_and_see_safe/utils/vibration_utils.dart';

/// Множител за големината на текстот на овој екран (поголеми букви).
const double _kCamText = 1.6;

class CameraRecognitionScreen extends StatefulWidget {
  const CameraRecognitionScreen({super.key});

  @override
  State<CameraRecognitionScreen> createState() =>
      _CameraRecognitionScreenState();
}

class _CameraRecognitionScreenState extends State<CameraRecognitionScreen> {
  CameraController? _cameraController;
  List<CameraDescription>? _cameras;
  bool _isInitialized = false;
  bool _isProcessing = false;
  String _recognitionMode = 'object';

  /// Клуч за превод на грешка при иницијализација на камерата (permission
  /// одбиена, нема камера, платформата не поддржува итн). null = сè уредно,
  /// или сè уште не сме пробале.
  String? _cameraErrorKey;

  /// Последниот резултат од препознавање - го движи "живиот" панел со
  /// резултат (наместо статичен пример).
  RecognitionResult? _lastResult;

  late VoiceAssistantService _voiceAssistant;
  late final ImageRecognitionService _recognitionService;

  static const List<String> _modes = ['object', 'color', 'clothing'];

  @override
  void initState() {
    super.initState();
    _voiceAssistant =
        Provider.of<VoiceAssistantService>(context, listen: false);
    _recognitionService = MlKitRecognitionService();
    _initializeCamera();
  }

  String get _langCode => context.locale.languageCode;

  Future<void> _initializeCamera() async {
    setState(() => _cameraErrorKey = null);
    try {
      final status = await Permission.camera.request();

      if (!status.isGranted) {
        await _failInit('camera.error_permission');
        return;
      }

      _cameras = await availableCameras();

      if (_cameras == null || _cameras!.isEmpty) {
        await _failInit('camera.error_no_camera');
        return;
      }

      _cameraController = CameraController(
        _cameras![0],
        ResolutionPreset.medium,
        enableAudio: false,
      );

      await _cameraController!.initialize();

      if (!mounted) return;

      setState(() {
        _isInitialized = true;
        _cameraErrorKey = null;
      });

      if (await VibrationUtils.hasVibrator()) {
        await VibrationUtils.vibrate(duration: 100);
      }
      await _voiceAssistant.speakWithLanguage(
        'camera.ready'.tr(),
        _langCode,
      );
    } catch (_) {
      await _failInit('camera.error_camera_unavailable');
    }
  }

  /// Заедничка логика кога иницијализацијата на камерата не успее - секогаш
  /// со видлива состојба (не бесконечен spinner), глас и посебен вибрациски
  /// шаблон за грешка.
  Future<void> _failInit(String errorKey) async {
    if (!mounted) return;
    setState(() {
      _isInitialized = false;
      _cameraErrorKey = errorKey;
    });
    if (await VibrationUtils.hasVibrator()) {
      await VibrationUtils.vibrate(pattern: const [0, 150, 100, 150]);
    }
    await _voiceAssistant.speakWithLanguage(errorKey.tr(), _langCode);
  }

  Future<void> _captureAndRecognize() async {
    final controller = _cameraController;

    // НИКОГАШ тивко - секое можно излегување без резултат добива глас +
    // вибрација + видлива порака, за корисникот секогаш да знае што се
    // случува (претходно тука имаше тивок `return` што личеше на "не
    // прави ништо" кога камерата не е подготвена).
    if (controller == null || !controller.value.isInitialized) {
      await _voiceAssistant.speakWithLanguage(
        'camera.error_not_ready'.tr(),
        _langCode,
        vibrate: false,
      );
      if (await VibrationUtils.hasVibrator()) {
        await VibrationUtils.vibrate(pattern: const [0, 150, 100, 150]);
      }
      return;
    }
    if (_isProcessing) return;

    setState(() {
      _isProcessing = true;
      _lastResult = null;
    });

    try {
      await _voiceAssistant.speakWithLanguage(
        'camera.analyzing'.tr(),
        _langCode,
        vibrate: false,
      );
      if (await VibrationUtils.hasVibrator()) {
        await VibrationUtils.vibrate(duration: 150);
      }

      final image = await controller.takePicture().timeout(
            const Duration(seconds: 8),
            onTimeout: () => throw const RecognitionException('camera.error_timeout'),
          );

      if (!mounted) return;

      final result = await _recognitionService
          .recognize(image: image, mode: _recognitionMode)
          .timeout(
            const Duration(seconds: 12),
            onTimeout: () => throw const RecognitionException('camera.error_timeout'),
          );

      if (!mounted) return;

      await _announceResult(result);

      setState(() => _lastResult = result);
      AccessibilityUtils.provideFeedback(context: context);
    } on RecognitionException catch (e) {
      if (!mounted) return;
      await _voiceAssistant.speakWithLanguage(e.messageKey.tr(), _langCode, vibrate: false);
      if (await VibrationUtils.hasVibrator()) {
        await VibrationUtils.vibrate(pattern: const [0, 150, 100, 150]);
      }
    } catch (_) {
      if (!mounted) return;
      await _voiceAssistant.speakWithLanguage('camera.error'.tr(), _langCode, vibrate: false);
      if (await VibrationUtils.hasVibrator()) {
        await VibrationUtils.vibrate(pattern: const [0, 150, 100, 150]);
      }
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  /// Говор + вибрација прилагодени на исходот - различен шаблон за
  /// "несигурно" наспроти "пронајдено", за лицата со оштетен вид да можат
  /// да го разликуваат исходот и само преку допир, без да гледаат екран.
  Future<void> _announceResult(RecognitionResult result) async {
    if (result.confidence < ImageRecognitionService.defaultConfidenceThreshold ||
        result.labelKey == 'camera.uncertain') {
      await _voiceAssistant.speakWithLanguage('camera.uncertain'.tr(), _langCode, vibrate: false);
      if (await VibrationUtils.hasVibrator()) {
        await VibrationUtils.vibrate(pattern: const [0, 100, 80, 100]);
      }
      return;
    }

    await _voiceAssistant.speakWithLanguage(result.labelKey.tr(), _langCode, vibrate: false);
    if (result.secondaryLabelKey != null) {
      await Future.delayed(const Duration(milliseconds: 350));
      if (!mounted) return;
      await _voiceAssistant.speakWithLanguage(result.secondaryLabelKey!.tr(), _langCode, vibrate: false);
    }
    if (await VibrationUtils.hasVibrator()) {
      await VibrationUtils.vibrate(duration: 250);
    }
  }

  static const Color _accent = Color(0xFFEA580C);

  /// Икона и боја за секој режим.
  static const Map<String, IconData> _modeIcons = {
    'object': Icons.category_rounded,
    'color': Icons.palette_rounded,
    'clothing': Icons.checkroom_rounded,
  };
  static const Map<String, Color> _modeColors = {
    'object': Color(0xFF2563EB),
    'color': Color(0xFFDB2777),
    'clothing': Color(0xFF9333EA),
  };

  Widget _buildCameraPreview() {
    if (_cameraController != null &&
        _cameraController!.value.isInitialized) {
      // Во средина, со својот однос на страни (без развлекување).
      return Center(child: CameraPreview(_cameraController!));
    }
    return _loading();
  }

  Widget _loading() {
    final hc = AccessibilityUtils.isHighContrast(context);
    return Center(
      child: SizedBox(
        width: 54,
        height: 54,
        child: CircularProgressIndicator(strokeWidth: 5, color: hc ? Colors.white : Playful.sun),
      ),
    );
  }

  @override
  void dispose() {
    _voiceAssistant.stop();
    _cameraController?.dispose();
    _recognitionService.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final hc = AccessibilityUtils.isHighContrast(context);

    final modeLabels = {
      'object': 'camera.object'.tr(),
      'color': 'camera.color'.tr(),
      'clothing': 'camera.clothing'.tr(),
    };

    return GameScreenChrome(
      accent: _accent,
      title: 'features.camera_recognition'.tr(),
      bodyBackground: const EmojiBackdrop(
        emojis: ['📷', '🎨', '👕', '🔍', '✨', '🧸'],
        tint: _accent,
      ),
      child: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final side = ((constraints.maxWidth - 980) / 2).clamp(16.0, double.infinity);
            final shortScreen = constraints.maxHeight < 620;
            // Режимите се еден под друг (цела ширина) кога има доволно
            // висина; на ниски екрани остануваат три во ред, за визирот на
            // камерата да не исчезне.
            final stackedModes = constraints.maxHeight >= 700;
            // На ниски екрани текстот во резултатот расте помалку.
            final resultScale = shortScreen ? 1.3 : _kCamText;
            return Padding(
              padding: EdgeInsets.fromLTRB(side, 12, side, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (stackedModes)
                    for (var i = 0; i < _modes.length; i++) ...[
                      if (i > 0) const SizedBox(height: 10),
                      PopIn(
                        index: i,
                        child: _modeButton(_modes[i], modeLabels[_modes[i]]!, hc, stacked: true),
                      ),
                    ]
                  else
                    Row(
                      children: [
                        for (var i = 0; i < _modes.length; i++) ...[
                          if (i > 0) const SizedBox(width: 10),
                          Expanded(
                            child: PopIn(
                              index: i,
                              child: _modeButton(_modes[i], modeLabels[_modes[i]]!, hc),
                            ),
                          ),
                        ],
                      ],
                    ),
                  const SizedBox(height: 14),
                  // Визир: камерата во рамка со златни агли; при анализа -
                  // златна линија што скенира.
                  Expanded(
                    child: Container(
                      decoration: BoxDecoration(
                        color: hc ? Colors.black : Playful.nightDeep,
                        borderRadius: BorderRadius.circular(26),
                        border: Border.all(color: hc ? AccessibilityUtils.getContrastColor(context) : Colors.white, width: hc ? 4 : 3),
                        boxShadow: hc ? null : [BoxShadow(color: _accent.withValues(alpha: 0.45), blurRadius: 26)],
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(22),
                        child: Stack(
                          fit: StackFit.expand,
                          children: [
                            _cameraErrorKey != null
                                ? _buildErrorState(hc)
                                : (_isInitialized ? _buildCameraPreview() : _loading()),
                            if (_cameraErrorKey == null)
                              IgnorePointer(
                                child: CustomPaint(painter: _ViewfinderPainter(highContrast: hc)),
                              ),
                            if (_isProcessing && !hc && !Playful.reduceMotion(context))
                              const IgnorePointer(child: _ScanLine()),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),
                  if (_lastResult != null || _isProcessing) ...[
                    _buildResultPanel(hc, compact: shortScreen, textScale: resultScale),
                    const SizedBox(height: 12),
                  ],
                  Center(
                    child: SoundOrb(
                      icon: Icons.camera_alt_rounded,
                      label: _isProcessing ? 'camera.analyzing'.tr() : 'camera.capture'.tr(),
                      onTap: _isProcessing ? null : _captureAndRecognize,
                      active: _isProcessing,
                      size: shortScreen ? 76 : 96,
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildErrorState(bool hc) {
    return Container(
      color: hc ? Colors.black : Playful.nightRaised,
      alignment: Alignment.center,
      padding: const EdgeInsets.all(24),
      child: SingleChildScrollView(
        primary: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 84,
              height: 84,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: hc ? Colors.black : const Color(0xFFDC2626),
                border: Border.all(color: Colors.white, width: 3),
              ),
              child: const Icon(Icons.videocam_off_rounded, color: Colors.white, size: 44),
            ),
            const SizedBox(height: 16),
            Text(
              _cameraErrorKey!.tr(),
              textAlign: TextAlign.center,
              style: Playful.title(19 * _kCamText, color: Colors.white),
            ),
            const SizedBox(height: 18),
            PressableScale(
              child: Material(
                color: hc ? Colors.black : Playful.sun,
                borderRadius: BorderRadius.circular(20),
                child: InkWell(
                  borderRadius: BorderRadius.circular(20),
                  onTap: _initializeCamera,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 14),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: Colors.white, width: hc ? 2 : 3),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.refresh_rounded, size: 32, color: hc ? Colors.white : Playful.ink),
                        const SizedBox(width: 8),
                        Flexible(
                          child: Text(
                            'camera.retry'.tr(),
                            textAlign: TextAlign.center,
                            style: Playful.title(18 * _kCamText, color: hc ? Colors.white : Playful.ink),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// „Жив“ резултат - бела картичка со златен раб: додека се анализира
  /// бранови, потоа зелена ✓ (пронајдено) или портокалово ? (несигурно).
  Widget _buildResultPanel(bool hc, {bool compact = false, double textScale = _kCamText}) {
    final result = _lastResult;
    final uncertain = result != null &&
        (result.confidence < ImageRecognitionService.defaultConfidenceThreshold ||
            result.labelKey == 'camera.uncertain');
    final stateColor = _isProcessing
        ? Playful.sun
        : (uncertain ? const Color(0xFFD97706) : const Color(0xFF16A34A));
    final ink = hc ? Colors.white : Playful.ink;

    return PopIn(
      key: ValueKey(_isProcessing ? 'processing' : 'result_${result?.labelKey}'),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: hc ? Colors.black : Colors.white,
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: hc ? Colors.white : stateColor, width: 3),
          boxShadow: hc ? null : [BoxShadow(color: stateColor.withValues(alpha: 0.45), blurRadius: 18)],
        ),
        child: Row(
          children: [
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: hc ? Colors.black : (_isProcessing ? Playful.night : stateColor),
                border: Border.all(color: hc ? Colors.white : stateColor, width: 2),
              ),
              child: Center(
                child: _isProcessing
                    ? (hc
                        ? const Icon(Icons.hourglass_top_rounded, color: Colors.white, size: 30)
                        : const SoundWave(color: Playful.sun, bars: 5, height: 24, barWidth: 4))
                    : Icon(
                        uncertain ? Icons.help_outline_rounded : Icons.check_rounded,
                        color: Colors.white,
                        size: 34,
                      ),
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Semantics(
                liveRegion: true,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('camera.result_label'.tr(), style: Playful.body(14 * textScale, color: ink.withValues(alpha: 0.7))),
                    const SizedBox(height: 2),
                    if (_isProcessing)
                      Text(
                        'camera.analyzing'.tr(),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Playful.display((compact ? 20 : 22) * textScale, color: ink),
                      )
                    else if (result != null)
                      // maxLines: на 360x640 со голем текст (до 1.6x) долгите
                      // MK/SQ пораки инаку го туркаат визирот под 0 и Column-от
                      // прелева. Целиот текст е и понатаму во семантиката/говорот.
                      Text(
                        uncertain ? 'camera.uncertain'.tr() : result.labelKey.tr(),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: Playful.display((compact ? 22 : 26) * textScale, color: ink),
                      ),
                    if (!_isProcessing && result != null && !uncertain && result.secondaryLabelKey != null) ...[
                      const SizedBox(height: 2),
                      Text(
                        result.secondaryLabelKey!.tr(),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Playful.body(17 * textScale, color: ink),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Плочка за режим - во својата боја; избраната е златна со бел раб.
  Widget _modeButton(String mode, String label, bool hc, {bool stacked = false}) {
    final isActive = _recognitionMode == mode;
    final color = _modeColors[mode] ?? _accent;
    final fg = isActive ? (hc ? Colors.black : Playful.ink) : Colors.white;

    return Semantics(
      label: label,
      button: true,
      selected: isActive,
      child: ExcludeSemantics(
        child: PressableScale(
          child: Material(
            color: Colors.transparent,
            borderRadius: BorderRadius.circular(20),
            child: InkWell(
              borderRadius: BorderRadius.circular(20),
              onTap: () {
                setState(() {
                  _recognitionMode = mode;
                  _lastResult = null;
                });
              },
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                padding: EdgeInsets.symmetric(vertical: stacked ? 8 : 10, horizontal: stacked ? 18 : 6),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(20),
                  color: hc ? (isActive ? const Color(0xFFFFFF00) : Colors.black) : (isActive ? Playful.sun : null),
                  gradient: hc || isActive
                      ? null
                      : LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [Color.lerp(color, Colors.white, 0.05)!, Color.lerp(color, Colors.black, 0.35)!],
                        ),
                  border: Border.all(color: Colors.white, width: isActive ? 3 : 2),
                  boxShadow: hc
                      ? null
                      : [BoxShadow(color: (isActive ? Playful.sun : color).withValues(alpha: isActive ? 0.6 : 0.35), blurRadius: isActive ? 20 : 12)],
                ),
                child: stacked
                    // Еден под друг: икона + натпис во ред, на средина.
                    ? Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(_modeIcons[mode], size: 36, color: fg),
                          const SizedBox(width: 12),
                          Flexible(
                            child: Text(label, textAlign: TextAlign.center, style: Playful.title(15 * _kCamText, color: fg)),
                          ),
                        ],
                      )
                    : Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(_modeIcons[mode], size: 34, color: fg),
                          const SizedBox(height: 4),
                          // Три во ред (низок екран) - натписот се смалува ако не собира.
                          FittedBox(
                            fit: BoxFit.scaleDown,
                            child: Text(label, textAlign: TextAlign.center, style: Playful.title(15 * _kCamText, color: fg)),
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

/// Златни агли на визирот (како кај камера).
class _ViewfinderPainter extends CustomPainter {
  _ViewfinderPainter({required this.highContrast});

  final bool highContrast;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = highContrast ? Colors.white : Playful.sun
      ..strokeWidth = 6
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;
    const inset = 18.0;
    final len = (size.shortestSide * 0.14).clamp(18.0, 48.0);
    final l = inset, t = inset, r = size.width - inset, b = size.height - inset;
    // горе-лево
    canvas.drawLine(Offset(l, t), Offset(l + len, t), paint);
    canvas.drawLine(Offset(l, t), Offset(l, t + len), paint);
    // горе-десно
    canvas.drawLine(Offset(r, t), Offset(r - len, t), paint);
    canvas.drawLine(Offset(r, t), Offset(r, t + len), paint);
    // долу-лево
    canvas.drawLine(Offset(l, b), Offset(l + len, b), paint);
    canvas.drawLine(Offset(l, b), Offset(l, b - len), paint);
    // долу-десно
    canvas.drawLine(Offset(r, b), Offset(r - len, b), paint);
    canvas.drawLine(Offset(r, b), Offset(r, b - len), paint);
  }

  @override
  bool shouldRepaint(covariant _ViewfinderPainter old) => old.highContrast != highContrast;
}

/// Златна линија што оди горе-долу низ визирот додека се анализира.
class _ScanLine extends StatefulWidget {
  const _ScanLine();

  @override
  State<_ScanLine> createState() => _ScanLineState();
}

class _ScanLineState extends State<_ScanLine> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 1400))
    ..repeat(reverse: true);

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _c,
      builder: (context, _) => Align(
        alignment: Alignment(0, -0.9 + 1.8 * Curves.easeInOut.transform(_c.value)),
        child: Container(
          height: 4,
          margin: const EdgeInsets.symmetric(horizontal: 22),
          decoration: BoxDecoration(
            color: Playful.sun,
            borderRadius: BorderRadius.circular(2),
            boxShadow: [BoxShadow(color: Playful.sun.withValues(alpha: 0.8), blurRadius: 16, spreadRadius: 3)],
          ),
        ),
      ),
    );
  }
}