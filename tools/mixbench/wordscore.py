# Word-level scoring shared by mixbench (score.py) and webbench (tools/webbench/scoring.py).
import re, unicodedata
TONES = set('\u0300\u0301\u0303\u0309\u0323')
def same(a, b):
    """Equal, or equal apart from where the tone mark sits (hoà/hòa, khoẻ/khỏe: both spellings are correct)."""
    if a == b: return True
    if a is None or b is None: return False
    da, db = unicodedata.normalize('NFD', a), unicodedata.normalize('NFD', b)
    strip = lambda d: ''.join(ch for ch in d if ch not in TONES)
    return strip(da) == strip(db) and sorted(ch for ch in da if ch in TONES) == sorted(ch for ch in db if ch in TONES)
WORD = re.compile(r'[^\W\d_]+')
def word_errors(target, flags, out, on_miss=None):
    """target: space-separated words; flags: one char per word, '1' = Vietnamese; out: typed line.
    Returns (words, wrong, wrong_vn, wrong_en), comparing the i-th typed letter-run with the i-th target word.
    on_miss(i, target_word, typed_word_or_None, is_vn), if given, is called for each wrong word."""
    tw, ow = target.split(), WORD.findall(unicodedata.normalize('NFC', out))
    tot = bad = bvn = ben = 0
    for i, t in enumerate(tw):
        isvn = flags[i] == '1'; tot += 1
        o = ow[i] if i < len(ow) else None
        if not same(o, t):
            bad += 1
            if isvn: bvn += 1
            else: ben += 1
            if on_miss: on_miss(i, t, o, isvn)
    return tot, bad, bvn, ben
