# KubeRay Demo

Provides a small demonstration of using the KubeRay. These instructions assume that you are using the correct K8s context and have already setup the KubeRay operator on your cluster.

First start off by deploying the RayCluster:

```sh
kubectl apply -f ray-cluster.demo.yaml
```

Once the cluster is running setup some local port forwarding in a separate terminal:
```
kubectl port-forward --address 0.0.0.0 service/raycluster-demo-head-svc 8265:8265
```

You can monitor activity on the cluster by visiting http://localhost:8265. Next we'll create our Python environment:

```sh
python3 -m venv demo-venv
source demo-venv/bin/activate
pip install -U "ray[default]==2.5.1" "pydantic<2"
```

I've noticed that the Ray CLI we build from source is missing the `ray job` subcommand which is something that needs to be looked into.

Next submit the job. Be sure to not put the virtual environment inside the demo directory as this results in unnecessary data being transferred to the cluster and may cause your job to fail:

```sh
ray job submit --address http://localhost:8265 --working-dir demo -- python demo.py
```
