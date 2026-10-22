"""Lower tessellation of the same fictional silhouettes, never decimated holes."""
import generate_traffic_models as g
import json
from pathlib import Path
g.BODY_STEPS=40;g.WHEEL_SEGMENTS=12
g.OUT=g.ROOT/'Assets/Traffic/Low';g.OUT.mkdir(exist_ok=True)
rows=[]
for p in g.PROFILES:
 rows.append(g.write_glb(p,[('Body',g.body(p)),('Wheel',g.wheel(p['wheel_radius']))]))
(g.ROOT/'Docs/traffic-low-metrics.json').write_text(json.dumps(rows,indent=2)+'\n')
print(rows)
