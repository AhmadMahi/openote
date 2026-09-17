import 'dart:math' as math;
import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';

import '../model/models.dart';
import '../quiz/quiz_import.dart';
import '../state/app_state.dart';
import '../theme/tokens.dart';

/// A multiple-choice quiz living on the page.
///
/// content: `{ name, questions:[{q,options,correct,explanation}], answers:[..],
/// revealed:[..] }`
///
/// One question at a time: its four options, a Submit that checks that
/// question and reveals the answer (green for right, red for the wrong pick)
/// with the one-line explanation, then Next. The last question leads to a
/// results card with the score and a Retake. The chosen answers and which
/// questions have been checked live in the block, so closing and reopening the
/// page keeps the reader where they were.
///
/// The questions come from a CSV or Excel file (see `quiz_import.dart`); this
/// view never edits them, it only asks and marks them.
class QuizBlockView extends StatefulWidget {
  const QuizBlockView({
    super.key,
    required this.block,
    required this.app,
    this.presentation = false,
  });
  final Block block;
  final AppState app;

  /// True inside the full-screen "present" overlay: the card fills its fixed
  /// box and scrolls, and the header offers a close instead of an expand.
  final bool presentation;

  @override
  State<QuizBlockView> createState() => _QuizBlockViewState();
}

class _QuizBlockViewState extends State<QuizBlockView> {
  int _current = 0;
  bool _showResults = false;

  Map<String, dynamic> get _c => widget.block.content;

  String get _name => (_c['name'] ?? 'Quiz').toString();

  List<QuizQuestion> get _questions => [
        for (final q in (_c['questions'] as List? ?? const []))
          QuizQuestion.fromJson((q as Map).cast<String, dynamic>()),
      ];

  // Per-question state, stored on the block so it survives a reopen.
  List<int> get _answers {
    final n = _questions.length;
    final raw = (_c['answers'] as List?) ?? const [];
    return [
      for (var i = 0; i < n; i++)
        i < raw.length ? (raw[i] as num?)?.toInt() ?? -1 : -1,
    ];
  }

  List<bool> get _revealed {
    final n = _questions.length;
    final raw = (_c['revealed'] as List?) ?? const [];
    return [
      for (var i = 0; i < n; i++) i < raw.length && raw[i] == true,
    ];
  }

  void _save(List<int> answers, List<bool> revealed) {
    _c['answers'] = answers;
    _c['revealed'] = revealed;
    widget.block.updatedAt = nowMs();
    widget.app.updateBlock(widget.block);
  }

  void _choose(int option) {
    final answers = _answers;
    if (_revealed[_current]) return; // locked once checked
    setState(() => answers[_current] = option);
    _save(answers, _revealed);
  }

  void _submit() {
    final revealed = _revealed;
    revealed[_current] = true;
    setState(() {});
    _save(_answers, revealed);
  }

  void _retake() {
    final n = _questions.length;
    setState(() {
      _current = 0;
      _showResults = false;
    });
    _save(List<int>.filled(n, -1), List<bool>.filled(n, false));
  }

  int get _score {
    final qs = _questions;
    final ans = _answers;
    var s = 0;
    for (var i = 0; i < qs.length; i++) {
      if (ans[i] == qs[i].correct) s++;
    }
    return s;
  }

  @override
  Widget build(BuildContext context) {
    final s = context.surfaces;
    // The full-screen "present" view is its own scaffold: a fixed header and
    // footer with a scrolling middle, so the Back/Next buttons never jump.
    if (_present) return _presentScaffold(context, s);

    final questions = _questions;
    if (questions.isEmpty) {
      return _shell(
        s,
        Padding(
          padding: const EdgeInsets.all(OnoteSpace.x4),
          child: Text('This quiz has no questions.',
              style: TextStyle(color: s.textSecondary)),
        ),
      );
    }
    return _shell(
        s, _showResults ? _results(context, s) : _questionCard(context, s));
  }

