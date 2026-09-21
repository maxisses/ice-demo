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
    body = res.get_json()
    assert body, "expected at least one location entry"


def test_get_loc_without_location_falls_back(client):
    res = client.get("/get_loc", query_string={"text": "Nothing to see here."})
    assert res.status_code == 200
    assert res.get_json()["1"]["extracted location"] == "none"
