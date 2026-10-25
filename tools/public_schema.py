"""Documented public effect registry shared by the scene generator and release audit."""
import math
EVENTS = {'slash','move','hit','charge','flash_step','cut','cast','camera','quake','swarm','caption','impact'}
GROUND = {'earth','ice','magma','magic','thunder','shadow','holy'}
MODES = {'radial','sweep','split','cone'}
MATERIALS = {'leaf','feather','sand'}
FORMATIONS = {'cloud','stream','vortex','sphere','burst','fall','gone'}
RAMPS = {'gold','violet','crimson','azure','jade','silver','abyss','autumn','ivory','dune'}

def validate_event(event):
    """Return an error string, or None. Existing melee and magic validation is separate."""
    if event.get('do') not in EVENTS:
        return 'event kind is not in the public registry'
    if not isinstance(event.get('t',0),(int,float)) or not math.isfinite(event.get('t',0)) or event.get('t',0)<0:
        return 't must be finite and nonnegative'
    kind=event['do']
    if kind=='quake':
        if event.get('unit','earth') not in GROUND:return 'unknown ground material'
        if event.get('mode','radial') not in MODES:return 'unknown ground propagation mode'
    if kind=='swarm':
        if event.get('material','leaf') not in MATERIALS:return 'unknown group material'
        if event.get('form','cloud') not in FORMATIONS:return 'unknown group formation'
        if not isinstance(event.get('id','group'),str):return 'group id must be a string'
        if not isinstance(event.get('count',6000),(int,float)) or not 1<=event.get('count',6000)<=16000:return 'group count must be between 1 and 16000'
        path=event.get('path',[])
        if not isinstance(path,list) or len(path)>12:return 'path must contain at most twelve points'
        if any(not isinstance(p,list) or len(p)!=2 or any(not isinstance(x,(int,float)) or not math.isfinite(x) for x in p) for p in path):return 'path points must be finite [x,y] pairs'
    if kind in {'quake','swarm'}:
        ramp=event.get('ramp','')
        if isinstance(ramp,str):
            if ramp and ramp not in RAMPS:return 'unknown public colour preset'
        elif isinstance(ramp,list):
            if len(ramp)!=5:return 'custom ramp needs five colours'
            for colour in ramp:
                try:
                    if not isinstance(colour,str) or len(colour.lstrip('#')) not in (6,8):return 'invalid custom colour'
                    int(colour.lstrip('#'),16)
                except ValueError:return 'invalid custom colour'
        else:return 'ramp must be a preset name or five colours'
    return None
