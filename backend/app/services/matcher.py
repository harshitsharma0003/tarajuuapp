"""Decide which Amazon and Flipkart listings are the same product (one tile).

Three kinds of evidence, strongest first:

1. Attributes (services/attrs.py): brand, model number, variant words
   (Pro / Max / e …), storage, RAM, size, pack count, accessory-vs-device,
   bundles (AppleCare). Any disagreement vetoes the pair — iPhone 17 Pro and
   17 Pro Max look identical in photos, so this gate comes first.
2. Text: fuzzy token-set similarity (rapidfuzz) of the identifying part of
   the titles, so Amazon's marketing copy doesn't drown the model name.
3. Image (services/imgsim.py): perceptual hash + colour histogram of the
   product photos. Confirms pairs the text alone can't settle (cases, fans,
   anything without a model number) and picks the same colour on both sides.

Colour variants inside one shop (Flipkart lists every colour separately)
are folded into a single group first, so "iPhone 17 Pro 256 GB" is one tile.
"""
import math
from dataclasses import dataclass

from rapidfuzz import fuzz

from ..scrapers.common import Listing
from . import imgsim
from .attrs import Attrs, parse

MAX_PRICE_RATIO = 1.6   # same product rarely differs more than this between the two shops
# Photo "design" similarity (imgsim.design, 0..1): same product at or above
# IMAGE_CONFIRMS, clearly different below IMAGE_REJECTS. Calibrated on real
# Amazon/Flipkart pairs (see tests).
IMAGE_CONFIRMS = 0.8
IMAGE_REJECTS = 0.65
SAME_COLOUR = 0.7       # imgsim.colour at which both photos show the same colour variant


def attrs_of(listing: Listing) -> Attrs:
    return parse(listing.title, listing.brand, listing.specs)


def conflict(a: Attrs, b: Attrs, price_a: int | None = None, price_b: int | None = None) -> str | None:
    """Reason the two can't be the same product, or None."""
    if a.brand and b.brand and a.brand != b.brand:
        return "brand"
    if a.accessory != b.accessory:
        return "accessory"
    if a.bundle != b.bundle:
        return "bundle"
    if a.models and b.models and not (a.models & b.models):
        return "model"
    if a.models and b.models and a.variants != b.variants:
        return "variant"
    for x, y, name in ((a.storage_gb, b.storage_gb, "storage"), (a.ram_gb, b.ram_gb, "ram")):
        if x and y and x != y:
            return name
    if a.inches and b.inches and abs(a.inches - b.inches) > 0.6:
        return "size"
    for unit in a.measures.keys() & b.measures.keys():
        if not (a.measures[unit] & b.measures[unit]):
            return unit
    if a.pack != b.pack:
        return "pack"
    if price_a and price_b and max(price_a, price_b) / min(price_a, price_b) > MAX_PRICE_RATIO:
        return "price"
    return None


def text_similarity(a: Attrs, b: Attrs) -> float:
    return fuzz.token_set_ratio(a.core, b.core) / 100


def strong_identity(a: Attrs, b: Attrs, text: float) -> bool:
    """Model-numbered device whose identifying attributes all agree — no photo needed."""
    return (not a.accessory and bool(a.brand) and a.brand == b.brand and bool(a.models & b.models)
            and text >= 0.6 and (a.storage_gb is None) == (b.storage_gb is None))


def score(a: Attrs, b: Attrs, img: float | None, price_a: int | None = None, price_b: int | None = None) -> float:
    """0 = different products; higher = more confident they are the same."""
    if conflict(a, b, price_a, price_b):
        return 0.0
    s = _evidence(a, b, img)
    if s and price_a and price_b:
        # Tie-break between near-identical candidates: closer prices win.
        s += 0.03 * (1 - min(1.0, abs(math.log(price_a / price_b)) / math.log(MAX_PRICE_RATIO)))
    return s


