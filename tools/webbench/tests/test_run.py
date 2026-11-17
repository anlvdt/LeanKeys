import contextlib
import io
import json
import os
import signal
import subprocess
import sys
import tempfile
import unittest
from unittest import mock

HERE = os.path.dirname(os.path.abspath(__file__))
WEBBENCH = os.path.dirname(HERE)
sys.path.insert(0, WEBBENCH)

import run  # noqa: E402
import report  # noqa: E402

APP = '/Applications/LeanKeys.app'
KEY = 'LeanKeys.engine'
BASE = 'http://127.0.0.1:9999'


class FakeMachine:
    """Records every side effect; the clock advances only through sleep()."""

    def __init__(self, engine='vikey', gone=True):
        self.store = {KEY: engine} if engine is not None else {}
        self.calls = []
        self.clock = 0.0
        self.gone = gone
        self.typist_calls = 0
        self.interrupt_on = None   # raise KeyboardInterrupt on this typist call (1-based)
        self.typist_codes = []     # exit codes handed out in order; default 0
        self.missing = False       # http_get always 404
        self.log_text = ''
        self.log_on_typist = ''    # appended to the log on every typist call
        self.log_enabled = False
        self.writes = 0
        self.kb_on_write = None    # raise KeyboardInterrupt on this defaults_write (1-based)
        self.kb_on_enable = False  # raise KeyboardInterrupt inside enable_log
        self.kill_on_write = None  # send SIGINT to ourselves during this defaults_write
        self.kill_on_enable = False  # create the log, send SIGINT, then return (owns it)
        self.close_results = []    # close_bench_tab answers in order; default True
        self.open_fail = 0         # the next N open_url calls raise
        self.check_code = 0        # typist --check exit code
        self.installed = True      # browser_installed answer
        self.watch_codes = []      # typist --watch exit codes in order; default 0

    def defaults_read(self, key):
        self.calls.append(('defaults_read', key))
        return self.store.get(key)

    def defaults_write(self, key, value):
        self.calls.append(('defaults_write', key, value))
        self.writes += 1
        if self.kill_on_write == self.writes:
            os.kill(os.getpid(), signal.SIGINT)  # a real Ctrl-C landing mid-write
        if self.kb_on_write == self.writes:
            raise KeyboardInterrupt
        self.store[key] = value

    def defaults_delete(self, key):
        self.calls.append(('defaults_delete', key))
        self.store.pop(key, None)

    def quit_leankeys(self):
        self.calls.append(('quit_leankeys',))

    def wait_gone(self, timeout):
        self.calls.append(('wait_gone', timeout))
        return self.gone

    def launch(self, app_path):
        self.calls.append(('launch', app_path))

    def open_url(self, bundle, url):
        self.calls.append(('open_url', bundle, url))
        if self.open_fail:
            self.open_fail -= 1
            raise subprocess.CalledProcessError(1, 'open')

    def close_bench_tab(self, bundle, token):
        self.calls.append(('close_bench_tab', bundle, token))
        return self.close_results.pop(0) if self.close_results else True

    def browser_installed(self, bundle):
        self.calls.append(('browser_installed', bundle))
        return self.installed

    def typist_check(self):
        self.calls.append(('typist_check',))
        return self.check_code

    def wait_running(self, timeout):
        self.calls.append(('wait_running', timeout))
        return True

    def watch(self, seconds):
        self.calls.append(('watch', seconds))
        self.clock += seconds
        return self.watch_codes.pop(0) if self.watch_codes else 0

    def run_typist(self, args):
        self.typist_calls += 1
        self.calls.append(('run_typist', list(args)))
        self.log_text += self.log_on_typist
        if self.interrupt_on == self.typist_calls:
            raise KeyboardInterrupt
        code = self.typist_codes.pop(0) if self.typist_codes else 0
        if code != 0:
            return code, ''
        keys = args[args.index('--keys') + 1]
        return 0, json.dumps({'sent': [1000 + 100 * i for i in range(len(keys))]})

    def http_get(self, url):
        self.calls.append(('http_get', url))
        if self.missing:
            return 404, 'not found'
        tail = url.split('/result/', 1)[1]
        token, case = tail.split('/')
        body = {'token': token, 'case': int(case), 'field': 'input',
                'text': 'ok', 'inputs': [1000.0, 1100.0]}
        return 200, json.dumps(body)

    def now(self):
        return self.clock

    def sleep(self, seconds):
        self.clock += seconds

    def enable_log(self):
        self.calls.append(('enable_log',))
        if self.kb_on_enable:
            raise KeyboardInterrupt
        if self.log_enabled:
            return False
        self.log_enabled = True  # the file now exists
        if self.kill_on_enable:
            os.kill(os.getpid(), signal.SIGINT)
        return True

    def disable_log(self):
        self.calls.append(('disable_log',))
        self.log_enabled = False

    def read_log(self):
        return self.log_text


