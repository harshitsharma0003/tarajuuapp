"""Pure-logic tests (no DB, no network). Run: python -m pytest tests -q"""
from app.scrapers.common import Listing, parse_float, parse_int
from app.services import matcher, rides
from app.services.catalog import category_for


def L(src, sid, title, price):
    return Listing(source=src, source_id=sid, title=title, price=price)


def test_parse_numbers():
    assert parse_int("₹1,699.00") == 1699
    assert parse_int("(10,111)") == 10111
    assert parse_int(None) is None
    assert parse_float("4.1 out of 5 stars") == 4.1


def test_matcher_pairs_same_sku_and_rejects_other_brand():
    amz = [
        L("amazon", "A1", "Orient Electric Apex-FX 1200mm Ceiling Fan (Brown)", 1699),
        L("amazon", "A2", "Havells Stealth Air 1200mm Ceiling Fan", 2999),
    ]
    fk = [
        L("flipkart", "F1", "Crompton Surebreeze 1200 mm Ceiling Fan", 1599),
        L("flipkart", "F2", "Orient Electric Apex-FX 1200 mm Ultra High Speed 3 Blade Ceiling Fan", 1850),
    ]
    pairs = matcher.pair(amz, fk)
    assert (amz[0], fk[1]) in pairs
    assert (amz[1], None) in pairs
    assert (None, fk[0]) in pairs


def test_matcher_model_numbers_matter():
    a = "Samsung Galaxy S24 5G 256GB"
    assert matcher.score(a, "Samsung Galaxy S24 5G 256GB Onyx Black") > matcher.score(a, "Samsung Galaxy S23 5G 128GB")


def test_category_routing():
    assert category_for("ceiling fan") == "fan"
    assert category_for("boat earbuds") == "headphones"
    assert category_for("iphone 15") == "mobile"
    assert category_for("1.5 ton ac") == "ac"
    assert category_for("random thing") is None


def test_rate_card_minimum_and_growth():
    short = rides.rate_card_fare("rapido", "bike", 0.5, 2)
    long = rides.rate_card_fare("rapido", "bike", 14.2, 30)
    assert short["price"] == 25  # minimum fare
    assert long["price"] > short["price"]


def test_uber_type_mapping():
    assert rides.uber_type("Uber Go") == "cab"
    assert rides.uber_type("Premier") == "premium"
    assert rides.uber_type("Uber Auto") == "auto"
    assert rides.uber_type("Uber Moto") == "bike"


def test_uber_parsers():
    riders = {"prices": [{"display_name": "UberGo", "product_id": "p1", "low_estimate": 310, "high_estimate": 380, "duration": 1680}]}
    assert rides._parse_riders(riders) == [{"name": "UberGo", "product_id": "p1", "low": 310, "high": 380, "duration_min": 28}]
    guests = {"product_estimates": [{"product": {"display_name": "Uber Go", "product_id": "p2"},
                                     "estimate_info": {"fare": {"value": 322.5}, "pickup_estimate": 3,
                                                       "trip": {"duration_estimate": 1500}}}]}
    out = rides._parse_guests(guests)[0]
    assert out["low"] == 322 and out["pickup_min"] == 3 and out["duration_min"] == 25


def test_deeplinks():
    a, b = {"lat": 28.6, "lon": 77.2, "name": "CP"}, {"lat": 28.55, "lon": 77.1, "name": "Airport"}
    assert rides.deeplink("uber", a, b).startswith("https://m.uber.com/ul/?action=setPickup")
    assert "drop_lat=28.55" in rides.deeplink("ola", a, b)
