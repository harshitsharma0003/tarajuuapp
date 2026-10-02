"""Pure-logic tests (no DB, no network). Run: python -m pytest tests -q"""
from app.scrapers.common import Listing, parse_float, parse_int
from app.services import matcher, rides, uber
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


def test_uber_estimates_parser():
    body = {"product_estimates": [
        {"product": {"display_name": "Uber Go", "product_id": "p2"},
         "estimate_info": {"fare_id": "f1", "fare": {"value": 322.5, "fare_id": "f1"}, "pickup_estimate": 3,
                           "trip": {"duration_estimate": 1500}},
         "fulfillment_indicator": "GREEN"},
        {"product": {"display_name": "Premier", "product_id": "p3"},
         "estimate_info": {"fare_id": "f2", "estimate": {"low_estimate": 400, "high_estimate": 460}}},
        {"product": {"display_name": "XL", "product_id": "p4"},
         "estimate_info": {"no_cars_available": True, "fare": {"value": 900}}},
    ]}
    out = uber.parse_estimates(body)
    assert [o["product_id"] for o in out] == ["p2", "p3"]  # no-cars product dropped
    go, premier = out
    assert go["low"] == 322 and go["fare_id"] == "f1" and go["pickup_min"] == 3 and go["duration_min"] == 25
    assert premier["low"] == 400 and premier["high"] == 460


def test_uber_trip_normalise():
    t = {"status": "accepted", "driver": {"name": "Ravi", "rating": 4.9, "phone_number": "+9100"},
         "vehicle": {"make": "Maruti", "model": "Dzire", "vehicle_color_name": "white", "license_plate": "DL1AB1234"},
         "location": {"latitude": 28.6, "longitude": 77.2, "bearing": 90}, "pickup": {"eta": 4},
         "rider_tracking_url": "https://trip.uber.com/x"}
    n = uber.normalise_trip(t)
    assert n["driver"]["name"] == "Ravi" and n["vehicle"]["plate"] == "DL1AB1234"
    assert n["driverLocation"] == {"lat": 28.6, "lon": 77.2, "bearing": 90} and n["pickupEtaMin"] == 4
    assert not n["terminal"] and uber.normalise_trip({"status": "completed"})["terminal"]


def test_deeplinks():
    a, b = {"lat": 28.6, "lon": 77.2, "name": "CP"}, {"lat": 28.55, "lon": 77.1, "name": "Airport"}
    assert rides.deeplink("uber", a, b).startswith("https://m.uber.com/ul/?action=setPickup")
    assert "drop_lat=28.55" in rides.deeplink("ola", a, b)