  bool get _present => widget.presentation;

  /// The in-page card: name at the top with a Present button, body below.
  Widget _shell(OnoteSurfaces s, Widget body) {
    return Container(
      decoration: BoxDecoration(
        color: s.raised,
        borderRadius: OnoteRadius.lgAll,
        border: Border.all(color: s.border),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(
                horizontal: OnoteSpace.x4, vertical: OnoteSpace.x3),
            color: s.well,
            child: Row(
              children: [
                Icon(Icons.quiz_outlined, size: 18, color: s.textSecondary),
                const SizedBox(width: OnoteSpace.x2),
                Expanded(
                  child: Text(_name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: OnoteType.title.copyWith(color: s.textPrimary)),
                ),
                // Fill the screen and dim everything else so the room looks at
                // the quiz.
                IconButton(
                  tooltip: 'Present',
                  visualDensity: VisualDensity.compact,
                  icon: Icon(Icons.open_in_full,
                      size: 18, color: s.textSecondary),
                  onPressed: () =>
                      showQuizPresentation(context, widget.app, widget.block),
                ),
              ],
            ),
          ),
          Flexible(child: body),
        ],
      ),
    );
  }

  // ── The full-screen present view ────────────────────────────────────────

  /// A fixed-frame card: header (name + progress + close), a scrolling middle
  /// (question and options, or the results), and a pinned footer (Back / Next,
  /// or Retake). The footer never moves as an answer reveals or the question
  /// grows, which is the whole point of the redesign.
  Widget _presentScaffold(BuildContext context, OnoteSurfaces s) {
    final questions = _questions;
    final empty = questions.isEmpty;
    return Container(
      decoration: BoxDecoration(
        color: s.raised,
        borderRadius: OnoteRadius.lgAll,
        border: Border.all(color: s.border),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _presentHeader(context, s),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(28, 24, 28, 24),
              child: empty
                  ? Text('This quiz has no questions.',
                      style: TextStyle(color: s.textSecondary))
                  : _showResults
                      ? _resultsContent(context, s)
                      : _questionContent(context, s),
            ),
          ),
          if (!empty)
            Container(
              padding: const EdgeInsets.fromLTRB(28, 14, 28, 18),
              decoration: BoxDecoration(
                color: s.raised,
                border: Border(top: BorderSide(color: s.border)),
              ),
              child: _showResults
                  ? _resultsNav(context, s)
                  : _questionNav(context, s),
            ),
        ],
      ),
    );
  }

  Widget _presentHeader(BuildContext context, OnoteSurfaces s) {
    final scheme = Theme.of(context).colorScheme;
    final total = _questions.length;
    return Container(
      padding: const EdgeInsets.fromLTRB(18, 14, 14, 14),
      decoration: BoxDecoration(
        color: s.well,
        border: Border(bottom: BorderSide(color: s.border)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: scheme.primary.withValues(alpha: 0.12),
              borderRadius: OnoteRadius.mdAll,
            ),
            child: Icon(Icons.quiz_outlined, size: 20, color: scheme.primary),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(_name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: OnoteType.headline.copyWith(
                    color: s.textPrimary, fontWeight: FontWeight.w700)),
          ),
          const SizedBox(width: 12),
          if (!_showResults && total > 0)
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('Question ${_current + 1} of $total',
                    style: OnoteType.caption.copyWith(
                        color: s.textSecondary, fontWeight: FontWeight.w600)),
                const SizedBox(height: 6),
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: SizedBox(
                    width: 150,
                    height: 6,
                    child: LinearProgressIndicator(
                      value: total == 0 ? 0 : (_current + 1) / total,
                      backgroundColor: scheme.primary.withValues(alpha: 0.14),
                      valueColor: AlwaysStoppedAnimation(scheme.primary),
                    ),
                  ),
                ),
              ],
            )
          else if (_showResults)
            Text('Results',
                style: OnoteType.caption.copyWith(
                    color: s.textSecondary, fontWeight: FontWeight.w600)),
          const SizedBox(width: 6),
          IconButton(
            tooltip: 'Back',
            visualDensity: VisualDensity.compact,
            icon: Icon(Icons.close, size: 20, color: s.textSecondary),
            onPressed: () => Navigator.of(context).maybePop(),
          ),
        ],
      ),
    );
  }

  /// In-page: the question, its options and the nav in one scrolling column.
  Widget _questionCard(BuildContext context, OnoteSurfaces s) => Padding(
        padding: const EdgeInsets.all(OnoteSpace.x4),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _questionContent(context, s),
            const SizedBox(height: OnoteSpace.x4),
            _questionNav(context, s),
          ],
        ),
      );

  /// The question, its options and (once checked) the explanation — no nav, so
  /// the present view can scroll this while the buttons stay pinned below. The
  /// "Question X of Y" caption is shown here only in the in-page card; in
  /// present mode the header carries it.
  Widget _questionContent(BuildContext context, OnoteSurfaces s) {
    final scheme = Theme.of(context).colorScheme;
    final questions = _questions;
    final q = questions[_current];
    final revealed = _revealed[_current];
    final chosen = _answers[_current];
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (!_present) ...[
          Text('Question ${_current + 1} of ${questions.length}',
              style: OnoteType.caption.copyWith(color: s.textSecondary)),
          const SizedBox(height: OnoteSpace.x2),
        ],
        Text(q.prompt,
            style: (_present ? OnoteType.headline : OnoteType.uiStrong)
                .copyWith(color: s.textPrimary, fontWeight: FontWeight.w700)),
        SizedBox(height: _present ? 20 : OnoteSpace.x3),
        for (var i = 0; i < q.options.length; i++)
          _option(context, s, q, i, chosen, revealed, large: _present),
        if (revealed && q.explanation.isNotEmpty) ...[
          SizedBox(height: _present ? 14 : OnoteSpace.x3),
          Container(
            padding: EdgeInsets.all(_present ? 16 : OnoteSpace.x3),
            decoration: BoxDecoration(
              // A soft blue note in present mode, matching the polished look;
              // the neutral well in the compact in-page card.
              color: _present ? scheme.primary.withValues(alpha: 0.10) : s.well,
              borderRadius: OnoteRadius.mdAll,
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.info_outline,
                    size: _present ? 18 : 16,
                    color: _present ? scheme.primary : s.textSecondary),
                SizedBox(width: _present ? 10 : OnoteSpace.x2),
                Expanded(
                  child: Text(q.explanation,
                      style: (_present ? OnoteType.ui : OnoteType.ui)
                          .copyWith(color: s.textSecondary)),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }

  /// Back / Submit / Next / See results — the row that is pinned to the footer
  /// in present mode and sits at the bottom of the column in the in-page card.
  Widget _questionNav(BuildContext context, OnoteSurfaces s) {
    final revealed = _revealed[_current];
    final chosen = _answers[_current];
    final isLast = _current == _questions.length - 1;
    return Row(
      children: [
        TextButton.icon(
          onPressed: _current > 0 ? () => setState(() => _current--) : null,
          icon: const Icon(Icons.chevron_left, size: 18),
          label: const Text('Back'),
        ),
        const Spacer(),
        if (!revealed)
          FilledButton(
            onPressed: chosen >= 0 ? _submit : null,
            child: const Text('Submit'),
          )
        else if (isLast)
          FilledButton.icon(
            onPressed: () => setState(() => _showResults = true),
            icon: const Icon(Icons.flag_outlined, size: 18),
            label: const Text('See results'),
          )
        else
          FilledButton.icon(
            onPressed: () => setState(() => _current++),
            icon: const Icon(Icons.chevron_right, size: 18),
            label: const Text('Next'),
          ),
      ],
    );
  }

  /// One answer row. Plain and tappable before the check; after it, the right
  /// option turns green and a wrong pick turns red. [large] gives the roomier,
  /// card-like option used in the present view.
  Widget _option(BuildContext context, OnoteSurfaces s, QuizQuestion q, int i,
      int chosen, bool revealed,
      {bool large = false}) {
    final scheme = Theme.of(context).colorScheme;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final isChosen = chosen == i;
    final isCorrect = q.correct == i;

    // In present mode an untouched option sits on a raised card so the list
    // reads as the polished mockup rather than four bare outlines.
    Color bg = large ? (dark ? s.raised : Colors.white) : Colors.transparent;
    Color border = s.border;
    Color fg = s.textPrimary;
    IconData? mark;
    Color markColor = s.textSecondary;

    if (!revealed) {
      if (isChosen) {
        bg = scheme.primary.withValues(alpha: large ? .10 : .12);
        border = scheme.primary;
      }
      mark =
          isChosen ? Icons.radio_button_checked : Icons.radio_button_unchecked;
      markColor = isChosen ? scheme.primary : s.textSecondary;
    } else {
      if (isCorrect) {
        bg = _green.withValues(alpha: .15);
        border = _green;
        markColor = _green;
        mark = Icons.check_circle;
      } else if (isChosen) {
        bg = _red.withValues(alpha: .15);
        border = _red;
        markColor = _red;
        mark = Icons.cancel;
      } else {
        mark = Icons.radio_button_unchecked;
      }
    }

    final letter = String.fromCharCode('A'.codeUnitAt(0) + i);
    final radius = large ? OnoteRadius.lgAll : OnoteRadius.mdAll;
    final textStyle = (large ? OnoteType.uiStrong : OnoteType.ui)
        .copyWith(color: fg, fontWeight: FontWeight.w500);
    return Padding(
      padding: EdgeInsets.only(bottom: large ? 12 : OnoteSpace.x2),
      child: InkWell(
        borderRadius: radius,
        onTap: revealed ? null : () => _choose(i),
        child: Container(
          padding: EdgeInsets.symmetric(
              horizontal: large ? 18 : OnoteSpace.x3,
              vertical: large ? 16 : OnoteSpace.x3),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: radius,
            border: Border.all(
                color: border, width: large && border != s.border ? 1.5 : 1),
          ),
          child: Row(
            children: [
              Icon(mark, size: large ? 22 : 18, color: markColor),
              SizedBox(width: large ? 14 : OnoteSpace.x3),
              Text('$letter.',
                  style: (large ? OnoteType.uiStrong : OnoteType.ui).copyWith(
                      color: s.textSecondary, fontWeight: FontWeight.w600)),
              SizedBox(width: large ? 12 : OnoteSpace.x2),
              Expanded(child: Text(q.options[i], style: textStyle)),
            ],
          ),
        ),
      ),
    );
  }

  /// In-page: the celebration, the per-question grid and Retake in one column.
  Widget _results(BuildContext context, OnoteSurfaces s) => Padding(
        padding: const EdgeInsets.all(OnoteSpace.x4),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _resultsContent(context, s),
            const SizedBox(height: OnoteSpace.x4),
            _resultsNav(context, s),
          ],
        ),
      );

  /// The score celebration and the tap-to-review grid — no nav.
  Widget _resultsContent(BuildContext context, OnoteSurfaces s) {
    final questions = _questions;
    final score = _score;
    final total = questions.length;
    final answers = _answers;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // The finish: the score counts up over a short confetti burst, with a
        // line that matches how it went. Plays once, the moment results show.
        _QuizCelebration(
          key: ValueKey('celebrate-$score-$total'),
          score: score,
          total: total,
          pass: _green,
          fail: _red,
          large: _present,
          textSecondary: s.textSecondary,
        ),
        const SizedBox(height: OnoteSpace.x3),
        Wrap(
          spacing: OnoteSpace.x2,
          runSpacing: OnoteSpace.x2,
          alignment: WrapAlignment.center,
          children: [
            for (var i = 0; i < total; i++)
              GestureDetector(
                onTap: () => setState(() {
                  _current = i;
                  _showResults = false;
                }),
                child: Container(
                  width: 28,
                  height: 28,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: (answers[i] == questions[i].correct ? _green : _red)
                        .withValues(alpha: .15),
                    borderRadius: OnoteRadius.smAll,
                    border: Border.all(
                        color:
                            answers[i] == questions[i].correct ? _green : _red),
                  ),
                  child: Text('${i + 1}',
                      style: OnoteType.caption.copyWith(
                          color: answers[i] == questions[i].correct
                              ? _green
                              : _red)),
                ),
              ),
          ],
        ),
      ],
    );
  }

  /// Retake — pinned in the footer in present mode.
  Widget _resultsNav(BuildContext context, OnoteSurfaces s) => Row(
        children: [
          const Spacer(),
          OutlinedButton.icon(
            onPressed: _retake,
            icon: const Icon(Icons.refresh, size: 18),
            label: const Text('Retake'),
          ),
        ],
      );

  // Readable in both themes: the tint carries the meaning, over a faint fill.
  static const _green = Color(0xFF2E9E5B);
  static const _red = Color(0xFFE5484D);
}

