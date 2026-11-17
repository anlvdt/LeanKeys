"""Orchestrator for webbench: walks browser x field x engine x speed x sentence.

For every case it opens the bench page in the browser, types the keys with typist,
waits for the page to POST its result, and appends one JSON line to the results file.
LeanKeys is restarted only when the engine changes. Whatever happens, the original
LeanKeys.engine value is restored, the debug log is disabled if this run enabled it,
and /Applications/LeanKeys.app is relaunched.

Latency baseline: take it WITHOUT --debug-log. The log's write cost sits inside the timed span.

A failing case is recorded and the run goes on, except for the stops listed in STOP_REASON
(permissions, guard, real input), a streak of unmeasured cases, or repeated failed tab closes:
those end the run, then the restore runs.

Usage: python3 -I tools/webbench/run.py --dry-run
"""
import argparse
import json
import os
import secrets
import signal
import subprocess
import sys
import threading
import time
import urllib.error
import urllib.request
from datetime import datetime

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)

import server  # noqa: E402
from scoring import char_diff, word_latencies, percentile  # noqa: E402
from wordscore import word_errors  # noqa: E402

KEY = 'LeanKeys.engine'
APP_PATH = '/Applications/LeanKeys.app'
BUNDLE_LEANKEYS = 'io.github.anlvdt.leankeys'
BUNDLES = {
    'chrome': 'com.google.Chrome',
    'safari': 'com.apple.Safari',
    'firefox': 'org.mozilla.firefox',
}
FIELD_NAMES = ['input', 'textarea', 'contenteditable', 'autocomplete',
               'lexical', 'slate', 'prosemirror', 'quill']
ENGINES = ['vikey', 'gonhanh', 'off']
SPEEDS = ['human', 'fast', 'burst']
GROUPS = ['office', 'chat', 'dbl', 'extra', 'research']
DEFAULT_GROUPS = 'office,chat,dbl,extra'
TYPIST = os.path.join(HERE, 'typist', '.build', 'release', 'typist')
CORPUS = os.path.join(HERE, 'corpus.tsv')
RESULTS_DIR = os.path.join(HERE, 'results')

READY_TIMEOUT_S = 15    # typist waits this long for the page's ready title, before any key
QUIET_S = 1.5           # after typing: the page posts 800 ms after the last key; typist --watch
PRE_OPEN_WATCH_S = 0.3  # before each open: a user key in the gap must not reach the next page
RESULT_TIMEOUT_S = 5.0  # poll window for the POSTed result
POLL_S = 0.25
QUIT_TIMEOUT_S = 10.0
LAUNCH_TIMEOUT_S = 10.0
CLOSE_FAIL_LIMIT = 3    # tab closes that failed in a row before the run stops
STATUS_STREAK_LIMIT = 5 # cases in a row without status ok before the run stops
# Per-case cost on top of the keys: the ready wait (typical; a cold editor CDN can take longer),
# QUIET_S, and open, typist start, the osascript close and the polls. A floor, not a forecast.
READY_EXPECT_S = 2.0
OPEN_CLOSE_S = 1.5
OVERHEAD_S = READY_EXPECT_S + QUIET_S + OPEN_CLOSE_S
# Mean inter-key delay per speed (human: uniform 1/12..1/8 s; fast: 25 keys/s; burst: none).
MEAN_KEY_S = {'human': (1 / 12 + 1 / 8) / 2, 'fast': 1 / 25, 'burst': 0.0}

# typist exit codes (see typist/Sources/typist/main.swift)
TYPIST_STATUS = {3: 'aborted', 4: 'aborted', 6: 'aborted'}   # the case is not measured
PER_CASE_CODES = (0, 5, 6)                                  # everything else ends the run
STOP_REASON = {                                             # these end the whole run
    1: 'typist usage or event failure',
    2: 'Accessibility, Input Monitoring or the US layout is missing',
    3: 'the browser was not frontmost on the bench tab (guard refused)',
    4: 'real keyboard or mouse input (the run gives the Mac back)',
}


class RunStopped(RuntimeError):
    """Ends the run at once. The restore still runs; the message says why."""


# MARK: - corpus and plan (pure)

