# Scoring for webbench: character-level duplicates/losses, per-word latency, percentiles.
import difflib, sys, os, unicodedata
sys.path.insert(0, os.path.join(os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__)))), 'tools', 'mixbench'))
from wordscore import WORD

def _letters(s):
    return ' '.join(WORD.findall(unicodedata.normalize('NFC', s)))

def char_diff(target, out):
    """(extra, lost): characters typed beyond the target (duplicates) and target characters missing,
    over letters-only words joined by one space. Punctuation and spacing are ignored."""
    a, b = _letters(target), _letters(out)
    extra = lost = 0
    for op, i1, i2, j1, j2 in difflib.SequenceMatcher(None, a, b, autojunk=False).get_opcodes():
        if op in ('insert', 'replace'): extra += j2 - j1
        if op in ('delete', 'replace'): lost += i2 - i1
    return extra, lost

def word_latencies(sent_ms, word_spans, input_ms):
    """Per word, latency = last input in its window minus the word's last key time.
    word_spans holds (end, next) key indexes: end is the word's last key; next is the first
    non-space key after it (the next word's first key, or None for the last word).
    The window is [sent[end], sent[next]), so an input that LeanKeys applies on the space
    after the word (a correction or auto-restore) counts, and the next word's typing does not.
    None when no input fell in the window."""
    out = []
    for end_idx, next_idx in word_spans:
        t = sent_ms[end_idx]
        stop = sent_ms[next_idx] if next_idx is not None else float('inf')
        inside = [x for x in input_ms if t <= x < stop]
        out.append(inside[-1] - t if inside else None)
    return out

def percentile(xs, p):
    """Linear-interpolated percentile p (0-100); None for an empty list."""
    if not xs: return None
    s = sorted(xs)
    rank = p / 100 * (len(s) - 1)
    lo = int(rank); hi = min(lo + 1, len(s) - 1)
    return s[lo] + (s[hi] - s[lo]) * (rank - lo)
