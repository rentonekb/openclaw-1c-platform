#!/usr/bin/env python3
import json
import os
import subprocess
import sys
from pathlib import Path

REPO_ROOT = Path("/opt/openclaw/repo")
MANIFEST_PATH = REPO_ROOT / "founder" / "manifest.json"

def run_cmd(cmd, cwd=None, env=None, check=True):
    print(f"[founder] RUN: {' '.join(cmd)}")
    result = subprocess.run(
        cmd,
        cwd=cwd,
        env=env or os.environ.copy(),
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        text=True
    )
    print(result.stdout)
    if check and result.returncode != 0:
        raise RuntimeError(f"Command failed: {' '.join(cmd)}")
    return result

def load_manifest():
    if not MANIFEST_PATH.exists():
        raise FileNotFoundError(f"Manifest not found: {MANIFEST_PATH}")
    with MANIFEST_PATH.open("r", encoding="utf-8") as f:
        return json.load(f)

def check_gate(gate: str) -> bool:
    # Примитивная реализация для двух типов gate'ов:
    # "docker version >= 24.0" и "url http://..."
    gate = gate.strip()
    if gate.startswith("docker version"):
        try:
            res = run_cmd(["docker", "version", "--format", "{{.Server.Version}}"], check=False)
            version = res.stdout.strip()
            print(f"[founder] Docker version detected: {version}")
            # Тут можно добавить реальное сравнение версий
            return bool(version)
        except Exception as e:
            print(f"[founder] Docker gate failed: {e}")
            return False

    if gate.startswith("clickhouse ") or gate.startswith("grafana ") or gate.startswith("portainer "):
        parts = gate.split()
        if len(parts) >= 2:
            url = parts[1]
            try:
                res = run_cmd(["curl", "-s", "-o", "/dev/null", "-w", "%{http_code}", url], check=False)
                code = res.stdout.strip()
                print(f"[founder] Gate {gate} HTTP {code}")
                return code.startswith("2") or code.startswith("3")
            except Exception as e:
                print(f"[founder] HTTP gate failed: {e}")
                return False
    print(f"[founder] Unknown gate type: {gate}")
    return False

def run_static_agent(agent_id: str, source: str):
    agent_dir = REPO_ROOT / source
    agent_cfg = agent_dir / "agent.json"
    if not agent_cfg.exists():
        raise FileNotFoundError(f"agent.json not found for static agent {agent_id} in {agent_dir}")
    with agent_cfg.open("r", encoding="utf-8") as f:
        cfg = json.load(f)
    entry = cfg.get("entrypoint")
    if not entry:
        raise RuntimeError(f"Static agent {agent_id} has no entrypoint")
    entry_path = agent_dir / entry
    if not entry_path.exists():
        raise FileNotFoundError(f"Entrypoint {entry} not found for agent {agent_id}")
    if entry_path.suffix == ".sh":
        run_cmd(["bash", str(entry_path)], cwd=str(agent_dir))
    elif entry_path.suffix == ".py":
        run_cmd(["python3", str(entry_path)], cwd=str(agent_dir))
    else:
        run_cmd([str(entry_path)], cwd=str(agent_dir))

def main():
    manifest = load_manifest()
    phases = manifest.get("phases", [])
    # сортируем по order, если есть
    phases_sorted = sorted(phases, key=lambda p: p.get("order", 0))
    print(f"[founder] Loaded {len(phases_sorted)} phases")

    for phase in phases_sorted:
        pid = phase.get("id")
        pname = phase.get("name")
        print(f"\n[founder] === Phase {pid} ({pname}) ===")

        # запустить агентов фазы
        for agent in phase.get("agents", []):
            aid = agent.get("id")
            atype = agent.get("type")
            print(f"[founder] Agent {aid} type={atype}")
            if atype == "static":
                source = agent.get("source")
                if not source:
                    raise RuntimeError(f"Static agent {aid} has no source")
                run_static_agent(aid, source)
            else:
                print(f"[founder] Skipping non-static agent {aid} (template={agent.get('template')})")

        # проверить gates фазы, если есть
        gates = phase.get("gates", [])
        for gate in gates:
            print(f"[founder] Checking gate: {gate}")
            if not check_gate(gate):
                print(f"[founder] Gate FAILED: {gate}")
                sys.exit(1)
        print(f"[founder] Phase {pid} completed")

    print("[founder] All phases completed successfully")

if __name__ == "__main__":
    main()
