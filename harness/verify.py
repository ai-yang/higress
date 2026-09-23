"""Build/test/runtime orchestration. Local only; never pushes or calls GitHub."""
import argparse
import hashlib
import json
import os
import pathlib
import socket
import subprocess
import time
import urllib.request
import urllib.error

urllib.request.install_opener(urllib.request.build_opener(urllib.request.ProxyHandler({})))

BUILDER = "golang@sha256:ef5b4be1f94b36c90385abd9b6b4f201723ae28e71acacb76d00687333c17282"
PLUGIN = "plugins/wasm-go/extensions/response-cache"
HERE = pathlib.Path(__file__).resolve().parent
PROJECT = "response-cache-4569-20260923"


def run(command, output, env=None, expected=0):
    output.parent.mkdir(parents=True, exist_ok=True)
    start = time.monotonic()
    with output.open("wb") as log:
        result = subprocess.run(command, stdout=log, stderr=subprocess.STDOUT, env=env)
    print(f"{output.name}: exit={result.returncode} elapsed={time.monotonic()-start:.2f}s", flush=True)
    assert result.returncode == expected, f"See {output} (exit {result.returncode})"
    return result.returncode


def render(out, timeout):
    config = {"cache": {"type": "redis", "serviceName": "redis.static", "serviceHost": "redis-fixture", "servicePort": 6379,
                        "timeout": timeout, "cacheKeyPrefix": "higress-audit:"},
              "cacheKeyFromHeader": "x-http-cache-key", "cacheValueFromBodyType": "application/json"}
    out.write_text((HERE / "envoy.yaml.in").read_text().replace("@@PLUGIN_CONFIG@@", json.dumps(config)))