/// Open [block]'s quiz full-screen: the same quiz, larger and centred, with the
/// page behind it blurred and dimmed so a room can focus on it. The card is a
/// fixed size, so the results celebration does not resize it; closing returns
/// to the in-page card, the same size, with every answer preserved (the state
/// lives on the block).
Future<void> showQuizPresentation(
    BuildContext context, AppState app, Block block) {
  return showGeneralDialog<void>(
    context: context,
    barrierDismissible: true,
    barrierLabel: 'Quiz',
    barrierColor: Colors.black.withValues(alpha: 0.45),
    transitionDuration: const Duration(milliseconds: 200),
    pageBuilder: (ctx, _, __) {
      final size = MediaQuery.sizeOf(ctx);
      final w = math.min(760.0, size.width * 0.92);
      final h = math.min(560.0, size.height * 0.86);
      return BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
        child: Center(
          child: SizedBox(
            width: w,
            height: h,
            // A touch larger type than the in-page card, so the answers read
            // from across a room.
            child: MediaQuery(
              data: MediaQuery.of(ctx)
                  .copyWith(textScaler: const TextScaler.linear(1.15)),
              child: Material(
                type: MaterialType.transparency,
                child:
                    QuizBlockView(block: block, app: app, presentation: true),
              ),
            ),
          ),
        ),
      );
    },
    transitionBuilder: (ctx, anim, _, child) => FadeTransition(
      opacity: anim,
      child: ScaleTransition(
        scale: Tween<double>(begin: 0.96, end: 1.0)
            .animate(CurvedAnimation(parent: anim, curve: Curves.easeOutCubic)),
        child: child,
      ),
    ),
  );
}

