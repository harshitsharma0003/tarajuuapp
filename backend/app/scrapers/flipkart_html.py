"""Flipkart.com: plain HTML scraping of the public search page.

The search URL with Flipkart's own tracking parameters (as produced by its
search box) returns server-rendered result cards. Each card is a
`div[data-id]` whose data-id is Flipkart's product id. Flipkart's CSS class
names are obfuscated and rotate, so fields are read from the card's text
pattern (₹ amounts, "% off", "Ratings") instead of class names.
"""
import re
from urllib.parse import quote

from selectolax.parser import HTMLParser

from .common import Listing, SourceBlocked, client, parse_int

_BASE = "https://www.flipkart.com"
_UNAVAILABLE = ("Currently unavailable", "Sold Out", "Coming Soon")


def search_url(query: str) -> str:
    return (f"{_BASE}/search?q={quote(query)}&otracker=search&otracker1=search"
            "&marketplace=FLIPKART&as-show=on&as=off")


def _hi_res(img: str | None) -> str | None:
    # rukminim CDN encodes the size in the path: /image/312/312/... → 832px.
    return re.sub(r"/image/\d+/\d+/", "/image/832/832/", img) if img else None


def _parse_card(card) -> Listing | None:
    pid = card.attributes.get("data-id")
    link = card.css_first("a[href*='/p/']")
    if not pid or not link:
        return None
    text = card.text(separator=" | ", strip=True)
    if any(u in text for u in _UNAVAILABLE):
        return None

    img = card.css_first("img")
    title = (img.attributes.get("alt") or "").strip() if img else ""
    if not title:
        title = (link.attributes.get("title") or link.text(strip=True) or "").strip()
    if not title:
        return None

    # The struck-through MRP renders "₹" and the digits in separate elements,
    # which the " | " separator splits ("₹ | 2,699").
    amounts = [parse_int(a) for a in re.findall(r"₹\s*(?:\|\s*)?[\d,]+", text)]
    amounts = [a for a in amounts if a]
    if not amounts:
        return None
    price = amounts[0]
    # MRP is the next, higher ₹ amount on the card (struck through on the site).
    mrp = next((a for a in amounts[1:4] if a > price), None)

    rating = None
    m = re.search(r"\|\s*([1-5](?:\.\d)?)\s*\|", text)
    if m:
        rating = float(m.group(1))
    reviews = None
    m = re.search(r"([\d,]+)\s*Ratings", text)
    if m:
        reviews = parse_int(m.group(1))

    href = link.attributes.get("href", "")
    url = _BASE + href.split("&")[0] if href.startswith("/") else href
    return Listing(
        source="flipkart",
        source_id=pid,
        title=title,
        price=price,
        mrp=mrp,
        rating=rating,
        reviews=reviews,
        image=_hi_res(img.attributes.get("src")) if img else None,
        url=url,
        brand=title.split()[0] if title else None,
    )


def parse_search(html: str, limit: int = 12) -> list[Listing]:
    out: list[Listing] = []
    seen: set[str] = set()
    for card in HTMLParser(html).css("div[data-id]"):
        listing = _parse_card(card)
        if listing and listing.source_id not in seen:
            seen.add(listing.source_id)
            out.append(listing)
            if len(out) >= limit:
                break
    return out


async def search(query: str, limit: int = 12) -> list[Listing]:
    async with client() as c:
        r = await c.get(search_url(query))
    if r.status_code in (403, 429, 529) or "Are you a human" in r.text:
        raise SourceBlocked("flipkart")
    r.raise_for_status()
    return parse_search(r.text, limit)
