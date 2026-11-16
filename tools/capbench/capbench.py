#!/usr/bin/env python3
"""Measures 4D auto-capitalisation (spec 17.1) on correctly cased corpora.

Each line is lowercased and retyped word by word; after every word the rules run on what is on screen so far,
exactly as ProperNounRules does. The result is compared with the original casing, skipping sentence-initial words:
  TP  capitalised and capitalised in the original
  FP  capitalised but lowercase in the original (all-caps originals such as FOMO count here too)
  missed  capitalised in the original but not by the rules
The lists come from leankeys/LeanKeysKit/Resources/ProperNouns.json, the file the app ships.

  python3 tools/capbench/capbench.py vendor/vikey/Tools/autoswitch/sim/corpus/chat_messages.txt \
      vendor/vikey/Tools/autoswitch/sim/corpus/synthetic_val.txt
"""
import argparse, collections, json, os, re, sys, unicodedata

DATA = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..", "leankeys", "LeanKeysKit", "Resources",
                    "ProperNouns.json")


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
    return dict(places=places, longest=max(len(k) for k in places), ambiguous=n(d["ambiguousPlaces"]),
                cues=n(d["placeCues"]), surnames=n(d["surnames"]), sure=n(d["sureSurnames"]),
                middle=n(d["middleNames"]), given=n(d["givenNames"]), titles=n(d["titles"]))


def cap(w):
    return w[:1].upper() + w[1:]


def run(lines, D, learned=None, show=0, label=""):
    learned = learned or {}
    PL, MAXN, AMBIGUOUS, CUES = D["places"], D["longest"], D["ambiguous"], D["cues"]
    SURNAMES, SURE, MIDDLE, GIVEN, TITLES = D["surnames"], D["sure"], D["middle"], D["given"], D["titles"]
    tp = fp = fn = 0
    ex = collections.Counter(); exfn = collections.Counter()
    for line in lines:
        toks = re.findall(r"\w+|[^\w\s]", unicodedata.normalize("NFC", line))
        out = []; orig = []
        for t in toks:
            if not t[0].isalnum():
                out.append(t); orig.append(t)
                continue
            low = t.lower(); out.append(low); orig.append(t); kw = key(low)
            i = len(out) - 1
            words = [j for j in range(len(out)) if out[j][0].isalnum()]
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
                    for k in idx:  # the user's own words, not the list's spelling
                        out[k] = cap(out[k])
                    break
            # Names.
            prevw = [out[k] for k in words[:-1]][-3:]
            if kw in SURE:
                out[i] = cap(low)
            elif kw in MIDDLE and prevw and key(prevw[-1]) in SURNAMES:
                out[i] = cap(low); out[words[-2]] = cap(out[words[-2]])
            elif prevw and prevw[-1][:1].isupper() and key(prevw[-1]) in MIDDLE and len(prevw) >= 2 \
                    and key(prevw[-2]) in SURNAMES:
                out[i] = cap(low)
            elif kw in GIVEN and prevw and key(prevw[-1]) in SURNAMES \
                    and (key(prevw[-1]) in SURE or prevw[-1][:1].isupper()):
                out[i] = cap(low); out[words[-2]] = cap(out[words[-2]])
            elif kw in GIVEN and prevw and prevw[-1][:1].isupper() and len(prevw) >= 2 and prevw[-2][:1].isupper() \
                    and key(prevw[-2]) in SURNAMES | MIDDLE:
                out[i] = cap(low)
            elif low in learned.get("title", set()) and prevw and key(prevw[-1]) in TITLES:
                out[i] = cap(low)
            elif low in learned.get("any", {}):
                out[i] = learned["any"][low]
        st = True
        for a, b in zip(out, orig):
            if not b[0].isalnum():
                if b in ".!?":
                    st = True
                continue
            if st:
                st = False; continue
            A = a[:1].isupper(); B = b[:1].isupper() and not b.isupper()
            if A and B: tp += 1
            elif A and not B: fp += 1; ex[b] += 1
            elif B and not A: fn += 1; exfn[b] += 1
    print(f"{label:<16} TP {tp}  FP {fp}  missed-capitals {fn}")
    if show:
        print("  FP:", ex.most_common(show)); print("  missed:", exfn.most_common(show))
    return tp, fp


def learn(lines, titles):
    """The learned-name simulation (spec 17.1.3): words capitalised mid-sentence at least twice."""
    title = collections.Counter(); capd = collections.Counter(); lower = set(); form = {}
    for l in lines:
        toks = re.findall(r"\w+|[.!?]", unicodedata.normalize("NFC", l)); st = True; prev = None
        for t in toks:
            if t in ".!?":
                st = True; prev = None; continue
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
    ap.add_argument("corpus", nargs="+")
    ap.add_argument("--data", default=DATA)
    ap.add_argument("--show", type=int, default=15, help="most common FP and missed words to list")
    a = ap.parse_args()
    lines = [l for f in a.corpus for l in open(f, encoding="utf-8")]
    D = load(a.data)
    _, fp = run(lines, D, show=a.show, label="fixed")
    L = learn(lines, D["titles"])
    print(f"learned: {len(L['title'])} after a title, {len(L['any'])} anywhere")
    run(lines, D, L, show=a.show, label="fixed + learned")
    sys.exit(1 if fp else 0)


if __name__ == "__main__":
    main()
