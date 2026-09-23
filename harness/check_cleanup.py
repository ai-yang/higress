"""Record final scoped resource cleanup without requiring jq."""
import argparse
import datetime
import json
import pathlib
import socket
import subprocess

ROOT = pathlib.Path(__file__).resolve().parent.parent
PROJECT = "response-cache-4569-20260923"


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--race-container")
    args = parser.parse_args()
    result = {"checked_at": datetime.datetime.now(datetime.timezone.utc).isoformat(),
              "project": PROJECT}
    for resource, command in (
        ("containers", ["docker", "ps", "-aq"]),
        ("networks", ["docker", "network", "ls", "-q"]),
        ("volumes", ["docker", "volume", "ls", "-q"]),
    ):
        remaining = subprocess.check_output(
            command + ["--filter", f"label=com.docker.compose.project={PROJECT}"],
            text=True).split()
        assert not remaining, (resource, remaining)
        result[resource + "_remaining"] = remaining
    if args.race_container:
        assert not subprocess.check_output(
            ["docker", "ps", "-aq", "--filter", "id=" + args.race_container], text=True).strip()
        result["race_builder_removed"] = True
    for port in (19468, 19469, 19470):
        with socket.socket() as sock:
            assert sock.connect_ex(("127.0.0.1", port)) != 0, port
    result["ports_closed"] = [19468, 19469, 19470]
    output = json.dumps(result, indent=2) + "\n"
    (ROOT / "results" / "final-resource-check.json").write_text(output)
    print(output, end="")


if __name__ == "__main__":
    main()
