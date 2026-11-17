"""Build corpus.tsv for webbench: keys<TAB>target<TAB>flags<TAB>group.

Run with no arguments; writes corpus.tsv next to this file. Deterministic:
every sample uses random.Random(17).
"""
import os
import random

HERE = os.path.dirname(os.path.abspath(__file__))
MIXBENCH = os.path.join(os.path.dirname(HERE), 'mixbench')
OUT = os.path.join(HERE, 'corpus.tsv')
SEED = 17

RESEARCH = [
    ('nhesee', 'nhéee'),
    ('asaaa', 'áaaa'),
    ('ooiii', 'ôiii'),
    ('owiii', 'ơiii'),
    ('Ddawsk Lawsk', 'Đắk Lắk'),
    ('Kroong Pawsc', 'Krông Pắc'),
]


def read_rows(name):
    path = os.path.join(MIXBENCH, name)
    rows = []
    with open(path, encoding='utf-8') as f:
        for line in f:
            line = line.rstrip('\n')
            if line:
                keys, target, flags = line.split('\t')
                rows.append((keys, target, flags))
    return rows


def clean(rows):
    return [r for r in rows if '|' not in r[0] and '^' not in r[0]]


def build():
    out = []
    for keys, target, flags in read_rows('mine.tsv'):
        out.append((keys, target, flags, 'office'))
    for keys, target, flags in random.Random(SEED).sample(read_rows('chat.tsv'), 20):
        out.append((keys, target, flags, 'chat'))
    for name, group in (('chat.dbl.tsv', 'dbl'), ('chat.extra.tsv', 'extra')):
        pool = clean(read_rows(name))
        for keys, target, flags in random.Random(SEED).sample(pool, min(10, len(pool))):
            out.append((keys, target, flags, group))
    for keys, target in RESEARCH:
        out.append((keys, target, '1' * len(target.split()), 'research'))
    return out


def main():
    rows = build()
    with open(OUT, 'w', encoding='utf-8', newline='\n') as f:
        for keys, target, flags, group in rows:
            f.write('\t'.join((keys, target, flags, group)) + '\n')


if __name__ == '__main__':
    main()
