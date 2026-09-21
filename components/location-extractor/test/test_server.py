"""Smoke tests that run inside the pipeline before we build the image."""

import pytest

from src.server import app


@pytest.fixture
def client():
    app.config["TESTING"] = True
    with app.test_client() as c:
        yield c


def test_home_returns_greeting(client):
    res = client.get("/")
    assert res.status_code == 200
    assert res.get_json()["greeting"]


def test_healthz(client):
    res = client.get("/healthz")
    assert res.status_code == 200
    assert res.get_json()["status"] == "ok"


def test_get_loc_finds_berlin(client):
    res = client.get("/get_loc", query_string={"text": "The game was played in Berlin."})
    assert res.status_code == 200
    entry = res.get_json()["1"]
    assert entry["extracted location"] == "Berlin"
    # Berlin, Germany - not one of the 27 other places called Berlin.
    assert 51.9 < entry["latitude"] < 53.2
    assert 12.8 < entry["longitude"] < 14.1


def test_get_loc_resolves_a_country_to_its_capital(client):
    res = client.get("/get_loc", query_string={"text": "Reports from Ukraine today."})
    assert res.get_json()["1"]["generated address"] == "Ukraine"


def test_get_loc_without_location_falls_back(client):
    res = client.get("/get_loc", query_string={"text": "Nothing to see here."})
    assert res.status_code == 200
    assert res.get_json()["1"]["extracted location"] == "none"
