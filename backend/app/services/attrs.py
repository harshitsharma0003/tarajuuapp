"""Structured attributes parsed from a listing's title (+ card specs).

Amazon and Flipkart describe the same SKU very differently:

    Amazon:   "Apple iPhone 17 Pro 256 GB: 15.93 cm (6.3″) Display with Promotion …"
    Flipkart: "Apple iPhone 17 Pro (Silver, 256 GB)"

so matching works on what identifies a product — brand, model number, variant
words (Pro / Max / e …), storage, RAM, size, pack count, accessory-or-device —
rather than on raw word overlap. Pure functions, no I/O.
"""
import re
from dataclasses import dataclass, field

# Product-line names that imply the brand when a title omits it ("iPhone 18 Pro …").
_FAMILY_BRAND = {
    "iphone": "apple", "ipad": "apple", "macbook": "apple", "airpods": "apple", "imac": "apple",
    "galaxy": "samsung", "pixel": "google", "redmi": "xiaomi", "mi": "xiaomi",
}
_BRAND_ALIAS = {"mi": "xiaomi", "redmi": "xiaomi", "oneplus": "oneplus", "lg": "lg"}

# Words that distinguish one model of a line from its neighbour.
VARIANT_WORDS = {"pro", "max", "plus", "ultra", "mini", "lite", "fe", "neo", "air", "fold", "flip",
                 "edge", "prime", "se", "slim", "turbo"}

ACCESSORY_WORDS = {"case", "cases", "cover", "covers", "glass", "protector", "guard", "charger", "cable",
                   "adapter", "adaptor", "skin", "holder", "stand", "strap", "pouch", "tempered", "sleeve",
                   "mount", "lens", "screenguard", "film", "keyboard", "stylus", "dock"}

COLOURS = {
    "black", "white", "blue", "silver", "gold", "golden", "grey", "gray", "green", "red", "orange",
    "purple", "violet", "lavender", "pink", "yellow", "teal", "sage", "mint", "natural", "desert",
    "cosmic", "deep", "mist", "ultramarine", "obsidian", "porcelain", "hazel", "frost", "titanium",
    "graphite", "midnight", "starlight", "space", "jet", "onyx", "phantom", "cream", "beige", "brown",
    "burgundy", "navy", "dark", "light", "clear", "transparent", "icyblue", "shadow", "rose", "coral",
    "aqua", "cyan", "peach", "lime", "matte", "glossy", "tan", "pistachio", "hibiscus", "charcoal",
}

_FILLER = {"for", "with", "and", "the", "of", "in", "to", "a", "by", "on", "new", "latest", "model",
           "colour", "color", "5g", "4g", "lte", "smartphone", "mobile", "phone", "compatible", "edition"}

_STORE = re.compile(r"(\d+(?:\.\d+)?)\s*(gb|tb)\b\s*(ram|rom|storage|ssd|hdd|internal|memory|emmc)?", re.I)
_INCH = re.compile(r"(\d{1,3}(?:\.\d+)?)\s*(?:inch(?:es)?|in\b|″|\"|''|-inch)", re.I)
_CM = re.compile(r"(\d{2,3}(?:\.\d+)?)\s*cm\b", re.I)
# Other quantities that tell SKUs apart (fan sweep, capacity, power …).
_MEASURE = re.compile(r"(\d+(?:\.\d+)?)\s*(mm|kg|litres?|liters?|ltrs?|l|tons?|w|watts?|mah|ml|g)\b", re.I)
_UNIT = {"litre": "l", "litres": "l", "liter": "l", "liters": "l", "ltr": "l", "ltrs": "l", "ton": "ton",
         "tons": "ton", "watt": "w", "watts": "w"}
# Network generation and camera/refresh specs: neither identifies a model.
_NOISE = re.compile(r"\b[2-5]g\b|\b\d+\s*(?:mp|hz)\b", re.I)
_PACK = re.compile(r"(?:pack\s+of|set\s+of)\s*(\d+)|(\d+)\s*(?:pcs|pieces|pack)\b", re.I)
_BUNDLE = re.compile(r"apple\s*care|protect\s*\+|\bcombo\b|\bbundle\b|\bwith\s+\w+\s+services\b", re.I)


