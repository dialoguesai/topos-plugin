#!/usr/bin/env python3
"""Generate agentsmd/AGENTS.md from AGENTS_TEMPLATE.md and SKILL.md frontmatter,
validate the marketplaces against the discovered skills, and refresh the skills
table in README.md. Adapted from dialogues-skills/scripts/generate_agents.py.

This repo is ONE plugin carrying several skills (the dialogues-skills repo is
one plugin per skill), so marketplace validation checks that each marketplace
has exactly one entry named like the plugin with a root source, not one entry
per skill. Run with `python3 -I`. Stdlib only.
"""
from __future__ import annotations

import json
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
TEMPLATE_PATH = ROOT / "scripts" / "AGENTS_TEMPLATE.md"
OUTPUT_PATH = ROOT / "agentsmd" / "AGENTS.md"
CLAUDE_MANIFEST = ROOT / ".claude-plugin" / "plugin.json"
MARKETPLACES = {
    ROOT / ".claude-plugin" / "marketplace.json": ("./", "."),
    ROOT / ".cursor-plugin" / "marketplace.json": (".", "./"),
}
CODEX_MARKETPLACE = ROOT / ".agents" / "plugins" / "marketplace.json"
README_PATH = ROOT / "README.md"
README_TABLE_START = "<!-- BEGIN_SKILLS_TABLE -->"
README_TABLE_END = "<!-- END_SKILLS_TABLE -->"


def parse_frontmatter(text: str) -> dict[str, str]:
    match = re.search(r"^---\s*\n(.*?)\n---\s*", text, re.DOTALL)
    if not match:
        return {}
    data: dict[str, str] = {}
    for line in match.group(1).splitlines():
        if ":" not in line:
            continue
        key, value = line.split(":", 1)
        data[key.strip()] = value.strip()
    return data


def collect_skills() -> list[dict[str, str]]:
    skills = []
    for skill_md in ROOT.glob("skills/*/SKILL.md"):
        meta = parse_frontmatter(skill_md.read_text(encoding="utf-8"))
        name, description = meta.get("name"), meta.get("description")
        if not name or not description:
            continue
        if name != skill_md.parent.name:
            raise SystemExit(f"{skill_md}: frontmatter name {name!r} != directory {skill_md.parent.name!r}")
        skills.append({"name": name, "description": description, "path": skill_md.parent.relative_to(ROOT).as_posix()})
    return sorted(skills, key=lambda s: s["name"].lower())


def render(template: str, skills: list[dict[str, str]]) -> str:
    def repl(match: re.Match[str]) -> str:
        block = match.group(1).strip("\n")
        return "\n".join(
            block.replace("{{name}}", s["name"]).replace("{{description}}", s["description"]).replace("{{path}}", s["path"])
            for s in skills
        )

    return re.sub(r"{{#skills}}(.*?){{/skills}}", repl, template, flags=re.DOTALL)


def validate_marketplaces(plugin_name: str) -> list[str]:
    errors: list[str] = []
    for path, accepted_sources in MARKETPLACES.items():
        if not path.exists():
            errors.append(f"missing {path.relative_to(ROOT)}")
            continue
        data = json.loads(path.read_text(encoding="utf-8"))
        if data.get("name") != plugin_name:
            errors.append(f"{path.relative_to(ROOT)}: marketplace name {data.get('name')!r} != {plugin_name!r}")
        plugins = data.get("plugins", [])
        if len(plugins) != 1:
            errors.append(f"{path.relative_to(ROOT)}: expected exactly one plugin entry, found {len(plugins)}")
            continue
        entry = plugins[0]
        if entry.get("name") != plugin_name:
            errors.append(f"{path.relative_to(ROOT)}: entry name {entry.get('name')!r} != {plugin_name!r}")
        if entry.get("source") not in accepted_sources:
            errors.append(f"{path.relative_to(ROOT)}: entry source {entry.get('source')!r} must be one of {accepted_sources}")
        if "version" in entry:
            errors.append(f"{path.relative_to(ROOT)}: do not set version on the entry; plugin.json carries it")
    if CODEX_MARKETPLACE.exists():
        data = json.loads(CODEX_MARKETPLACE.read_text(encoding="utf-8"))
        plugins = data.get("plugins", [])
        if data.get("name") != plugin_name or len(plugins) != 1 or plugins[0].get("name") != plugin_name:
            errors.append(f"{CODEX_MARKETPLACE.relative_to(ROOT)}: expected marketplace and single entry named {plugin_name!r}")
        src = plugins[0].get("source") if plugins else None
        if not (isinstance(src, dict) and src.get("source") == "local" and src.get("path") in ("./", ".")):
            errors.append(f"{CODEX_MARKETPLACE.relative_to(ROOT)}: entry source must be {{source: local, path: ./}}")
    else:
        errors.append(f"missing {CODEX_MARKETPLACE.relative_to(ROOT)}")
    return errors


def readme_table(skills: list[dict[str, str]]) -> str:
    lines = ["| Skill | What it does | File |", "|---|---|---|"]
    for s in skills:
        lines.append(f"| `{s['name']}` | {s['description']} | [SKILL.md]({s['path']}/SKILL.md) |")
    return "\n".join(lines)


def update_readme(skills: list[dict[str, str]]) -> bool:
    if not README_PATH.exists():
        print("Warning: README.md not found", file=sys.stderr)
        return False
    content = README_PATH.read_text(encoding="utf-8")
    start, end = content.find(README_TABLE_START), content.find(README_TABLE_END)
    if start == -1 or end == -1 or end < start:
        print(f"Warning: README.md needs {README_TABLE_START} … {README_TABLE_END} markers", file=sys.stderr)
        return False
    new = content[: start + len(README_TABLE_START)] + "\n" + readme_table(skills) + "\n" + content[end:]
    if new != content:
        README_PATH.write_text(new, encoding="utf-8")
    return True


def main() -> None:
    plugin_name = json.loads(CLAUDE_MANIFEST.read_text(encoding="utf-8"))["name"]
    skills = collect_skills()
    if not skills:
        raise SystemExit("no skills found under skills/*/SKILL.md")
    OUTPUT_PATH.parent.mkdir(parents=True, exist_ok=True)
    output = render(TEMPLATE_PATH.read_text(encoding="utf-8"), skills)
    if not OUTPUT_PATH.exists() or OUTPUT_PATH.read_text(encoding="utf-8") != output:
        OUTPUT_PATH.write_text(output, encoding="utf-8")
    print(f"Wrote {OUTPUT_PATH.relative_to(ROOT)} with {len(skills)} skills.")
    errors = validate_marketplaces(plugin_name)
    if errors:
        print("Marketplace validation errors:", file=sys.stderr)
        for e in errors:
            print(f"  - {e}", file=sys.stderr)
        sys.exit(1)
    print("Marketplace validation passed.")
    if update_readme(skills):
        print(f"README.md skills table is current.")


if __name__ == "__main__":
    main()
