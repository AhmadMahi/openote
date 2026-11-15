/// Central backup: keep EVERY notebook in one GitHub repo, as clean folders.
///
/// This is the "one place where everything lives" the owner asked for. Turn it
/// on once and, on a fresh notebook, on a change, and on a schedule, every
/// notebook is written into a single repository as a readable folder tree (the
/// same `Save as folders and files` format — Markdown, JSON and images, no
/// `ops`/`blobs`/`.onote` clutter), one folder per notebook.
///
/// **It is a one-way mirror, not the op-log sync.** It never pulls edits back
/// into a notebook; it exports what is here into the repo. That is what makes it
/// safe to run across ALL notebooks at once, and what keeps the repo clean and
/// browsable. The engine below owns a persistent local clone of the central
/// repo ([_mirrorDir]) so each push sends only what changed.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import '../export/md_common.dart' show safeFilename;
import '../export/open_export.dart'
    show MaterializedNotebook, materializeNotebookInto;
import '../state/app_state.dart';
import 'git_sync.dart';
import 'github_api.dart';

class CentralSync {
  CentralSync(this._app);
  final AppState _app;

  bool enabled = false;
  String? remote; // clone URL of the central repo
  String? fullName; // owner/repo
  String? status;
  bool busy = false;

  /// notebook id → the folder name it lives under in the mirror. Kept so a
  /// renamed notebook moves its folder instead of leaving the old one behind.
  final Map<String, String> _folders = {};

  Timer? _debounce;

  /// What the last export wrote for each notebook (see [MaterializedNotebook]),
  /// so a backup costs what changed rather than everything. Kept in a file
  /// inside the clone's `.git`, which git never tracks, so it is thrown away
  /// with the clone it describes. Null until first read.
  Map<String, MaterializedNotebook>? _exported;

  /// True once everything the export wrote has been committed and pushed. A
  /// cycle that changed nothing on disk then skips git entirely — no pull, no
  /// `add -A` over the whole tree, no push. False at launch, because it is not
  /// known then, so the first cycle always runs git once.
  bool _gitClean = false;

  String get _mirrorDir => p.join(_app.workspaceDirPath, 'central-mirror');

  String get _exportedFile =>
      p.join(_mirrorDir, '.git', 'slate-backup-state.json');

  Future<Map<String, MaterializedNotebook>> _loadExported() async {
    final known = _exported;
    if (known != null) return known;
    final out = <String, MaterializedNotebook>{};
    try {
      final f = File(_exportedFile);
      if (await f.exists()) {
        final raw = jsonDecode(await f.readAsString());
        if (raw is Map && raw['v'] == 1 && raw['notebooks'] is Map) {
          (raw['notebooks'] as Map).forEach((k, v) {
            if (k is String && v is Map) {
              out[k] = MaterializedNotebook.fromJson(v.cast<String, dynamic>());
            }
          });
        }
      }
    } catch (_) {
      // Unreadable: start from nothing, which only costs one full export.
    }
    return _exported = out;
  }

  Future<void> _saveExported() async {
    final known = _exported;
    if (known == null || !_gitReady) return;
    try {
      await File(_exportedFile).writeAsString(jsonEncode({
        'v': 1,
        'notebooks': {for (final e in known.entries) e.key: e.value.toJson()},
      }));
    } catch (_) {}
  }

  // ── Staying out of the user's way ────────────────────────────────────────

  /// How long the user must have left the canvas alone before a backup runs.
  static const _quietMs = 2000;

  /// The most a backup will wait for that pause, so someone who never stops
  /// still gets backed up.
  static const _maxQuietWait = Duration(minutes: 10);

  /// Wait until the user has paused drawing, writing and scrolling. The export
  /// runs on the UI thread, so running it mid-stroke is a dropped frame.
  Future<void> _waitForQuiet() async {
    final start = DateTime.now();
    while (_app.msSinceInteraction < _quietMs &&
        DateTime.now().difference(start) < _maxQuietWait) {
      await Future<void>.delayed(const Duration(milliseconds: 500));
    }
  }

  /// Between pages of an export: let a frame through, then wait out any burst
  /// of activity that started while the export was running.
  Future<void> _breathe() async {
    await Future<void>.delayed(Duration.zero);
    await _waitForQuiet();
  }

  bool get _gitReady => Directory(p.join(_mirrorDir, '.git')).existsSync();

  // ── Persistence ─────────────────────────────────────────────────────────

  void load(Object? raw) {
    if (raw is! Map) return;
    enabled = raw['enabled'] == true;
    remote = raw['remote'] as String?;
    fullName = raw['fullName'] as String?;
    _folders.clear();
    final f = raw['folders'];
    if (f is Map) {
      f.forEach((k, v) {
        if (k is String && v is String) _folders[k] = v;
      });
    }
  }

