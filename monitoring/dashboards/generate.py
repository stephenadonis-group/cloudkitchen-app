#!/usr/bin/env python3
"""
Generates per-service Grafana dashboards as ConfigMaps for cloudkitchen.
One dashboard per microservice; each is auto-loaded by the kube-prometheus-stack
Grafana sidecar (watches for ConfigMaps with label grafana_dashboard=1 in any
namespace).

Run:   python3 generate.py  >  cloudkitchen-dashboards.yaml
Apply: kubectl apply -f cloudkitchen-dashboards.yaml
"""
import json, sys

SERVICES = [
    "auth-service", "user-service", "restaurant-service", "menu-service",
    "order-service", "payment-service", "delivery-service", "notification-service",
]

def dashboard(service: str) -> dict:
    """Build the dashboard JSON for one service."""
    return {
        "annotations": {"list": []},
        "editable": True,
        "fiscalYearStartMonth": 0,
        "graphTooltip": 1,
        "links": [],
        "liveNow": False,
        "panels": [
            # ---- Row 1: stats across the top ----
            stat(0, 0, 6, 4, "Requests / sec",
                 f'sum(rate(http_requests_total{{service="{service}"}}[5m]))', "reqps"),
            stat(6, 0, 6, 4, "Error rate (5xx)",
                 f'sum(rate(http_requests_total{{service="{service}",status=~"5.."}}[5m]))'
                 f' / clamp_min(sum(rate(http_requests_total{{service="{service}"}}[5m])), 1e-9)',
                 "percentunit"),
            stat(12, 0, 6, 4, "p95 latency",
                 f'histogram_quantile(0.95, sum by (le) (rate(http_request_duration_seconds_bucket{{service="{service}"}}[5m])))',
                 "s"),
            stat(18, 0, 6, 4, "Pods up",
                 f'count(up{{service="{service}"}} == 1)', "short"),

            # ---- Row 2: traffic ----
            timeseries(0, 4, 12, 8, "Requests / sec  by status",
                       [(f'sum by (status) (rate(http_requests_total{{service="{service}"}}[5m]))',
                         "{{status}}")], "reqps"),
            timeseries(12, 4, 12, 8, "Requests / sec  by path",
                       [(f'topk(5, sum by (path) (rate(http_requests_total{{service="{service}"}}[5m])))',
                         "{{path}}")], "reqps"),

            # ---- Row 3: latency percentiles ----
            timeseries(0, 12, 24, 8, "HTTP latency  (p50 / p95 / p99)",
                       [
                           (f'histogram_quantile(0.50, sum by (le) (rate(http_request_duration_seconds_bucket{{service="{service}"}}[5m])))', "p50"),
                           (f'histogram_quantile(0.95, sum by (le) (rate(http_request_duration_seconds_bucket{{service="{service}"}}[5m])))', "p95"),
                           (f'histogram_quantile(0.99, sum by (le) (rate(http_request_duration_seconds_bucket{{service="{service}"}}[5m])))', "p99"),
                       ], "s"),

            # ---- Row 4: pod resources ----
            timeseries(0, 20, 12, 8, "CPU usage  (cores, per pod)",
                       [(f'sum by (pod) (rate(container_cpu_usage_seconds_total{{namespace="cloudkitchen",pod=~"{service}.*",container!="",container!="POD"}}[5m]))',
                         "{{pod}}")], "short"),
            timeseries(12, 20, 12, 8, "Memory  (MiB, per pod)",
                       [(f'sum by (pod) (container_memory_working_set_bytes{{namespace="cloudkitchen",pod=~"{service}.*",container!="",container!="POD"}}) / 1024 / 1024',
                         "{{pod}}")], "decmbytes"),

            # ---- Row 5: logs (Loki) ----
            logs(0, 28, 24, 10, f'Logs  (Loki)',
                 f'{{namespace="cloudkitchen", app="{service}"}}'),
        ],
        "refresh": "30s",
        "schemaVersion": 39,
        "tags": ["cloudkitchen", service],
        "time": {"from": "now-1h", "to": "now"},
        "title": f"CloudKitchen / {service}",
        "uid": f"ck-{service}",
        "version": 1,
        "weekStart": "",
    }

def _grid(x, y, w, h):
    return {"h": h, "w": w, "x": x, "y": y}

