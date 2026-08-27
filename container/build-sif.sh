#!/usr/bin/env bash
# Build loco-pipe.sif on a machine that has Docker but no Apptainer
# (e.g. macOS). Apptainer is run inside a container to do the conversion.
#
# Usage, from the repository root:
#   ./container/build-sif.sh [output.sif]
#
# On a cluster that already has Apptainer, skip this and use:
#   apptainer build --fakeroot loco-pipe.sif container/loco-pipe.def
set -euo pipefail

OUT=${1:-loco-pipe.sif}
IMAGE=loco-pipe:latest
# ohana is linux-64 only, so the image is x86_64 regardless of the build host.
PLATFORM=linux/amd64
APPTAINER_IMAGE=kaczmarj/apptainer:latest

cd "$(dirname "$0")/.."
ROOT=$PWD

command -v docker >/dev/null || { echo "error: docker not found" >&2; exit 1; }

echo "==> building $IMAGE for $PLATFORM"
docker build --platform "$PLATFORM" -f container/Dockerfile -t "$IMAGE" .

echo "==> verifying dependencies inside the image"
docker run --rm --platform "$PLATFORM" "$IMAGE" loco-pipe-check

WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT

echo "==> exporting to a docker archive"
docker save "$IMAGE" -o "$WORK/image.tar"

echo "==> converting to $OUT"
docker run --rm --platform "$PLATFORM" --privileged \
  -v "$WORK:/work" -v "$ROOT:/out" \
  "$APPTAINER_IMAGE" \
  build --force "/out/$(basename "$OUT")" docker-archive:///work/image.tar

echo "==> done: $ROOT/$(basename "$OUT")"
ls -lh "$ROOT/$(basename "$OUT")"
echo
echo "Copy it to your cluster and check it with:"
echo "  apptainer exec $(basename "$OUT") loco-pipe-check"
