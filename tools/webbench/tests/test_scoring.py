import os
import sys
import unittest

HERE = os.path.dirname(os.path.abspath(__file__))
WEBBENCH = os.path.dirname(HERE)
MIXBENCH = os.path.join(os.path.dirname(WEBBENCH), 'mixbench')
sys.path.insert(0, WEBBENCH)
sys.path.insert(0, MIXBENCH)

from scoring import char_diff, word_latencies, percentile  # noqa: E402
from wordscore import same, word_errors  # noqa: E402


class ScoringTests(unittest.TestCase):
    def test_same_accepts_both_tone_placements(self):
        self.assertTrue(same("hoà", "hòa"))
        self.assertFalse(same("hoà", "hoa"))

    def test_word_errors_counts_vn_and_en(self):
        self.assertEqual(word_errors("tôi test", "10", "tôi tét"), (2, 1, 0, 1))

    def test_char_diff_finds_duplicates_and_losses(self):
        self.assertEqual(char_diff("bạn tôi", "bạnn tôi"), (1, 0))
        self.assertEqual(char_diff("bạn tôi", "bạ tôi"), (0, 1))
        self.assertEqual(char_diff("bạn tôi", "bạn, tôi!"), (0, 0))  # punctuation ignored

    def test_word_latency_window_ends_at_next_word_first_key(self):
        # Word ends at key 1; the next word starts at key 2 (sent 200). Input at 205 is the next word.
        self.assertEqual(word_latencies([0, 100, 200], [(1, 2)], [101, 130, 205]), [30])
        self.assertEqual(word_latencies([0, 100], [(1, None)], []), [None])

    def test_word_latency_counts_replacement_applied_on_the_space(self):
        # Key 0 ends the word, key 1 is the space, key 2 starts the next word (sent 200).
        # The correction lands at 150, after the space's send time (100): it must count.
        self.assertEqual(word_latencies([0, 100, 200], [(0, 2)], [50, 150, 205]), [150])

    def test_word_latency_last_word_has_no_upper_bound(self):
        self.assertEqual(word_latencies([0, 100], [(1, None)], [50, 150, 900]), [800])

    def test_percentile(self):
        self.assertEqual(percentile([10, 20, 30, 40], 50), 25)
        self.assertIsNone(percentile([], 95))


if __name__ == '__main__':
    unittest.main()
