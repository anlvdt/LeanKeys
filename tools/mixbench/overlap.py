import sys, re, unicodedata, collections
msgs=[l.rstrip('\n').split('\t') for l in open(sys.argv[1],encoding='utf-8')]
A=[unicodedata.normalize('NFC',l.rstrip('\n')) for l in open(sys.argv[2],encoding='utf-8')]
Bv=[unicodedata.normalize('NFC',l.rstrip('\n')) for l in open(sys.argv[3],encoding='utf-8')]
W=re.compile(r'[^\W\d_]+'); both=only_vk=only_gn=0; ex=collections.Counter()
for (k,t,f),a,b in zip(msgs,A,Bv):
    tw,aw,bw=t.split(),W.findall(a),W.findall(b)
    for i,w in enumerate(tw):
        ga=(aw[i] if i<len(aw) else None)==w; vb=(bw[i] if i<len(bw) else None)==w
        if not ga and not vb: both+=1
        elif not vb: only_vk+=1; ex[(w, bw[i] if i<len(bw) else None, 'VN' if f[i]=='1' else 'EN')]+=1
        elif not ga: only_gn+=1
print(f'wrong in both {both}, only Vikey wrong {only_vk}, only GoNhanh wrong {only_gn}')
print('top Vikey-only errors (want -> got):'); [print('  ',w,'->',g,v,'x',n) for (w,g,v),n in ex.most_common(15)]
