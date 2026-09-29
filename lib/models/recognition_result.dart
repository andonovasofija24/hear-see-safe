/// Резултат од препознавање преку камера.
///
/// ВАЖНО: `labelKey`/`secondaryLabelKey` се КЛУЧЕВИ ЗА ПРЕВОД (на пр.
/// 'camera.object_apple'), НЕ готов текст и НЕ суровото англиско име што го
/// враќа моделот/API-то. Екранот ги преведува со `.tr()` на јазикот што
/// корисникот моментално го користи (mk/en/sq) пред да ги изговори или
/// прикаже - никогаш не читаме англиско име на класа на корисник кој ја
/// користи апликацијата на македонски или албански.
class RecognitionResult {
  /// Клуч за превод на главниот резултат (пр. 'camera.object_apple',
  /// 'camera.color_red', 'camera.clothing_type_shirt').
  final String labelKey;

  /// Клуч за превод на дополнителна информација, ако постои (пр. за облека
  /// - бојата пресметана од истата слика). null ако нема втор резултат.
  final String? secondaryLabelKey;

  /// Доверба на моделот во распон 0.0-1.0. За "боја" (пресметана локално од
  /// пикселите, без надворешен модел) секогаш е 1.0, бидејќи не е
  /// веројатносна проценка туку директна мерка.
  final double confidence;

  /// Режимот во кој е добиен резултатот: 'object' | 'color' | 'clothing'.
  final String mode;

  const RecognitionResult({
    required this.labelKey,
    required this.confidence,
    required this.mode,
    this.secondaryLabelKey,
  });
}