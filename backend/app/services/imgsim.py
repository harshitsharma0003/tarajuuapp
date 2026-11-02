"""Product-photo similarity, two separate signals:

* design — is it the same product? DINOv2-small (Meta, open source) image
  embeddings, which are strong at instance-level "same object" retrieval and
  largely ignore colour, lighting and studio background. Falls back to
  perceptual hashes (imagehash) if torch/transformers aren't installed.
* colour — is it the same colour variant? Hue/saturation histogram of the
  product pixels only (white studio background masked out).

Images are fetched small, background-trimmed, and cached per URL.
"""
import asyncio
import io
import logging
import os
import re
import threading
from collections import OrderedDict
from dataclasses import dataclass

import httpx
import imagehash
from PIL import Image, ImageChops, ImageOps

from ..scrapers.common import BROWSER_HEADERS

log = logging.getLogger(__name__)

_MODEL_ID = os.environ.get("IMAGE_MODEL", "facebook/dinov2-small")
_CACHE: "OrderedDict[str, _Feat | None]" = OrderedDict()
_CACHE_MAX = 3000
_SEM = asyncio.Semaphore(8)
_model_lock = threading.Lock()
_model = None          # (processor, model) once loaded; False if unavailable


@dataclass
class _Feat:
    embedding: list[float] | None   # L2-normalised DINOv2 vector
    hashes: tuple                   # (phash, dhash) fallback for design
    colour: list[float]             # normalised foreground colour histogram


def _small_url(url: str) -> str:
    # Ask the CDNs for a modest size — enough for recognition and much faster.
    url = re.sub(r"/image/\d+/\d+/", "/image/416/416/", url)          # Flipkart rukminim
    return re.sub(r"\._[A-Z0-9_,]+_\.", "._AC_SL400_.", url)          # Amazon media


def _model_cached() -> bool:
    hub = os.environ.get("HF_HUB_CACHE") or os.path.join(
        os.environ.get("HF_HOME") or os.path.join(os.path.expanduser("~"), ".cache", "huggingface"), "hub")
    return os.path.isdir(os.path.join(hub, "models--" + _MODEL_ID.replace("/", "--")))


def _load_model():
    global _model
    with _model_lock:
        if _model is None:
            if _model_cached():
                # Already downloaded: never touch the network (a flaky route made
                # the hub's update checks hang for minutes).
                os.environ.setdefault("HF_HUB_OFFLINE", "1")
            try:
                import torch  # noqa: F401
                from transformers import AutoImageProcessor, AutoModel
                try:
                    proc = AutoImageProcessor.from_pretrained(_MODEL_ID, local_files_only=True)
                    mdl = AutoModel.from_pretrained(_MODEL_ID, local_files_only=True)
                except OSError:
                    proc = AutoImageProcessor.from_pretrained(_MODEL_ID)
                    mdl = AutoModel.from_pretrained(_MODEL_ID)
                mdl.eval()
                _model = (proc, mdl)
                log.info("image model %s loaded", _MODEL_ID)
            except Exception as e:  # noqa: BLE001 — degrade to hashes
                log.warning("image model unavailable (%s); using perceptual hashes", e)
                _model = False
    return _model


def _foreground(im: Image.Image) -> tuple[Image.Image, Image.Image]:
    """Crop to the product and return (cropped RGB, its foreground mask)."""
    r, g, b = im.split()
    darkest = ImageChops.darker(ImageChops.darker(r, g), b)
    # near-white studio background (every channel bright) → 0, product → 255
    mask = darkest.point(lambda p: 255 if p < 236 else 0)
    box = mask.getbbox()
    if box:
        im, mask = im.crop(box), mask.crop(box)
    return im, mask


def _colour_hist(im: Image.Image, mask: Image.Image) -> list[float]:
    small = im.resize((96, 96))
    m = mask.resize((96, 96)).getdata()
    hsv = small.convert("HSV").getdata()
    bins = [0.0] * (12 * 3 + 4)
    for (h, s, v), keep in zip(hsv, m):
        if not keep:
            continue
        if s < 40:  # greys: black / grey / silver / white by brightness
            bins[36 + min(3, v // 64)] += 1
        else:
            bins[(h * 12 // 256) * 3 + min(2, (s - 40) // 72)] += 1
    total = sum(bins) or 1
    return [x / total for x in bins]


def _features(data: bytes) -> _Feat:
    im = Image.open(io.BytesIO(data)).convert("RGB")
    im, mask = _foreground(im)
    square = ImageOps.pad(im, (224, 224), color=(255, 255, 255))
    emb = None
    model = _load_model()
    if model:
        import torch
        proc, mdl = model
        with torch.no_grad():
            out = mdl(**proc(images=square, return_tensors="pt"))
        v = out.last_hidden_state[:, 0][0]  # CLS token
        emb = (v / v.norm()).tolist()
    return _Feat(emb, (imagehash.phash(square), imagehash.dhash(square)), _colour_hist(im, mask))


async def _get(client: httpx.AsyncClient, url: str):
    if url in _CACHE:
        _CACHE.move_to_end(url)
        return _CACHE[url]
    feats = None
    try:
        async with _SEM:
            r = await client.get(_small_url(url))
        r.raise_for_status()
        feats = await asyncio.to_thread(_features, r.content)
    except Exception as e:  # noqa: BLE001 — a missing photo only means "no image evidence"
        log.info("image fetch failed %s: %s", url, e)
    _CACHE[url] = feats
    if len(_CACHE) > _CACHE_MAX:
        _CACHE.popitem(last=False)
    return feats


async def warm_up() -> None:
    """Load the model in the background at startup so the first search doesn't wait."""
    await asyncio.to_thread(_load_model)


async def prefetch(urls: set[str]) -> None:
    urls = {u for u in urls if u and u not in _CACHE}
    if not urls:
        return
    await asyncio.to_thread(_load_model)
    transport = httpx.AsyncHTTPTransport(local_address="0.0.0.0", retries=1)  # IPv4: see firebase_auth
    async with httpx.AsyncClient(headers=BROWSER_HEADERS, timeout=10, follow_redirects=True, transport=transport) as c:
        await asyncio.gather(*(_get(c, u) for u in urls))


def design(url_a: str | None, url_b: str | None) -> float | None:
    """0..1: same product design (any colour). None when a photo is unavailable."""
    fa, fb = _CACHE.get(url_a or ""), _CACHE.get(url_b or "")
    if not fa or not fb:
        return None
    if fa.embedding and fb.embedding:
        cos = sum(x * y for x, y in zip(fa.embedding, fb.embedding))
        # DINOv2 CLS cosine on shop photos (calibrated on Amazon vs Flipkart):
        # same item ≥ 0.92, same kind of product but other design 0.7–0.88,
        # unrelated < 0.6. Spread the decisive 0.8–0.95 band over 0..1.
        return round(max(0.0, min(1.0, (cos - 0.8) / 0.15)), 3)
    dist = min(fa.hashes[0] - fb.hashes[0], fa.hashes[1] - fb.hashes[1])
    return round(max(0.0, 1 - dist / 32), 3)


def colour(url_a: str | None, url_b: str | None) -> float | None:
    """0..1: histogram intersection of the product colours."""
    fa, fb = _CACHE.get(url_a or ""), _CACHE.get(url_b or "")
    if not fa or not fb:
        return None
    return round(sum(min(x, y) for x, y in zip(fa.colour, fb.colour)), 3)
