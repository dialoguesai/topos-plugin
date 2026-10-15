#!/usr/bin/env python3
"""Validate plugin.json and mcp.json against the vendored Agent Plugins 1.0.0 schemas,
and check every JSON manifest in the repo parses. Run with `python3 -I`. Stdlib only.

The validator covers the subset these two schemas use: type, properties, required,
additionalProperties (bool or schema), propertyNames, not, enum, const, pattern,
minLength, maxLength, items, oneOf, $ref (local). It is not a general JSON Schema
engine; `--jsonschema` uses the jsonschema package instead when it is installed.
`--refresh` re-downloads the schemas and reports a diff (network).
"""
from __future__ import annotations

import argparse
import json
import re
import sys
import urllib.request
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SCHEMA_DIR = ROOT / "schemas" / "agent-plugins-1.0.0"
CHECKS = {
    ROOT / "plugin.json": SCHEMA_DIR / "plugin.schema.json",
    ROOT / "mcp.json": SCHEMA_DIR / "mcp.schema.json",
}
LIVE = {
    "plugin.schema.json": "https://agent-plugins.org/schemas/1.0.0/plugin.schema.json",
    "mcp.schema.json": "https://agent-plugins.org/schemas/1.0.0/mcp.schema.json",
}
JSON_MANIFESTS = [
    "plugin.json", ".claude-plugin/plugin.json", ".claude-plugin/marketplace.json",
    ".cursor-plugin/plugin.json", ".cursor-plugin/marketplace.json", ".codex-plugin/plugin.json",
    ".agents/plugins/marketplace.json", "gemini-extension.json", ".mcp.json", "mcp.json",
    "mcp.cursor.json", "hooks/hooks.json", "hooks/cursor.hooks.json", "hooks/codex.hooks.json",
]


class Invalid(Exception):
    pass


def resolve_ref(root: dict, ref: str) -> dict:
    if not ref.startswith("#/"):
        raise Invalid(f"unsupported $ref {ref}")
    cur = root
    for part in ref[2:].split("/"):
        cur = cur[part]
    return cur


def check(instance, schema: dict, root: dict, path: str = "$") -> None:
    if "$ref" in schema:
        check(instance, resolve_ref(root, schema["$ref"]), root, path)
        return
    if "const" in schema and instance != schema["const"]:
        raise Invalid(f"{path}: expected const {schema['const']!r}")
    if "enum" in schema and instance not in schema["enum"]:
        raise Invalid(f"{path}: {instance!r} not in {schema['enum']}")
    if "not" in schema:
        try:
            check(instance, schema["not"], root, path)
        except Invalid:
            pass
        else:
            raise Invalid(f"{path}: {instance!r} matches a forbidden schema")
    if "oneOf" in schema:
        matches = 0
        errors = []
        for alt in schema["oneOf"]:
            try:
                check(instance, alt, root, path)
                matches += 1
            except Invalid as exc:
                errors.append(str(exc))
        if matches != 1:
            raise Invalid(f"{path}: matched {matches} of oneOf ({'; '.join(errors)[:300]})")
    t = schema.get("type")
    if t == "object":
        if not isinstance(instance, dict):
            raise Invalid(f"{path}: expected object")
        for req in schema.get("required", []):
            if req not in instance:
                raise Invalid(f"{path}: missing required {req!r}")
        props = schema.get("properties", {})
        for key, value in instance.items():
            if "propertyNames" in schema:
                check(key, schema["propertyNames"], root, f"{path}.{key} (name)")
            if key in props:
                check(value, props[key], root, f"{path}.{key}")
            else:
                ap = schema.get("additionalProperties", True)
                if ap is False:
                    raise Invalid(f"{path}: unexpected property {key!r}")
                if isinstance(ap, dict):
                    check(value, ap, root, f"{path}.{key}")
    elif t == "array":
        if not isinstance(instance, list):
            raise Invalid(f"{path}: expected array")
        if "items" in schema:
            for i, item in enumerate(instance):
                check(item, schema["items"], root, f"{path}[{i}]")
    elif t == "string":
        if not isinstance(instance, str):
            raise Invalid(f"{path}: expected string")
        if "minLength" in schema and len(instance) < schema["minLength"]:
            raise Invalid(f"{path}: shorter than {schema['minLength']}")
        if "maxLength" in schema and len(instance) > schema["maxLength"]:
            raise Invalid(f"{path}: longer than {schema['maxLength']}")
        if "pattern" in schema and not re.search(schema["pattern"], instance):
            raise Invalid(f"{path}: {instance!r} does not match {schema['pattern']}")


def validate(instance_path: Path, schema_path: Path, use_jsonschema: bool) -> bool:
    instance = json.loads(instance_path.read_text(encoding="utf-8"))
    schema = json.loads(schema_path.read_text(encoding="utf-8"))
    label = f"{instance_path.relative_to(ROOT)} vs {schema_path.name}"
    if use_jsonschema:
        try:
            import jsonschema  # type: ignore
        except ImportError:
            print(f"  {label}: jsonschema package not installed; using the built-in validator")
        else:
            try:
                jsonschema.Draft202012Validator(schema).validate(instance)
            except jsonschema.ValidationError as exc:  # type: ignore[attr-defined]
                print(f"  FAIL {label}: {exc.message}")
                return False
            print(f"  ok   {label} (jsonschema)")
            return True
    try:
        check(instance, schema, schema)
    except Invalid as exc:
        print(f"  FAIL {label}: {exc}")
        return False
    print(f"  ok   {label} (built-in validator)")
    return True


def refresh() -> int:
    rc = 0
    for name, url in LIVE.items():
        local = SCHEMA_DIR / name
        try:
            with urllib.request.urlopen(url, timeout=20) as resp:  # noqa: S310
                live = resp.read().decode("utf-8")
        except Exception as exc:  # noqa: BLE001
            print(f"  {name}: could not fetch {url}: {exc}")
            rc = 1
            continue
        same = json.loads(live) == json.loads(local.read_text(encoding="utf-8"))
        print(f"  {name}: {'identical to' if same else 'DIFFERS from'} {url}")
        if not same:
            rc = 1
    return rc


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--jsonschema", action="store_true", help="use the jsonschema package when available")
    ap.add_argument("--refresh", action="store_true", help="download the live schemas and diff them")
    a = ap.parse_args()
    ok = True
    print("JSON manifests parse:")
    for relpath in JSON_MANIFESTS:
        p = ROOT / relpath
        if not p.exists():
            print(f"  MISSING {relpath}")
            ok = False
            continue
        try:
            json.loads(p.read_text(encoding="utf-8"))
            print(f"  ok   {relpath}")
        except ValueError as exc:
            print(f"  FAIL {relpath}: {exc}")
            ok = False
    print("Agent Plugins 1.0.0 schema checks:")
    for inst, sch in CHECKS.items():
        ok = validate(inst, sch, a.jsonschema) and ok
    if a.refresh:
        print("Live schema refresh:")
        ok = refresh() == 0 and ok
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())
