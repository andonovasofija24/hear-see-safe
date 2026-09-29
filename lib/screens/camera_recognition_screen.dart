import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:provider/provider.dart';
import 'package:easy_localization/easy_localization.dart';

import 'package:hear_and_see_safe/models/recognition_result.dart';
import 'package:hear_and_see_safe/services/image_recognition_service.dart';
import 'package:hear_and_see_safe/services/voice_assistant_service.dart';
import 'package:hear_and_see_safe/theme/app_style.dart';
import 'package:hear_and_see_safe/utils/accessibility_utils.dart';
import 'package:hear_and_see_safe/widgets/game_screen_chrome.dart';
import 'package:hear_and_see_safe/utils/vibration_utils.dart';

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

  Widget _buildCameraPreview() {
    if (_cameraController != null &&
        _cameraController!.value.isInitialized) {
      return CameraPreview(_cameraController!);
    }
    return const Center(child: CircularProgressIndicator());
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
    final contrastColor = AccessibilityUtils.getContrastColor(context);
    final hc = AccessibilityUtils.isHighContrast(context);

    final modeLabels = {
      'object': 'camera.object'.tr(),
      'color': 'camera.color'.tr(),
      'clothing': 'camera.clothing'.tr(),
    };

    return GameScreenChrome(
      accent: const Color(0xFFEA580C),
      title: 'features.camera_recognition'.tr(),
      child: SafeArea(
        child: Column(
          children: [
            const SizedBox(height: 12),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Row(
                children: [
                  for (final mode in _modes)
                    _modeButton(context, mode, modeLabels[mode]!, contrastColor),
                ],
              ),
            ),
            const SizedBox(height: 12),
            Expanded(
              flex: 5,
              child: Container(
                margin: const EdgeInsets.symmetric(horizontal: 16),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: contrastColor, width: 4),
                  boxShadow: hc ? const <BoxShadow>[] : AppStyle.cardShadow(false),
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(16),
                  child: _cameraErrorKey != null
                      ? _buildErrorState(contrastColor)
                      : (_isInitialized
                          ? _buildCameraPreview()
                          : const Center(child: CircularProgressIndicator())),
                ),
              ),
            ),
            const SizedBox(height: 12),
            if (_lastResult != null || _isProcessing)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: _buildResultPanel(contrastColor, hc),
              ),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 12, 24, 24),
              child: SizedBox(
                width: double.infinity,
                height: 56,
                child: ElevatedButton.icon(
                  onPressed: _isProcessing ? null : _captureAndRecognize,
                  icon: _isProcessing
                      ? const SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(strokeWidth: 2.4, color: Colors.white),
                        )
                      : const Icon(Icons.camera_alt, size: 28),
                  label: Text(_isProcessing ? 'camera.analyzing'.tr() : 'camera.capture'.tr()),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildErrorState(Color contrastColor) {
    return Container(
      color: Colors.black87,
      alignment: Alignment.center,
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.videocam_off_rounded, color: Colors.white, size: 56),
          const SizedBox(height: 14),
          Text(
            _cameraErrorKey!.tr(),
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 18),
          ElevatedButton.icon(
            onPressed: _initializeCamera,
            icon: const Icon(Icons.refresh_rounded),
            label: Text('camera.retry'.tr()),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFEA580C),
              foregroundColor: Colors.white,
            ),
          ),
        ],
      ),
    );
  }

  /// "Жив" резултат-панел - го покажува вистинскиот резултат (или дека сè
  /// уште анализираме), не мок/пример.
  Widget _buildResultPanel(Color contrastColor, bool hc) {
    final result = _lastResult;
    final uncertain = result != null &&
        (result.confidence < ImageRecognitionService.defaultConfidenceThreshold ||
            result.labelKey == 'camera.uncertain');
    final borderColor = _isProcessing
        ? contrastColor.withOpacity(0.4)
        : (uncertain ? const Color(0xFFD97706) : const Color(0xFF16A34A));

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AccessibilityUtils.getCardBackgroundColor(context),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: hc ? Colors.white : borderColor, width: hc ? 2 : 1.6),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('camera.result_label'.tr(), style: GameTypography.body(context, contrastColor, 14)),
          const SizedBox(height: 4),
          if (_isProcessing)
            Text('camera.analyzing'.tr(), style: GameTypography.heading(context, contrastColor, 22))
          else if (result != null)
            Text(
              uncertain ? 'camera.uncertain'.tr() : result.labelKey.tr(),
              style: GameTypography.heading(context, contrastColor, 26),
            ),
          if (!_isProcessing && result != null && !uncertain && result.secondaryLabelKey != null) ...[
            const SizedBox(height: 4),
            Text(result.secondaryLabelKey!.tr(), style: GameTypography.body(context, contrastColor, 17)),
          ],
        ],
      ),
    );
  }

  Widget _modeButton(
    BuildContext context,
    String mode,
    String label,
    Color contrastColor,
  ) {
    final isActive = _recognitionMode == mode;

    return Expanded(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4),
        child: Semantics(
          label: label,
          button: true,
          selected: isActive,
          child: ElevatedButton(
            onPressed: () {
              setState(() {
                _recognitionMode = mode;
                _lastResult = null;
              });
            },
            style: ElevatedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 4),
              textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
              backgroundColor: isActive
                  ? AccessibilityUtils.getAccentColor(context)
                  : AccessibilityUtils.getDisabledColor(context),
            ),
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(label, textAlign: TextAlign.center),
            ),
          ),
        ),
      ),
    );
  }
}