def _evidence(a: Attrs, b: Attrs, img: float | None) -> float:
    text = text_similarity(a, b)
    if strong_identity(a, b, text):
        return 0.85 + 0.1 * text + (0.05 if img is not None and img >= IMAGE_CONFIRMS else 0)
    if img is None:
        return 0.6 * text if text >= 0.92 else 0.0
    if img >= IMAGE_CONFIRMS and text >= 0.55:
        return 0.4 * text + 0.6 * img
    if img >= IMAGE_REJECTS and text >= 0.85:
        return 0.5 * text + 0.5 * img
    if text >= 0.97:
        return 0.5 * text
    return 0.0


@dataclass
class _Group:
    rank: int                  # position of its first member in the shop's results
    members: list[tuple[Listing, Attrs]]

    def cheapest(self) -> Listing:
        priced = [m for m, _ in self.members if m.price]
        return min(priced, key=lambda m: m.price) if priced else self.members[0][0]


def _group(listings: list[Listing]) -> list[_Group]:
    groups: dict[tuple, _Group] = {}
    for i, l in enumerate(listings):
        at = attrs_of(l)
        groups.setdefault(at.group_key(), _Group(i, [])).members.append((l, at))
    return list(groups.values())


def _best_pair(ga: _Group, gf: _Group, use_images: bool) -> tuple[float, Listing, Listing]:
    """Group-vs-group score (best member pair). The listings returned are the
    same-colour pair when the photos show one, else each group's cheapest."""
    best = 0.0
    same_colour = None
    for la, aa in ga.members:
        for lf, af in gf.members:
            look = imgsim.design(la.image, lf.image) if use_images else None
            s = score(aa, af, look, la.price, lf.price)
            best = max(best, s)
            tint = imgsim.colour(la.image, lf.image) if use_images else None
            if s and tint is not None and tint >= SAME_COLOUR and (same_colour is None or tint > same_colour[0]):
                same_colour = (tint, la, lf)
    if best and same_colour:
        return best, same_colour[1], same_colour[2]
    return best, ga.cheapest(), gf.cheapest()


async def match(amazon: list[Listing], flipkart: list[Listing],
                use_images: bool = True) -> list[tuple[Listing | None, Listing | None]]:
    """One (amazon, flipkart) tuple per tile, in relevance order. Either side may be None."""
    ga, gf = _group(amazon), _group(flipkart)

    if use_images:
        # Only photos that could change a decision: groups with a non-vetoed counterpart.
        urls: set[str] = set()
        for x in ga:
            for y in gf:
                if any(not conflict(aa, af, la.price, lf.price) for la, aa in x.members for lf, af in y.members):
                    urls |= {m.image for m, _ in x.members + y.members if m.image}
        await imgsim.prefetch(urls)

    candidates = []
    for i, x in enumerate(ga):
        for j, y in enumerate(gf):
            s, la, lf = _best_pair(x, y, use_images)
            if s > 0:
                candidates.append((s, i, j, la, lf))
    candidates.sort(key=lambda c: c[0], reverse=True)

    paired: dict[int, tuple[int, Listing, Listing]] = {}
    used_f: set[int] = set()
    for s, i, j, la, lf in candidates:
        if i in paired or j in used_f:
            continue
        paired[i] = (j, la, lf)
        used_f.add(j)

    tiles: list[tuple[int, int, Listing | None, Listing | None]] = []
    for i, x in enumerate(ga):
        if i in paired:
            j, la, lf = paired[i]
            tiles.append((min(x.rank, gf[j].rank), 0, la, lf))
        else:
            tiles.append((x.rank, 1, x.cheapest(), None))
    for j, y in enumerate(gf):
        if j not in used_f:
            tiles.append((y.rank, 1, None, y.cheapest()))
    # Interleave both shops by rank; at equal rank, matched tiles first.
    tiles.sort(key=lambda t: (t[0], t[1]))
    return [(a, f) for _, _, a, f in tiles]


def pair(amazon: list[Listing], flipkart: list[Listing]) -> list[tuple[Listing | None, Listing | None]]:
    """Text-and-attributes-only matching (no network) — for tests and quick checks."""
    import asyncio
    return asyncio.run(match(amazon, flipkart, use_images=False))
