#!/usr/bin/env python3
"""Measures 4D auto-capitalisation (spec 17.1) on correctly cased corpora.

Each line is lowercased and retyped word by word; after every word the rules run on what is on screen so far, as
ProperNounRules does, except that the context is the whole line (README, "Known approximation"). The result is compared with the original casing, skipping sentence-initial words:
  TP  capitalised and capitalised in the original
  FP  capitalised but lowercase in the original
All-caps words (FOMO) are retyped as written, not lowercased, and not counted when the output leaves them so.
  missed  capitalised in the original but not by the rules
Then the negatives corpus (ordinary sentences, tools/capbench/negatives.txt) is retyped as written, sentence-initial
capitals included, with the fixed rules: any word the rules change there is an FP.
The lists come from leankeys/LeanKeysKit/Resources/ProperNouns.json, the file the app ships.

  python3 tools/capbench/capbench.py      # the two Vikey corpora below, then the negatives
  python3 tools/capbench/capbench.py vendor/vikey/Tools/autoswitch/sim/corpus/chat_messages.txt \
      vendor/vikey/Tools/autoswitch/sim/corpus/synthetic_val.txt
"""
import argparse, collections, json, os, re, sys, unicodedata

HERE = os.path.dirname(os.path.abspath(__file__))
DATA = os.path.join(HERE, "..", "..", "leankeys", "LeanKeysKit", "Resources", "ProperNouns.json")
CORPORA = [os.path.join(HERE, "..", "..", "vendor", "vikey", "Tools", "autoswitch", "sim", "corpus", f)
           for f in ("chat_messages.txt", "synthetic_val.txt")]
NEGATIVES = os.path.join(HERE, "negatives.txt")


TONES = {"\u0300", "\u0301", "\u0303", "\u0309", "\u0323"}  # grave, acute, tilde, hook above, dot below


def key(word):
    """Lookup form, as ProperNounRules.key: lowercase with the tone mark moved to the end ("hoá" == "hóa")."""
    chars = unicodedata.normalize("NFD", word.lower())
    tones = [c for c in chars if c in TONES]
    return "".join(c for c in chars if c not in TONES) + "".join(tones[:1])


def load(path):
    d = json.load(open(path, encoding="utf-8"))
    n = lambda xs: {" ".join(key(w) for w in x.split()) for x in xs}
    places = {tuple(key(w) for w in p.split()) for p in d["places"] + d["singleWords"]}
    not_after = {" ".join(key(w) for w in p.split()): n(ws) for p, ws in d["placeNotAfter"].items()}
    given_not_after = {key(w): n(ws) for w, ws in d["givenNameNotAfter"].items()}
    return dict(places=places, longest=max((len(k) for k in places), default=0), ambiguous=n(d["ambiguousPlaces"]),
                cues=n(d["placeCues"]), not_after=not_after, given_not_after=given_not_after, surnames=n(d["surnames"]), sure=n(d["sureSurnames"]),
                middle=n(d["middleNames"]), given=n(d["givenNames"]), titles=n(d["titles"]))


def cap(w):
    """As ProperNounRules.capitalized: only an all-lowercase word gets a capital; any other is left as typed."""
    return w[:1].upper() + w[1:] if w == w.lower() else w


def all_caps(w):
    """At least 2 letters, every letter a capital (`FOMO`, `HCM`, `COVID19`)."""
    letters = [c for c in w if c.isalpha()]
    return len(letters) >= 2 and all(c.isupper() for c in letters)


def touchable(w):
    """As ProperNounRules.isTouchable: all lowercase, or capitalised (`iPhone`, `FOMO` are never touched)."""
    return w == w.lower() or (w[:1].isupper() and w[1:] == w[1:].lower())


OPENING_QUOTES = set("“‘«")


TOKEN = re.compile(r"\w+|[^\w\s]")


def starts_sentence(text, m):
    """As AutoCapitalizer.startsSentence, for the punctuation token `m` in `text`: after `:` or an opening quote the
    next word's capital is sentence case. A straight quote opens when the raw character before it (a space
    included) is no letter or digit, or it starts the line: `nói "Mai` opens, `"ok" mai` closes."""
    t = m.group()
    if t == ":" or t in OPENING_QUOTES:
        return True
    if t in "\"'":
        return m.start() == 0 or not text[m.start() - 1].isalnum()
    return False