def make_case(n, engine='vikey', field='input', speed='human', browser='chrome',
              keys='ab cd', target='ab cd', flags='11', group='office'):
    return {
        'browser': browser, 'bundle': run.BUNDLES[browser], 'field': field,
        'engine': engine, 'speed': speed, 'group': group, 'case': n,
        'token': 'tok%d' % n, 'keys': keys, 'target': target, 'flags': flags,
        'word_spans': run.word_spans(keys),
    }


def read_records(path):
    with open(path, encoding='utf-8') as f:
        return [json.loads(line) for line in f if line.strip()]


class FinalSpaceTests(unittest.TestCase):
    def test_every_case_is_typed_with_one_final_space(self):
        rows = [{'case': 1, 'keys': 'ab cd', 'target': 'ab cd', 'flags': '11', 'group': 'office'}]
        plan = run.build_plan(rows, ['chrome'], ['input'], ['vikey'], ['human'], ['office'],
                              None, 'run1')
        self.assertEqual(plan[0]['keys'], 'ab cd ')
        self.assertEqual(plan[0]['word_spans'], [(1, 3), (4, None)])
        args = run.typist_args(plan[0])
        self.assertEqual(args[args.index('--keys') + 1], 'ab cd ')


class WatchAndCrashTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.mkdtemp()
        self.out = os.path.join(self.tmp, 'results.jsonl')
        quiet = contextlib.redirect_stderr(io.StringIO())
        quiet.__enter__()
        self.addCleanup(quiet.__exit__, None, None, None)

    def test_negative_exit_code_from_a_signal_stops_the_run(self):
        m = FakeMachine()
        m.typist_codes = [-11]  # typist killed by SIGSEGV
        summary = run.run_matrix(m, [make_case(1), make_case(2)], self.out, app_path=APP,
                                 base_url=BASE)
        self.assertEqual(m.typist_calls, 1)
        self.assertIn('typist exit -11', summary['stopped'])
        self.assertTrue(summary['restored'])
        self.assertEqual(m.calls[-1], ('launch', APP))
        self.assertEqual(read_records(self.out)[0]['status'], 'typist-error')

    def test_unknown_positive_exit_code_stops_the_run(self):
        m = FakeMachine()
        m.typist_codes = [134]  # Swift trap
        summary = run.run_matrix(m, [make_case(1), make_case(2)], self.out, app_path=APP,
                                 base_url=BASE)
        self.assertEqual(m.typist_calls, 1)
        self.assertIsNotNone(summary['stopped'])

    def test_watch_exit_4_before_open_stops_and_opens_nothing_for_that_case(self):
        m = FakeMachine()
        m.watch_codes = [4]
        summary = run.run_matrix(m, [make_case(1), make_case(2)], self.out, app_path=APP,
                                 base_url=BASE)
        self.assertIn('real keyboard or mouse input', summary['stopped'])
        self.assertEqual([c[2] for c in m.calls if c[0] == 'open_url'], [])
        self.assertEqual(m.typist_calls, 0)
        self.assertTrue(summary['restored'])

    def test_watch_exit_4_after_typing_marks_the_case_aborted_and_stops(self):
        m = FakeMachine()
        m.watch_codes = [0, 4]  # quiet before the first open, then real input after typing
        summary = run.run_matrix(m, [make_case(1), make_case(2)], self.out, app_path=APP,
                                 base_url=BASE)
        self.assertIn('real keyboard or mouse input', summary['stopped'])
        recs = read_records(self.out)
        self.assertEqual([r['status'] for r in recs], ['aborted'])
        self.assertIsNone(recs[0]['text'])
        self.assertEqual(m.typist_calls, 1)

    def test_watch_runs_before_each_open_and_after_each_case(self):
        m = FakeMachine()
        run.run_matrix(m, [make_case(1)], self.out, app_path=APP, base_url=BASE)
        watches = [c[1] for c in m.calls if c[0] == 'watch']
        self.assertEqual(watches, [run.PRE_OPEN_WATCH_S, run.QUIET_S])
        names = [c[0] for c in m.calls]
        self.assertLess(names.index('watch'), names.index('open_url'))
        self.assertLess(names.index('open_url'), names.index('run_typist'))


