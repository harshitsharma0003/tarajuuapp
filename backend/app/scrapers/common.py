"""Shared scraping helpers and the listing shape every source returns."""
import re
from dataclasses import dataclass, field

import httpx

from ..config import get_settings

# A single, ordinary desktop-browser header set. No rotation, proxies or
# fingerprint tricks: if a source blocks us we report it and fall back.
BROWSER_HEADERS = {
    "User-Agent": (
        "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 "
        "(KHTML, like Gecko) Chrome/140.0.0.0 Safari/537.36"
    ),
    "Accept": "text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8",
    "Accept-Language": "en-IN,en;q=0.9",
}


class SourceBlocked(Exception):
    """The source answered with a CAPTCHA / robot check instead of content."""


@dataclass
class Listing:
    source: str               # "amazon" | "flipkart"
    source_id: str            # ASIN or Flipkart product id
    title: str
    price: int | None
    mrp: int | None = None
    rating: float | None = None
    reviews: int | None = None
    image: str | None = None
    url: str | None = None
    brand: str | None = None
    images: list[str] = field(default_factory=list)
    delivery: str | None = None  # e.g. "Friday, 3 October" when the page states it


def client() -> httpx.AsyncClient:
    return httpx.AsyncClient(
        headers=BROWSER_HEADERS,
        follow_redirects=True,
        timeout=get_settings().scrape_timeout_seconds,
    )


_num = re.compile(r"[\d,]+(?:\.\d+)?")


def parse_int(text: str | None) -> int | None:
    """'₹1,699.00' -> 1699, '(10,111)' -> 10111."""
    if not text:
        return None
    m = _num.search(text)
    if not m:
        return None
    try:
        return int(float(m.group(0).replace(",", "")))
    except ValueError:
        return None


def parse_float(text: str | None) -> float | None:
    if not text:
        return None
    m = re.search(r"\d+(?:\.\d+)?", text)
    return float(m.group(0)) if m else None
