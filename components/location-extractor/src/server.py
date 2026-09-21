"""Location Extractor - the NLP microservice of the LocalNews demo app.

Takes a piece of text, finds the places mentioned in it with spaCy,
and turns those place names into coordinates.
"""

import json
import os
import random

import spacy
from flask import Flask, jsonify, request
from prometheus_client import Counter, Info, generate_latest

from src import geocode as geo

# --- the bit we change live on stage -----------------------------------
GREETING = "Lets go"
# -----------------------------------------------------------------------

VERSION = os.getenv("LOC_EXT_VERSION", "dev")

# Two stories about Berlin would otherwise land on the same pixel, so we
# scatter the markers a little. 0.3 degrees is roughly 30 km - enough to see
# them apart, small enough to stay in the right city.
JITTER = 0.3

COUNTER_LOCATIONS_EXTRACTED = Counter(
    "locations_extracted", "Number of extracted locations"
)
COUNTER_LOCATIONS_UNKNOWN = Counter(
    "locations_unknown", "Place names spaCy found but we could not geocode"
)
INFO_LOCATION_EXTRACTOR = Info(
    "location_extractor", "Information regarding the location extractor"
)
INFO_LOCATION_EXTRACTOR.info({"version": VERSION})

nlp = spacy.load("en_core_web_md")
geo.warm_up()

app = Flask(__name__)


@app.get("/")
def home():
    return jsonify(
        {
            "greeting": GREETING,
            "version": VERSION,
            "usage": '/get_loc?text="..."',
        }
    )


@app.get("/healthz")
def healthz():
    return jsonify({"status": "ok", "version": VERSION})


@app.get("/get_loc")
def get_coords():
    text = request.args.get("text", "")
    doc = nlp(text)
    print("Analyzing this text: " + doc.text, flush=True)

    names = [ent.text for ent in doc.ents if ent.label_ in ("GPE", "LOC")]

    if not names:
        print("Not found any location in this text", flush=True)
        return _json(_fallback())

    print("Those entities were recognized as locations: " + str(names), flush=True)

    found = {}
    for idx, name in enumerate(names):
        # Hack to simulate a worse-performing model in case of version v2
        if VERSION == "v2-worse-performance" and random.randint(0, 1) == 0:
            continue

        hit = geo.geocode(name)
        if not hit:
            print("no coordinates for this location: " + name, flush=True)
            COUNTER_LOCATIONS_UNKNOWN.inc()
            continue

        latitude, longitude, address = hit
        found[idx + 1] = {
            "extracted location": name,
            "generated address": address,
            "latitude": latitude + random.uniform(-JITTER, JITTER),
            "longitude": longitude + random.uniform(-JITTER, JITTER),
        }
        print("found lat & long for this location: " + name, flush=True)
        COUNTER_LOCATIONS_EXTRACTED.inc()

    return _json(found or _fallback())


def _fallback():
    """Nothing recognised - drop a marker somewhere in the ocean."""
    return {
        "1": {
            "extracted location": "none",
            "generated address": "Brisbane City, Queensland, Australia",
            "latitude": 0.4689682 - random.uniform(0.1, 5),
            "longitude": -30.0234991 + random.uniform(0.1, 5),
        }
    }


def _json(payload):
    return (
        json.dumps(payload),
        200,
        {"Content-Type": "application/json; charset=utf-8"},
    )


@app.get("/metrics")
def metrics():
    return generate_latest()


if __name__ == "__main__":
    app.run(host="0.0.0.0", port=5000, debug=True)