  Map<String, Object?> _toJson() => {
        'enabled': enabled,
        if (remote != null) 'remote': remote,
        if (fullName != null) 'fullName': fullName,
        'folders': Map<String, String>.from(_folders),
      };

  void _save() => _app.persistCentralSync(enabled ? _toJson() : null);

  // ── Enable / disable ──────────────────────────────────────────────────────

  /// Turn central backup on. With [existingRemote] it binds to a repo you
  /// already have; otherwise it creates a new private one (named `slate-<you>`
  /// or [name]). Then it clones the repo locally and runs a first full backup.
  /// Returns null on success, or a message.
  Future<String?> enable({String? existingRemote, String? name}) async {
    if (!_app.githubConnected) return 'Connect a GitHub account first.';
    if (await GitSync.gitExecutable() == null) {
      return 'Git is not installed on this computer. Install it from '
          'git-scm.com to back up all notebooks.';
    }
    busy = true;
    status = 'Preparing the backup repository…';
    _app.notifyCentral();
    try {
      final api = _app.githubApi();
      if (api == null) return 'Connect a GitHub account first.';
      String url;
      String full;
      if (existingRemote != null && existingRemote.trim().isNotEmpty) {
        url = existingRemote.trim();
        final fn = repoFullNameFromRemote(url);
        if (fn == null) return 'That is not a GitHub repository URL.';
        full = fn;
      } else {
        final repoName = (name?.trim().isNotEmpty ?? false)
            ? repoNameFor(name!)
            : 'slate-${_app.githubLogin ?? 'notebooks'}';
        final made = await api.createRepo(repoName,
            private: true, description: 'Slate — all notebooks backup');
        if (!made.ok) return made.error;
        url = made.cloneUrl!;
        full = made.fullName!;
      }
      remote = url;
      fullName = full;
      enabled = true;
      // A fresh clone of the (possibly empty) repo, so pushes send only deltas.
      await _prepareMirror();
      _save();
      final err = await syncAll();
      return err;
    } catch (e) {
      return 'Could not enable backup: $e';
    } finally {
      busy = false;
      _app.notifyCentral();
    }
  }

  void disable() {
    enabled = false;
    _debounce?.cancel();
    status = null;
    _save();
    _app.notifyCentral();
  }

  /// Clone the central repo into [_mirrorDir] if it is not already a clone.
  Future<void> _prepareMirror() async {
    if (_gitReady) return;
    _exported = null;
    _gitClean = false;
    final dir = Directory(_mirrorDir);
    if (dir.existsSync()) dir.deleteSync(recursive: true);
    // Shallow: the mirror only ever writes the newest snapshot and pushes it.
    // The history lives on GitHub; a local copy of it is disk nothing reads.
    final r = await GitSync.clone(remote!, _mirrorDir,
        token: _app.githubTokenForSync, depth: 1);
    if (!r.ok) {
      // An empty repo clones to an empty working tree with a .git; some git
      // builds still return non-zero with a warning. Fall back to init when the
      // clone did not leave a usable repo.
      if (!_gitReady) {
        final g = GitSync(_mirrorDir, token: _app.githubTokenForSync);
        await Directory(_mirrorDir).create(recursive: true);
        await g.init();
        await g.setRemote(remote!);
      }
    }
  }

  // ── Syncing ───────────────────────────────────────────────────────────────

  /// Debounced backup of the OPEN notebook — cheap enough to run after edits.
  void scheduleSync() {
    if (!enabled) return;
    _debounce?.cancel();
    _debounce = Timer(const Duration(seconds: 90), () {
      unawaited(syncCurrent());
    });
  }

  /// Back up every notebook. Used on enable, on create, and periodically.
  Future<String?> syncAll() => _run((mirror) async {
        await _app.flushSave();
        var changed = false;
        for (final nb in _app.notebooks) {
          if (await _materialiseNotebook(nb.id, nb.title)) changed = true;
        }
        return changed;
      }, 'Slate: back up all notebooks');

  /// Back up just the open notebook (the debounced path).
  Future<String?> syncCurrent() {
    final id = _app.notebookId;
    if (id == null) return Future.value();
    final nb = _app.notebooks.where((n) => n.id == id).firstOrNull;
    if (nb == null) return Future.value();
    return _run((mirror) async {
      await _app.flushSave();
      return _materialiseNotebook(nb.id, nb.title);
    }, 'Slate: back up ${nb.title}');
  }

