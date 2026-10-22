import generate_traffic_models as g
import json
g.BODY_STEPS=60;g.WHEEL_SEGMENTS=18
g.OUT=g.ROOT/'Assets/Traffic/Medium';g.OUT.mkdir(exist_ok=True)
rows=[g.write_glb(p,[('Body',g.body(p)),('Wheel',g.wheel(p['wheel_radius']))]) for p in g.PROFILES]
(g.ROOT/'Docs/traffic-medium-metrics.json').write_text(json.dumps(rows,indent=2)+'\n')
print(rows)