def load_corpus(path=CORPUS):
    """Rows of (keys, target, flags, group); case number is the 1-based row number."""
    rows = []
    with open(path, encoding='utf-8') as f:
        for line in f:
            line = line.rstrip('\n')
            if not line:
                continue
            keys, target, flags, group = line.split('\t')
            rows.append({'case': len(rows) + 1, 'keys': keys, 'target': target,
                         'flags': flags, 'group': group})
    return rows


def word_spans(keys):
    """(end, next) per word, for the latency window (see scoring.word_latencies).
    A word is a run of non-space keys that has at least one letter key. end is the run's
    last key; next is the first key of the following run of any kind, or None at the end.
    A digit-only run (the 2 in 'lúc 2 giờ') is not a word: it gets no entry, but it still
    closes the previous word's window. Backspace (`) inside a word counts as a key."""
    runs = []
    i, n = 0, len(keys)
    while i < n:
        if keys[i] == ' ':
            i += 1
            continue
        j = i
        while j < n and keys[j] != ' ':
            j += 1
        runs.append((i, j - 1))
        i = j
    spans = []
    for idx, (first, last) in enumerate(runs):
        if not any(ch.isalpha() for ch in keys[first:last + 1]):
            continue
        nxt = runs[idx + 1][0] if idx + 1 < len(runs) else None
        spans.append((last, nxt))
    return spans


def build_plan(rows, browsers, fields, engines, speeds, groups, limit, run_id):
    """Cases in run order: engine, browser, field, speed, sentence. `limit` keeps the first
    N sentences of each group. Each case gets its own token, so no page result is reused."""
    chosen = []
    for group in groups:
        in_group = [r for r in rows if r['group'] == group]
        chosen.extend(in_group[:limit] if limit else in_group)
    plan = []
    for engine in engines:
        for browser in browsers:
            for field in fields:
                for speed in speeds:
                    for row in chosen:
                        seq = len(plan) + 1
                        plan.append({
                            'browser': browser, 'bundle': BUNDLES[browser],
                            'field': field, 'engine': engine, 'speed': speed,
                            'group': row['group'], 'case': row['case'],
                            'token': '%s%06d' % (run_id, seq),
                            'keys': row['keys'], 'target': row['target'],
                            'flags': row['flags'],
                            'word_spans': word_spans(row['keys']),
                        })
    return plan


def estimate_seconds(plan):
    total = 0.0
    for c in plan:
        total += len(c['keys']) * MEAN_KEY_S[c['speed']] + OVERHEAD_S
    return total


def page_url(case, base):
    return '%s/?field=%s&token=%s&case=%d' % (base, case['field'], case['token'], case['case'])


def result_url(case, base):
    return '%s/result/%s/%d' % (base, case['token'], case['case'])


def typist_args(case):
    return ['--keys', case['keys'], '--speed', case['speed'], '--seed', str(case['case']),
            '--bundle', case['bundle'], '--token', case['token'],
            '--ready-timeout', str(READY_TIMEOUT_S)]


# MARK: - machine (every side effect; FakeMachine in tests)

def _block_signals():
    return signal.pthread_sigmask(signal.SIG_BLOCK, {signal.SIGINT, signal.SIGTERM})


def _unblock_signals(old):
    signal.pthread_sigmask(signal.SIG_SETMASK, old)


def _close_script(bundle, token):
    """AppleScript that closes this run's bench tab, or None for an unknown browser.
    Each script checks, then closes the tab it checked (by reference), in one block.
    Firefox has no tab scripting, so it is System Events plus Cmd+W. Residual risk: focus
    can move between the check and the keystroke. The check still refuses unless Firefox is
    frontmost and its front window title carries this run's token."""
    mark = 'webbench-%s-' % token
    if bundle in (BUNDLES['chrome'], BUNDLES['safari']):
        # Chrome tabs have `title`; Safari tabs have `name` (no `title`).
        tab, prop = (('active tab', 'title') if bundle == BUNDLES['chrome']
                     else ('current tab', 'name'))
        return '\n'.join([
            'tell application id "%s"' % bundle,
            '  if not frontmost then return "no"',
            '  if (count of windows) is 0 then return "no"',
            '  set t to %s of front window' % tab,
            '  if not ((%s of t) contains "%s") then return "no"' % (prop, mark),
            '  close t',
            '  return "yes"',
            'end tell',
        ])
    if bundle == BUNDLES['firefox']:
        return '\n'.join([
            'tell application "System Events"',
            '  set p to first application process whose frontmost is true',
            '  if bundle identifier of p is not "%s" then return "no"' % bundle,
            '  if (count of windows of p) is 0 then return "no"',
            '  if not ((name of front window of p) contains "%s") then return "no"' % mark,
            '  tell p to keystroke "w" using command down',
            '  return "yes"',
            'end tell',
        ])
    return None


