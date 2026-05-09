#!/usr/bin/env python3
"""Apply the ASO refresh — keywords, description, promotional text,
subtitle, and "What's New" — to a new App Store version on en-US + es-MX.

The current live version (v1.2 RELEASED) is locked: keywords/description
can only be edited on a version that's still editable. So this script:

  1. Looks for an editable App Store version (or creates v1.3 in
     PREPARE_FOR_SUBMISSION if none exists) — that automatically spawns
     a new editable AppInfo where the subtitle can change.
  2. PATCHes name + subtitle on the new editable AppInfoLocalization
     for en-US and es-MX.
  3. PATCHes keywords + description + promotional text + what's new on
     the new version's localizations for en-US and es-MX.
  4. Leaves screenshots, builds, and review submission untouched —
     `ship-to-testflight.sh --marketing 1.3 --auto-notes` attaches the
     new build, and `asc_submit_for_review.py` ships it for review.

Idempotent: re-running on an existing editable version PATCHes in place.
Pass `--target X.Y` to override the version string (default 1.3).
"""
from __future__ import annotations

import argparse
import json
import os
import sys
import time
import urllib.error
import urllib.parse
import urllib.request
from pathlib import Path

try:
    import jwt
except ImportError:
    sys.stderr.write("error: PyJWT not installed. run: pip3 install --user 'pyjwt[crypto]'\n")
    sys.exit(1)

ROOT = Path(__file__).resolve().parent.parent
CONFIG = ROOT / "scripts" / "asc-config.env"
API = "https://api.appstoreconnect.apple.com"

DEFAULT_TARGET_VERSION = "1.3"

