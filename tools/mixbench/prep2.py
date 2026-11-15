# Per message: keys<TAB>target words (space-joined)<TAB>flags (1=Vietnamese word). Reuses Vikey's telex().
import sys, re, unicodedata, importlib.util
spec = importlib.util.spec_from_file_location("prep", sys.argv[1]); prep = importlib.util.module_from_spec(spec)
saved = sys.argv; sys.argv = [saved[1]]; spec.loader.exec_module(prep); sys.argv = saved
for path in sys.argv[2:]:
    for line in open(path, encoding='utf-8'):
        line = unicodedata.normalize('NFC', line.strip())
        if not line: continue
        keys, words, flags = [], [], []
        for tok in re.findall(r'[^\W\d_]+|[^\w]|\d|_', line):
            if tok[0].isalpha():
                if prep.VN_CHARS.search(tok):
                    k = prep.telex(tok)
                    if k is None or not k.isascii(): keys.append(' '); continue
                    keys.append(k); words.append(tok); flags.append('1')
                else:
                    keys.append(tok); words.append(tok); flags.append('0')
            else:
                keys.append(tok if tok in prep.SEPS else ' ')
        # target words as they appear between separators: rebuild by splitting the target the same way the output is split
        print(''.join(keys) + '\t' + ' '.join(words) + '\t' + ''.join(flags))
