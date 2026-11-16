# capbench

Measures LeanKeys' auto-capitalisation of proper nouns (spec §17.1) on two corpora with correct casing:
`chat_messages.txt` and `synthetic_val.txt` in `vendor/vikey/Tools/autoswitch/sim/corpus/`.

Each line is lowercased and retyped word by word, except all-caps words (`FOMO`), which are retyped as written: the
app never touches them, and people type them so. After every word the rules run on what is on screen, as
`ProperNounRules` does. The output is then compared with the original casing. Sentence-initial words are not counted.
The lists are read from `leankeys/LeanKeysKit/Resources/ProperNouns.json`, the file the app ships.

```
python3 tools/capbench/capbench.py          # the two corpora above, then the negatives
C=vendor/vikey/Tools/autoswitch/sim/corpus
python3 tools/capbench/capbench.py $C/chat_messages.txt $C/synthetic_val.txt
```

Then `negatives.txt` (61 ordinary sentences with correct casing, including the ones the final review found) is
retyped **as written**, sentence-initial capitals included, with the fixed rules. Any word the rules change there is
an FP. This catches what the lowercased replay cannot: a sentence-initial capital taken as a name cue
(`Mai anh đi đâu thế`), and ordinary phrases that hold a list entry (`cập nhật bản mới`, `xã hội an toàn`).

Matching ignores tone placement (`hoá` and `hóa` share a key), as in `ProperNounRules.key`. A replacement capitalises
the typed words themselves and never substitutes the list's spelling.

The script exits 1 when the fixed rules make any wrong capital, on the corpora or on the negatives.

## Results (2026-11-16, after the audit follow-ups)

| Rules | TP | FP | Missed |
| --- | --- | --- | --- |
| Fixed (spec §17.1.1–17.1.2) | 302 | 0 | 1166 |
| Fixed + learned names (§17.1.3 simulation) | 777 | 0 (2 before all-caps words were retyped as written) | 691 |
| Negatives, fixed rules, retyped as written | – | 0 (39 before ruling R11; 5 on the 59 lines before R15; 2 on the 61 lines before the `:`/quote rule) | – |

Ruling R11 (a phrase-initial capital is no name cue, the middle-name rule needs a sure or capitalised surname, only
`nguyễn` is a sure surname, `về` is no place cue, `placeNotAfter` guards) and ruling R15 (strong place cues only, no `quốc` given name after `vương`) left the two
corpora's numbers unchanged.

- The 2 learned-run FPs before the audit follow-ups were `FOMO`, all caps in the original: a replay artifact of
  lowercasing it. The app never learns or touches all-caps words; the harness now retypes them as written and does
  not count a word it leaves as written.
- A capital right after `:` or an opening quote is sentence case (final re-review N2): the phrase restarts there,
  for the rules and for the learned-name simulation. It left the corpora's numbers unchanged.
- `Tết` is not in the list. The corpus writes `tết` in lowercase 11 times, so adding it gave FP 11. It is left out per spec §17.1.1.

## Known approximation

The harness keeps context across a whole line, so place cues and the previous words of a name can reach back past
a `.`, `!`, `?` or comma. `ProperNounRules` sees only the current phrase, which starts after the last `.`, `!`, `?`
or newline. The numbers are therefore an approximation of the app. The harness is kept as it is so the prototype's
302/0 baseline stays comparable. The phrase-initial rule uses the harness's own phrase: the first word after the
line's start, a `.`, `!`, `?`, a `:` or an opening quote.
