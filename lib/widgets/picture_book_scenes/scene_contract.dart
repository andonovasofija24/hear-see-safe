import 'package:flutter/widgets.dart';

/// Еден поим како што го гледа сцената на категоријата во сликовницата.
class PbSceneItem {
  const PbSceneItem({required this.id, required this.emoji, required this.label, this.visited = false});

  final String id;
  final String emoji;
  final String label;

  /// Дали страницата за овој поим е веќе отворена (може да се означи
  /// дискретно, на пр. мала ✓).
  final bool visited;
}

/// Заеднички договор за сите сцени на категориите (дрво, лента, планета,
/// уво, лав). Сцената ја црта само „сцената“: централниот објект, иконите
/// на поимите (осветлена е избраната) и копчето за квиз. Стрелките,
/// големата избрана икона со името под неа и тастатурата ги прави
/// екранот на сликовницата.
///
/// Правила за секоја сцена:
///  * Ја пополнува дадената големина (LayoutBuilder) - висината ја одредува
///    родителот.
///  * Кога [selected] ќе се смени, анимирано (~400 ms) го носи избраниот
///    поим на „фокус“ местото (напред / во средина / најгоре).
///  * Допир на НЕизбран поим -> [onSelect](index). Допир на избраниот ->
///    [onOpen]().
///  * Копчето за квиз е секогаш достапно и е дел од сцената -> [onQuiz]().
///  * Избраниот поим е јасно поголем и посветол; останатите се затемнети.
///  * [highContrast]: црна позадина, бели/жолти рабови, без бледи бои.
///  * Семантика: секој поим е копче со [PbSceneItem.label]; квизот со
///    [quizLabel].
abstract class PbScene extends StatefulWidget {
  const PbScene({
    super.key,
    required this.items,
    required this.selected,
    required this.onSelect,
    required this.onOpen,
    required this.onQuiz,
    required this.quizLabel,
    required this.highContrast,
    this.reduceMotion = false,
  });

  final List<PbSceneItem> items;
  final int selected;
  final ValueChanged<int> onSelect;
  final VoidCallback onOpen;
  final VoidCallback onQuiz;
  final String quizLabel;
  final bool highContrast;

  /// Системско „помалку движење“ - без постојана анимација, само скок до
  /// избраниот поим.
  final bool reduceMotion;
}