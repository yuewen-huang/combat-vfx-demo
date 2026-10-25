"""Audit public registries, source dependencies and runnable example data without Godot."""
from pathlib import Path
import json,re,sys
from public_schema import EVENTS,GROUND,MODES,MATERIALS,FORMATIONS,RAMPS,validate_event
ROOT=Path(__file__).resolve().parents[1]
failures=[]
def expect(ok,message):
    if not ok:failures.append(message)

def audit():
    materials=(ROOT/'vfx/quake/materials.gd').read_text(encoding='utf-8')
    colours=materials.split('const COLORWAYS := {',1)[1].split('\n}',1)[0]
    expect(set(re.findall(r'^\s*"([a-z_]+)":',colours,re.M))==RAMPS,'colour registry differs from release contents')
    pieces=(ROOT/'vfx/swarm/materials.gd').read_text(encoding='utf-8')
    expect(set(re.findall(r'"([a-z_]+)"',pieces.split('const KEYS :=',1)[1].split('\n',1)[0]))==MATERIALS,'piece-material registry differs')
    forms=(ROOT/'vfx/swarm_effect.gd').read_text(encoding='utf-8')
    expect(set(re.findall(r'"([a-z_]+)"',forms.split('const FORMS :=',1)[1].split('\n',1)[0]))==FORMATIONS,'formation registry differs')
    top={'app_window','boot','caption_effect','claw_rake','claw_stage','combo_editor','combo_player','combo_stage','combo_style','editor_canvas','editor_catalog','editor_timeline','flow_document','flow_editor','flow_stage','gallery','impact','impact_effect','ink_stage','ink_stroke','magic_stage','pixel_slash','preview_context','quake_editor','quake_effect','quake_stage','render_caps','ribbon_stage','screen_loading','studio_editor','swarm_effect','trajectory_ribbon'}
    for path in (ROOT/'vfx').iterdir():
        if path.is_file() and path.suffix in {'.gd','.gdshader','.gdshaderinc'}:expect(path.stem in top,'unregistered top-level effect: '+path.name)
    count=0
    for path in ROOT.rglob('*'):
        if not path.is_file() or any(part in {'.git','.godot','verification','__pycache__'} for part in path.relative_to(ROOT).parts):continue
        if path.suffix not in {'.gd','.gdshader','.gdshaderinc','.tscn','.godot'}:continue
        text=path.read_text(encoding='utf-8-sig')
        for reference in re.findall(r'(?:res://)([^"\s\)]+)',text):
            if '%' in reference or '<' in reference or reference.endswith('/') or reference.endswith('+'):continue
            # Comments may document generic output directories; only concrete resources matter.
            if Path(reference).suffix not in {'.gd','.gdshader','.gdshaderinc','.tscn','.json'}:continue
            expect((ROOT/reference).is_file(),str(path.relative_to(ROOT))+': missing '+reference)
    for path in (ROOT/'combos').glob('*/combo.json'):
        data=json.loads(path.read_text(encoding='utf-8-sig'))
        for event in data.get('events',[]):
            error=validate_event(event);expect(error is None,str(path.relative_to(ROOT))+': '+str(error));count+=1
        for node in data.get('_flow',{}).get('nodes',[]):
            for event in node['data']['events']:
                error=validate_event(event);expect(error is None,'graph node: '+str(error))
    expect((ROOT/'LICENSE').read_text(encoding='utf-8').find('PolyForm Noncommercial')>=0,'license missing')
    if failures:
        print('\n'.join('FAIL: '+message for message in failures));return 1
    print(f'PASS: public registries, local resource dependencies, license and {count} authored events');return 0
if __name__=='__main__':sys.exit(audit())
