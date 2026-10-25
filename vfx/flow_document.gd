extends RefCounted
## A DAG schedules move starts. Compiled event data remains ordinary, editable combo JSON.
const Catalog = preload("res://vfx/editor_catalog.gd")
const AUX := ["camera","caption","impact"]

static func empty(title := "新多技能演出") -> Dictionary:
	return {"version":1,"name":title,"nodes":[],"edges":[]}

static func span(node: Dictionary) -> float:
	if float(node.get("span",-1))>=0: return float(node.span)
	var last := 0.1
	for e: Dictionary in node.data.get("events",[]):
		last = maxf(last,float(e.get("t",0))+Catalog.duration(e,String(node.style.get("renderer",""))))
	return last

static func schedule(graph: Dictionary) -> Dictionary:
	var starts := {}
	var nodes := {}
	var waiting: Array = []
	for node: Dictionary in graph.get("nodes",[]):
		if nodes.has(String(node.id)): return {"error":"招式节点标识重复"}
		nodes[String(node.id)] = node
		waiting.append(String(node.id))
	for edge: Dictionary in graph.get("edges",[]):
		if not nodes.has(String(edge.from)) or not nodes.has(String(edge.to)): return {"error":"连线引用了已不存在的节点"}
	while not waiting.is_empty():
		var advanced := false
		for id: String in waiting.duplicate():
			var ready := true
			var at := 0.0
			for edge: Dictionary in graph.get("edges",[]):
				if String(edge.to)!=id: continue
				if not starts.has(String(edge.from)):
					ready = false
					break
				var parent: Dictionary = nodes[String(edge.from)]
				at = maxf(at,float(starts[String(edge.from)])+(0.0 if nodes[id].get("join","after")=="with" else span(parent)))
			if ready:
				starts[id] = maxf(0.0,at+float(nodes[id].get("delay",0)))
				waiting.erase(id)
				advanced = true
		if not advanced: return {"error":"流程图不能形成循环，请断开回到前招的连线"}
	return {"starts":starts,"error":""}

static func compile(graph: Dictionary) -> Dictionary:
	var timing := schedule(graph)
	if not String(timing.get("error","")).is_empty(): return timing
	var events: Array = []
	for node: Dictionary in graph.get("nodes",[]):
		for raw: Dictionary in node.data.get("events",[]):
			var e := raw.duplicate(true)
			e.t = float(timing.starts[String(node.id)])+float(e.get("t",0))
			e["_flow_node"] = String(node.id)
			e["_flow_renderer"] = String(raw.get("_flow_renderer",node.style.get("renderer","")))
			e["_flow_style"] = raw.get("_flow_style",node.style).duplicate(true)
			e["_flow_order"] = events.size()
			events.append(e)
	events.sort_custom(func(a: Dictionary,b: Dictionary)->bool:return float(a.t)<float(b.t) if not is_equal_approx(float(a.t),float(b.t)) else int(a._flow_order)<int(b._flow_order))
	var compiled: Dictionary = graph.get("metadata",{}).duplicate(true)
	compiled.merge({"name":graph.get("name","多技能演出"),"events":events,"_flow":graph.duplicate(true),"starts":timing.starts,"error":""},true)
	return compiled

static func from_combo(data: Dictionary, style: Dictionary) -> Dictionary:
	if data.get("_flow") is Dictionary: return data._flow.duplicate(true)
	var graph := empty(String(style.get("title",data.get("name","多技能演出"))))
	graph["metadata"] = data.duplicate(true)
	graph.metadata.erase("events")
	var events: Array = data.get("events",[]).duplicate(true)
	events.sort_custom(func(a: Dictionary,b: Dictionary)->bool:return float(a.get("t",0))<float(b.get("t",0)))
	# Pair strikes with their nearby hits, and keep overlays beside their preceding action.
	var groups: Array = []
	for e: Dictionary in events:
		if e.has("_editor_source"):
			var owner: Array = []
			for group: Array in groups:
				if group[0].get("_editor_id")==e._editor_source: owner = group
			if not owner.is_empty():
				owner.append(e)
				continue
		if String(e.get("do","")) in AUX and not groups.is_empty():
			groups[-1].append(e)
		elif e.get("do")=="hit" and not groups.is_empty() and String(groups[-1][0].do) in ["slash","cast","cut"] and float(e.t)-float(groups[-1][0].t)<2.0:
			groups[-1].append(e)
		else: groups.append([e])
	for i in groups.size():
		var group: Array = groups[i]
		var start := float(group[0].get("t",0))
		for e: Dictionary in group:
			e.t = float(e.get("t",0))-start
			for key: String in ["_flow_node","_flow_renderer","_flow_style"]: e.erase(key)
		var id := "move_%d" % (i+1)
		var kind := String(group[0].do)
		var title: String = Catalog.NAMES[Catalog.KEYS.find(Catalog.kind_category(kind))]+" · "+String(preload("res://vfx/combo_editor.gd").DO_NAMES.get(kind,kind))
		graph.nodes.append({"id":id,"title":title,"category":Catalog.kind_category(kind),"data":{"name":title,"events":group},"style":style.duplicate(true),
			"position":[80+(i%4)*310,80+(i/4)*230],"delay":start if i==0 else 0.0,"join":"after","span":float(groups[i+1][0].get("t",0))-start if i+1<groups.size() else -1.0})
		if i>0: graph.edges.append({"from":"move_%d" % i,"to":id})
	return graph
