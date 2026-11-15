import sys, re, unicodedata, collections
msgs=[l.rstrip('\n').split('\t') for l in open(sys.argv[1],encoding='utf-8')]
A=[unicodedata.normalize('NFC',l.rstrip('\n')) for l in open(sys.argv[2],encoding='utf-8')]
Bv=[unicodedata.normalize('NFC',l.rstrip('\n')) for l in open(sys.argv[3],encoding='utf-8')]
TONES = set('\u0300\u0301\u0303\u0309\u0323')
def same(a, b):
    """Equal, or equal apart from where the tone mark sits (hoà/hòa, khoẻ/khỏe: both spellings are correct)."""
    if a == b: return True
    if a is None or b is None: return False
    da, db = unicodedata.normalize('NFD', a), unicodedata.normalize('NFD', b)
    strip = lambda d: ''.join(ch for ch in d if ch not in TONES)
    return strip(da) == strip(db) and sorted(ch for ch in da if ch in TONES) == sorted(ch for ch in db if ch in TONES)
W=re.compile(r'[^\W\d_]+'); both=only_vk=only_gn=0; ex=collections.Counter()
for (k,t,f),a,b in zip(msgs,A,Bv):
    tw,aw,bw=t.split(),W.findall(a),W.findall(b)
    for i,w in enumerate(tw):
        ga=same(aw[i] if i<len(aw) else None,w); vb=same(bw[i] if i<len(bw) else None,w)
        if not ga and not vb: both+=1
        elif not vb: only_vk+=1; ex[(w, bw[i] if i<len(bw) else None, 'VN' if f[i]=='1' else 'EN')]+=1
        elif not ga: only_gn+=1
print(f'wrong in both {both}, only Vikey wrong {only_vk}, only GoNhanh wrong {only_gn}')
print('top Vikey-only errors (want -> got):'); [print('  ',w,'->',g,v,'x',n) for (w,g,v),n in ex.most_common(15)]
