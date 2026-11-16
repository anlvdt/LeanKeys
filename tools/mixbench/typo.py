# usage: typo.py msgs.tsv mode seed > typo.tsv
# Adds a typo the typist then fixes with Backspace to some words of prep2.py's output. Only the keys change; the
# target stays, so score.py counts the words that still come out wrong after the fix.
# Keys: '`' is Backspace; '|' marks the word's length on screen; '^' presses Backspace until the word is back to it.
# Vietnamese modes (30% of Vietnamese words):
#   dbl    the last tone key pressed twice, then Backspace (hocj -> hocjj`)
#   extra  a stray letter, then Backspace
#   mid    a wrong letter in the middle, noticed at the end: Backspace back to it, retype the rest
# English modes (50% of English words):
#   endbl  the last letter pressed twice, then Backspace (use -> usee`)
#   enextra, enmid  as extra and mid
import sys, re, random

VN_MODES = {'dbl': 0.3, 'extra': 0.3, 'mid': 0.3}
EN_MODES = {'endbl': 0.5, 'enextra': 0.5, 'enmid': 0.5}
TONE_KEYS = set('sfrxj')
LETTERS = 'qwertyuiopasdfghjklzxcvbnm'


def with_typo(word, mode):
    if mode == 'dbl':
        tones = [i for i, c in enumerate(word) if c in TONE_KEYS and i > 0]
        if tones:
            i = tones[-1]
            return word[:i + 1] + word[i] + '`' + word[i + 1:]
    elif mode == 'endbl':
        return word + word[-1] + '`'
    elif mode in ('extra', 'enextra'):
        i = random.randrange(1, len(word) + 1)
        return word[:i] + random.choice(LETTERS) + '`' + word[i:]
    elif mode in ('mid', 'enmid') and len(word) >= 3:
        i = random.randrange(1, len(word) - 1)
        wrong = random.choice(LETTERS)
        rest = word[i:]
        return word[:i] + '|' + wrong + rest[1:] + '^' + rest
    return word


def main():
    path, mode, seed = sys.argv[1], sys.argv[2], int(sys.argv[3])
    if mode not in VN_MODES and mode not in EN_MODES:
        sys.exit(f'unknown mode {mode}; one of {" ".join([*VN_MODES, *EN_MODES])}')
    random.seed(seed)
    vietnamese, rate = mode in VN_MODES, VN_MODES.get(mode) or EN_MODES[mode]
    for line in open(path, encoding='utf-8'):
        keys, target, flags = line.rstrip('\n').split('\t')
        wi, out = 0, []
        for tok in re.findall(r'[A-Za-z]+|[^A-Za-z]', keys):
            if tok[0].isalpha():
                isvn = wi < len(flags) and flags[wi] == '1'
                wi += 1
                if isvn == vietnamese and random.random() < rate:
                    tok = with_typo(tok, mode)
            out.append(tok)
        print(''.join(out) + '\t' + target + '\t' + flags)


main()
