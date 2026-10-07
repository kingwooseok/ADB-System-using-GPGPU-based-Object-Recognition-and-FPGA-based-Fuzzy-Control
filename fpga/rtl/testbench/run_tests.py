#!/usr/bin/env python3
"""Run the RTL unit and full-system tests using Icarus Verilog.

No FPGA board, Python packages, or vendor software is required. The tests use
div_gen_0_model.v, so passing them does not validate the generated AMD divider,
Vivado implementation/timing, XSA, or physical motor wiring.
"""

from __future__ import annotations

import argparse
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import time


def executable(value: str, option: str) -> str:
    found = shutil.which(value)
    if found is None:
        raise ValueError(f"Cannot find {value!r}; provide {option} or add it to PATH")
    return str(Path(found).resolve())


def main() -> int:
    bench = Path(__file__).resolve().parent
    rtl = bench.parent
    repository = bench.parents[2]
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--iverilog", default=os.environ.get("IVERILOG", "iverilog"),
                        help="Compiler executable (or IVERILOG environment variable)")
    parser.add_argument("--vvp", default=os.environ.get("VVP", "vvp"),
                        help="Simulator executable (or VVP environment variable)")
    parser.add_argument("--build-dir", type=Path,
                        default=repository / "build/rtl-tests")
    parser.add_argument("--timeout", type=int, default=900,
                        help="Wall-clock timeout in seconds for each command")
    args = parser.parse_args()
    if args.timeout <= 0:
        parser.error("--timeout must be positive")
    compiler = executable(args.iverilog, "--iverilog")
    simulator = executable(args.vvp, "--vvp")
    build = args.build_dir.resolve()
    build.mkdir(parents=True, exist_ok=True)
    temporary = build / "tmp"
    temporary.mkdir(exist_ok=True)
    environment = os.environ.copy()
    # Icarus uses temporary files while compiling; keep them in the chosen build.
    environment.update(TEMP=str(temporary), TMP=str(temporary), TMPDIR=str(temporary))
    sources = [str(path) for path in sorted(rtl.glob("*.v"))]
    model = str(bench / "div_gen_0_model.v")
    results: list[dict] = []

    def run(name: str, command: list[str]) -> bool:
        start = time.monotonic()
        log_path = build / f"{name}.log"
        try:
            # Write directly to disk so long 50 MHz simulations can be inspected
            # while running, without a subprocess pipe or an in-memory log.
            with log_path.open("w", encoding="utf-8") as log:
                process = subprocess.run(command, cwd=build, env=environment,
                                         stdout=log, stderr=subprocess.STDOUT,
                                         timeout=args.timeout, check=False)
            record = {"name": name, "command": command,
                      "returncode": process.returncode,
                      "stdout": log_path.read_text(encoding="utf-8", errors="replace"),
                      "stderr": ""}
        except subprocess.TimeoutExpired:
            record = {"name": name, "command": command, "returncode": None,
                      "stdout": log_path.read_text(encoding="utf-8", errors="replace"),
                      "stderr": f"\nTimeout after {args.timeout}s\n"}
        record["seconds"] = round(time.monotonic() - start, 3)
        results.append(record)
        if record["stderr"]:
            with log_path.open("a", encoding="utf-8") as log:
                log.write(record["stderr"])
        (build / "results.json").write_text(json.dumps(results, indent=2), encoding="utf-8")
        passed = record["returncode"] == 0
        print(f"{'PASS' if passed else 'FAIL'} {name} ({record['seconds']:.3f}s)", flush=True)
        if record["stdout"]:
            print(record["stdout"], end="", flush=True)
        if record["stderr"]:
            print(record["stderr"], end="", file=sys.stderr, flush=True)
        return passed

    for top, filename in (("tb_regression", "tb_regression.sv"), ("tb_system", "tb_system.v")):
        output = str(build / f"{top}.vvp")
        command = [compiler, "-g2012", "-Wall", "-s", top, "-o", output,
                   *sources, model, str(bench / filename)]
        if not run(f"{top}_compile", command):
            return 1
        if not run(f"{top}_simulate", [simulator, output]):
            return 1
    print("All RTL tests passed using the simulation-only divider model.", flush=True)
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except (OSError, ValueError) as error:
        print(f"RTL test setup failed: {error}", file=sys.stderr)
        raise SystemExit(1)