@dataclass
class Attrs:
    title: str
    core: str                      # identifying part of the title, lowercase, colours/measures removed
    brand: str = ""
    accessory: bool = False
    bundle: bool = False
    variants: frozenset = field(default_factory=frozenset)
    models: frozenset = field(default_factory=frozenset)  # alphanumeric model tokens: "17", "s25", "17e"
    storage_gb: float | None = None
    ram_gb: float | None = None
    inches: float | None = None
    measures: dict = field(default_factory=dict)  # unit → set of values
    pack: int = 1
    colours: frozenset = field(default_factory=frozenset)

    def group_key(self) -> tuple:
        """Listings with the same key are colour variants of one product."""
        return (self.brand, self.core, self.accessory, self.bundle, self.storage_gb, self.ram_gb,
                self.inches and round(self.inches), self.pack,
                tuple(sorted((u, tuple(sorted(v))) for u, v in self.measures.items())))


def _core_text(title: str) -> str:
    """Identity part of a title: Amazon appends marketing copy after ':' / '|' / ' - '."""
    t = re.split(r"\s*[:|｜]\s*|\s+[-–—]\s+", title, maxsplit=1)[0]
    t = re.split(r"(?<=\))\s*,", t, maxsplit=1)[0]  # "(Gray, 12GB RAM, 256GB), 200MP Camera …"
    t = _NOISE.sub(" ", t)
    return t if len(t) >= 8 else title


def _words(text: str) -> list[str]:
    text = re.sub(r"(\w)\+", r"\1 plus", text.lower())  # "S25+" → "s25 plus"
    return re.findall(r"[a-z0-9]+(?:\.[0-9]+)?", text)


def _gb(value: str, unit: str) -> float:
    return float(value) * (1024 if unit.lower() == "tb" else 1)


def parse(title: str, brand: str | None = None, specs: str = "") -> Attrs:
    core_raw = _core_text(title)
    text_all = f"{title} | {specs}"

    # storage / RAM
    labelled_ram, labelled_rom, unlabelled = [], [], []
    for v, unit, label in _STORE.findall(text_all):
        gb = _gb(v, unit)
        label = (label or "").lower()
        (labelled_ram if label in ("ram", "memory") else labelled_rom if label else unlabelled).append(gb)
    ram = labelled_ram[0] if labelled_ram else None
    storage = labelled_rom[0] if labelled_rom else None
    rest = [g for g in unlabelled if g not in (ram, storage)]
    if storage is None and rest:
        storage = max(rest)
        rest = [g for g in rest if g != storage]
    if ram is None and rest and storage and min(rest) < storage:
        ram = min(rest)

    # screen / product size in inches
    inches = None
    m = _INCH.search(text_all)
    if m:
        inches = float(m.group(1))
    else:
        m = _CM.search(text_all)
        if m:
            inches = round(float(m.group(1)) / 2.54, 1)

    measures: dict[str, set] = {}
    for v, unit in _MEASURE.findall(core_raw):
        u = _UNIT.get(unit.lower(), unit.lower())
        measures.setdefault(u, set()).add(float(v))

    pack = 1
    m = _PACK.search(title)
    if m:
        pack = int(m.group(1) or m.group(2))

    # strip quantities before tokenising so "256 GB" / "6.3″" don't look like model numbers
    stripped = _STORE.sub(" ", core_raw)
    stripped = _INCH.sub(" ", _CM.sub(" ", _MEASURE.sub(" ", stripped)))
    words = _words(stripped)
    colours = frozenset(w for w in words if w in COLOURS)
    ident = [w for w in words if w not in COLOURS and w not in _FILLER]

    b = (brand or "").strip().lower().split(" ")[0] if brand else ""
    first = ident[0] if ident else ""
    if not b or b in _FAMILY_BRAND:
        b = _FAMILY_BRAND.get(b) or _FAMILY_BRAND.get(first) or first
    b = _BRAND_ALIAS.get(b, b)
    if ident and _BRAND_ALIAS.get(ident[0], ident[0]) == b:
        ident = ident[1:]
    # "17", "s25", "17e", "wh1000xm5" — but not decimals like "6.3"
    models = frozenset(w for w in ident if any(c.isdigit() for c in w) and "." not in w and len(w) <= 12)
    return Attrs(
        title=title,
        core=" ".join(ident),
        brand=b,
        accessory=any(w in ACCESSORY_WORDS for w in _words(core_raw)),
        bundle=bool(_BUNDLE.search(title)),
        variants=frozenset(w for w in ident if w in VARIANT_WORDS),
        models=models,
        storage_gb=storage,
        ram_gb=ram,
        inches=inches,
        measures=measures,
        pack=pack,
        colours=colours,
    )