def stat(x, y, w, h, title, expr, unit):
    return {
        "id": _id(), "type": "stat", "title": title, "gridPos": _grid(x, y, w, h),
        "datasource": {"type": "prometheus", "uid": "prometheus"},
        "targets": [{"expr": expr, "refId": "A", "datasource": {"type": "prometheus", "uid": "prometheus"}}],
        "fieldConfig": {"defaults": {"unit": unit, "color": {"mode": "thresholds"},
                                     "thresholds": {"mode": "absolute", "steps": [
                                         {"color": "green", "value": None},
                                         {"color": "yellow", "value": 1},
                                         {"color": "red", "value": 5},
                                     ]}}, "overrides": []},
        "options": {"colorMode": "value", "graphMode": "area",
                    "justifyMode": "center", "orientation": "auto",
                    "reduceOptions": {"calcs": ["lastNotNull"], "fields": "", "values": False}},
    }

def timeseries(x, y, w, h, title, targets, unit):
    return {
        "id": _id(), "type": "timeseries", "title": title, "gridPos": _grid(x, y, w, h),
        "datasource": {"type": "prometheus", "uid": "prometheus"},
        "targets": [{"expr": e, "legendFormat": l, "refId": chr(65 + i),
                     "datasource": {"type": "prometheus", "uid": "prometheus"}}
                    for i, (e, l) in enumerate(targets)],
        "fieldConfig": {"defaults": {"unit": unit, "custom": {"drawStyle": "line",
                                                              "lineWidth": 1, "fillOpacity": 10,
                                                              "showPoints": "never"}},
                        "overrides": []},
        "options": {"legend": {"displayMode": "list", "placement": "bottom",
                               "showLegend": True, "calcs": []},
                    "tooltip": {"mode": "multi", "sort": "desc"}},
    }

def logs(x, y, w, h, title, expr):
    return {
        "id": _id(), "type": "logs", "title": title, "gridPos": _grid(x, y, w, h),
        "datasource": {"type": "loki", "uid": "loki"},
        "targets": [{"expr": expr, "refId": "A",
                     "datasource": {"type": "loki", "uid": "loki"}}],
        "options": {"showTime": True, "showLabels": False, "showCommonLabels": False,
                    "wrapLogMessage": False, "prettifyLogMessage": False,
                    "enableLogDetails": True, "dedupStrategy": "none",
                    "sortOrder": "Descending"},
    }

_n = [0]
def _id():
    _n[0] += 1
    return _n[0]

def configmap(service: str) -> str:
    """Wrap a dashboard in a ConfigMap. The grafana_dashboard=1 label is what
    triggers Grafana's sidecar to auto-load it."""
    name = f"grafana-dashboard-{service}"
    body = {
        "apiVersion": "v1", "kind": "ConfigMap",
        "metadata": {"name": name, "namespace": "monitoring",
                     "labels": {"grafana_dashboard": "1",
                                "app.kubernetes.io/part-of": "cloudkitchen-dashboards"}},
        "data": {f"{service}.json": json.dumps(dashboard(service), indent=2)},
    }
    return _yaml(body)

def _yaml(obj) -> str:
    """Tiny YAML serializer — we keep the dashboard JSON as a literal block
    scalar so jsonpath in Grafana doesn't choke on quoting."""
    import io
    out = io.StringIO()
    out.write(f"apiVersion: {obj['apiVersion']}\n")
    out.write(f"kind: {obj['kind']}\n")
    out.write("metadata:\n")
    out.write(f"  name: {obj['metadata']['name']}\n")
    out.write(f"  namespace: {obj['metadata']['namespace']}\n")
    out.write("  labels:\n")
    for k, v in obj['metadata']['labels'].items():
        out.write(f'    {k}: "{v}"\n')
    out.write("data:\n")
    for k, v in obj['data'].items():
        out.write(f"  {k}: |\n")
        for line in v.splitlines():
            out.write(f"    {line}\n")
    return out.getvalue()

if __name__ == "__main__":
    print("# =============================================================================")
    print("# CloudKitchen per-service Grafana dashboards.")
    print("# Auto-loaded by the kube-prometheus-stack Grafana sidecar (label-watched).")
    print("# Apply:  kubectl apply -f cloudkitchen-dashboards.yaml")
    print("# Generated by observability/grafana-dashboards/generate.py — do NOT edit by hand.")
    print("# =============================================================================")
    for i, svc in enumerate(SERVICES):
        _n[0] = 0  # reset panel-id counter per dashboard
        if i > 0:
            print("---")
        sys.stdout.write(configmap(svc))
