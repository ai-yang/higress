"""Create a reviewed local evidence bundle only after complete verification."""
import hashlib
import gzip
import json
import pathlib
import re
import shutil
import subprocess
import tarfile

ROOT = pathlib.Path(__file__).resolve().parent.parent


def main():
    subprocess.run(["python3", str(ROOT / "harness" / "audit.py")], check=True)
    audit = json.loads((ROOT / "results" / "audit.json").read_text())
    assert audit["all_passed"] and audit["scope"] == "full-verification"
    bundle = ROOT / "bundle"
    archive = ROOT / "response-cache-header-pause-evidence.tar.gz"
    assert not archive.exists(), "Preserve the earlier archive before sealing a new run"
    # Never replace an earlier sealed bundle; move it aside explicitly after review.
    bundle.mkdir(exist_ok=False)
    report = ROOT / "EVIDENCE.md"
    shutil.copy2(report if report.exists() else ROOT / "README.md", bundle / "README.md")
    for name in ("RERUN.md", "change.patch"):
        shutil.copy2(ROOT / name, bundle / name)
    for name in ("harness", "governance", "results"):
        shutil.copytree(ROOT / name, bundle / name,
                        ignore=shutil.ignore_patterns("__pycache__", ".keep"))
    # Manifest covers all evidence, not mutable local PR/TASK submission drafts.
    lines = []
    forbidden = re.compile(rb"|".join([
        rb"/(?:developer|AIAssd|home|Users)/[A-Za-z0-9_.-]+/",
        rb"ghp_[A-Za-z0-9]{20,}", rb"github_pat_[A-Za-z0-9_]{20,}",
        rb"-----BEGIN (?:RSA |EC |OPENSSH |ENCRYPTED )?PRIVATE KEY-----[\r\n]+[A-Za-z0-9+/=]{32,}",
    ]))
    for path in sorted(bundle.rglob("*")):
        if not path.is_file():
            continue
        data = path.read_bytes()
        assert not forbidden.search(data), f"Review potentially sensitive path/content in {path.name}"
        lines.append(hashlib.sha256(data).hexdigest() + "  " + path.relative_to(bundle).as_posix())
    manifest = bundle / "SHA256SUMS"
    manifest.write_text("\n".join(lines) + "\n")
    subprocess.run(["sha256sum", "-c", "SHA256SUMS"], cwd=bundle, check=True,
                   stdout=subprocess.DEVNULL)
    def sanitized_metadata(info):
        info.uid = info.gid = 0
        info.uname = info.gname = ""
        info.mtime = 0
        info.pax_headers = {}
        return info

    with archive.open("wb") as raw, gzip.GzipFile(fileobj=raw, mode="wb", mtime=0) as compressed:
        with tarfile.open(fileobj=compressed, mode="w") as output:
            output.add(bundle, arcname="response-cache-header-pause-evidence", filter=sanitized_metadata)
    status = {"all_local_verification_complete": True, "published": False,
              "fixed_sha": audit["build"]["sources"]["fixed"],
              "manifest_sha256": hashlib.sha256(manifest.read_bytes()).hexdigest(),
              "archive_sha256": hashlib.sha256(archive.read_bytes()).hexdigest(),
              "files_hashed": len(lines)}
    (ROOT / "sealed.json").write_text(json.dumps(status, indent=2) + "\n")
    print(json.dumps(status, indent=2))


if __name__ == "__main__":
    main()
