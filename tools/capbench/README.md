# capbench

Measures LeanKeys' auto-capitalisation of proper nouns (spec §17.1) on two corpora with correct casing:
`chat_messages.txt` and `synthetic_val.txt` in `vendor/vikey/Tools/autoswitch/sim/corpus/`.

Each line is lowercased and retyped word by word. After every word the rules run on what is on screen, as
`ProperNounRules` does. The output is then compared with the original casing. Sentence-initial words are not counted.
The lists are read from `leankeys/LeanKeysKit/Resources/ProperNouns.json`, the file the app ships.

```
C=vendor/vikey/Tools/autoswitch/sim/corpus
python3 tools/capbench/capbench.py $C/chat_messages.txt $C/synthetic_val.txt
```

Matching ignores tone placement (`hoá` and `hóa` share a key), as in `ProperNounRules.key`. A replacement capitalises
the typed words themselves and never substitutes the list's spelling.

The script exits 1 when the fixed rules make any wrong capital.

## Results (2026-11-16)

| Rules | TP | FP | Missed |
| --- | --- | --- | --- |
| Fixed (spec §17.1.1–17.1.2) | 302 | 0 | 1166 |
| Fixed + learned names (§17.1.3 simulation) | 777 | 2 | 691 |

- The 2 learned-run FPs are `FOMO`, which is all caps in the original. The app never learns all-caps words.
- `Tết` is not in the list. The corpus writes `tết` in lowercase 11 times, so adding it gave FP 11. It is left out per spec §17.1.1.

## Known approximation

The harness keeps context across a whole line, so place cues and the previous words of a name can reach back past
a `.`, `!`, `?` or comma. `ProperNounRules` sees only the current phrase, which starts after the last `.`, `!`, `?`
or newline. The numbers are therefore an approximation of the app. The harness is kept as it is so the prototype's
302/0 baseline stays comparable.