# Per-locale copy. Keep the keyword strings ≤100 chars, no spaces after
# commas — Apple counts every byte.
LOCALES = {
    "en-US": {
        # appInfoLocalizations attributes
        "name": "Barrel Baseball",
        "subtitle": "AI Coach + Live Hitting Stats",   # 29 chars
        # appStoreVersionLocalizations attributes
        "keywords": (
            # 96 chars, 0 dupes with name/subtitle. Brand-name competitor
            # (gamechanger), 1.2-AI angle (swing), counting-stat
            # abbreviations, and tball/lineup for parent + coach searches.
            "gamechanger,scorekeeper,swing,mlb,rbi,tracker,at-bat,coach,softball,youth,ops,slg,obp,tball,lineup"
        ),
        "promotionalText": (
            "AI swing coach in your pocket. Tap once to log every at-bat — "
            "AVG, OBP, SLG, OPS update live. No accounts, no cloud, no noise."
        ),
        "description": (
            "Barrel is the fastest baseball stat tracker for coaches and parents — "
            "log every at-bat in one tap and watch AVG, OBP, SLG, and OPS update live.\n\n"
            "Built for travel, little league, and high-school dugouts where you don't "
            "have a free hand for a spreadsheet between innings.\n\n"
            "WHY YOU'LL LIKE IT\n"
            "• One tap per at-bat. 1B, 2B, 3B, HR, BB, K, stolen bases, RBIs — all one press away.\n"
            "• Live slash line. AVG, OBP, SLG, OPS recalculate the moment you log a result.\n"
            "• AI swing coach. Upload a photo or short clip of any swing — frame-by-frame feedback in seconds.\n"
            "• Counting stats, ready. AB, H, HR, RBI, BB, K, SB, GO, FO, LO — expand the grid when you want the detail.\n"
            "• Contact quality. Tag a hit as strong or weak to read how the ball came off the bat.\n"
            "• Full game log. Every at-bat is timestamped and grouped by day so you can scroll back through a whole season.\n"
            "• Recent form meter. See the last five at-bats at a glance — streaks and slumps, visible.\n"
            "• Undo and redo anything. Tapped the wrong button mid-inning? One press and it's gone.\n"
            "• Your whole roster. Add every player on the bench — numbers, positions, ages — and flip between them instantly.\n\n"
            "BUILT FOR THE DUGOUT\n"
            "No accounts. No ads. No tracking. Sign in with Apple if you want your session to follow you "
            "across reinstalls, or use a simple email fallback. Everything stays on your device.\n\n"
            "PRIVACY FIRST\n"
            "Barrel does not collect your data. No analytics. No third-party trackers. Your roster, "
            "at-bats, and game logs are stored locally on your iPhone.\n\n"
            "MADE FOR YOUTH, TRAVEL, AND REC LEAGUES\n"
            "If you coach a 9–12 team, track your kid's season, or just watch your own numbers tick up "
            "with every swing — this is the app.\n\n"
            "Find the sweet spot. Train for impact. Track. Improve. Dominate."
        ),
        "whatsNew": (
            "ASO refresh — clearer naming and faster discovery in the App Store.\n\n"
            "• Subtitle now highlights the AI swing coach.\n"
            "• Refreshed keywords so coaches and parents searching for a "
            "GameChanger alternative can actually find Barrel.\n"
            "• Description leads with what makes Barrel fastest: one tap per "
            "at-bat, live slash line, AI swing analysis, fully offline."
        ),
    },
    "es-MX": {
        "name": "Barrel Baseball",
        "subtitle": "Estadísticas y coach con IA",   # 27 chars
        "keywords": (
            # 95 chars. Competitor (gamechanger), DR/LATAM term (lidom),
            # AI angle (swing), MLB cross-locale, rbi universal.
            "gamechanger,bateo,promedio,turno,jugador,entrenador,liga,juvenil,softbol,ops,slg,obp,lidom,swing,mlb"
        ),
        "promotionalText": (
            "Coach de swing con IA en tu bolsillo. Un toque por turno — "
            "AVG, OBP, SLG, OPS en vivo. Sin cuentas, sin nube, sin ruido."
        ),
        "description": (
            "Barrel es el rastreador de estadísticas de béisbol más rápido para coaches y padres — "
            "registra cada turno al bate con un toque y mira AVG, OBP, SLG y OPS actualizarse en vivo.\n\n"
            "Hecho para ligas juveniles, travel y secundaria donde no tienes una mano libre para una "
            "hoja de cálculo entre entradas.\n\n"
            "POR QUÉ TE VA A GUSTAR\n"
            "• Un toque por turno al bate. 1B, 2B, 3B, HR, BB, K, bases robadas, RBIs — todo a un botón.\n"
            "• Línea de bateo en vivo. AVG, OBP, SLG, OPS se recalculan en el momento en que registras un resultado.\n"
            "• Coach de swing con IA. Sube una foto o un clip corto de cualquier swing — feedback cuadro a cuadro en segundos.\n"
            "• Estadísticas acumuladas, listas. AB, H, HR, RBI, BB, K, SB, GO, FO, LO — expande la grilla cuando quieras el detalle.\n"
            "• Calidad de contacto. Etiqueta un hit como fuerte o débil para leer cómo salió la bola del bate.\n"
            "• Bitácora completa de juego. Cada turno está marcado con hora y agrupado por día.\n"
            "• Medidor de forma reciente. Mira los últimos cinco turnos de un vistazo — rachas y bajones, visibles.\n"
            "• Deshacer y rehacer todo. ¿Tocaste el botón equivocado en plena entrada? Un toque y se borra.\n"
            "• Toda tu plantilla. Agrega cada jugador del banquillo — número, posición, edad — y cambia entre ellos al instante.\n\n"
            "HECHO PARA EL DUGOUT\n"
            "Sin cuentas. Sin anuncios. Sin tracking. Inicia sesión con Apple si quieres que tu sesión "
            "te siga entre reinstalaciones, o usa email como respaldo. Todo se queda en tu iPhone.\n\n"
            "PRIVACIDAD PRIMERO\n"
            "Barrel no recopila tus datos. Sin analítica. Sin rastreadores de terceros. Tu plantilla, "
            "turnos al bate y bitácoras de juego se guardan localmente en tu iPhone.\n\n"
            "PARA LIGAS JUVENILES, TRAVEL Y RECREATIVAS\n"
            "Si entrenas un equipo de 9–12 años, llevas la temporada de tu hijo, o solo quieres ver tus "
            "propios números subir con cada swing — esta es la app.\n\n"
            "Encuentra el punto perfecto. Entrena para el impacto. Registra. Mejora. Domina."
        ),
        "whatsNew": (
            "Renovación ASO — naming más claro y descubrimiento más rápido en el App Store.\n\n"
            "• El subtítulo ahora destaca al coach de swing con IA.\n"
            "• Palabras clave renovadas para que coaches y padres que buscan "
            "alternativa a GameChanger puedan encontrar Barrel.\n"
            "• Descripción que lidera con lo que hace a Barrel la más rápida: un toque "
            "por turno, slash line en vivo, análisis de swing con IA, totalmente sin conexión."
        ),
    },
}

