"""Add a combo scene to the Godot project: combos/NAME/{NAME.tscn, combo.json, style.json}.

Usage:
  python new_combo.py NAME [--project DIR] [--combo combo.json] [--style style.json] [--prompt TEXT]
                         [--thickness thin|medium|bold|NUMBER] [--pixel N] [--title TEXT]
                         [--lang en|zh] [--palette NAME=HEX,HEX,HEX,HEX ...] [--color ROLE=HEX ...]
                         [--force]

--project defaults to this repository (itself a Godot project). Pointing it at another Godot
project copies the vfx/ scripts there first; pointing it at a new or empty folder makes a
fresh demo project there (project settings, gallery, vfx/). Without --combo the ember_launcher combo is
used; without --style, styles/default.json. Command-line options override the style file. The event format is in
references/combo_events.md; how to compose a combo from a request, references/choreography.md.
"""
from __future__ import annotations

import argparse
import json
import math
import re
import shutil
import sys
from pathlib import Path

SKILL = Path(__file__).resolve().parents[1]
NAME = re.compile(r"^[a-z][a-z0-9_]*$")
SCENE = """[gd_scene format=3]

[ext_resource type="Script" path="res://vfx/combo_player.gd" id="1"]

[node name="ComboPlayer" type="Node2D"]
script = ExtResource("1")
combo_file = "res://combos/{name}/combo.json"
style_file = "res://combos/{name}/style.json"
"""
THICKNESS = {"thin": 0.6, "medium": 1.0, "normal": 1.0, "bold": 1.4}
HEX = re.compile(r"^#?[0-9a-fA-F]{6}$")
ROLES = {"background", "ground", "outline", "flash", "dummy", "dummy_band", "blade", "marker_core", "text", "text_gold"}
PALETTES = {"normal", "violet", "red", "gold", "green"}
from public_schema import EVENTS, validate_event
# cast (the magic renderer, "renderer": "magic"): what it is and how it travels.
ELEMENTS = {"fire", "thunder", "ice", "wind", "sand"}
CAST_CHOICES = {"start": {"hand", "above", "sky", "behind", "self", "below", "target"}, "end": {"target", "ground", "self"},
                "path": {"straight", "arc", "wave", "spiral", "stay"}}
SHAPES = {"", "comet", "beam", "ring", "pillar", "vortex", "circle"}


def number(value) -> bool:
    return isinstance(value, (int, float)) and not isinstance(value, bool) and math.isfinite(value)


def point(value) -> bool:
    return isinstance(value, list) and len(value) == 2 and all(number(v) for v in value)


def endpoint(value, choices) -> bool:
    if isinstance(value, str):
        return value in choices
    return point(value) or (isinstance(value, list) and bool(value) and all(
        (isinstance(v, str) and v in choices) or point(v) for v in value))


def hex6(value: str) -> str:
    if not HEX.match(value.strip()):
        raise SystemExit(f"not a 6-digit hex colour: {value!r}")
    return value.strip().lstrip("#").lower()


def read_json(path: Path, what: str) -> dict:
    try:
        data = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as error:
        raise SystemExit(f"cannot read {what} {path}: {error}")
    if not isinstance(data, dict):
        raise SystemExit(f"{what} {path} must be a JSON object")
    return data


def check_combo(combo: dict) -> int:
    """Checks the event list; returns the number of hits."""
    events = combo.get("events")
    if not isinstance(events, list) or not events:
        raise SystemExit("combo.json needs a non-empty \"events\" list")
    for i, e in enumerate(events):
        where = f"event {i}"
        if not isinstance(e, dict) or e.get("do") not in EVENTS:
            raise SystemExit(f"{where}: \"do\" must be one of {', '.join(sorted(EVENTS))}")
        if not number(e.get("t")) or e["t"] < 0:
            raise SystemExit(f"{where}: \"t\" must be a number of seconds >= 0")
        if "palette" in e and e["palette"] not in PALETTES:
            raise SystemExit(f"{where}: palette must be one of {', '.join(sorted(PALETTES))}")
        if "by" in e and not (isinstance(e["by"], list) and len(e["by"]) == 2):
            raise SystemExit(f"{where}: \"by\" must be [x, y]")
        if e["do"] == "cast":
            if e.get("element", "fire") not in ELEMENTS:
                raise SystemExit(f"{where}: element must be one of {', '.join(sorted(ELEMENTS))}")
            for key, choices in CAST_CHOICES.items():
                if key not in e:
                    continue
                valid = endpoint(e[key], choices) if key in {"start", "end"} else isinstance(e[key], str) and e[key] in choices
                if not valid:
                    raise SystemExit(f"{where}: {key} must be one of {', '.join(sorted(choices))}")
            if not isinstance(e.get("shape", ""), str) or e.get("shape", "") not in SHAPES:
                raise SystemExit(f"{where}: unknown magic shape")
            if not isinstance(e.get("mix", []), list) or any(not isinstance(x, str) or x not in ELEMENTS for x in e.get("mix", [])):
                raise SystemExit(f"{where}: mix must be a list of known elements")
            for key in ("charge", "travel", "interval", "radius", "hold", "linger", "fuse"):
                if key in e and (not number(e[key]) or e[key] < 0):
                    raise SystemExit(f"{where}: {key} must be a finite non-negative number")
            for key in ("size", "swell", "ease"):
                if key in e and (not number(e[key]) or e[key] <= 0):
                    raise SystemExit(f"{where}: {key} must be positive")
            if "count" in e and (not number(e["count"]) or e["count"] < 1 or int(e["count"]) != e["count"]):
                raise SystemExit(f"{where}: count must be a positive integer")
            if "burst" in e and not isinstance(e["burst"], bool):
                raise SystemExit(f"{where}: burst must be true or false")
        if e["do"] == "camera":
            if not point(e.get("at", [640, 360])):
                raise SystemExit(f"{where}: camera at must be [x, y]")
            for key, default in (("zoom", 1), ("time", .5)):
                if not number(e.get(key, default)) or e.get(key, default) <= 0:
                    raise SystemExit(f"{where}: camera {key} must be positive")
    for i, event in enumerate(events):
        error = validate_event(event)
        if error: raise SystemExit(f"event {i}: {error}")
    hits = sum(1 for e in events if e["do"] == "hit")
    if hits == 0 and not any(e["do"] in {"quake","swarm","caption","impact","slash","cast","cut","charge"} for e in events):
        raise SystemExit("combo.json has no visible effect or hit")
    return hits