def ready():
    for _ in range(600):
        try:
            with urllib.request.urlopen("http://127.0.0.1:19470/ready", timeout=1) as response:
                if response.status == 200:
                    return
        except (OSError, urllib.error.URLError):
            pass
        time.sleep(0.1)
    raise RuntimeError("Envoy not ready within startup probe budget")


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--baseline-source", type=pathlib.Path, required=True)
    parser.add_argument("--fixed-source", type=pathlib.Path, required=True)
    parser.add_argument("--output", type=pathlib.Path, required=True)
    parser.add_argument("--cache", type=pathlib.Path, required=True)
    parser.add_argument("--stage", choices=["build", "runtime"], required=True)
    parser.add_argument("--smoke", action="store_true")
    args = parser.parse_args()
    out = args.output.resolve()
    out.mkdir(parents=True, exist_ok=True)
    args.cache.mkdir(parents=True, exist_ok=True)
    sources = {"baseline": args.baseline_source.resolve(), "fixed": args.fixed_source.resolve()}
    if args.stage == "build":
        metadata = {"builder": BUILDER, "sources": {}, "commands": []}
        for variant, source in sources.items():
            assert not subprocess.check_output(["git", "-C", str(source), "status", "--porcelain"]), "Dirty source"
            sha = subprocess.check_output(["git", "-C", str(source), "rev-parse", "HEAD"], text=True).strip()
            metadata["sources"][variant] = sha
            command = ["docker", "run", "--rm", "--network", "none", "--cpus", "3", "--memory", "3g",
                       "--user", f"{os.getuid()}:{os.getgid()}", "-e", "GOTOOLCHAIN=local",
                       "-e", "GOMAXPROCS=3",
                       "-e", "GOPATH=/cache/gopath", "-e", "GOMODCACHE=/cache/mod", "-e", "GOCACHE=/cache/build",
                       "-v", f"{args.cache.resolve()}:/cache", "-v", f"{source / PLUGIN}:/src:ro",
                       "-v", f"{out}:/evidence", "-w", "/src", BUILDER]
            build = f"go version && GOOS=wasip1 GOARCH=wasm go build -buildmode=c-shared -o /evidence/{variant}.wasm ./"
            run(command + ["sh", "-c", build], out / f"build-{variant}.log")
            metadata["commands"].append(build)
            metadata["sources"][variant + "_wasm_sha256"] = hashlib.sha256((out / f"{variant}.wasm").read_bytes()).hexdigest()
            if variant == "fixed":
                for name, cmd, wasm, expected in [
                    ("regression-red", "go test -run TestHeaderKeyLookupABI -count=1 -v ./...", "baseline", 1),
                    ("test", "go test ./... -count=1 -v", "fixed", 0),
                    ("race", "go test -race ./... -count=20 -timeout=3h -v", "fixed", 0),
                    ("vet", "go vet ./...", "fixed", 0),
                ]:
                    full = f"export WASM_FILE_PATH=/evidence/{wasm}.wasm; {cmd}"
                    run(command + ["sh", "-c", full], out / (name + ".log"), expected=expected)
                    metadata["commands"].append(full)
                red = (out / "regression-red.log").read_text()
                assert "expected: 0x4" in red and "actual  : 0x0" in red, "Red must fail for pause assertion"
        (out / "build.json").write_text(json.dumps(metadata, indent=2) + "\n")
        return

    # Prove these ports were not occupied before starting the isolated project.
    for port in (19468, 19469, 19470):
        with socket.socket() as sock:
            sock.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
            sock.bind(("127.0.0.1", port))
    for name, timeout in (("normal", 10000), ("timeout", 100)):
        render(out / f"envoy-{name}.yaml", timeout)
    compose = ["docker", "compose", "--project-name", PROJECT, "--file", str(HERE / "compose.yaml")]
    env = dict(os.environ)
    try:
        for variant, config in (("baseline", "normal"), ("fixed", "normal"), ("fixed", "timeout")):
            label = variant if config == "normal" else "fixed-timeout"
            logdir = out / ("smoke" if args.smoke else "runtime") / label
            env.update(ENVOY_CONFIG=str(out / f"envoy-{config}.yaml"), WASM_PATH=str(out / f"{variant}.wasm"))
            run(compose + ["up", "-d", "--force-recreate", "--wait"], logdir / "compose-up.log", env)
            try:
                ready()
                for endpoint in ("server_info", "stats", "clusters"):
                    with urllib.request.urlopen("http://127.0.0.1:19470/" + endpoint, timeout=3) as response:
                        (logdir / (endpoint + "-before.txt")).write_bytes(response.read())
                assert "outbound|6379||redis.static" in (logdir / "clusters-before.txt").read_text()
                cmd = ["python3", str(HERE / "driver.py"), "--variant", variant, "--output", str(logdir / "requests")]
                if args.smoke:
                    cmd.append("--smoke")
                if config == "timeout":
                    cmd.append("--timeout-only")
                run(cmd, logdir / "driver.log")
                with urllib.request.urlopen("http://127.0.0.1:19470/stats", timeout=3) as response:
                    (logdir / "stats-after.txt").write_bytes(response.read())
            finally:
                # Flush Envoy's buffered access logs before taking the snapshot.
                # Containers remain available for `logs` until the next up/down.
                run(compose + ["stop", "--timeout", "5"], logdir / "compose-stop.log", env)
                run(compose + ["logs", "--no-color", "--timestamps"], logdir / "containers.log", env)
            logs = (logdir / "containers.log").read_text()
            assert "panic:" not in logs and "wasm vm failed" not in logs.lower()
    finally:
        run(compose + ["down", "--remove-orphans", "--timeout", "5"], out / "cleanup.log", env)
        remaining = subprocess.check_output(["docker", "ps", "-aq", "--filter", f"label=com.docker.compose.project={PROJECT}"], text=True)
        networks = subprocess.check_output(["docker", "network", "ls", "-q", "--filter", f"label=com.docker.compose.project={PROJECT}"], text=True)
        volumes = subprocess.check_output(["docker", "volume", "ls", "-q", "--filter", f"label=com.docker.compose.project={PROJECT}"], text=True)
        assert not remaining.strip() and not networks.strip() and not volumes.strip()
        for port in (19468, 19469, 19470):
            with socket.socket() as sock:
                assert sock.connect_ex(("127.0.0.1", port)) != 0
        (out / "cleanup.json").write_text(json.dumps({"project": PROJECT, "containers_remaining": [],
            "networks_remaining": [], "volumes_remaining": [],
            "ports_closed": [19468, 19469, 19470]}, indent=2) + "\n")


if __name__ == "__main__":
    main()