/// The results flourish: a count-up to the score over a short confetti fall,
/// with a line that matches how it went. Deliberately restrained — a burst
/// that settles in about a second and a half, not a party that keeps going.
class _QuizCelebration extends StatefulWidget {
  const _QuizCelebration({
    super.key,
    required this.score,
    required this.total,
    required this.pass,
    required this.fail,
    required this.large,
    required this.textSecondary,
  });

  final int score;
  final int total;
  final Color pass;
  final Color fail;
  final bool large;
  final Color textSecondary;

  @override
  State<_QuizCelebration> createState() => _QuizCelebrationState();
}

class _QuizCelebrationState extends State<_QuizCelebration>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c;

  bool get _passed => widget.total > 0 && widget.score * 2 >= widget.total;

  @override
  void initState() {
    super.initState();
    _c = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 1500))
      ..forward();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  String get _message {
    final t = widget.total;
    final s = widget.score;
    if (t == 0) return '';
    if (s == t) return 'Perfect score!';
    if (s * 2 >= t) return 'Well done!';
    return 'Keep practising.';
  }

  @override
  Widget build(BuildContext context) {
    final color = _passed ? widget.pass : widget.fail;
    final scoreStyle = (widget.large ? OnoteType.display : OnoteType.headline)
        .copyWith(color: color, fontWeight: FontWeight.w700);
    return SizedBox(
      height: widget.large ? 168 : 120,
      child: AnimatedBuilder(
        animation: _c,
        builder: (context, _) {
          // Count the score up over the first two thirds, then hold.
          final countT =
              Curves.easeOutCubic.transform((_c.value / 0.66).clamp(0.0, 1.0));
          final shown = (widget.score * countT).round();
          // A gentle pop as the number lands.
          final pop =
              0.9 + 0.1 * Curves.easeOut.transform((_c.value).clamp(0, 1));
          return Stack(
            alignment: Alignment.center,
            children: [
              // Confetti only when it went well — a red result should not throw
              // a party. Fades out as it falls.
              if (_passed)
                Positioned.fill(
                  child: IgnorePointer(
                    child: CustomPaint(
                      painter: _ConfettiPainter(
                          progress: _c.value, seed: widget.total * 31 + 7),
                    ),
                  ),
                ),
              Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text('Your score',
                      style: OnoteType.caption
                          .copyWith(color: widget.textSecondary)),
                  const SizedBox(height: OnoteSpace.x1),
                  Transform.scale(
                    scale: pop,
                    child: Text('$shown / ${widget.total}', style: scoreStyle),
                  ),
                  const SizedBox(height: OnoteSpace.x1),
                  Opacity(
                    opacity: Curves.easeIn
                        .transform(((_c.value - 0.5) / 0.5).clamp(0.0, 1.0)),
                    child: Text(_message,
                        style: OnoteType.uiStrong.copyWith(
                            color: color, fontWeight: FontWeight.w600)),
                  ),
                ],
              ),
            ],
          );
        },
      ),
    );
  }
}

