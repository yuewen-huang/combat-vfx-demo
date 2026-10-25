extends RefCounted
## Preview-only sources are constructed here; they never enter a saved move document.
static func prepare(local: Array, context: Array, start: float) -> Dictionary:
	var events: Array = local.duplicate(true)
	var sources: Array = []
	var note := "带入流程图的真实前置状态" if start>0 else ""
	var lead := start
	for event: Dictionary in events:
		if event.get("do")!="swarm":continue
		var form := String(event.get("form","cloud"))
		if form=="gone":
			var found := false
			for e: Dictionary in context:
				if e.get("do")=="swarm" and e.get("form")!="gone" and e.get("id")==event.get("id") and float(e.get("t",0))<start:found=true
			for e: Dictionary in events:
				if e.get("do")=="swarm" and e.get("form")!="gone" and e.get("id")==event.get("id") and float(e.get("t",0))<float(event.get("t",0)):found=true
			if not found:
				var cloud := event.duplicate(true)
				cloud.merge({"t":0.0,"form":"cloud","time":.1,"linger":6.0},true)
				sources.append(cloud)
				note = "预览用来源：临时群体，展示消散前状态（不写入作品）"
				lead = maxf(lead,.65)
	var timeline: Array = []
	for raw: Dictionary in context:
		var e := raw.duplicate(true)
		e.t = float(e.get("t",0))+lead-start
		timeline.append(e)
	for raw: Dictionary in sources: timeline.append(raw)
	for raw: Dictionary in events:
		var e := raw.duplicate(true)
		e.t = float(e.get("t",0))+lead
		timeline.append(e)
	timeline.sort_custom(func(a: Dictionary,b: Dictionary)->bool:return float(a.t)<float(b.t))
	return {"local":events,"timeline":timeline,"lead":lead,"note":note}
