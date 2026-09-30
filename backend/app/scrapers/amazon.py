"""Amazon.in: plain HTML scraping of the public search and product pages."""
import re
from urllib.parse import quote_plus

from selectolax.parser import HTMLParser

from ..config import get_settings
from .common import Listing, SourceBlocked, client, parse_float, parse_int

_ROBOT_MARKERS = ("api-services-support@amazon.com", "Type the characters you see", "/errors/validateCaptcha")


def _check_blocked(status: int, html: str) -> None:
    if status == 503 or any(m in html for m in _ROBOT_MARKERS):
        raise SourceBlocked("amazon")


def product_url(asin: str) -> str:
    s = get_settings()
    url = f"{s.amazon_host}/dp/{asin}"
    return f"{url}?tag={s.amazon_partner_tag}" if s.amazon_partner_tag else url


def _text(node, sel: str) -> str | None:
    n = node.css_first(sel)
    return n.text(strip=True) if n else None


def parse_search(html: str, limit: int = 12) -> list[Listing]:
    tree = HTMLParser(html)
    out: list[Listing] = []
    for item in tree.css('div[data-component-type="s-search-result"]'):
        asin = item.attributes.get("data-asin")
        title = _text(item, "h2")
        if not asin or not title:
            continue
        price = parse_int(_text(item, "span.a-price:not(.a-text-price) span.a-offscreen"))
        if price is None:
            continue  # "currently unavailable" rows are useless for comparison
        img = item.css_first("img.s-image")
        rating_label = item.css_first('[aria-label*="ratings"]')
        out.append(Listing(
            source="amazon",
            source_id=asin,
            title=title,
            price=price,
            mrp=parse_int(_text(item, "span.a-price.a-text-price span.a-offscreen")),
            rating=parse_float(_text(item, "span.a-icon-alt")),
            reviews=parse_int(rating_label.attributes.get("aria-label")) if rating_label else None,
            image=img.attributes.get("src") if img else None,
            url=product_url(asin),
        ))
        if len(out) >= limit:
            break
    return out


async def search_direct(query: str, limit: int = 12) -> list[Listing]:
    async with client() as c:
        r = await c.get(f"{get_settings().amazon_host}/s?k={quote_plus(query)}")
    _check_blocked(r.status_code, r.text)
    r.raise_for_status()
    return parse_search(r.text, limit)


def parse_product(asin: str, html: str) -> Listing:
    tree = HTMLParser(html)
    title = _text(tree, "#productTitle") or ""
    price = (
        parse_int(_text(tree, ".priceToPay .a-price-whole"))
        or parse_int(_text(tree, "#corePrice_feature_div .a-price-whole"))
        or parse_int(_text(tree, "#corePriceDisplay_desktop_feature_div .a-price-whole"))
    )
    mrp = parse_int(_text(tree, ".basisPrice .a-offscreen"))
    rating_node = tree.css_first("#acrPopover")
    rating = parse_float(rating_node.attributes.get("title")) if rating_node else None
    reviews = parse_int(_text(tree, "#acrCustomerReviewText"))
    brand = _text(tree, "#bylineInfo")
    if brand:
        brand = re.sub(r"^(Visit the |Brand: )|( Store)$", "", brand).strip()

    # Gallery: the page embeds every image as "hiRes" (≈1500px) in a script blob.
    images: list[str] = []
    for url in re.findall(r'"hiRes":"(https://[^"]+)"', html) + re.findall(r'"large":"(https://[^"]+\._[^"]+)"', html):
        if url not in images:
            images.append(url)
    if not images:
        landing = tree.css_first("#landingImage")
        if landing and landing.attributes.get("data-old-hires"):
            images.append(landing.attributes["data-old-hires"])

    delivery_node = tree.css_first("[data-csa-c-delivery-time]")
    delivery = delivery_node.attributes.get("data-csa-c-delivery-time") if delivery_node else None

    return Listing(
        source="amazon", source_id=asin, title=title, price=price, mrp=mrp,
        rating=rating, reviews=reviews, image=images[0] if images else None,
        url=product_url(asin), brand=brand, images=images[:8], delivery=delivery,
    )


async def product_direct(asin: str) -> Listing:
    async with client() as c:
        r = await c.get(f"{get_settings().amazon_host}/dp/{asin}")
    _check_blocked(r.status_code, r.text)
    r.raise_for_status()
    return parse_product(asin, r.text)


# ── public entry points: direct fetch, or via the scrape agent ──

async def search(query: str, limit: int = 12) -> list[Listing]:
    if get_settings().scrape_mode == "agent":
        from ..services import agent_queue
        return await agent_queue.run("amazon_search", {"query": query, "limit": limit})
    return await search_direct(query, limit)


async def product(asin: str) -> Listing:
    if get_settings().scrape_mode == "agent":
        from ..services import agent_queue
        return await agent_queue.run("amazon_product", {"asin": asin})
    return await product_direct(asin)