class PlanHelpers(unittest.TestCase):
    def test_word_spans_end_before_space_and_point_at_next_word(self):
        self.assertEqual(run.word_spans('ab cd'), [(1, 3), (4, None)])

    def test_word_spans_count_backspace_as_a_key(self):
        # "ab`" then space: the word ends at the backspace (index 2).
        self.assertEqual(run.word_spans('ab` cd'), [(2, 4), (5, None)])

    def test_word_spans_skip_repeated_and_trailing_spaces(self):
        self.assertEqual(run.word_spans('a  b  '), [(0, 3), (3, None)])

    def test_digit_token_is_not_a_word_but_ends_the_previous_window(self):
        # "lusc 2 giowf": the 2 gets no entry; "lusc" window ends at the 2's key (index 5).
        self.assertEqual(run.word_spans('lusc 2 giowf'), [(3, 5), (11, None)])

    def test_field_names_match_page_factories(self):
        with open(os.path.join(WEBBENCH, 'page', 'fields.js'), encoding='utf-8') as f:
            src = f.read()
        for name in run.FIELD_NAMES:
            self.assertIn('  %s: ' % name, src)


class RunMatrixTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.mkdtemp()
        self.out = os.path.join(self.tmp, 'results.jsonl')
        # The run's own warnings (WEBBENCH: ...) are asserted where they matter; keep stderr clean.
        quiet = contextlib.redirect_stderr(io.StringIO())
        quiet.__enter__()
        self.addCleanup(quiet.__exit__, None, None, None)

    def test_restore_runs_on_interrupt(self):
        m = FakeMachine(engine='vikey')
        m.interrupt_on = 2
        plan = [make_case(1), make_case(2), make_case(3)]
        summary = run.run_matrix(m, plan, self.out, app_path=APP, base_url=BASE)
        self.assertTrue(summary['interrupted'])
        # Restore order: engine write, then quit and confirm, then launch (every launch
        # must follow a confirmed quit), so the last three calls are fixed in that order.
        self.assertEqual(m.calls[-4], ('defaults_write', KEY, 'vikey'))
        self.assertEqual(m.calls[-3], ('quit_leankeys',))
        self.assertEqual(m.calls[-2][0], 'wait_gone')
        self.assertEqual(m.calls[-1], ('launch', APP))
        self.assertEqual(m.store[KEY], 'vikey')

    def test_restore_completes_when_interrupted_inside_a_restore_step(self):
        m = FakeMachine(engine='vikey')
        m.kb_on_write = 2  # the restore write of the original engine
        summary = run.run_matrix(m, [make_case(1)], self.out, app_path=APP, base_url=BASE)
        self.assertTrue(summary['interrupted'])
        self.assertEqual(m.calls.count(('defaults_write', KEY, 'vikey')), 2)
        self.assertEqual(m.calls[-2][0], 'wait_gone')
        self.assertEqual(m.calls[-1], ('launch', APP))

    def test_restore_finishes_when_ctrl_c_lands_during_the_engine_write(self):
        # Original engine gonhanh, plan engine vikey: restore must write gonhanh back.
        m = FakeMachine(engine='gonhanh')
        m.kill_on_write = 2  # the restore write
        summary = run.run_matrix(m, [make_case(1, engine='vikey')], self.out, app_path=APP,
                                 base_url=BASE, perf_log=True)
        self.assertEqual(m.store[KEY], 'gonhanh')
        self.assertIn(('disable_log',), m.calls)
        self.assertFalse(m.log_enabled)
        self.assertEqual(m.calls[-1], ('launch', APP))
        self.assertTrue(summary['restored'])
        self.assertTrue(summary['interrupted'])

    def test_start_by_hand_line_when_not_relaunched(self):
        m = FakeMachine(engine='vikey', gone=False)
        err = io.StringIO()
        with contextlib.redirect_stderr(err):
            summary = run.run_matrix(m, [make_case(1)], self.out, app_path=APP, base_url=BASE)
        self.assertIn('did not quit', summary['stopped'])
        self.assertIn('LeanKeys did not quit; quit it, then open /Applications/LeanKeys.app',
                      err.getvalue())
        self.assertNotIn('LeanKeys relaunched.', run.final_message({'restored': False}))
        self.assertEqual(run.final_message({'restored': True}), 'LeanKeys relaunched.')

    def test_ctrl_c_just_after_enable_log_still_disables_our_log(self):
        m = FakeMachine(engine='vikey')
        m.kill_on_enable = True
        summary = run.run_matrix(m, [make_case(1)], self.out, app_path=APP, base_url=BASE,
                                 perf_log=True)
        self.assertIn(('disable_log',), m.calls)
        self.assertFalse(m.log_enabled)
        self.assertTrue(summary['interrupted'])
        self.assertEqual(m.calls[-1], ('launch', APP))

    def test_interrupt_during_enable_log_ends_with_restore(self):
        m = FakeMachine(engine='vikey')
        m.kb_on_enable = True
        summary = run.run_matrix(m, [make_case(1)], self.out, app_path=APP, base_url=BASE,
                                 perf_log=True)
        self.assertTrue(summary['interrupted'])
        self.assertFalse([c for c in m.calls if c[0] == 'run_typist'])
        self.assertEqual(m.calls[-1], ('launch', APP))

    def test_bench_tab_closed_once_per_case(self):
        m = FakeMachine()
        run.run_matrix(m, [make_case(1), make_case(2)], self.out, app_path=APP, base_url=BASE)
        closes = [c for c in m.calls if c[0] == 'close_bench_tab']
        self.assertEqual(closes, [('close_bench_tab', 'com.google.Chrome', 'tok1'),
                                  ('close_bench_tab', 'com.google.Chrome', 'tok2')])

    def test_restore_deletes_key_when_it_was_unset(self):
        m = FakeMachine(engine=None)
        run.run_matrix(m, [make_case(1)], self.out, app_path=APP, base_url=BASE)
        self.assertIn(('defaults_delete', KEY), m.calls)
        self.assertNotIn(KEY, m.store)
        self.assertEqual(m.calls[-1], ('launch', APP))

    def test_launch_quits_running_copy_first(self):
        m = FakeMachine(engine='vikey')
        plan = [make_case(1, engine='vikey'), make_case(2, engine='gonhanh')]
        run.run_matrix(m, plan, self.out, app_path=APP, base_url=BASE)
        launches = [i for i, c in enumerate(m.calls) if c[0] == 'launch']
        self.assertTrue(launches)
        for i in launches:
            self.assertEqual(m.calls[i - 2][0], 'quit_leankeys')
            self.assertEqual(m.calls[i - 1][0], 'wait_gone')

    def test_run_stops_and_launches_nothing_when_copy_does_not_quit(self):
        m = FakeMachine(engine='vikey', gone=False)
        with contextlib.redirect_stderr(io.StringIO()):  # the restore prints its own line
            summary = run.run_matrix(m, [make_case(1)], self.out, app_path=APP, base_url=BASE)
        self.assertIsNotNone(summary['stopped'])
        self.assertFalse([c for c in m.calls if c[0] == 'launch'])

    def test_aborted_case_is_not_scored(self):
        m = FakeMachine()
        m.typist_codes = [4]
        summary = run.run_matrix(m, [make_case(1), make_case(2)], self.out, app_path=APP,
                                 base_url=BASE)
        self.assertIn('real keyboard or mouse input', summary['stopped'])
        recs = read_records(self.out)
        self.assertEqual([r['status'] for r in recs], ['aborted'])
        self.assertIsNone(recs[0]['sent'])
        rows = report.summarize(recs)
        self.assertEqual(sum(r['words'] for r in rows), 0)
        self.assertEqual(sum(r['cases']['aborted'] for r in rows), 1)

    def test_exit_3_and_4_stop_the_run_and_restore(self):
        for code in (3, 4):
            m = FakeMachine()
            m.typist_codes = [0, code]
            plan = [make_case(n) for n in (1, 2, 3)]
            summary = run.run_matrix(m, plan, self.out, app_path=APP, base_url=BASE)
            self.assertEqual(m.typist_calls, 2, 'no case after the stop')
            self.assertIn('case 2', summary['stopped'])
            self.assertTrue(summary['restored'])
            self.assertEqual(m.calls[-1], ('launch', APP))
            recs = read_records(self.out)
            self.assertEqual([r['status'] for r in recs], ['ok', 'aborted'])

    def test_exit_1_and_2_stop_the_run_as_typist_error(self):
        for code in (1, 2):
            m = FakeMachine()
            m.typist_codes = [code]
            summary = run.run_matrix(m, [make_case(1), make_case(2)], self.out,
                                     app_path=APP, base_url=BASE)
            self.assertEqual(m.typist_calls, 1)
            self.assertIsNotNone(summary['stopped'])
            self.assertEqual(read_records(self.out)[0]['status'], 'typist-error')
            self.assertEqual(m.calls[-1], ('launch', APP))

    def test_exit_5_and_6_are_per_case_and_the_run_goes_on(self):
        m = FakeMachine()
        m.typist_codes = [5, 6]
        summary = run.run_matrix(m, [make_case(1), make_case(2), make_case(3)], self.out,
                                 app_path=APP, base_url=BASE)
        self.assertIsNone(summary['stopped'])
        self.assertEqual(m.typist_calls, 3)
        recs = read_records(self.out)
        self.assertEqual([r['status'] for r in recs], ['typist-error', 'aborted', 'ok'])
        self.assertEqual(recs[1]['reason'], 'typist exit 6')

    def test_five_unmeasured_cases_in_a_row_stop_the_run(self):
        m = FakeMachine()
        m.typist_codes = [6] * 9
        summary = run.run_matrix(m, [make_case(n) for n in range(1, 10)], self.out,
                                 app_path=APP, base_url=BASE)
        self.assertEqual(m.typist_calls, run.STATUS_STREAK_LIMIT)
        self.assertIn('not measured', summary['stopped'])
        self.assertTrue(summary['restored'])

    def test_three_failed_tab_closes_in_a_row_stop_the_run(self):
        m = FakeMachine()
        m.close_results = [False, False, False]
        summary = run.run_matrix(m, [make_case(n) for n in range(1, 7)], self.out,
                                 app_path=APP, base_url=BASE)
        self.assertEqual(m.typist_calls, 3)
        self.assertEqual(summary['close_failures'], 3)
        self.assertIn('could not be closed', summary['stopped'])

    def test_a_good_close_resets_the_failure_count(self):
        m = FakeMachine()
        m.close_results = [False, False, True, False, False, True]
        summary = run.run_matrix(m, [make_case(n) for n in range(1, 7)], self.out,
                                 app_path=APP, base_url=BASE)
        self.assertIsNone(summary['stopped'])
        self.assertEqual(summary['close_failures'], 4)

    def test_browser_that_fails_to_open_is_recorded_and_the_run_goes_on(self):
        m = FakeMachine()
        m.open_fail = 1
        summary = run.run_matrix(m, [make_case(1), make_case(2)], self.out,
                                 app_path=APP, base_url=BASE)
        self.assertIsNone(summary['stopped'])
        recs = read_records(self.out)
        self.assertEqual([r['status'] for r in recs], ['aborted', 'ok'])
        self.assertIn('could not open', recs[0]['reason'])

    def test_launch_waits_until_leankeys_runs(self):
        m = FakeMachine(engine='vikey')
        run.run_matrix(m, [make_case(1, engine='gonhanh')], self.out, app_path=APP,
                       base_url=BASE)
        i = m.calls.index(('launch', APP))
        self.assertEqual(m.calls[i + 1][0], 'wait_running')

    def test_results_file_is_private(self):
        m = FakeMachine()
        run.run_matrix(m, [make_case(1)], self.out, app_path=APP, base_url=BASE)
        self.assertEqual(os.stat(self.out).st_mode & 0o777, 0o600)

    def test_typist_gets_the_ready_timeout(self):
        args = run.typist_args(make_case(1))
        self.assertEqual(args[args.index('--ready-timeout') + 1], str(run.READY_TIMEOUT_S))

    def test_missing_result_times_out(self):
        m = FakeMachine()
        m.missing = True
        run.run_matrix(m, [make_case(1), make_case(2)], self.out, app_path=APP, base_url=BASE)
        recs = read_records(self.out)
        self.assertEqual([r['status'] for r in recs], ['no-result', 'no-result'])
        self.assertEqual(m.typist_calls, 2)
        self.assertGreaterEqual(m.clock, 5.0)

    def test_engine_switch_only_on_change(self):
        m = FakeMachine(engine='vikey')
        plan = [make_case(n, engine='vikey') for n in (1, 2, 3)] + \
               [make_case(n, engine='gonhanh') for n in (4, 5, 6)]
        run.run_matrix(m, plan, self.out, app_path=APP, base_url=BASE)
        writes = [c for c in m.calls if c[0] == 'defaults_write' and c[1] == KEY]
        self.assertEqual([w[2] for w in writes], ['vikey', 'gonhanh', 'vikey'])

    def test_off_engine_quits_and_never_launches(self):
        m = FakeMachine(engine='vikey')
        run.run_matrix(m, [make_case(1, engine='off')], self.out, app_path=APP, base_url=BASE)
        launches = [c for c in m.calls if c[0] == 'launch']
        self.assertEqual(launches, [('launch', APP)])  # only the final relaunch

    def test_debug_log_enabled_only_when_asked_and_disabled_after(self):
        m = FakeMachine()
        run.run_matrix(m, [make_case(1)], self.out, app_path=APP, base_url=BASE)
        self.assertNotIn(('enable_log',), m.calls)
        m2 = FakeMachine()
        m2.log_on_typist = 'I: perf: key ms=0.123\n'  # LeanKeys writes while typing
        run.run_matrix(m2, [make_case(1)], self.out, app_path=APP, base_url=BASE, perf_log=True)
        self.assertIn(('enable_log',), m2.calls)
        self.assertIn(('disable_log',), m2.calls)
        perf = [r for r in read_records(self.out) if r.get('kind') == 'perf']
        self.assertEqual(perf[0]['engine'], 'vikey')
        self.assertIn('perf: key ms=0.123', perf[0]['lines'][0])

    def test_pre_existing_debug_log_is_left_alone(self):
        m = FakeMachine()
        m.log_enabled = True  # user already had it on
        run.run_matrix(m, [make_case(1)], self.out, app_path=APP, base_url=BASE, perf_log=True)
        self.assertNotIn(('disable_log',), m.calls)