def _osa(script):
    """Run an AppleScript; '' on any failure (the caller decides what that means)."""
    try:
        p = subprocess.run(['osascript', '-e', script], capture_output=True, text=True)
    except OSError:
        return ''
    return p.stdout.strip() if p.returncode == 0 else ''

class Machine:
    """Real side effects. Tests pass a fake with the same methods."""

    def defaults_read(self, key):
        p = subprocess.run(['defaults', 'read', BUNDLE_LEANKEYS, key],
                           capture_output=True, text=True)
        return p.stdout.rstrip('\n') if p.returncode == 0 else None

    def defaults_write(self, key, value):
        subprocess.run(['defaults', 'write', BUNDLE_LEANKEYS, key, '-string', value], check=True)

    def defaults_delete(self, key):
        subprocess.run(['defaults', 'delete', BUNDLE_LEANKEYS, key], capture_output=True)

    def quit_leankeys(self):
        subprocess.run(['osascript', '-e',
                        'tell application id "%s" to quit' % BUNDLE_LEANKEYS],
                       capture_output=True)

    def wait_gone(self, timeout):
        deadline = time.monotonic() + timeout
        while True:
            p = subprocess.run(['pgrep', '-f', 'LeanKeys.app/Contents/MacOS/'],
                               capture_output=True)
            if p.returncode != 0:
                return True
            if time.monotonic() >= deadline:
                return False
            time.sleep(0.2)

    def launch(self, app_path):
        subprocess.run(['open', app_path], check=True)

    def open_url(self, bundle, url):
        subprocess.run(['open', '-b', bundle, url], check=True)

    def close_bench_tab(self, bundle, token):
        """Check and close the bench tab in ONE AppleScript per browser. Returns True only if
        the script ran and reported that it closed the tab."""
        script = _close_script(bundle, token)
        if script is None:
            return False
        return _osa(script) == 'yes'

    def browser_installed(self, bundle):
        p = subprocess.run(['/usr/bin/mdfind', 'kMDItemCFBundleIdentifier == "%s"' % bundle],
                           capture_output=True, text=True)
        return p.returncode == 0 and bool(p.stdout.strip())

    def typist_check(self):
        """typist --check: permissions and layout, nothing posted. Its message goes to stderr."""
        return subprocess.run([TYPIST, '--check']).returncode

    def wait_running(self, timeout):
        deadline = time.monotonic() + timeout
        while True:
            p = subprocess.run(['pgrep', '-f', 'LeanKeys.app/Contents/MacOS/'],
                               capture_output=True)
            if p.returncode == 0:
                return True
            if time.monotonic() >= deadline:
                return False
            time.sleep(0.2)

    def watch(self, seconds):
        """typist --watch: 0 if no real input for `seconds`, 4 if some came, posts nothing."""
        return subprocess.run([TYPIST, '--watch', '%.2f' % seconds]).returncode

    def run_typist(self, args):
        p = subprocess.run([TYPIST] + args, stdout=subprocess.PIPE, text=True)
        return p.returncode, p.stdout

    def http_get(self, url):
        try:
            with urllib.request.urlopen(url, timeout=2) as resp:
                return resp.status, resp.read().decode('utf-8', 'replace')
        except urllib.error.HTTPError as e:
            return e.code, ''
        except OSError:
            return 0, ''

    def now(self):
        return time.monotonic()

    def sleep(self, seconds):
        time.sleep(seconds)

    def log_path(self):
        return os.path.expanduser('~/Library/Logs/LeanKeys/debug.log')

    def enable_log(self):
        """True if this call created the log (and so owns it); False if it was already on."""
        path = self.log_path()
        if os.path.exists(path):
            return False
        folder = os.path.dirname(path)
        os.makedirs(folder, mode=0o700, exist_ok=True)
        fd = os.open(path, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
        os.close(fd)
        os.chmod(path, 0o600)
        return True

    def disable_log(self):
        try:
            os.unlink(self.log_path())
        except FileNotFoundError:
            pass

    def read_log(self):
        try:
            with open(self.log_path(), encoding='utf-8', errors='replace') as f:
                return f.read()
        except FileNotFoundError:
            return ''


# MARK: - run

def _blank_record(case):
    return {'browser': case['browser'], 'field': case['field'], 'engine': case['engine'],
            'speed': case['speed'], 'group': case['group'], 'case': case['case'],
            'status': None, 'reason': None, 'text': None, 'target': case['target'],
            'flags': case['flags'], 'sent': None, 'inputs': None,
            'word_spans': case['word_spans']}


def _where(case):
    return 'case %d (%s %s %s %s)' % (case['case'], case['browser'], case['field'],
                                      case['engine'], case['speed'])


class _Session:
    def __init__(self, machine, out, app_path, perf_log, base):
        self.m = machine
        self.base = base
        self.out = out
        self.app_path = app_path
        self.perf_log = perf_log
        self.engine = None
        self.perf_offset = 0
        self.owns_log = False
        self.warned_no_log = False
        self.close_streak = 0
        self.close_failures = 0
        self.status_streak = 0

    def write(self, record):
        self.out.write(json.dumps(record, ensure_ascii=False) + '\n')
        self.out.flush()

    def quit_confirmed(self):
        self.m.quit_leankeys()
        return self.m.wait_gone(QUIT_TIMEOUT_S)

    def harvest(self):
        """Write the perf lines LeanKeys logged since the last harvest, for the current engine."""
        if not self.perf_log or self.engine in (None, 'off'):
            return
        text = self.m.read_log()
        if not text and not self.warned_no_log:
            self.warned_no_log = True
            print('WEBBENCH: the LeanKeys debug log is missing or empty; no perf lines are '
                  'collected for it (it may have expired)', file=sys.stderr, flush=True)
        new = text[self.perf_offset:]
        self.perf_offset = len(text)
        lines = [ln for ln in new.splitlines() if 'perf: ' in ln]
        if lines:
            self.write({'kind': 'perf', 'engine': self.engine, 'lines': lines})

    def set_engine(self, engine):
        if engine == self.engine:
            return
        self.harvest()
        if engine != 'off':
            self.m.defaults_write(KEY, engine)
        if not self.quit_confirmed():
            raise RunStopped('LeanKeys did not quit within %ds; nothing was launched'
                             % QUIT_TIMEOUT_S)
        self.engine = engine
        if engine != 'off':
            self.m.launch(self.app_path)
            if not self.m.wait_running(LAUNCH_TIMEOUT_S):
                raise RunStopped('LeanKeys did not start within %ds' % LAUNCH_TIMEOUT_S)

    def run_case(self, case):
        rec = _blank_record(case)
        stop = self._watch_stop(PRE_OPEN_WATCH_S)
        if stop:
            raise RunStopped('stopped before %s: %s' % (_where(case), stop))
        try:
            self.m.open_url(case['bundle'], page_url(case, self.base))
        except (OSError, subprocess.CalledProcessError) as e:
            rec['status'] = 'aborted'
            rec['reason'] = 'could not open %s: %s' % (case['browser'], e)
        else:
            stop = self._type(case, rec)
        self.write(rec)
        closed = self.m.close_bench_tab(case['bundle'], case['token'])
        if closed:
            self.close_streak = 0
        else:
            self.close_streak += 1
            self.close_failures += 1
            print('WEBBENCH: could not close the bench tab for %s; it may still be open'
                  % _where(case), file=sys.stderr, flush=True)
        if stop:
            raise RunStopped('stopped at %s: %s' % (_where(case), stop))
        if self.close_streak >= CLOSE_FAIL_LIMIT:
            raise RunStopped(
                'the bench tab could not be closed %d times in a row. Grant Automation for '
                'the browser (Chrome, Safari) or Accessibility for Terminal (Firefox) in System '
                'Settings > Privacy & Security, close the leftover webbench tabs, then run again'
                % CLOSE_FAIL_LIMIT)
        self.status_streak = 0 if rec['status'] == 'ok' else self.status_streak + 1
        if self.status_streak >= STATUS_STREAK_LIMIT:
            raise RunStopped('%d cases in a row were not measured (last: %s, %s)'
                             % (STATUS_STREAK_LIMIT, _where(case), rec['reason'] or rec['status']))
        return rec

    def _watch_stop(self, seconds):
        """Stop reason if real input arrived (or typist --watch could not run), else None."""
        code = self.m.watch(seconds)
        if code == 0:
            return None
        return STOP_REASON.get(code, 'typist --watch exit %d' % code)

    def _type(self, case, rec):
        """Types the case and collects the page result into rec. Returns a stop reason or None.
        Any exit code outside PER_CASE_CODES (signals and crashes included) ends the run."""
        code, out = self.m.run_typist(typist_args(case))
        if code == 0:
            sent = _parse_sent(out, len(case['keys']))
            if sent is None:
                rec['status'] = 'typist-error'
                rec['reason'] = 'typist printed no usable sent list'
                return None
            rec['sent'] = sent
            # Real input during the quiet wait, the poll and the page's last POST would be scored
            # as typed text, so the wait is a watch: any real input aborts the case.
            watch_stop = self._watch_stop(QUIET_S)
            if watch_stop:
                rec['status'] = 'aborted'
                rec['reason'] = 'real input after typing'
                return watch_stop
            self._collect(case, rec)
            return None
        rec['status'] = TYPIST_STATUS.get(code, 'typist-error')
        rec['reason'] = 'typist exit %d' % code
        if code in PER_CASE_CODES:
            return None
        return STOP_REASON.get(code, 'typist exit %d (crash or unknown code)' % code)

    def _collect(self, case, rec):
        url = result_url(case, self.base)
        deadline = self.m.now() + RESULT_TIMEOUT_S
        while True:
            status, body = self.m.http_get(url)
            if status == 200:
                try:
                    data = json.loads(body)
                    rec['text'] = data['text']
                    rec['inputs'] = data['inputs']
                    rec['status'] = 'ok'
                    return
                except (ValueError, KeyError, TypeError):
                    pass
            if self.m.now() >= deadline:
                rec['status'] = 'no-result'
                rec['reason'] = 'no result POST within %d s' % RESULT_TIMEOUT_S
                return
            self.m.sleep(POLL_S)

    def restore(self, original, app_path):
        """Put the engine back, stop the debug log if this run started it, relaunch
        /Applications/LeanKeys.app. SIGINT and SIGTERM are blocked for the whole restore, so
        no step is cut short; a signal that arrived meanwhile is delivered on unblock.
        Each step still runs if an earlier one fails. Returns a dict with
        'interrupted' (a Ctrl-C or SIGTERM arrived) and 'relaunched' (the relaunch happened)."""
        errors = []
        flags = {'interrupted': False, 'relaunched': False}
        gone = [False]

        def attempt(fn):
            try:
                fn()
            except KeyboardInterrupt:
                flags['interrupted'] = True
            except BaseException as e:  # keep restoring the rest
                errors.append(e)

        def restore_engine():
            if original is None:
                self.m.defaults_delete(KEY)
            else:
                self.m.defaults_write(KEY, original)

        def confirm_quit():
            gone[0] = self.quit_confirmed()

        def relaunch():
            self.m.launch(app_path)
            flags['relaunched'] = True

        old = _block_signals()
        try:
            attempt(self.harvest)
            attempt(lambda: self.m.disable_log() if self.owns_log else None)
            attempt(restore_engine)
            attempt(confirm_quit)
            if gone[0]:
                attempt(relaunch)
        finally:
            try:
                _unblock_signals(old)
            except KeyboardInterrupt:
                flags['interrupted'] = True
        if not flags['relaunched']:
            if gone[0]:
                why = 'LeanKeys relaunch failed; open /Applications/LeanKeys.app by hand'
            else:
                why = 'LeanKeys did not quit; quit it, then open /Applications/LeanKeys.app'
            print('WEBBENCH: ' + why, file=sys.stderr, flush=True)
        for e in errors:
            print('webbench restore: %r' % (e,), file=sys.stderr, flush=True)
        return flags

def _parse_sent(stdout, n):
    try:
        sent = json.loads(stdout)['sent']
    except (ValueError, KeyError, TypeError):
        return None
    return sent if isinstance(sent, list) and len(sent) == n else None


def run_matrix(machine, plan, out_path, app_path=APP_PATH, base_url=None, perf_log=False,
               progress=None):
    """Run every case in `plan`, appending records to out_path (created 0600). Returns a summary.
    summary['interrupted']: Ctrl-C or SIGTERM. summary['stopped']: the reason the run ended
    early (a typist stop code, too many failed tab closes, a streak of unmeasured cases).
    The restore always runs and survives a second interrupt."""
    original = machine.defaults_read(KEY)
    summary = {'interrupted': False, 'stopped': None, 'restored': False, 'cases': 0,
               'close_failures': 0, 'out': out_path}
    fd = os.open(out_path, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
    with os.fdopen(fd, 'w', encoding='utf-8') as out:
        s = _Session(machine, out, app_path, perf_log, base_url)
        try:
            try:
                if perf_log:
                    # Masked so a Ctrl-C cannot land between the file appearing and owns_log.
                    old = _block_signals()
                    try:
                        s.perf_offset = len(machine.read_log())
                        s.owns_log = machine.enable_log()
                    finally:
                        _unblock_signals(old)
                for i, case in enumerate(plan, 1):
                    s.set_engine(case['engine'])
                    rec = s.run_case(case)
                    summary['cases'] += 1
                    if progress:
                        progress(i, len(plan), rec)
            except KeyboardInterrupt:
                summary['interrupted'] = True
            except RunStopped as e:
                summary['stopped'] = str(e)
        finally:
            # Masked before restore() so a Ctrl-C arriving here cannot skip the restore.
            old = _block_signals()
            try:
                flags = s.restore(original, APP_PATH)
                summary['restored'] = flags['relaunched']
                if flags['interrupted']:
                    summary['interrupted'] = True
            finally:
                try:
                    _unblock_signals(old)
                except KeyboardInterrupt:
                    summary['interrupted'] = True
        summary['close_failures'] = s.close_failures
    return summary


# MARK: - command line

def _csv(value, allowed, name):
    items = [v.strip() for v in value.split(',') if v.strip()]
    for v in items:
        if v not in allowed:
            raise SystemExit('%s: unknown value %r (allowed: %s)' % (name, v, ','.join(allowed)))
    return items


def final_message(summary):
    if summary.get('restored'):
        return 'LeanKeys relaunched.'
    return 'LeanKeys was not relaunched: see the line above.'


def preflight(machine, browsers):
    """Checks before the consent prompt: every chosen browser is installed and typist can
    type (Accessibility, Input Monitoring, US layout). Posts nothing. Returns a message or None."""
    for b in browsers:
        if not machine.browser_installed(BUNDLES[b]):
            return '%s is not installed (%s); leave it out of --browsers' % (b, BUNDLES[b])
    if machine.typist_check() != 0:
        return ('typist --check failed (see the message above). Give this terminal Accessibility '
                'and Input Monitoring, switch to the US layout, then run again.')
    return None


def _interrupt(signum, frame):
    raise KeyboardInterrupt


def main(argv=None, machine=None):
    p = argparse.ArgumentParser(
        description='webbench orchestrator. Engine changes during the run launch the copy '
                    'given by --app. The final relaunch is always /Applications/LeanKeys.app; '
                    'if that copy cannot be confirmed quit, the run prints a line telling you '
                    'to start LeanKeys by hand. Latency: take the baseline WITHOUT --debug-log '
                    '(the log write cost is inside the timed span); --debug-log is for the perf '
                    'section, in a separate run.')
    p.add_argument('--browsers', default='chrome,safari,firefox')
    p.add_argument('--fields', default='all')
    p.add_argument('--engines', default=','.join(ENGINES))
    p.add_argument('--speeds', default='human,fast')
    p.add_argument('--groups', default=DEFAULT_GROUPS)
    p.add_argument('--app', default=APP_PATH,
                   help='copy launched for mid-run engine changes (the final relaunch is '
                        'always /Applications/LeanKeys.app)')
    p.add_argument('--limit', type=int, default=None, help='first N sentences of each group')
    p.add_argument('--out', default=None, help='results file (default results/<time>.jsonl)')
    p.add_argument('--debug-log', action='store_true',
                   help='enable LeanKeys perf logging for the run and collect it. Its write cost '
                        'is inside the latency span, so do not take the latency baseline with it')
    p.add_argument('--yes', action='store_true', help='do not ask before running')
    p.add_argument('--dry-run', action='store_true', help='print the plan and estimate only')
    args = p.parse_args(argv)

    browsers = _csv(args.browsers, list(BUNDLES), '--browsers')
    fields = FIELD_NAMES if args.fields == 'all' else _csv(args.fields, FIELD_NAMES, '--fields')
    engines = _csv(args.engines, ENGINES, '--engines')
    speeds = _csv(args.speeds, SPEEDS, '--speeds')
    groups = _csv(args.groups, GROUPS, '--groups')

    rows = load_corpus()
    run_id = secrets.token_hex(4)
    plan = build_plan(rows, browsers, fields, engines, speeds, groups, args.limit, run_id)
    secs = estimate_seconds(plan)
    switches = 0
    last = None
    for c in plan:
        if c['engine'] != last:
            switches += 1
            last = c['engine']
    print('Matrix: %d cases, %d engine segments' % (len(plan), switches))
    print('Estimate: at least %.1f h (%.0f min); includes about %.1f s per case for the ready '
          'wait, the quiet wait and tab work' % (secs / 3600, secs / 60, OVERHEAD_S))
    if args.debug_log:
        print('Note: --debug-log adds its own cost to the latency numbers of this run.')
    if args.dry_run:
        counts = {}
        for c in plan:
            k = (c['browser'], c['field'], c['engine'], c['speed'], c['group'])
            counts[k] = counts.get(k, 0) + 1
        for k in sorted(counts):
            print('  %s x %s x %s x %s x %s: %d' % (k + (counts[k],)))
        print('Dry run: nothing was started or changed.')
        return 0

    if not plan:
        print('Nothing to run.', file=sys.stderr)
        return 2
    if not os.path.isfile(TYPIST):
        print('typist is not built: run `swift build -c release` in tools/webbench/typist',
              file=sys.stderr)
        return 2
    if not os.path.isdir(args.app):
        print('app not found: %s' % args.app, file=sys.stderr)
        return 2
    machine = machine or Machine()
    problem = preflight(machine, browsers)
    if problem:
        print('webbench: ' + problem, file=sys.stderr)
        return 2
    if not args.yes:
        answer = input('Run %d cases (at least %.1f h)? Type y to continue: '
                       % (len(plan), secs / 3600))
        if answer.strip().lower() != 'y':
            print('Not run.')
            return 1

    out_path = args.out or os.path.join(
        RESULTS_DIR, datetime.now().strftime('%Y%m%d-%H%M%S') + '.jsonl')
    os.makedirs(os.path.dirname(os.path.abspath(out_path)), exist_ok=True)

    httpd = server.make_server(0, server.PAGE_DIR)
    thread = threading.Thread(target=httpd.serve_forever, daemon=True)
    thread.start()
    base = 'http://127.0.0.1:%d' % httpd.server_address[1]
    signal.signal(signal.SIGTERM, _interrupt)

    def progress(i, n, rec):
        extra = ' (%s)' % rec['reason'] if rec.get('reason') and rec['status'] != 'ok' else ''
        print('[%d/%d] %s %s %s %s case %d: %s%s' % (i, n, rec['browser'], rec['field'],
                                                   rec['engine'], rec['speed'], rec['case'],
                                                   rec['status'], extra),
              file=sys.stderr, flush=True)

    try:
        summary = run_matrix(machine, plan, out_path, app_path=args.app, base_url=base,
                             perf_log=args.debug_log, progress=progress)
    finally:
        httpd.shutdown()
        httpd.server_close()
    print('Results: %s (%d records)' % (out_path, summary['cases']))
    print('Report: python3 -I %s %s' % (os.path.join(HERE, 'report.py'), out_path))
    if summary['close_failures']:
        print('Bench tabs not closed: %d (listed above); close them by hand.'
              % summary['close_failures'])
    print(final_message(summary))
    if summary['interrupted']:
        print('Interrupted.', file=sys.stderr)
        return 130
    if summary['stopped']:
        print('Stopped: %s' % summary['stopped'], file=sys.stderr)
        return 1
    if not summary['restored']:
        return 1
    return 0


if __name__ == '__main__':
    sys.exit(main())
