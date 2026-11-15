# usage: score.py msgs.tsv outputs.txt [label] [--show N]  -> word error stats (letters-only tokens)
import sys, re, unicodedata
msgs = [l.rstrip('\n').split('\t') for l in open(sys.argv[1], encoding='utf-8')]
outs = [unicodedata.normalize('NFC', l.rstrip('\n')) for l in open(sys.argv[2], encoding='utf-8')]
show = int(sys.argv[sys.argv.index('--show') + 1]) if '--show' in sys.argv else 0
TONES = set('\u0300\u0301\u0303\u0309\u0323')
def same(a, b):
    """Equal, or equal apart from where the tone mark sits (hoà/hòa, khoẻ/khỏe: both spellings are correct)."""
    if a == b: return True
    if a is None or b is None: return False
    da, db = unicodedata.normalize('NFD', a), unicodedata.normalize('NFD', b)
    strip = lambda d: ''.join(ch for ch in d if ch not in TONES)
    return strip(da) == strip(db) and sorted(ch for ch in da if ch in TONES) == sorted(ch for ch in db if ch in TONES)
W = re.compile(r'[^\W\d_]+')
tot = bad = vn = en = bvn = ben = perfect = 0; ex = []
for (keys, target, flags), out in zip(msgs, outs):
    tw, ow = target.split(), W.findall(out)
    mb = 0
    for i, t in enumerate(tw):
        isvn = flags[i] == '1'; tot += 1; vn += isvn; en += not isvn
        o = ow[i] if i < len(ow) else None
        if not same(o, t):
            bad += 1; mb += 1
            if isvn: bvn += 1
            else: ben += 1
            if len(ex) < show: ex.append(f'{t} -> {o}  [{"VN" if isvn else "EN"}]')
    perfect += mb == 0
print(f'{sys.argv[3] if len(sys.argv)>3 and not sys.argv[3].startswith("--") else ""}: words {tot}  wrong {bad} ({100*bad/tot:.2f}%)  VN wrong {bvn}/{vn} ({100*bvn/max(vn,1):.2f}%)  EN wrong {ben}/{en} ({100*ben/max(en,1):.2f}%)  perfect msgs {perfect}/{len(msgs)} ({100*perfect/len(msgs):.1f}%)')
for e in ex: print('   ', e)
