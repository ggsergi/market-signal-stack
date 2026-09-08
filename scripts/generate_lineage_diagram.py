"""Generate a Mermaid lineage diagram from target/manifest.json and write it into README.md.

Usage:
    uv run dbt docs generate          # refresh target/manifest.json first
    uv run python scripts/generate_lineage_diagram.py

Re-run after adding or renaming a model so the diagram in README.md stays in
sync with the actual dbt DAG, instead of a hand-drawn diagram going stale.
"""

import json
import re
import sys
from pathlib import Path

PROJECT_ROOT = Path(__file__).resolve().parent.parent
MANIFEST_PATH = PROJECT_ROOT / "target" / "manifest.json"
README_PATH = PROJECT_ROOT / "README.md"

# Subgraph display order; any layer not listed here (e.g. a future
# models/marts/ subfolder) is appended after these, alphabetically.
LAYER_ORDER = ["source", "staging", "marts"]

# --- Nodos fijos, NO generados desde el manifest ---
# Representan el destino físico del dataset y el consumidor externo (fuera del DAG de dbt).
# Editar aquí manualmente si cambia el destino o el consumidor.
FIXED_DOWNSTREAM_NODES = """
    marts --> market_signal_marts[("market_signal_marts<br/>(BigQuery)")]
    market_signal_marts --> agent["AI agent<br/>(consumer)"]
"""


def sanitize_id(name: str) -> str:
    """Mermaid node/subgraph ids can't contain dots or other punctuation."""
    return re.sub(r"[^0-9a-zA-Z_]", "_", name)


def load_manifest() -> dict:
    if not MANIFEST_PATH.exists():
        raise SystemExit(
            f"No se encontró {MANIFEST_PATH}. Corre `uv run dbt docs generate` primero."
        )
    with MANIFEST_PATH.open(encoding="utf-8") as f:
        return json.load(f)


def build_graph(manifest: dict) -> tuple[dict, list]:
    """Return (nodes, edges) from the manifest, excluding test nodes.

    nodes: node_id -> {"label": str, "layer": str}
    edges: list of (upstream_node_id, downstream_node_id)
    """
    nodes: dict = {}

    for source_id, source in manifest["sources"].items():
        nodes[source_id] = {"label": source["name"], "layer": "source"}

    for node_id, node in manifest["nodes"].items():
        if node["resource_type"] == "test":
            continue
        # fqn = [project_name, folder, ..., node_name] -> folder is the layer
        # (e.g. "staging", "marts"), matching the models/ directory structure.
        layer = node["fqn"][1] if len(node["fqn"]) > 2 else node["resource_type"]
        nodes[node_id] = {"label": node["name"], "layer": layer}

    edges = []
    for node_id, node in manifest["nodes"].items():
        if node["resource_type"] == "test":
            continue
        for upstream_id in node.get("depends_on", {}).get("nodes", []):
            if upstream_id in nodes:
                edges.append((upstream_id, node_id))

    return nodes, edges


def render_mermaid(nodes: dict, edges: list) -> str:
    layers: dict = {}
    for node_id, info in nodes.items():
        layers.setdefault(info["layer"], []).append(node_id)

    ordered_layers = sorted(
        layers,
        key=lambda layer: (
            LAYER_ORDER.index(layer) if layer in LAYER_ORDER else len(LAYER_ORDER),
            layer,
        ),
    )

    aliases = {node_id: sanitize_id(info["label"]) for node_id, info in nodes.items()}

    lines = ["flowchart LR"]
    for layer in ordered_layers:
        lines.append(f'    subgraph {sanitize_id(layer)}["{layer}"]')
        for node_id in sorted(layers[layer], key=lambda n: nodes[n]["label"]):
            alias = aliases[node_id]
            label = nodes[node_id]["label"]
            lines.append(f'        {alias}["{label}"]')
        lines.append("    end")

    for upstream_id, downstream_id in sorted(edges, key=lambda e: (nodes[e[0]]["label"], nodes[e[1]]["label"])):
        lines.append(f"    {aliases[upstream_id]} --> {aliases[downstream_id]}")

    generated = "\n".join(lines)
    return generated + FIXED_DOWNSTREAM_NODES.rstrip("\n")


def update_readme(mermaid_block: str) -> None:
    content = README_PATH.read_text(encoding="utf-8")
    pattern = re.compile(r"```mermaid\n.*?\n```", re.DOTALL)
    replacement = f"```mermaid\n{mermaid_block}\n```"
    new_content, count = pattern.subn(replacement, content, count=1)
    if count == 0:
        raise SystemExit("No se encontró ningún bloque ```mermaid en README.md para reemplazar.")
    README_PATH.write_text(new_content, encoding="utf-8")


def main() -> None:
    manifest = load_manifest()
    nodes, edges = build_graph(manifest)
    mermaid_block = render_mermaid(nodes, edges)
    update_readme(mermaid_block)
    print(mermaid_block)


if __name__ == "__main__":
    sys.exit(main())
