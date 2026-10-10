import 'package:flutter/material.dart';
import 'scene_contract.dart';

/// Airport departures + passport stamps + museum exhibition.
/// Uses only Flutter primitives, respects accessibility and reduced motion.
class WorldCulturesScene extends PbScene {
  const WorldCulturesScene({super.key, required super.items, required super.selected,
    required super.onSelect, required super.onOpen, required super.onQuiz,
    required super.quizLabel, required super.highContrast, super.reduceMotion});

  @override
  State<WorldCulturesScene> createState() => _WorldCulturesSceneState();
}

class _WorldCulturesSceneState extends State<WorldCulturesScene> {
  final ScrollController _board = ScrollController();
  static const _capitals = ['Токио','Каиро','Рим','Мексико Сити','Париз',
    'Атина','Пекинг','Њу Делхи','Најроби','Анкара'];
  static const _flags = ['🇯🇵','🇪🇬','🇮🇹','🇲🇽','🇫🇷','🇬🇷','🇨🇳','🇮🇳','🇰🇪','🇹🇷'];
  static const _stamps = ['🌸','🔺','🏛️','🎨','🗼','🏺','🏮','🕌','🪘','🧿'];

  @override
  void didUpdateWidget(covariant WorldCulturesScene oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.selected != widget.selected) {
      _scrollToSelected(widget.selected);
    }
  }

  // Keep the visible departures in sync with the selected museum.
  // A fixed itemExtent makes scrolling reliable even for offscreen rows.
  void _scrollToSelected(int index) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_board.hasClients) return;
      final viewport = _board.position.viewportDimension;
      final extent = _departureExtent;
      final target = (index * extent - (viewport - extent) / 2)
          .clamp(0.0, _board.position.maxScrollExtent);
      if (widget.reduceMotion) {
        _board.jumpTo(target);
      } else {
        _board.animateTo(target,
          duration: const Duration(milliseconds: 350),
          curve: Curves.easeOutCubic);
      }
    });
  }

  double _departureExtent = 91;

  @override
  void dispose() { _board.dispose(); super.dispose(); }

  void _choose(int index) {
    if (index == widget.selected) { widget.onOpen(); }
    else { widget.onSelect(index); _scrollToSelected(index); }
  }

  @override
  Widget build(BuildContext context) {
    final hc = widget.highContrast;
    final ink = hc ? Colors.yellow : const Color(0xFFFFD991);
    final dark = hc ? Colors.black : const Color(0xFF142A38);
    final gold = hc ? Colors.yellow : const Color(0xFFDCA55B);
    if (widget.items.isEmpty) return const SizedBox.shrink();
    final active = widget.selected.clamp(0, widget.items.length - 1);
    return LayoutBuilder(builder: (context, box) {
      final narrow = box.maxWidth < 370;
      final short = box.maxHeight < 390;
      _departureExtent = short ? 71 : 91;
      return ClipRRect(
        borderRadius: BorderRadius.circular(22),
        child: DecoratedBox(
          decoration: BoxDecoration(
            gradient: hc ? null : const LinearGradient(
              colors: [Color(0xFF183D54), Color(0xFF536E79), Color(0xFFD4AD75)],
              begin: Alignment.topCenter, end: Alignment.bottomCenter),
            color: hc ? Colors.black : null,
            border: Border.all(color: gold, width: 2),
          ),
          child: Padding(
            padding: EdgeInsets.all(short ? 5 : 9),
            child: ListView(padding: EdgeInsets.zero, children: [
              // Departure board. Vertical scrolling is independent of the main page.
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                decoration: BoxDecoration(color: dark, borderRadius: BorderRadius.circular(10)),
                child: Row(children: [
                  Icon(Icons.flight_takeoff_rounded, color: ink, size: 23),
                  const SizedBox(width: 7),
                  Expanded(child: Text('DEPARTURES · ОДЛЕТУВАЊА',
                    maxLines: 2, softWrap: true,
                    style: TextStyle(color: ink, fontWeight: FontWeight.w900,
                      fontSize: narrow ? 21 : 27, letterSpacing: 0.4))),
                  Flexible(child: FittedBox(fit: BoxFit.scaleDown, child: Text('${active + 1}/${widget.items.length}', style: TextStyle(color: ink, fontWeight: FontWeight.bold)))),
                ]),
              ),
              const SizedBox(height: 6),
              SizedBox(height: (box.maxHeight * (short ? 0.30 : 0.43)).clamp(80.0, 360.0), child: ListView.builder(
                controller: _board,
                itemCount: widget.items.length,
                itemExtent: _departureExtent,
                itemBuilder: (context, i) {
                  final item = widget.items[i];
                  final selected = i == active;
                  return Padding(padding: const EdgeInsets.only(bottom: 3),
                    child: Semantics(button: true, selected: selected,
                      label: item.label,
                      child: Material(color: selected ? const Color(0xFFAA7438) : dark,
                        borderRadius: BorderRadius.circular(7),
                        child: InkWell(
                          onTap: () => _choose(i),
                          borderRadius: BorderRadius.circular(7),
                          child: SizedBox(height: short ? 68 : 88,
                            child: Padding(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                              child: Row(children: [
                                Text(_flags[i % _flags.length], style: const TextStyle(fontSize: 38)),
                                const SizedBox(width: 9),
                                Expanded(child: Text(item.label, maxLines: 2, softWrap: true,
                                  style: TextStyle(color: Colors.white, fontSize: narrow ? 24 : 29,
                                    fontWeight: FontWeight.w800))),
                                if (!narrow) Text(_capitals[i % _capitals.length],
                                  style: const TextStyle(color: Color(0xFFFFE2A9), fontSize: 16)),
                                const SizedBox(width: 6),
                                Icon(item.visited ? Icons.verified : Icons.chevron_right,
                                  color: ink, size: 22),
                              ])),
                          ),
                        ),
                      ),
                    ),
                  );
                },
              )),
              const SizedBox(height: 6),
              // Passport: fixed-height responsive cells; no vertical Flex overflow.
              SizedBox(height: short ? 110 : 145, child: Container(
                width: double.infinity,
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(color: const Color(0xFFFFE7B6),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0xFF8B6036), width: 3)),
                child: LayoutBuilder(builder: (context, passportBox) {
                  final available = passportBox.maxHeight;
                  return Row(children: [
                    Expanded(child: Column(children: [
                      SizedBox(height: 17, child: FittedBox(fit: BoxFit.scaleDown,
                        child: const Text('PASSPORT · ПАСОШ',
                          style: TextStyle(color: Color(0xFF5B3927),
                            fontSize: 12, fontWeight: FontWeight.bold)))),
                      Expanded(child: Center(child: AnimatedSwitcher(
                        duration: widget.reduceMotion ? Duration.zero : const Duration(milliseconds: 300),
                        child: FittedBox(key: ValueKey(active), fit: BoxFit.contain,
                          child: Text(_stamps[active % _stamps.length],
                            style: const TextStyle(fontSize: 40))))),
                      ),
                    ])),
                    Container(width: 2, color: const Color(0xFFB68E58)),
                    const SizedBox(width: 8),
                    Expanded(flex: 2, child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SizedBox(height: 24, child: Align(alignment: Alignment.centerLeft,
                          child: Text(widget.items[active].label, maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900,
                              color: Color(0xFF59351B))))),
                        SizedBox(height: 16, child: Align(alignment: Alignment.centerLeft,
                          child: Text(widget.items[active].visited ? '✓ VISITED' : '✈ DISCOVER',
                            maxLines: 1, overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 12, color: Color(0xFF6E4B32))))),
                        const Spacer(),
                        SizedBox(height: (available - 43).clamp(28.0, 40.0),
                          width: double.infinity,
                          child: FilledButton.icon(
                            onPressed: widget.onOpen,
                            icon: const Icon(Icons.museum, size: 17),
                            label: const FittedBox(fit: BoxFit.scaleDown,
                              child: Text('МУЗЕЈ', style: TextStyle(fontSize: 13))),
                            style: FilledButton.styleFrom(
                              backgroundColor: const Color(0xFF81532D),
                              padding: const EdgeInsets.symmetric(horizontal: 5)),
                          )),
                      ])),
                  ]);
                }),
              )),
              const SizedBox(height: 5),
              SizedBox(width: double.infinity, height: short ? 42 : 48,
                child: FilledButton.icon(onPressed: widget.onQuiz,
                  icon: const Icon(Icons.quiz_rounded, size: 27),
                  label: Text(widget.quizLabel, maxLines: 1, overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
                  style: FilledButton.styleFrom(backgroundColor: hc ? Colors.yellow : const Color(0xFF9A481C),
                    foregroundColor: hc ? Colors.black : Colors.white),
                )),
            ]),
          ),
        ),
      );
    });
  }
}