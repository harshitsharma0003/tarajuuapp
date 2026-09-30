"""Categories: the chips/tabs the app shows and what we actually search for."""

CATEGORIES: dict[str, dict] = {
    "fan":        {"label": "Fan",    "emoji": "🌀", "query": "ceiling fan 1200mm"},
    "tv":         {"label": "TV",     "emoji": "📺", "query": "smart tv 43 inch"},
    "laptop":     {"label": "Laptop", "emoji": "💻", "query": "laptop 16gb ram"},
    "headphones": {"label": "Audio",  "emoji": "🎧", "query": "bluetooth headphones"},
    "mobile":     {"label": "Mobile", "emoji": "📱", "query": "5g smartphone"},
    "ac":         {"label": "AC",     "emoji": "❄️", "query": "1.5 ton 5 star inverter split ac"},
    "watch":      {"label": "Watch",  "emoji": "⌚", "query": "smartwatch"},
    "washing":    {"label": "Washer", "emoji": "🫧", "query": "washing machine"},
}


def category_for(query: str) -> str | None:
    """Same keyword routing as the prototype's getKey(), minus the 'fan' default."""
    q = query.lower()
    rules = [
        ("fan", ("fan",)),
        ("tv", ("tv", "television")),
        ("laptop", ("laptop", "notebook")),
        ("headphones", ("head", "ear", "tws", "audio")),
        ("mobile", ("mobile", "phone", "iphone", "smartphone")),
        ("watch", ("watch",)),
        ("washing", ("wash", "machine")),
        ("ac", (" ac", "ac ", "air con")),
    ]
    padded = f" {q} "
    for key, words in rules:
        if any(w in padded for w in words):
            return key
    return None


def emoji_for(category: str | None) -> str:
    return CATEGORIES.get(category or "", {}).get("emoji", "🛍️")