EDITABLE_VERSION_STATES = {
    "PREPARE_FOR_SUBMISSION", "DEVELOPER_REJECTED", "REJECTED",
    "METADATA_REJECTED", "WAITING_FOR_REVIEW", "INVALID_BINARY",
}


def load_env(path: Path) -> dict:
    env = {}
    for line in path.read_text().splitlines():
        line = line.strip()
        if not line or line.startswith("#") or "=" not in line:
            continue
        k, _, v = line.partition("=")
        v = v.strip().strip('"').strip("'")
        v = os.path.expandvars(os.path.expanduser(v))
        env[k.strip()] = v
    return env


def make_token(key_id: str, issuer: str, key_path: str) -> str:
    with open(os.path.expanduser(key_path)) as f:
        key = f.read()
    now = int(time.time())
    return jwt.encode(
        {"iss": issuer, "iat": now, "exp": now + 20 * 60, "aud": "appstoreconnect-v1"},
        key, algorithm="ES256", headers={"kid": key_id, "typ": "JWT"},
    )


def api(method: str, path: str, token: str, body=None):
    url = f"{API}{path}" if path.startswith("/") else path
    data = None if body is None else json.dumps(body).encode()
    headers = {"Authorization": f"Bearer {token}", "Content-Type": "application/json"}
    req = urllib.request.Request(url, data=data, method=method, headers=headers)
    try:
        with urllib.request.urlopen(req, timeout=60) as r:
            raw = r.read()
            return r.status, (json.loads(raw) if raw else {})
    except urllib.error.HTTPError as e:
        body_text = e.read().decode(errors="replace")[:6000]
        try:
            return e.code, json.loads(body_text)
        except json.JSONDecodeError:
            return e.code, {"error": body_text}


def require(status: int, body, what: str):
    if status >= 300:
        raise SystemExit(f"ASC API error on {what} (status {status}): {json.dumps(body, indent=2)[:2000]}")
    return body


# ---------- versions ----------

def find_or_create_version(app_id: str, target_version: str, token: str, dry: bool) -> dict:
    """Return an editable App Store version. Reuses one if found at the
    target version, otherwise creates a fresh PREPARE_FOR_SUBMISSION
    version with `target_version`.
    """
    q = urllib.parse.urlencode({"filter[versionString]": target_version, "limit": "5"})
    status, d = api("GET", f"/v1/apps/{app_id}/appStoreVersions?{q}", token)
    require(status, d, "list versions")
    for v in d.get("data", []):
        state = v["attributes"].get("appStoreState")
        if state in EDITABLE_VERSION_STATES:
            print(f"  reusing editable version {target_version} ({v['id']}, state={state})")
            return v

    # Look for any other editable version in case the user already started
    # work under a different version string.
    status, d_all = api("GET", f"/v1/apps/{app_id}/appStoreVersions?limit=20", token)
    require(status, d_all, "list all versions")
    for v in d_all.get("data", []):
        state = v["attributes"].get("appStoreState")
        ver = v["attributes"].get("versionString")
        if state in EDITABLE_VERSION_STATES:
            print(f"  reusing existing editable version {ver} ({v['id']}, state={state})")
            return v

    if dry:
        print(f"  [dry] would CREATE appStoreVersion {target_version}")
        return {"id": "DRY-RUN", "attributes": {"versionString": target_version}}

    print(f"  creating new App Store version {target_version} (PREPARE_FOR_SUBMISSION)")
    body = {
        "data": {
            "type": "appStoreVersions",
            "attributes": {
                "platform": "IOS",
                "versionString": target_version,
                "copyright": "© 2026 Divine Davis",
                "releaseType": "MANUAL",
            },
            "relationships": {
                "app": {"data": {"type": "apps", "id": app_id}}
            },
        }
    }
    status, d = api("POST", "/v1/appStoreVersions", token, body)
    require(status, d, f"create appStoreVersion {target_version}")
    return d["data"]


