// A shortcut is one PRINTABLE character, or nothing.
//
// This is not a style rule. Ctrl+A does not report the letter A — it reports
// the control character U+0001, which is a single character and passed the
// "length == 1" check the capture originally had. So a stray Ctrl-chord while
// the picker was listening stored an invisible byte as an ink shortcut, and
// from then on that chord would change colour mid-stroke with nothing on
// screen to explain it.
//
// Found by binding a key on a real build and reading the settings file back,
// which is the only way it could have been found: the dialog displayed the
// key it thought it had captured, and the file on disk disagreed.
//
// Sanitising lives in the state layer as well as in the field that captures,
// because a settings file is not a trusted input — it can be hand-edited, and
// it can carry values written by an older, laxer build.
import 'package:flutter_test/flutter_test.dart';
import 'package:openote/state/app_state.dart';

void main() {
  group('what counts as a shortcut', () {
    test('a printable character does, folded to lower case', () {
      expect(AppState.sanitiseShortcut('q'), 'q');
      expect(AppState.sanitiseShortcut('Q'), 'q');
      expect(AppState.sanitiseShortcut('5'), '5');
      expect(AppState.sanitiseShortcut('/'), '/');
    });

    test('a control character does NOT — this is the one that bit', () {
      expect(AppState.sanitiseShortcut('\u0001'), '',
          reason: 'Ctrl+A, which is what actually landed in the settings file');
      expect(AppState.sanitiseShortcut('\u001b'), '', reason: 'Escape');
      expect(AppState.sanitiseShortcut('\u007f'), '', reason: 'Delete');
      expect(AppState.sanitiseShortcut('\n'), '');
      expect(AppState.sanitiseShortcut('\t'), '');
    });

    test('nor does a space, nothing, or more than one character', () {
      expect(AppState.sanitiseShortcut(' '), '',
          reason: 'an invisible binding is one nobody can see they have');
      expect(AppState.sanitiseShortcut(''), '');
      expect(AppState.sanitiseShortcut(null), '');
      expect(AppState.sanitiseShortcut('qq'), '');
    });
  });
}