class CloseBenchTabTests(unittest.TestCase):
    def setUp(self):
        self.scripts = []
        self.answer = 'yes'
        self._orig = run._osa

        def fake_osa(script):
            self.scripts.append(script)
            return self.answer
        run._osa = fake_osa

    def tearDown(self):
        run._osa = self._orig

    def test_one_script_per_browser_checks_then_closes_by_reference(self):
        for bundle in (run.BUNDLES['chrome'], run.BUNDLES['safari']):
            self.scripts.clear()
            self.assertTrue(run.Machine().close_bench_tab(bundle, 'tok9'))
            self.assertEqual(len(self.scripts), 1)
            script = self.scripts[0]
            self.assertIn('webbench-tok9-', script)
            self.assertIn(bundle, script)
            self.assertIn('frontmost', script)
            self.assertIn('close t', script)

    def test_tab_title_property_per_browser(self):
        # Chrome tabs have `title`; Safari tabs have `name` (no `title`).
        run.Machine().close_bench_tab(run.BUNDLES['chrome'], 'tok9')
        self.assertIn('(title of t)', self.scripts[-1])
        self.assertNotIn('name of t', self.scripts[-1])
        run.Machine().close_bench_tab(run.BUNDLES['safari'], 'tok9')
        self.assertIn('(name of t)', self.scripts[-1])
        self.assertNotIn('title of t', self.scripts[-1])

    def test_firefox_uses_one_system_events_block_with_cmd_w(self):
        self.assertTrue(run.Machine().close_bench_tab(run.BUNDLES['firefox'], 'tok9'))
        self.assertEqual(len(self.scripts), 1)
        self.assertIn('webbench-tok9-', self.scripts[0])
        self.assertIn('keystroke "w" using command down', self.scripts[0])

    def test_false_when_script_fails_or_check_refuses(self):
        self.answer = ''  # osascript failed
        self.assertFalse(run.Machine().close_bench_tab(run.BUNDLES['chrome'], 'tok9'))
        self.answer = 'no'  # check refused
        self.assertFalse(run.Machine().close_bench_tab(run.BUNDLES['chrome'], 'tok9'))

    def test_unknown_bundle_touches_nothing(self):
        self.assertFalse(run.Machine().close_bench_tab('com.example.other', 'tok9'))
        self.assertEqual(self.scripts, [])


class PreflightAndExitTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.mkdtemp()
        self.patch = mock.patch.object(run, 'TYPIST', __file__)  # any existing file
        self.patch.start()

    def tearDown(self):
        self.patch.stop()

    def _main(self, machine, extra=()):
        args = ['--yes', '--browsers', 'chrome', '--fields', 'input', '--engines', 'vikey',
                '--speeds', 'human', '--limit', '1', '--app', self.tmp,
                '--out', os.path.join(self.tmp, 'r.jsonl')] + list(extra)
        with contextlib.redirect_stdout(io.StringIO()), contextlib.redirect_stderr(io.StringIO()):
            return run.main(args, machine=machine)

    def test_failed_typist_check_refuses_before_anything_runs(self):
        m = FakeMachine()
        m.check_code = 2
        self.assertEqual(self._main(m), 2)
        self.assertIn(('typist_check',), m.calls)
        self.assertFalse([c for c in m.calls if c[0] in ('run_typist', 'launch', 'open_url')])

    def test_missing_browser_refuses_before_anything_runs(self):
        m = FakeMachine()
        m.installed = False
        self.assertEqual(self._main(m), 2)
        self.assertFalse([c for c in m.calls if c[0] in ('run_typist', 'launch', 'open_url')])

    def test_run_that_could_not_relaunch_exits_non_zero(self):
        m = FakeMachine(gone=False)
        self.assertEqual(self._main(m), 1)

    def test_clean_run_exits_zero(self):
        m = FakeMachine()
        self.assertEqual(self._main(m), 0)

    def test_stopped_run_exits_non_zero_and_names_the_reason(self):
        m = FakeMachine()
        m.typist_codes = [4]
        err = io.StringIO()
        with contextlib.redirect_stdout(io.StringIO()), contextlib.redirect_stderr(err):
            code = run.main(['--yes', '--browsers', 'chrome', '--fields', 'input',
                             '--engines', 'vikey', '--speeds', 'human', '--limit', '1',
                             '--app', self.tmp, '--out', os.path.join(self.tmp, 'r.jsonl')],
                            machine=m)
        self.assertEqual(code, 1)
        self.assertIn('real keyboard or mouse input', err.getvalue())


