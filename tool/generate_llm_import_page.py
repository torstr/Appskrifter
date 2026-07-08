#!/usr/bin/env python3
"""Oppdaterer ingredienslisten i web/llm-import.html med gjeldende innhold fra
den sentrale ingredienslisten i Firestore.

Kjør denne før en deploy (`flutter build web && firebase deploy --only hosting`)
for å holde listen språkmodeller ser noenlunde fersk — den blir stående som den
var ved forrige deploy fram til dette skriptet kjøres på nytt og siden bygges/
deployes igjen.

Bruker samme autentiseringsteknikk som resten av prosjektets engangs-scripts:
gjenbruker den innloggede `firebase`-CLI-brukerens OAuth-refresh-token
(fra ~/.config/configstore/firebase-tools.json) sammen med firebase-tools sin
offentlig kjente CLI-klient-id/hemmelighet (samme for alle firebase-tools-
installasjoner, ingen hemmelig nøkkel som tilhører dette prosjektet) for å
hente et vanlig OAuth-access-token mot Firestores REST-API. Krever at du er
logget inn med `firebase login` som en bruker med lesetilgang til prosjektet.
"""

import json
import os
import re
import sys
import urllib.error
import urllib.parse
import urllib.request

PROJECT = "appskrifter"
BASE = f"https://firestore.googleapis.com/v1/projects/{PROJECT}/databases/(default)/documents"

CONFIG_PATH = os.path.expanduser("~/.config/configstore/firebase-tools.json")
FIREBASE_CLIENT_ID = "563584335869-fgrhgmd47bqnekij5i8b5pr03ho849e6.apps.googleusercontent.com"
FIREBASE_CLIENT_SECRET = "j9iVZfS8kkCEFUPaAeJV0sAi"

HTML_PATH = os.path.join(os.path.dirname(__file__), "..", "web", "llm-import.html")
START = "<!-- INGREDIENT_LIST_START -->"
END = "<!-- INGREDIENT_LIST_END -->"


def get_access_token():
    with open(CONFIG_PATH) as f:
        cfg = json.load(f)
    refresh_token = cfg["tokens"]["refresh_token"]
    data = urllib.parse.urlencode({
        "client_id": FIREBASE_CLIENT_ID,
        "client_secret": FIREBASE_CLIENT_SECRET,
        "refresh_token": refresh_token,
        "grant_type": "refresh_token",
    }).encode()
    req = urllib.request.Request("https://oauth2.googleapis.com/token", data=data, method="POST")
    with urllib.request.urlopen(req) as resp:
        return json.load(resp)["access_token"]


def fetch_all_ingredients(token):
    items = []
    page_token = None
    while True:
        path = "/ingredients?pageSize=300"
        if page_token:
            path += f"&pageToken={page_token}"
        r = urllib.request.Request(f"{BASE}{path}", headers={"Authorization": f"Bearer {token}"})
        try:
            with urllib.request.urlopen(r) as resp:
                data = json.load(resp)
        except urllib.error.HTTPError as e:
            print("Feil ved henting av ingredienser:", e.read().decode(), file=sys.stderr)
            raise
        for doc in data.get("documents", []):
            fields = doc["fields"]
            items.append({
                "name": fields["name"]["stringValue"],
                "category": fields["category"]["stringValue"],
            })
        page_token = data.get("nextPageToken")
        if not page_token:
            break
    items.sort(key=lambda i: i["name"].lower())
    return items


def main():
    token = get_access_token()
    items = fetch_all_ingredients(token)

    block = json.dumps(items, ensure_ascii=False, indent=2)
    snippet = f"{START}\n<pre>{block}</pre>\n{END}"

    with open(HTML_PATH, encoding="utf-8") as f:
        html = f.read()

    pattern = re.compile(re.escape(START) + r".*?" + re.escape(END), re.DOTALL)
    if not pattern.search(html):
        print(f"Fant ikke markørene {START} / {END} i {HTML_PATH}, ingen endring gjort.", file=sys.stderr)
        sys.exit(1)
    html = pattern.sub(snippet, html)

    with open(HTML_PATH, "w", encoding="utf-8") as f:
        f.write(html)
    print(f"Oppdaterte web/llm-import.html med {len(items)} ingredienser.")


if __name__ == "__main__":
    main()
