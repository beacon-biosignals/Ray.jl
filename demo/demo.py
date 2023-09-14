"""
kubectl port-forward --address 0.0.0.0 service/raycluster-demo-head-svc 8265:8265

python3 -m venv demo-venv
source demo-venv/bin/activate
pip install -U "ray[default]==2.5.1" "pydantic<2"
ray job submit --address http://localhost:8265 --working-dir demo -- python demo.py
"""

import ray

@ray.remote
def f(x):
    return x

local_ref = ray.put(1)
return_ref = f.remote(local_ref)
print(ray.get(return_ref))
