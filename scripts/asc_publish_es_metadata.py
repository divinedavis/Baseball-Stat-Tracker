#!/usr/bin/env python3
"""Publish Spanish (Mexico / Latin America) localization metadata for the
current editable App Store version.

Adds — or updates in place — the es-MX appStoreVersionLocalization (description,
keywords, promotional text, what's new, URLs) and the es-MX appInfoLocalization
(localized name + subtitle). Idempotent: re-running PATCHes existing fields.

Picks `es-MX` because Apple does not offer `es-DO`; iOS maps Dominican Spanish
users to the Latin American Spanish listing automatically.

Usage:
    scripts/asc_publish_es_metadata.py                # push
    scripts/asc_publish_es_metadata.py --dry-run      # show what would change
    scripts/asc_publish_es_metadata.py --version 1.1  # target a specific version
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
    import jwt  # PyJWT
except ImportError:
    sys.stderr.write("error: PyJWT not installed. run: pip3 install --user 'pyjwt[crypto]'\n")
    sys.exit(1)

ROOT = Path(__file__).resolve().parent.parent
CONFIG = ROOT / "scripts" / "asc-config.env"
API = "https://api.appstoreconnect.apple.com"

LOCALE = "es-MX"
DEFAULT_VERSION = "1.1"

# ---- Spanish copy (review before shipping) ----

APP_INFO_COPY = {
    # 30 char max each. Brand name kept in English; subtitle is keyword-rich.
    "name": "Bball Tracker",
    "subtitle": "Estadísticas de béisbol",
}

VERSION_COPY = {
    "promotionalText": (
        "Encuentra el punto perfecto. Registra cada turno al bate con un toque — "
        "AVG, OBP, SLG, OPS en vivo. Sin cuentas, sin nube, sin ruido. "
        "Hecho para el dugout."
    ),
    "description": (
        "BARREL es la forma más rápida de capturar un turno al bate en juego real. "
        "Un toque — las estadísticas se actualizan al instante.\n\n"
        "Hecho para coaches, padres y jugadores que quieren números reales sin "
        "pelearse con una hoja de cálculo entre entradas.\n\n"
        "POR QUÉ TE VA A GUSTAR\n"
        "• Un toque por turno al bate. 1B, 2B, 3B, HR, BB, K, bases robadas, RBIs — todo a un botón.\n"
        "• Línea de bateo en vivo. AVG, OBP, SLG, OPS se recalculan en el momento que registras un resultado.\n"
        "• Estadísticas acumuladas, listas. AB, H, HR, RBI, BB, K, SB, GO, FO, LO — expande la grilla cuando quieras el detalle.\n"
        "• Calidad de contacto. Marca un hit como fuerte o débil para llevar lectura de cómo salió la pelota del bate.\n"
        "• Bitácora completa del juego. Cada turno al bate queda con hora y agrupado por día para que puedas mirar atrás toda una temporada.\n"
        "• Forma reciente. Mira los últimos cinco turnos al bate de un vistazo — rachas y bajones, visibles.\n"
        "• Deshacer y rehacer todo. ¿Tocaste el botón equivocado en plena entrada? Una pulsación y desaparece.\n"
        "• Tu roster completo. Agrega cada jugador del banco — números, posiciones, edades — y cambia entre ellos al instante.\n\n"
        "HECHO PARA EL DUGOUT\n"
        "Sin cuentas. Sin anuncios. Sin suscripción. Inicia sesión con Apple si quieres que tu sesión te siga "
        "entre reinstalaciones, o usa el correo. Todo se queda en tu dispositivo.\n\n"
        "PRIVACIDAD PRIMERO\n"
        "BARREL no recopila tus datos. Sin analítica. Sin rastreo. Tu roster, tus turnos al bate "
        "y tus registros de juego se guardan localmente en tu iPhone.\n\n"
        "HECHO PARA LIGAS JUVENILES, TRAVEL Y RECREATIVAS\n"
        "Si estás coacheando un equipo 9–12, llevando la temporada de tu hijo, o simplemente quieres ver "
        "tus propios números subir con cada swing — esta es la app.\n\n"
        "Encuentra el punto perfecto. Entrena para el impacto. Registra. Mejora. Domina."
    ),
    # 100 char max, comma-separated, NO spaces. Don't repeat title/subtitle terms.
    # "pelota" is DR slang for baseball ("vamos a jugar pelota") — important inclusion.
    "keywords": "pelota,bateo,promedio,turno,jugador,coach,liga,juvenil,scorebook,softbol,ops,slg,obp",
    "supportUrl": "https://github.com/divinedavis/Baseball-Stat-Tracker",
    "marketingUrl": "https://github.com/divinedavis/Baseball-Stat-Tracker",
    "whatsNew": (
        "Localización completa en español para usuarios de República Dominicana y toda Latinoamérica. "
        "Toca EN/ES en la pantalla de inicio para cambiar de idioma cuando quieras."
    ),
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
        key,
        algorithm="ES256",
        headers={"kid": key_id, "typ": "JWT"},
    )


def api(method: str, path: str, token: str, body=None, timeout=60):
    url = f"{API}{path}" if path.startswith("/") else path
    data = None if body is None else json.dumps(body).encode()
    headers = {"Authorization": f"Bearer {token}"}
    if data is not None:
        headers["Content-Type"] = "application/json"
    req = urllib.request.Request(url, data=data, method=method, headers=headers)
    try:
        with urllib.request.urlopen(req, timeout=timeout) as r:
            raw = r.read()
            return r.status, (json.loads(raw) if raw else {})
    except urllib.error.HTTPError as e:
        body_text = e.read().decode(errors="replace")[:6000]
        return e.code, {"error": body_text}


def require(status: int, body, what: str):
    if status >= 300:
        raise SystemExit(f"ASC API error on {what} (status {status}): {body}")
    return body


# ---------- App Store Version localization (description, keywords, what's new) ----------

def find_editable_version(app_id: str, version_string: str, token: str) -> dict | None:
    q = urllib.parse.urlencode({
        "filter[versionString]": version_string,
        "limit": "5",
    })
    status, d = api("GET", f"/v1/apps/{app_id}/appStoreVersions?{q}", token)
    require(status, d, "list versions")
    editable_states = {
        "PREPARE_FOR_SUBMISSION", "DEVELOPER_REJECTED", "REJECTED",
        "METADATA_REJECTED", "WAITING_FOR_REVIEW", "INVALID_BINARY",
    }
    for v in d.get("data", []):
        if v["attributes"].get("appStoreState") in editable_states:
            return v
    if d.get("data"):
        return d["data"][0]
    return None


def find_latest_valid_build(app_id: str, version_string: str, token: str) -> dict | None:
    """Latest VALID build for `version_string` (a marketing version), newest first."""
    q = urllib.parse.urlencode({
        "filter[app]": app_id,
        "filter[preReleaseVersion.version]": version_string,
        "filter[processingState]": "VALID",
        "sort": "-uploadedDate",
        "limit": "1",
    })
    status, d = api("GET", f"/v1/builds?{q}", token)
    require(status, d, "list builds")
    items = d.get("data", [])
    return items[0] if items else None


def create_app_store_version(app_id: str, version_string: str, build_id: str | None, token: str, dry: bool) -> dict:
    body = {
        "data": {
            "type": "appStoreVersions",
            "attributes": {
                "platform": "IOS",
                "versionString": version_string,
                # MANUAL: after Apple approves, the user clicks "Release" — no surprise auto-go-live.
                "releaseType": "MANUAL",
            },
            "relationships": {
                "app": {"data": {"type": "apps", "id": app_id}},
            },
        }
    }
    if build_id:
        body["data"]["relationships"]["build"] = {"data": {"type": "builds", "id": build_id}}
    if dry:
        print(f"  [dry] would CREATE appStoreVersion {version_string} (build={build_id or 'none'}, releaseType=MANUAL)")
        return {"id": "<new>", "attributes": {"versionString": version_string, "appStoreState": "PREPARE_FOR_SUBMISSION"}}
    status, d = api("POST", "/v1/appStoreVersions", token, body)
    require(status, d, "create app store version")
    print(f"  ✓ created App Store Version {version_string} ({d['data']['id']})")
    return d["data"]


def find_or_create_version_localization(version_id: str, token: str, dry: bool) -> dict:
    if dry and version_id == "<new>":
        print(f"  [dry] would CREATE {LOCALE} version localization on <new>")
        return {"id": "<new-loc>", "attributes": {"locale": LOCALE}}
    status, d = api("GET", f"/v1/appStoreVersions/{version_id}/appStoreVersionLocalizations", token)
    require(status, d, "list version localizations")
    for loc in d.get("data", []):
        if loc["attributes"].get("locale") == LOCALE:
            return loc
    if dry:
        print(f"  [dry] would CREATE {LOCALE} version localization on {version_id}")
        return {"id": "<new>", "attributes": {"locale": LOCALE}}
    body = {
        "data": {
            "type": "appStoreVersionLocalizations",
            "attributes": {"locale": LOCALE},
            "relationships": {
                "appStoreVersion": {"data": {"type": "appStoreVersions", "id": version_id}}
            },
        }
    }
    status, d = api("POST", "/v1/appStoreVersionLocalizations", token, body)
    require(status, d, "create version localization")
    print(f"  ✓ created {LOCALE} version localization {d['data']['id']}")
    return d["data"]


def patch_version_localization(loc_id: str, token: str, dry: bool):
    body = {
        "data": {
            "type": "appStoreVersionLocalizations",
            "id": loc_id,
            "attributes": VERSION_COPY,
        }
    }
    if dry:
        print(f"  [dry] would PATCH {LOCALE} version localization {loc_id}:")
        for k, v in VERSION_COPY.items():
            preview = v.replace("\n", " ⏎ ")[:120]
            print(f"      {k} ({len(v)} chars): {preview}{'...' if len(v) > 120 else ''}")
        return
    if loc_id == "<new-loc>":
        return  # only reachable via stacked dry-run paths
    status, d = api("PATCH", f"/v1/appStoreVersionLocalizations/{loc_id}", token, body)
    require(status, d, "patch version localization")
    print(f"  ✓ {LOCALE} version localization patched")


# ---------- App Info localization (localized name + subtitle) ----------

def find_editable_app_info(app_id: str, token: str) -> dict:
    """The appInfo record carries the localized name/subtitle. There can be
    multiple (one per state); we want the editable one."""
    status, d = api("GET", f"/v1/apps/{app_id}/appInfos", token)
    require(status, d, "list app infos")
    editable_states = {
        "PREPARE_FOR_SUBMISSION", "DEVELOPER_REJECTED", "REJECTED",
        "METADATA_REJECTED", "WAITING_FOR_REVIEW",
    }
    for info in d.get("data", []):
        if info["attributes"].get("appStoreState") in editable_states:
            return info
    if d.get("data"):
        return d["data"][0]
    raise SystemExit(f"no appInfo found for app {app_id}")


def find_or_create_app_info_localization(app_info_id: str, token: str, dry: bool) -> dict:
    status, d = api("GET", f"/v1/appInfos/{app_info_id}/appInfoLocalizations", token)
    require(status, d, "list app info localizations")
    for loc in d.get("data", []):
        if loc["attributes"].get("locale") == LOCALE:
            return loc
    if dry:
        print(f"  [dry] would CREATE {LOCALE} app info localization on {app_info_id}")
        return {"id": "<new>", "attributes": {"locale": LOCALE}}
    body = {
        "data": {
            "type": "appInfoLocalizations",
            "attributes": {"locale": LOCALE},
            "relationships": {
                "appInfo": {"data": {"type": "appInfos", "id": app_info_id}}
            },
        }
    }
    status, d = api("POST", "/v1/appInfoLocalizations", token, body)
    require(status, d, "create app info localization")
    print(f"  ✓ created {LOCALE} app info localization {d['data']['id']}")
    return d["data"]


def patch_app_info_localization(loc_id: str, token: str, dry: bool):
    body = {
        "data": {
            "type": "appInfoLocalizations",
            "id": loc_id,
            "attributes": APP_INFO_COPY,
        }
    }
    if dry:
        print(f"  [dry] would PATCH {LOCALE} app info localization {loc_id}:")
        for k, v in APP_INFO_COPY.items():
            print(f"      {k} ({len(v)} chars): {v}")
        return
    status, d = api("PATCH", f"/v1/appInfoLocalizations/{loc_id}", token, body)
    require(status, d, "patch app info localization")
    print(f"  ✓ {LOCALE} app info localization patched")


def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("--version", default=DEFAULT_VERSION, help=f"app store version to target (default: {DEFAULT_VERSION})")
    p.add_argument("--dry-run", action="store_true", help="print intended actions without hitting ASC")
    p.add_argument("--skip-app-info", action="store_true", help="only patch version localization, leave app name/subtitle alone")
    p.add_argument("--skip-version", action="store_true", help="only patch app info, leave version metadata alone")
    args = p.parse_args()

    if not CONFIG.exists():
        raise SystemExit(f"{CONFIG} not found.")
    env = load_env(CONFIG)
    for k in ("ASC_KEY_ID", "ASC_ISSUER_ID", "ASC_KEY_PATH", "ASC_APP_ID"):
        if not env.get(k):
            raise SystemExit(f"{k} not set in {CONFIG}")
    key_path = os.path.expanduser(env["ASC_KEY_PATH"])
    if not os.path.exists(key_path):
        raise SystemExit(f"ASC_KEY_PATH not found: {key_path}")

    token = make_token(env["ASC_KEY_ID"], env["ASC_ISSUER_ID"], key_path)
    app_id = env["ASC_APP_ID"]

    print(f"▸ target locale: {LOCALE}")
    print(f"▸ target version: {args.version}")
    print(f"▸ app: {app_id}")
    if args.dry_run:
        print("▸ DRY RUN — no writes")
    print()

    if not args.skip_version:
        print(f"▸ resolving editable version {args.version}")
        version = find_editable_version(app_id, args.version, token)
        if version is None:
            print(f"  no {args.version} version found — creating one")
            build = find_latest_valid_build(app_id, args.version, token)
            build_id = build["id"] if build else None
            if build:
                build_num = build["attributes"].get("version")
                print(f"  attaching build {args.version} ({build_num}) → {build_id}")
            else:
                print(f"  no VALID build for {args.version} yet; creating version without build")
            version = create_app_store_version(app_id, args.version, build_id, token, args.dry_run)
        version_id = version["id"]
        state = version["attributes"].get("appStoreState")
        print(f"  version {version_id} state={state}")

        loc = find_or_create_version_localization(version_id, token, args.dry_run)
        loc_id = loc["id"]
        print(f"  {LOCALE} version localization: {loc_id}")
        patch_version_localization(loc_id, token, args.dry_run)

    if not args.skip_app_info:
        print()
        print("▸ resolving editable app info (for localized name + subtitle)")
        info = find_editable_app_info(app_id, token)
        info_id = info["id"]
        print(f"  app info {info_id} state={info['attributes'].get('appStoreState')}")

        loc = find_or_create_app_info_localization(info_id, token, args.dry_run)
        loc_id = loc["id"]
        print(f"  {LOCALE} app info localization: {loc_id}")
        patch_app_info_localization(loc_id, token, args.dry_run)

    print()
    print("✓ done")


if __name__ == "__main__":
    main()