/// A short, tasteful confetti fall painted over the score. No package: a fixed
/// set of seeded particles drift down and fade, driven by a single 0..1
/// progress value so it stays cheap and deterministic.
class _ConfettiPainter extends CustomPainter {
  _ConfettiPainter({required this.progress, required this.seed});
  final double progress;
  final int seed;

  static const _colors = [
    Color(0xFF2E9E5B),
    Color(0xFF3B82F6),
    Color(0xFFF59E0B),
    Color(0xFFEC4899),
    Color(0xFF8B5CF6),
  ];

  @override
  void paint(Canvas canvas, Size size) {
    if (progress <= 0) return;
    final rnd = math.Random(seed);
    const count = 28;
    final paint = Paint();
    for (var i = 0; i < count; i++) {
      final startX = rnd.nextDouble() * size.width;
      final drift = (rnd.nextDouble() - 0.5) * 40;
      final delay = rnd.nextDouble() * 0.25;
      final speed = 0.8 + rnd.nextDouble() * 0.5;
      final t = ((progress - delay) / speed).clamp(0.0, 1.0);
      if (t <= 0) continue;
      final x = startX + drift * t;
      final y = -8 + (size.height + 16) * t;
      final fade = (1.0 - t).clamp(0.0, 1.0);
      if (fade <= 0) continue;
      final c = _colors[i % _colors.length];
      paint.color = c.withValues(alpha: fade);
      final w = 4.0 + rnd.nextDouble() * 3;
      final h = 6.0 + rnd.nextDouble() * 4;
      canvas.save();
      canvas.translate(x, y);
      canvas.rotate((rnd.nextDouble() * 2 - 1) * math.pi + t * 6);
      canvas.drawRect(
          Rect.fromCenter(center: Offset.zero, width: w, height: h), paint);
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(_ConfettiPainter old) =>
      old.progress != progress || old.seed != seed;
}
