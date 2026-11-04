#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
mkdir -p .build
swiftc -swift-version 6 -strict-concurrency=complete -warnings-as-errors \
    Sources/HeatWatch/HeatStatus.swift Sources/HeatWatch/Models.swift \
    Sources/HeatWatch/SamplingRules.swift Sources/HeatWatch/Sharing.swift \
    Tests/*.swift -o .build/heatwatch-checks
.build/heatwatch-checks
