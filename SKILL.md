---
name: combat-vfx-demo
description: Turn a plain-language combo description into a runnable Godot 4 demo of fighting-game sword VFX — crescent slash smears, star hit sparks, hit-stop, knockback, launch and slam, screen shake, a hit counter and a big finisher — e.g. "1st cut horizontal, 2nd vertical chop, 3rd rising, 4th spin, ultimate aerial combo; rhythm slow slow fast fast fast; black and red; medium width". Use it whenever someone wants to prototype or preview slash / sword-trail / combo / hit effects or combat rhythm and game feel, or asks for 刀光 / 连斩 / 招式节奏 / 打击感 / 顿帧 / 横斩竖劈上挑 effects, even if they never say "demo" or "Godot". Optional: moves, rhythm, colours, width, pixel size, language; anything unspecified uses defaults.
---

# Combo VFX demo

The user describes a combo in plain words; you compose it as a timed list of events
(`combo.json`) plus a look (`style.json`); the tools turn that into one scene in a Godot 4
project (`combos/<name>/<name>.tscn`) and check it. The renderer is already done — crescent smears that grow from the attacker,
star sparks, rings, hit-stop, knockback, launch/slam physics, screen shake. What makes each
demo good is the choreography you write: which way each cut swings, how the gaps breathe,
how hard each hit freezes, and how the finisher escalates.

## What the user may specify (and the defaults)

| Aspect | Example words | Default when not given |
|---|---|---|
| moves | 横斩 / horizontal, 竖劈 / vertical chop, 上挑 / rising, 突刺 / thrust, 旋转 / spin, 空中连斩 / aerial combo, 冲刺斩, 居合 / iaido … | three or four varied cuts ending in a launcher and a finisher |
| rhythm | 慢 慢 快快快 / slow slow fast fast fast, steady, accelerating | normal, accelerating toward the finisher |
| colours | 黑红 / black and red, ice blue, gold … | `styles/default.json` (steel blue); also `ember`, `neon`, `ink` presets |
| width | 细 / thin, 中等 / medium, 粗 / bold | medium (1.0) |
| pixel size | 细腻 / finer 2, 颗粒粗 / chunky 4–5, retro 6 | 3 |
| language | — | the language the user wrote in (`en` or `zh`) |
| title | a game or move-set name | a short name in the user's language (e.g. "黑红五连斩"); if it states a count, count `hit` events |

Don't ask about anything the user left out — use the default and mention it in the report.

## Workflow

1. **Read** `references/choreography.md` (how moves, rhythm, width and colours become events)
   and `references/combo_events.md` (the exact event fields, the stage coordinates, angles).
   `combos/*/` holds finished prompt → combo pairs (`prompt.md`, `combo.json`,
   `style.json`); learn from them, don't copy them.
2. **Write `combo.json`**: for each requested move, a `slash` (shape from the move), `move`s
   for lunges or jumps, and a `hit` 0.03–0.05 s after the slash; space the moves by the
   rhythm words; build the finisher bigger than everything before it. Draft both files in a
   scratch folder.
3. **Write `style.json`** (start from a preset in `styles/`): palettes from the colour words
   using the contrast rules, `thickness` from the width words, `language`, `title`.
4. **Generate** the scene. Pick a snake_case name for the combo and a project:
   the user's Godot project if they are working in one (the folder with `project.godot`),
   otherwise a new empty folder, which becomes a fresh demo project with a gallery.
   ```bash
   python <skill>/tools/new_combo.py <name> --project <godot_project> --combo combo.json --style style.json --prompt "<the user's request>" [--force]
   ```
   It validates the events (known `do`, numeric `t`, palette names, a visible effect or a `hit`),
   copies the `vfx/` scripts into the project if they are missing, and writes
   `combos/<name>/` with the scene, both JSON files and `prompt.md`. It refuses to replace an
   existing combo without `--force`.
5. **Verify** when Godot 4.3+ is available (`--godot PATH` if it is not `godot4`/`godot` on
   PATH or in `$GODOT`; on Windows use the `_console.exe` build):
   ```bash
   python <skill>/tools/verify_combo.py <name> --project <godot_project> --gif [--godot PATH]
   ```
   The headless self-test must print `PASS: N hits landed` with N = your number of `hit`
   events. Then open `verification/<name>/combo_sheet.png` (frames from start to finish in a grid)
   and check: each crescent swings the requested way and reaches the target, the slow/fast
   contrast is visible, launches and slams happen, the finisher clearly stands out, the
   colours read against the background. Fix the JSON and re-run if not.
   A fast string can fall between the sheet's tiles; `--keep-frames` keeps the frames so
   you can tile just that stretch (see the checklist in choreography.md). The run takes a
   few minutes on a slow machine; run it once, fix, then re-run.
   Without Godot, say so and give the user the command.
6. **Report**: folder, how each requested move/rhythm/colour/width was mapped (and what used
   defaults or was improvised), the self-test line, the GIF and sheet paths, and how to run
   it: open the project in Godot, open `combos/<name>/<name>.tscn` and press F6 (it loops;
   1/Space replay, 2 slow motion, R reset, Esc to the gallery). The scene also shows the
   stage in the editor without running.


## Public editor and environmental effects

For ground impacts or natural groups, read `references/public_effects.md`. Use only the documented event and material registry. Zero-hit visual scenes are supported. For sequential or parallel shows, use `references/multi_skill_flow.md`. The library routes editing through the move graph. Validate with `tools/verify_public.gd` and render with `tools/capture_public.gd`.