def main(argv=None) -> int:
    parser = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    parser.add_argument("name", help="snake_case folder and scene name, e.g. frost_swordsman")
    parser.add_argument("--project", type=Path, default=SKILL, help="Godot project folder (default: this repository)")
    parser.add_argument("--prompt", help="the request this combo was made from; saved as prompt.md")
    parser.add_argument("--combo", type=Path, default=SKILL / "combos" / "ember_launcher" / "combo.json")
    parser.add_argument("--style", type=Path, default=SKILL / "styles" / "default.json")
    parser.add_argument("--thickness")
    parser.add_argument("--pixel", type=int)
    parser.add_argument("--title")
    parser.add_argument("--lang", choices=["en", "zh"])
    parser.add_argument("--palette", action="append", default=[], metavar="NAME=HEX,HEX,HEX,HEX",
                        help="replace a slash palette (normal, violet, red, gold, green), brightest first")
    parser.add_argument("--color", action="append", default=[], metavar="ROLE=HEX")
    parser.add_argument("--force", action="store_true", help="replace an existing combos/NAME")
    args = parser.parse_args(argv)
    if not NAME.match(args.name):
        raise SystemExit("NAME must be snake_case: lowercase letters, digits and _")
    project = args.project.resolve()
    if not (project / "project.godot").is_file():
        if project.exists() and any(project.iterdir()):
            raise SystemExit(f"{project} is not a Godot project (no project.godot) and not empty")
        # A new demo project: project settings, the gallery and the vfx scripts.
        project.mkdir(parents=True, exist_ok=True)
        for name in ("project.godot", "main.tscn", "boot.tscn", "editor.tscn", "quake_editor.tscn", "flow_editor.tscn", "node_editor.tscn"):
            shutil.copy(SKILL / name, project / name)
        print(f"Created a new Godot project in {project}")

    combo = read_json(args.combo, "combo")
    contacts = check_combo(combo)
    style = read_json(args.style, "style")
    style.setdefault("colors", {})
    style.setdefault("palettes", {})
    if args.thickness:
        try:
            style["thickness"] = THICKNESS.get(args.thickness) or float(args.thickness)
        except ValueError:
            raise SystemExit("--thickness is thin, medium, bold or a number")
    if args.pixel:
        style["pixel"] = max(1, args.pixel)
    if args.title:
        style["title"] = args.title
    if args.lang:
        style["language"] = args.lang
    for item in args.palette:
        name, _, value = item.rpartition("=")
        name = name or "normal"
        if name not in PALETTES:
            raise SystemExit(f"unknown palette {name!r}; palettes: {', '.join(sorted(PALETTES))}")
        colours = [hex6(c) for c in value.split(",")]
        if len(colours) != 4:
            raise SystemExit("--palette needs 4 colours, brightest first")
        style["palettes"][name] = colours
    for item in args.color:
        role, _, value = item.partition("=")
        if role not in ROLES:
            raise SystemExit(f"unknown colour role {role!r}; roles: {', '.join(sorted(ROLES))}")
        style["colors"][role] = hex6(value)

    if project != SKILL.resolve() and not (project / "vfx" / "combo_player.gd").is_file():
        shutil.copytree(SKILL / "vfx", project / "vfx", dirs_exist_ok=True, ignore=shutil.ignore_patterns("*.uid"))
        print(f"Copied the vfx/ scripts into {project}")
    out = project / "combos" / args.name
    if out.exists():
        if not args.force:
            raise SystemExit(f"{out} exists; pass --force to replace it")
        shutil.rmtree(out)
    out.mkdir(parents=True)
    (out / "combo.json").write_text(json.dumps(combo, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
    (out / "style.json").write_text(json.dumps(style, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
    (out / f"{args.name}.tscn").write_text(SCENE.format(name=args.name), encoding="utf-8")
    if args.prompt:
        (out / "prompt.md").write_text(f"# {style.get('title', args.name)}\n\nPrompt:\n\n> {args.prompt}\n", encoding="utf-8")
    print(f"Created res://combos/{args.name}/{args.name}.tscn in {project}: {contacts} hits, "
          f"thickness {style.get('thickness', 1.0)}, pixel {style.get('pixel', 3)}.")
    print("Open the project in Godot 4.3+, open the scene and press F6 (it loops; 1/Space replay, 2 slow motion, R reset).")
    print(f'Check it: "{sys.executable}" "{Path(__file__).with_name("verify_combo.py")}" {args.name} --project "{project}" --gif [--godot PATH_TO_GODOT]')
    return 0


if __name__ == "__main__":
    sys.exit(main())
