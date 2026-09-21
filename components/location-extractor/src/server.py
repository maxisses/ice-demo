"""Location Extractor - the NLP microservice of the LocalNews demo app.

Takes a piece of text, finds the places mentioned in it with spaCy,
and turns those place names into coordinates with Nominatim.
"""

import json
import os
import random

import spacy
from flask import Flask, jsonify, request
from geopy.geocoders import Nominatim
from prometheus_client import Counter, Info, generate_latest

# --- the bit we change live on stage -----------------------------------
GREETING = "Hello from the ICE demo - built on OpenShift"
# -----------------------------------------------------------------------

VERSION = os.getenv("LOC_EXT_VERSION", "dev")

COUNTER_LOCATIONS_EXTRACTED = Counter(
    "locations_extracted", "Number of extracted locations"
)
INFO_LOCATION_EXTRACTOR = Info(
    "location_extractor", "Information regarding the location extractor"
)
INFO_LOCATION_EXTRACTOR.info({"version": VERSION})

nlp = spacy.load("en_core_web_md")

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

    locations = [
        ent.text for ent in doc.ents if ent.label_ in ("GPE", "LOC")
    ]

    if not locations:
        print("Not found any location in this text", flush=True)
        return _fallback(), 200, {"Content-Type": "application/json; charset=utf-8"}

    print("Those entities were recognized as locations: " + str(locations), flush=True)
    geolocator = Nominatim(user_agent="ice-demo-location-extractor")
    locs_dict = {}
    for idx, location in enumerate(locations):
        # Hack to simulate a worse-performing model in case of version v2
        if VERSION == "v2-worse-performance" and random.randint(0, 1) == 0:
            continue
        try:
            loc = geolocator.geocode(location)
            locs_dict[idx + 1] = {
                "extracted location": location,
                "generated address": loc.address,
                "latitude": loc.latitude - random.uniform(0.05, 2),
                "longitude": loc.longitude + random.uniform(0.05, 2),
            }
            print("found lat & long for this location: " + str(location), flush=True)
            COUNTER_LOCATIONS_EXTRACTED.inc(1)
        except Exception:
            print("not found lat & long for this location: " + str(location), flush=True)

    if not locs_dict:
        return _fallback(), 200, {"Content-Type": "application/json; charset=utf-8"}

    return (
        json.dumps(locs_dict),
        200,
        {"Content-Type": "application/json; charset=utf-8"},
    )


def _fallback():
    """Nothing recognised - drop a marker somewhere in the ocean."""
    return json.dumps(
        {
            "1": {
                "extracted location": "none",
                "generated address": "Brisbane City, Queensland, Australia",
                "latitude": 0.4689682 - random.uniform(0.1, 5),
                "longitude": -30.0234991 + random.uniform(0.1, 5),
            }
        }
    )


@app.get("/metrics")
def metrics():
    return generate_latest()


if __name__ == "__main__":
    app.run(host="0.0.0.0", port=5000, debug=True)
