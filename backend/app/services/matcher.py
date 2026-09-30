"""Pair Amazon and Flipkart listings that describe the same product.

Pure functions (no I/O) so they are easy to unit-test. Two listings match when
they share a brand (first title word) and enough of their title tokens, with
numeric/model tokens such as "1200mm", "43", "256gb" weighted double: those are
what distinguish one SKU from its neighbour.
"""
import re

from ..scrapers.common import Listing

_STOP = {
    "for", "with", "and", "the", "of", "in", "to", "a", "by", "on", "new", "pack",
    "home", "latest", "model", "colour", "color", "black", "white", "blue", "brown",
    "|", "-", "&",
}
MIN_SCORE = 0.34


def tokens(title: str) -> set[str]:
    words = re.findall(r"[a-z0-9]+", title.lower())
    return {w for w in words if w not in _STOP and len(w) > 1}


def _brand(title: str) -> str:
    m = re.match(r"\s*([A-Za-z0-9]+)", title)
    return m.group(1).lower() if m else ""


def score(a: str, b: str) -> float:
    if _brand(a) != _brand(b):
        return 0.0
    ta, tb = tokens(a), tokens(b)
    if not ta or not tb:
        return 0.0

    def weight(t: str) -> float:
        return 2.0 if any(ch.isdigit() for ch in t) else 1.0

    inter = sum(weight(t) for t in ta & tb)
    union = sum(weight(t) for t in ta | tb)
    return inter / union


def pair(amazon: list[Listing], flipkart: list[Listing]) -> list[tuple[Listing | None, Listing | None]]:
    """Greedy best-first pairing. Unmatched listings come back alone.

    Order follows Amazon's ranking, with unmatched Flipkart items appended.
    """
    candidates = sorted(
        ((score(a.title, f.title), i, j) for i, a in enumerate(amazon) for j, f in enumerate(flipkart)),
        reverse=True,
    )
    a_to_f: dict[int, int] = {}
    used_f: set[int] = set()
    for s, i, j in candidates:
        if s < MIN_SCORE:
            break
        if i in a_to_f or j in used_f:
            continue
        a_to_f[i] = j
        used_f.add(j)

    out: list[tuple[Listing | None, Listing | None]] = [
        (a, flipkart[a_to_f[i]] if i in a_to_f else None) for i, a in enumerate(amazon)
    ]
    out += [(None, f) for j, f in enumerate(flipkart) if j not in used_f]
    return out
