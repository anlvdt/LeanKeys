import os
import sys
import unittest

HERE = os.path.dirname(os.path.abspath(__file__))
WEBBENCH = os.path.dirname(HERE)
MIXBENCH = os.path.join(os.path.dirname(os.path.dirname(WEBBENCH)), 'mixbench')
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

    def test_word_latency_uses_last_input_before_next_key(self):
        self.assertEqual(word_latencies([0, 100, 200], [1], [101, 130, 205]), [30])
        self.assertEqual(word_latencies([0, 100], [1], []), [None])

    def test_percentile(self):
        self.assertEqual(percentile([10, 20, 30, 40], 50), 25)
        self.assertIsNone(percentile([], 95))


if __name__ == '__main__':
    unittest.main()
