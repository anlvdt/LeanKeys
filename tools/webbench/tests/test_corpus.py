import collections
import os
import sys
import unittest

HERE = os.path.dirname(os.path.abspath(__file__))
WEBBENCH = os.path.dirname(HERE)
CORPUS = os.path.join(WEBBENCH, 'corpus.tsv')
sys.path.insert(0, WEBBENCH)

from make_corpus import RESEARCH  # noqa: E402

# typist supports printable ASCII 0x20-0x7E, backtick included (controller ruling).
SUPPORTED = {chr(c) for c in range(0x20, 0x7F)}


class CorpusShapeTests(unittest.TestCase):
    def setUp(self):
        with open(CORPUS, encoding='utf-8') as f:
            self.lines = [line.rstrip('\n') for line in f if line.rstrip('\n')]
        self.rows = [line.split('\t') for line in self.lines]

    def test_every_line_has_four_fields(self):
        bad = [line for line in self.rows if len(line) != 4]
        self.assertEqual(bad, [])

    def test_group_counts(self):
        counts = collections.Counter(row[3] for row in self.rows)
        self.assertEqual(counts['office'], 40)
        self.assertEqual(counts['chat'], 20)
        self.assertLessEqual(counts['dbl'], 10)
        self.assertLessEqual(counts['extra'], 10)
        self.assertEqual(counts['research'], 6)
        self.assertEqual(set(counts), {'office', 'chat', 'dbl', 'extra', 'research'})

    def test_keys_have_no_pipe_or_caret(self):
        bad = [row[0] for row in self.rows if '|' in row[0] or '^' in row[0]]
        self.assertEqual(bad, [])

    def test_keys_are_within_typist_supported_set(self):
        bad = [row[0] for row in self.rows if not set(row[0]) <= SUPPORTED]
        self.assertEqual(bad, [])

    def test_word_count_matches_flag_count(self):
        bad = [row for row in self.rows if len(row[1].split()) != len(row[2])]
        self.assertEqual(bad, [])

    def test_research_rows_are_the_probe_pairs(self):
        research = [(row[0], row[1]) for row in self.rows if row[3] == 'research']
        self.assertEqual(research, RESEARCH)

    def test_research_flags_are_all_one(self):
        bad = [row for row in self.rows if row[3] == 'research' and set(row[2]) != {'1'}]
        self.assertEqual(bad, [])


if __name__ == '__main__':
    unittest.main()
