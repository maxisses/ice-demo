from src.geocode import geocode


def test_picks_the_biggest_berlin():
    lat, lon, name = geocode("Berlin")
    assert name == "Berlin"
    assert 51.9 < lat < 53.2


def test_is_case_insensitive():
    assert geocode("denver") == geocode("Denver")


def test_country_falls_back_to_capital():
    assert geocode("Yemen")[2] == "Yemen"


def test_alias():
    assert geocode("U.S.")[2] == "United States"


def test_unknown_place_returns_none():
    assert geocode("Atletico") is None