  /// Remove a notebook's folder from the backup (after the user confirmed the
  /// deletion should also apply to GitHub).
  Future<String?> removeNotebook(String nbId, String title) =>
      _run((mirror) async {
        final folder = _folders[nbId] ?? safeFilename(title);
        final dir = Directory(p.join(mirror, folder));
        final existed = await dir.exists();
        if (existed) await dir.delete(recursive: true);
        _folders.remove(nbId);
        (await _loadExported()).remove(nbId);
        return existed;
      }, 'Slate: remove $title from backup');

  /// Bring `mirror/<folder>/` up to date with one notebook, moving the folder
  /// if the notebook was renamed. Returns whether anything on disk changed.
  ///
  /// In place and incremental (see [materializeNotebookInto]): it used to wipe
  /// the folder and rebuild every page, picture and PDF on each run — and for
  /// a closed notebook it first read every PDF in the folder into memory, on
  /// the UI thread, just to write them back afterwards. Now an unchanged
  /// notebook costs a couple of database reads, and a closed notebook's PDFs
  /// simply stay where they are.
  ///
  /// Page PDFs are written for the OPEN notebook only (the PDF builder reads
  /// the open notebook); a closed notebook keeps the PDFs from the last time it
  /// was open.
  Future<bool> _materialiseNotebook(String nbId, String title) async {
    final exported = await _loadExported();
    final desired = _uniqueFolder(nbId, title);
    final prev = _folders[nbId];
    var changed = false;
    if (prev != null && prev != desired) {
      final old = Directory(p.join(_mirrorDir, prev));
      if (await old.exists()) {
        await old.delete(recursive: true);
        changed = true;
      }
      exported.remove(nbId);
    }
    final mine = exported[nbId] ??= MaterializedNotebook();
    if (await materializeNotebookInto(
        _app, nbId, p.join(_mirrorDir, desired),
        withPagePdf: nbId == _app.notebookId,
        incremental: mine,
        breathe: _breathe)) {
      changed = true;
    }
    _folders[nbId] = desired;
    return changed;
  }

  /// A stable, readable, collision-free folder name for a notebook.
  String _uniqueFolder(String nbId, String title) {
    final base = safeFilename(title);
    // Keep the name this notebook already uses if it still matches its title.
    if (_folders[nbId] != null &&
        _folders[nbId] == base &&
        !_folders.entries.any((e) => e.key != nbId && e.value == base)) {
      return base;
    }
    var candidate = base;
    var i = 2;
    bool taken(String c) =>
        _folders.entries.any((e) => e.key != nbId && e.value == c);
    while (taken(candidate)) {
      candidate = '$base-$i';
      i++;
    }
    return candidate;
  }

  /// Shared wrapper: guard, prepare the mirror, run [body], commit and push.
  ///
  /// Quiet by design. It waits for the user to pause before starting, skips
  /// git when [body] changed nothing and the last push went through, and only
  /// tells the app to rebuild when the status line actually changes — every
  /// status change rebuilds the whole window, and a check that finds nothing
  /// to do every five minutes should not cost two of those.
  Future<String?> _run(
      Future<bool> Function(String mirror) body, String message) async {
    if (!enabled) return null;
    if (!_app.githubConnected) {
      _setStatus('Sign in to GitHub to back up.');
      return status;
    }
    if (busy) return null;
    busy = true;
    try {
      await _waitForQuiet();
      await _prepareMirror();
      final changed = await body(_mirrorDir);
      _save();
      await _saveExported();
      if (!changed && _gitClean) {
        _setStatus('Backed up');
        return null;
      }
      _setStatus('Backing up…');
      final git = GitSync(_mirrorDir, token: _app.githubTokenForSync);
      final r = await git.syncOnce(message: message);
      _gitClean = r.ok;
      _setStatus(
          r.ok ? 'Backed up' : 'Backup failed: ${r.message.split('\n').first}');
      return r.ok ? null : status;
    } catch (e) {
      _gitClean = false;
      _setStatus('Backup failed: $e');
      return status;
    } finally {
      busy = false;
    }
  }

  void _setStatus(String? next) {
    if (status == next) return;
    status = next;
    _app.notifyCentral();
  }

  /// Delete the LOCAL copies of every notebook — the GitHub backup keeps them.
  /// For wiping a borrowed machine clean after a restore. Returns how many were
  /// removed (the app keeps at least one notebook, so the last may remain).
  Future<int> removeLocalCopies() async {
    var removed = 0;
    for (final id in [for (final n in _app.notebooks) n.id]) {
      if (await _app.deleteNotebook(id)) removed++;
    }
    _folders.clear();
    if (enabled) _save();
    _app.notifyCentral();
    return removed;
  }

  void dispose() => _debounce?.cancel();
}