def run(lines, D, learned=None, show=0, label="", as_typed=False):
    """as_typed: retype each word as written (the negatives) instead of lowercased; then every word the rules
    change is an FP, sentence-initial words included."""
    learned = learned or {}
    PL, MAXN, AMBIGUOUS, CUES, NOT_AFTER = D["places"], D["longest"], D["ambiguous"], D["cues"], D["not_after"]
    SURNAMES, SURE, MIDDLE, GIVEN, TITLES = D["surnames"], D["sure"], D["middle"], D["given"], D["titles"]
    tp = fp = fn = 0
    ex = collections.Counter(); exfn = collections.Counter()
    for line in lines:
        text = unicodedata.normalize("NFC", line)
        out = []; orig = []
        phrase_first = None  # index of the phrase's first word: its capital is sentence case, not a name cue
        for m in TOKEN.finditer(text):
            t = m.group()
            if not t[0].isalnum():
                # The phrase restarts at . ! ?; a sentence restarts after : or an opening quote (final re-review N2).
                if t in ".!?" or starts_sentence(text, m):
                    phrase_first = None
                out.append(t); orig.append(t)
                continue
            # All-caps words (`FOMO`, `HCM`) are retyped as written: people type them so, and the app never
            # touches them. Single letters are lowercased like the rest ("I", "A" at a line start).
            low = t.lower(); out.append(t if as_typed or all_caps(t) else low); orig.append(t); kw = key(low)
            i = len(out) - 1
            if phrase_first is None:
                phrase_first = i
            if not touchable(out[i]):
                continue
            words = [j for j in range(len(out)) if out[j][0].isalnum()]

            def upper(k):
                """A capital on screen that marks a name: not the phrase's first word's, unless a sure surname."""
                return out[k][:1].isupper() and (k != phrase_first or key(out[k]) in SURE)

            # Place phrases ending here, longest first, never across punctuation.
            for n in range(MAXN, 0, -1):
                if len(words) < n:
                    continue
                idx = words[-n:]
                if any(not out[k][0].isalnum() for k in range(idx[0], i)):
                    continue
                phrase = tuple(key(out[k]) for k in idx)
                if phrase in PL:
                    prev = [key(out[k]) for k in words if k < idx[0]][-2:]
                    if " ".join(phrase) in AMBIGUOUS and not (prev and (prev[-1] in CUES or " ".join(prev) in CUES)):
                        break
                    if prev and prev[-1] in NOT_AFTER.get(" ".join(phrase), ()):
                        break
                    for k in idx:  # the user's own words, not the list's spelling
                        out[k] = cap(out[k])
                    break
            # Names.
            p1 = words[-2] if len(words) >= 2 else None
            p2 = words[-3] if len(words) >= 3 else None
            given = kw in GIVEN and not (p1 is not None and key(out[p1]) in D["given_not_after"].get(kw, ()))
            if kw in SURE:
                out[i] = cap(out[i])
            elif kw in MIDDLE and p1 is not None and key(out[p1]) in SURNAMES \
                    and (key(out[p1]) in SURE or upper(p1)):
                out[i] = cap(out[i]); out[p1] = cap(out[p1])
            elif p2 is not None and upper(p1) and key(out[p1]) in MIDDLE and key(out[p2]) in SURNAMES:
                out[i] = cap(out[i])
            elif given and p1 is not None and key(out[p1]) in SURNAMES \
                    and (key(out[p1]) in SURE or upper(p1)):
                out[i] = cap(out[i]); out[p1] = cap(out[p1])
            elif given and p2 is not None and upper(p1) and upper(p2) and key(out[p2]) in SURNAMES | MIDDLE:
                out[i] = cap(out[i])
            elif out[i] == low and low in learned.get("title", set()) and p1 is not None and key(out[p1]) in TITLES:
                out[i] = cap(out[i])
            elif out[i] == low and low in learned.get("any", {}):
                out[i] = learned["any"][low]
        if as_typed:
            for a, b in zip(out, orig):
                if a != b:
                    fp += 1; ex[b] += 1
            continue
        st = True
        for a, b in zip(out, orig):
            if not b[0].isalnum():
                if b in ".!?":
                    st = True
                continue
            if st:
                st = False; continue
            if all_caps(b) and a == b:
                continue  # retyped as written and left alone: neither right nor wrong
            A = a[:1].isupper(); B = b[:1].isupper() and not b.isupper()
            if A and B: tp += 1
            elif A and not B: fp += 1; ex[b] += 1
            elif B and not A: fn += 1; exfn[b] += 1
    if as_typed:
        print(f"{label:<16} FP {fp}  (in {len(lines)} lines retyped as written)")
        if show and fp:
            print("  FP:", ex.most_common(show))
        return tp, fp
    print(f"{label:<16} TP {tp}  FP {fp}  missed-capitals {fn}")
    if show:
        print("  FP:", ex.most_common(show)); print("  missed:", exfn.most_common(show))
    return tp, fp


def learn(lines, titles):
    """The learned-name simulation (spec 17.1.3): words capitalised mid-sentence at least twice."""
    title = collections.Counter(); capd = collections.Counter(); lower = set(); form = {}
    for l in lines:
        text = unicodedata.normalize("NFC", l); st = True; prev = None
        for m in TOKEN.finditer(text):
            t = m.group()
            if t in ".!?":
                st = True; prev = None; continue
            if not t[0].isalnum():
                # After `:` or an opening quote a capital is sentence case: not learned (final re-review N2).
                if starts_sentence(text, m):
                    st = True
                continue
            if t.islower():
                lower.add(t)
            if not st and t[:1].isupper() and not t.isupper() and len(t) > 1:
                capd[t.lower()] += 1; form[t.lower()] = t
                if prev and key(prev) in titles:
                    title[t.lower()] += 1
            st = False; prev = t
    return {"title": {w for w, c in title.items() if c >= 2},
            "any": {w: form[w] for w, c in capd.items() if c >= 2 and w not in lower}}


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("corpus", nargs="*", default=CORPORA, help="default: Vikey's chat_messages and synthetic_val")
    ap.add_argument("--negatives", default=NEGATIVES, help="ordinary sentences retyped as written; must give FP 0")
    ap.add_argument("--data", default=DATA)
    ap.add_argument("--show", type=int, default=15, help="most common FP and missed words to list")
    a = ap.parse_args()
    lines = [l for f in a.corpus for l in open(f, encoding="utf-8")]
    D = load(a.data)
    _, fp = run(lines, D, show=a.show, label="fixed")
    L = learn(lines, D["titles"])
    print(f"learned: {len(L['title'])} after a title, {len(L['any'])} anywhere")
    run(lines, D, L, show=a.show, label="fixed + learned")
    negatives = [l for l in open(a.negatives, encoding="utf-8") if l.strip()]
    _, nfp = run(negatives, D, show=a.show, label="negatives", as_typed=True)
    sys.exit(1 if fp or nfp else 0)


if __name__ == "__main__":
    main()