class EstimateAndDryRunTests(unittest.TestCase):
    def test_dry_run_touches_nothing(self):
        buf = io.StringIO()
        with mock.patch('subprocess.run', side_effect=AssertionError('side effect')), \
             mock.patch('subprocess.Popen', side_effect=AssertionError('side effect')), \
             contextlib.redirect_stdout(buf):
            code = run.main(['--dry-run', '--limit', '2', '--browsers', 'chrome',
                             '--fields', 'input', '--engines', 'vikey,off', '--speeds', 'human'])
        self.assertIn('Dry run', buf.getvalue())
        self.assertEqual(code, 0)

    def test_estimate_counts_schedule_and_overhead(self):
        plan = [make_case(1, speed='fast', keys='a' * 25)]
        # 25 keys at 25 keys/s is 1 s, plus the per-case overhead.
        self.assertAlmostEqual(run.estimate_seconds(plan), 1.0 + run.OVERHEAD_S, places=6)

    def test_overhead_covers_ready_wait_quiet_wait_and_tab_work(self):
        self.assertGreaterEqual(run.OVERHEAD_S, run.READY_EXPECT_S + run.QUIET_S + 1.0)
        self.assertGreater(run.OVERHEAD_S, 3.5)  # the old constant undercounted


if __name__ == '__main__':
    unittest.main()