def list_version_localizations(version_id: str, token: str) -> list:
    status, d = api("GET", f"/v1/appStoreVersions/{version_id}/appStoreVersionLocalizations", token)
    require(status, d, "list version localizations")
    return d.get("data", [])


def patch_version_localization(loc_id: str, locale: str, copy: dict, token: str, dry: bool):
    body = {
        "data": {
            "type": "appStoreVersionLocalizations",
            "id": loc_id,
            "attributes": {
                "keywords": copy["keywords"],
                "description": copy["description"],
                "promotionalText": copy["promotionalText"],
                "whatsNew": copy["whatsNew"],
            },
        }
    }
    if dry:
        print(f"    [dry] would PATCH {locale} version-loc {loc_id} ({len(copy['keywords'])}-char keywords)")
        return
    status, d = api("PATCH", f"/v1/appStoreVersionLocalizations/{loc_id}", token, body)
    require(status, d, f"patch {locale} version localization")
    print(f"    ✓ {locale} version-loc updated ({len(copy['keywords'])}-char keywords)")


def create_version_localization(version_id: str, locale: str, copy: dict, token: str, dry: bool):
    if dry:
        print(f"    [dry] would CREATE {locale} version-loc")
        return
    body = {
        "data": {
            "type": "appStoreVersionLocalizations",
            "attributes": {
                "locale": locale,
                "keywords": copy["keywords"],
                "description": copy["description"],
                "promotionalText": copy["promotionalText"],
                "whatsNew": copy["whatsNew"],
            },
            "relationships": {
                "appStoreVersion": {"data": {"type": "appStoreVersions", "id": version_id}}
            },
        }
    }
    status, d = api("POST", "/v1/appStoreVersionLocalizations", token, body)
    require(status, d, f"create {locale} version localization")
    print(f"    ✓ {locale} version-loc created")


# ---------- AppInfo (subtitle / name) ----------

def find_editable_app_info(app_id: str, token: str) -> dict:
    """Return the editable AppInfo. After we create a new App Store
    version, ASC spawns a fresh AppInfo in PREPARE_FOR_SUBMISSION.
    """
    status, d = api("GET", f"/v1/apps/{app_id}/appInfos?limit=10", token)
    require(status, d, "list appInfos")
    for i in d.get("data", []):
        a = i["attributes"]
        # The AppInfo `state` flips to `READY_FOR_REVIEW` once it's
        # bundled into a submitted version. The editable one is anything
        # not yet `READY_FOR_DISTRIBUTION` / not currently live.
        state = a.get("state") or a.get("appStoreState")
        if state and state != "READY_FOR_DISTRIBUTION":
            return i
    raise SystemExit("no editable AppInfo found — did you create v1.3 first?")


def list_app_info_localizations(info_id: str, token: str) -> list:
    status, d = api("GET", f"/v1/appInfos/{info_id}/appInfoLocalizations", token)
    require(status, d, "list app info localizations")
    return d.get("data", [])


