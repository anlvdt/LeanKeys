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

def word_latencies(sent_ms, word_end_idx, input_ms):
    """For each word-end key index k, latency = last input time inside [t, t_next) minus t,
    where t = sent_ms[k] and t_next = sent_ms[k+1] (+inf for the last key). None if no input fell in the window."""
    out = []
    for k in word_end_idx:
        t = sent_ms[k]
        end = sent_ms[k + 1] if k + 1 < len(sent_ms) else float('inf')
        inside = [x for x in input_ms if t <= x < end]
        out.append(inside[-1] - t if inside else None)
    return out

def percentile(xs, p):
    """Linear-interpolated percentile p (0-100); None for an empty list."""
    if not xs: return None
    s = sorted(xs)
    rank = p / 100 * (len(s) - 1)
    lo = int(rank); hi = min(lo + 1, len(s) - 1)
    return s[lo] + (s[hi] - s[lo]) * (rank - lo)
