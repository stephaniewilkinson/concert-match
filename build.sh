#!/usr/bin/env bash
# Build script for Render. Referenced by render.yaml as the buildCommand.
set -o errexit

# Fetch and compile production dependencies.
mix deps.get --only prod
MIX_ENV=prod mix compile

# Build assets. Phoenix 1.8 runs esbuild and tailwind through mix rather than
# npm, so there is no assets/package.json to install -- Render's older Phoenix
# guide predates this and tells you to npm install here, which would fail.
MIX_ENV=prod mix assets.deploy

# Pin the output path rather than letting Mix derive it. By default the release
# lands in _build/$MIX_ENV, but Mix prefixes that with MIX_TARGET when one is
# set -- and this machine exports MIX_TARGET=rpi4 globally from ~/.zshrc, so
# the release builds to _build/rpi4_prod locally and _build/prod on Render.
# --path makes the start command in render.yaml correct in both places.
MIX_ENV=prod mix release --overwrite --path _build/release
