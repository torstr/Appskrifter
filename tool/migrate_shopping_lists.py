#!/usr/bin/env python3
"""Engangsmigrering for «flere handlelister»-funksjonen (august 2026).

For hver husholdning som ikke allerede har en `shoppingLists`-underkolleksjon:
  1. Oppretter `households/{id}/shoppingLists/{ny}` («Hjemme», grønn farge),
     med `defaultServings`/`staples` kopiert fra husholdningens gamle felt
     (default 4 / tom liste hvis de ikke finnes).
  2. Kopierer alle dokumenter i `mealPlanItems` og `shoppingListItems` inn
     under den nye listen (samme dokument-id-er og innhold), og sletter
     originalene på husholdningsnivå.
`manualItemHistory` og husholdningens gamle `defaultServings`/`staples`-felt
røres ikke (se CLAUDE.md «Inkonsistenser» for hvorfor de sistnevnte blir
liggende urørt).

Idempotent: husholdninger som allerede har minst én `shoppingLists`-dokument
(f.eks. nyopprettede etter denne funksjonen ble lagt til) hoppes over.

Bruker samme autentiseringsteknikk som `generate_llm_import_page.py`: den
innloggede `firebase`-CLI-brukerens OAuth-refresh-token. Krever
`firebase login` med en bruker som har skrivetilgang til prosjektet.

Kjør med --dry-run for kun å se hva som ville skjedd, uten å skrive noe.
"""

import argparse
import datetime
import json
import os
import sys
import urllib.error
import urllib.parse
import urllib.request

PROJECT = "appskrifter"
BASE = f"https://firestore.googleapis.com/v1/projects/{PROJECT}/databases/(default)/documents"

CONFIG_PATH = os.path.expanduser("~/.config/configstore/firebase-tools.json")
FIREBASE_CLIENT_ID = "563584335869-fgrhgmd47bqnekij5i8b5pr03ho849e6.apps.googleusercontent.com"
FIREBASE_CLIENT_SECRET = "j9iVZfS8kkCEFUPaAeJV0sAi"


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


def _request(token, method, path, body=None):
    url = f"{BASE}{path}"
    data = json.dumps(body).encode() if body is not None else None
    req = urllib.request.Request(url, data=data, method=method, headers={
        "Authorization": f"Bearer {token}",
        "Content-Type": "application/json",
    })
    try:
        with urllib.request.urlopen(req) as resp:
            return json.load(resp) if resp.length != 0 else {}
    except urllib.error.HTTPError as e:
        print(f"Feil ved {method} {path}: {e.read().decode()}", file=sys.stderr)
        raise


def list_documents(token, path):
    """Henter alle dokumenter i en (under)kolleksjon, paginert."""
    docs = []
    page_token = None
    while True:
        query = "pageSize=300"
        if page_token:
            query += f"&pageToken={page_token}"
        data = _request(token, "GET", f"{path}?{query}")
        docs.extend(data.get("documents", []))
        page_token = data.get("nextPageToken")
        if not page_token:
            break
    return docs


def doc_id(doc):
    return doc["name"].rsplit("/", 1)[-1]


def migrate_household(token, household_doc, dry_run):
    household_id = doc_id(household_doc)
    fields = household_doc.get("fields", {})

    existing_lists = list_documents(token, f"/households/{household_id}/shoppingLists")
    if existing_lists:
        print(f"[{household_id}] har allerede {len(existing_lists)} handleliste(r) — hopper over.")
        return

    meal_plan_items = list_documents(token, f"/households/{household_id}/mealPlanItems")
    shopping_list_items = list_documents(token, f"/households/{household_id}/shoppingListItems")

    default_servings = fields.get("defaultServings", {}).get("integerValue", "4")
    staples = fields.get("staples", {}).get("arrayValue", {}).get("values", [])

    print(
        f"[{household_id}] oppretter «Hjemme» (defaultServings={default_servings}, "
        f"{len(staples)} standardvare(r)), flytter {len(meal_plan_items)} middagsplan-vare(r) og "
        f"{len(shopping_list_items)} handleliste-vare(r)."
    )
    if dry_run:
        return

    now = datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%S.%fZ")
    new_list = _request(token, "POST", f"/households/{household_id}/shoppingLists", {
        "fields": {
            "name": {"stringValue": "Hjemme"},
            "color": {"stringValue": "gronn"},
            "defaultServings": {"integerValue": default_servings},
            "staples": {"arrayValue": {"values": staples}},
            "createdAt": {"timestampValue": now},
        }
    })
    list_id = doc_id(new_list)

    for doc in meal_plan_items:
        item_id = doc_id(doc)
        _request(
            token, "PATCH",
            f"/households/{household_id}/shoppingLists/{list_id}/mealPlanItems/{item_id}",
            {"fields": doc.get("fields", {})},
        )
        _request(token, "DELETE", f"/households/{household_id}/mealPlanItems/{item_id}")

    for doc in shopping_list_items:
        item_id = doc_id(doc)
        _request(
            token, "PATCH",
            f"/households/{household_id}/shoppingLists/{list_id}/shoppingListItems/{item_id}",
            {"fields": doc.get("fields", {})},
        )
        _request(token, "DELETE", f"/households/{household_id}/shoppingListItems/{item_id}")

    print(f"[{household_id}] ferdig — ny liste-id: {list_id}")


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--dry-run", action="store_true", help="Vis hva som ville skjedd, uten å skrive noe.")
    parser.add_argument("--yes", action="store_true", help="Hopp over den interaktive bekreftelsen.")
    args = parser.parse_args()

    token = get_access_token()
    households = list_documents(token, "/households")
    print(f"Fant {len(households)} husholdning(er).")

    if not args.dry_run and not args.yes:
        confirm = input("Dette skriver og sletter ekte produksjonsdata. Fortsette? [skriv JA]: ")
        if confirm.strip() != "JA":
            print("Avbrutt.")
            sys.exit(1)

    for household_doc in households:
        migrate_household(token, household_doc, args.dry_run)

    print("Dry-run fullført, ingenting skrevet." if args.dry_run else "Migrering fullført.")


if __name__ == "__main__":
    main()
