# usage: score.py msgs.tsv outputs.txt [label] [--show N]  -> word error stats (letters-only tokens)
import sys, unicodedata, os
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
msgs = [l.rstrip('\n').split('\t') for l in open(sys.argv[1], encoding='utf-8')]
outs = [unicodedata.normalize('NFC', l.rstrip('\n')) for l in open(sys.argv[2], encoding='utf-8')]
show = int(sys.argv[sys.argv.index('--show') + 1]) if '--show' in sys.argv else 0
from wordscore import word_errors
tot = bad = vn = en = bvn = ben = perfect = 0; ex = []
def miss(i, t, o, isvn):
    if len(ex) < show: ex.append(f'{t} -> {o}  [{"VN" if isvn else "EN"}]')
for (keys, target, flags), out in zip(msgs, outs):
    n, wrong, wvn, wen = word_errors(target, flags, out, on_miss=miss)
    nvn = sum(flags[i] == '1' for i in range(n))
    tot += n; bad += wrong; bvn += wvn; ben += wen; vn += nvn; en += n - nvn
    perfect += wrong == 0
print(f'{sys.argv[3] if len(sys.argv)>3 and not sys.argv[3].startswith("--") else ""}: words {tot}  wrong {bad} ({100*bad/tot:.2f}%)  VN wrong {bvn}/{vn} ({100*bvn/max(vn,1):.2f}%)  EN wrong {ben}/{en} ({100*ben/max(en,1):.2f}%)  perfect msgs {perfect}/{len(msgs)} ({100*perfect/len(msgs):.1f}%)')
for e in ex: print('   ', e)