def patch_app_info_localization(loc_id: str, locale: str, copy: dict, token: str, dry: bool):
    body = {
        "data": {
            "type": "appInfoLocalizations",
            "id": loc_id,
            "attributes": {
                "name": copy["name"],
                "subtitle": copy["subtitle"],
            },
        }
    }
    if dry:
        print(f"    [dry] would PATCH {locale} appInfo-loc {loc_id} subtitle={copy['subtitle']!r}")
        return
    status, d = api("PATCH", f"/v1/appInfoLocalizations/{loc_id}", token, body)
    require(status, d, f"patch {locale} app info localization")
    print(f"    ✓ {locale} appInfo-loc updated (subtitle={copy['subtitle']!r})")


def create_app_info_localization(info_id: str, locale: str, copy: dict, token: str, dry: bool):
    if dry:
        print(f"    [dry] would CREATE {locale} appInfo-loc")
        return
    body = {
        "data": {
            "type": "appInfoLocalizations",
            "attributes": {
                "locale": locale,
                "name": copy["name"],
                "subtitle": copy["subtitle"],
            },
            "relationships": {
                "appInfo": {"data": {"type": "appInfos", "id": info_id}}
            },
        }
    }
    status, d = api("POST", "/v1/appInfoLocalizations", token, body)
    require(status, d, f"create {locale} app info localization")
    print(f"    ✓ {locale} appInfo-loc created")


# ---------- main ----------

def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("--target", default=DEFAULT_TARGET_VERSION,
                   help=f"target version string to apply metadata to (default: {DEFAULT_TARGET_VERSION})")
    p.add_argument("--dry-run", action="store_true",
                   help="print intended actions without hitting ASC")
    args = p.parse_args()

    if not CONFIG.exists():
        raise SystemExit(f"{CONFIG} not found.")
    env = load_env(CONFIG)
    for k in ("ASC_KEY_ID", "ASC_ISSUER_ID", "ASC_KEY_PATH", "ASC_APP_ID"):
        if not env.get(k):
            raise SystemExit(f"{k} not set in {CONFIG}")

    token = make_token(env["ASC_KEY_ID"], env["ASC_ISSUER_ID"], env["ASC_KEY_PATH"])
    app_id = env["ASC_APP_ID"]

    print(f"▸ resolving editable version (target={args.target})")
    version = find_or_create_version(app_id, args.target, token, args.dry_run)
    version_id = version["id"]
    vstr = version["attributes"].get("versionString", args.target)
    print(f"  using version {vstr} ({version_id})")

    print("▸ patching version localizations (keywords, description, promo, whatsNew)")
    if not args.dry_run:
        existing_locs = list_version_localizations(version_id, token)
        existing_by_locale = {l["attributes"]["locale"]: l["id"] for l in existing_locs}
    else:
        existing_by_locale = {}

    for locale, copy in LOCALES.items():
        loc_id = existing_by_locale.get(locale)
        if loc_id:
            patch_version_localization(loc_id, locale, copy, token, args.dry_run)
        else:
            create_version_localization(version_id, locale, copy, token, args.dry_run)

    print("▸ patching AppInfo localizations (name, subtitle)")
    if args.dry_run:
        print("  [dry] would resolve editable AppInfo + PATCH each locale")
    else:
        info = find_editable_app_info(app_id, token)
        info_id = info["id"]
        print(f"  editable AppInfo {info_id} (state={info['attributes'].get('state')})")
        info_locs = list_app_info_localizations(info_id, token)
        info_by_locale = {l["attributes"]["locale"]: l["id"] for l in info_locs}
        for locale, copy in LOCALES.items():
            iloc = info_by_locale.get(locale)
            if iloc:
                patch_app_info_localization(iloc, locale, copy, token, args.dry_run)
            else:
                create_app_info_localization(info_id, locale, copy, token, args.dry_run)

    print("\n✓ ASO metadata staged on version", vstr)
    print("  Next: ship a build at this version (`scripts/ship-to-testflight.sh")
    print(f"  --marketing {vstr} --auto-notes`) then submit for App Review.")


if __name__ == "__main__":
    main()
