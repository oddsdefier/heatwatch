#!/usr/bin/env python3
"""Validate real diagnostic output without printing process or app names."""

import argparse
import json
import math
from pathlib import Path


def finite_number(value):
    return isinstance(value, (int, float)) and not isinstance(value, bool) and math.isfinite(value)


def validate(samples, expected):
    assert len(samples) == expected, "Unexpected diagnostic sample count"
    for sample in samples:
        assert isinstance(sample, dict), "Snapshot must be an object"
        assert isinstance(sample.get("date"), str), "Missing timestamp"
        assert isinstance(sample.get("chip"), str), "Missing chip description"
        assert sample.get("thermalState") in {"Normal", "Warm", "High", "Critical", "Unknown"}
        for key in ("cpuTemperature", "cpuPeak", "gpuTemperature", "batteryTemperature"):
            value = sample.get(key)
            assert value is None or (finite_number(value) and 10 <= value < 150), f"Invalid {key}"
        if sample.get("cpuTemperature") is None:
            assert "unavailable" in sample.get("notice", "").lower(), "Missing unavailable notice"
        gpu = sample.get("gpuUsage")
        assert gpu is None or (finite_number(gpu) and 0 <= gpu <= 100), "Invalid GPU usage"
        fan = sample.get("fanRPM")
        assert fan is None or (finite_number(fan) and 0 <= fan <= 20000), "Invalid fan speed"
        for key in ("sampleSeconds", "evidenceSeconds", "observedProcesses"):
            assert finite_number(sample.get(key)) and sample[key] >= 0, f"Invalid {key}"
        for key in ("contributors", "processes", "sensors"):
            assert isinstance(sample.get(key), list), f"Missing {key}"
        for contributor in sample["contributors"]:
            assert "applicationPaths" not in contributor, "UI-only paths leaked into diagnostics"
            for key in ("cpu", "averageCPU"):
                assert finite_number(contributor.get(key)) and contributor[key] >= 0, f"Invalid {key}"
        for sensor in sample["sensors"]:
            assert finite_number(sensor.get("value")) and 10 <= sensor["value"] < 150, "Invalid sensor"
    print(f"Passed {expected} live diagnostic snapshots. Missing hardware readings are allowed.")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("path", type=Path)
    parser.add_argument("--samples", type=int, default=2)
    args = parser.parse_args()
    samples = [json.loads(line) for line in args.path.read_text().splitlines() if line.strip()]
    validate(samples, args.samples)


if __name__ == "__main__":
    main()
