#!/usr/bin/env bash
# Build all Rust libraries into one archive, with system SQLite shared by GRDB.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OCR_SOURCE="${OCRUS_SOURCE_DIR:-$ROOT/Native/ocrus}"
AI_SOURCE="${AI_USAGE_SOURCE_DIR:-$ROOT/Native/ai-usage}"
MD_SOURCE="${GET_MD_SOURCE_DIR:-$ROOT/Native/get-md}"
WORK="$ROOT/.build/native-tools"
OUTPUT="$ROOT/Native/IgniteroNative.xcframework"
for source in "$OCR_SOURCE" "$AI_SOURCE" "$MD_SOURCE"; do
  test -f "$source/Cargo.toml" || { echo 'Initialize the Native submodules first.' >&2; exit 1; }
done
mkdir -p "$WORK/src"
cmp -s "$ROOT/Native/LauncherBridge/src/lib.rs" "$WORK/src/lib.rs" || cp "$ROOT/Native/LauncherBridge/src/lib.rs" "$WORK/src/lib.rs"
/usr/bin/python3 - "$ROOT" "$WORK" "$OCR_SOURCE" "$AI_SOURCE" "$MD_SOURCE" <<'PY'
import json, pathlib, sys
root, work, ocr, ai, md = map(pathlib.Path, sys.argv[1:])
text = (root/'Native/LauncherBridge/Cargo.toml').read_text()
for before, after in [('../ocrus/crates/ocrus-ffi', ocr/'crates/ocrus-ffi'), ('../ai-usage', ai), ('../get-md', md)]:
    text = text.replace(json.dumps(before), json.dumps(str(after.resolve())))
manifest = work/'Cargo.toml'
if not manifest.exists() or manifest.read_text() != text: manifest.write_text(text)
lock = root/'Native/LauncherBridge/Cargo.lock'
if lock.exists():
    destination = work/'Cargo.lock'
    if not destination.exists() or destination.read_bytes() != lock.read_bytes(): destination.write_bytes(lock.read_bytes())
PY
cd "$AI_SOURCE"
if command -v mise >/dev/null 2>&1; then
  MISE_LOCKED=0 mise install cmake
  cmake_path="$(MISE_LOCKED=0 mise which cmake)"
  export PATH="$(dirname "$cmake_path"):$PATH"
fi
cd "$OCR_SOURCE"
MISE_LOCKED=0 mise install rust
toolchain="$(MISE_LOCKED=0 mise exec -- rustup show active-toolchain | cut -d ' ' -f 1)"
compiler="$(MISE_LOCKED=0 mise exec -- rustup which --toolchain "$toolchain" rustc)"
MISE_LOCKED=0 mise exec -- rustup component add --toolchain "$toolchain" llvm-tools
sysroot="$("$compiler" --print sysroot)"
host="$($compiler -vV | sed -n 's/^host: //p')"
nm_tool="$sysroot/lib/rustlib/$host/bin/llvm-nm"
if [[ ! -f "$ROOT/Native/LauncherBridge/Cargo.lock" ]]; then
  RUSTC="$compiler" MISE_LOCKED=0 mise exec -- rustup run "$toolchain" cargo generate-lockfile --manifest-path "$WORK/Cargo.toml"
  cp "$WORK/Cargo.lock" "$ROOT/Native/LauncherBridge/Cargo.lock"
fi
STAGE="$(mktemp -d)"
trap 'rm -rf "$STAGE"' EXIT
ARCHIVES=()
for arch in ${IGNITERO_NATIVE_ARCHS:-$(uname -m)}; do
  case "$arch" in arm64|aarch64) target=aarch64-apple-darwin ;; x86_64) target=x86_64-apple-darwin ;; *) exit 1 ;; esac
  MISE_LOCKED=0 mise exec -- rustup target add --toolchain "$toolchain" "$target"
  MACOSX_DEPLOYMENT_TARGET=26.0 RUSTC="$compiler" MISE_LOCKED=0 mise exec -- rustup run "$toolchain" cargo build \
    --locked --release --manifest-path "$WORK/Cargo.toml" --target "$target"
  if [[ "${IGNITERO_NATIVE_TESTS:-0}" == 1 && "$target" == "$host" ]]; then
    MACOSX_DEPLOYMENT_TARGET=26.0 RUSTC="$compiler" MISE_LOCKED=0 mise exec -- rustup run "$toolchain" cargo test \
      --locked --release --manifest-path "$WORK/Cargo.toml" --target "$target" --lib
  fi
  archive="$WORK/target/$target/release/libignitero_native.a"
  # A dependency's C exports must survive LTO; SQLite must remain a system library.
  if ! "$nm_tool" --defined-only --extern-only "$archive" > "$STAGE/symbols" 2> "$STAGE/nm-warnings"; then cat "$STAGE/nm-warnings" >&2; exit 1; fi
  /usr/bin/python3 - "$STAGE/symbols" <<'PYCODE'
import pathlib, sys
symbols = {line.split()[-1] for line in pathlib.Path(sys.argv[1]).read_text().splitlines() if line.split()}
required = {'_ocrus_abi_version', '_ocrus_engine_create', '_ocrus_recognize_pixels', '_ignitero_job_start', '_ignitero_job_poll', '_ignitero_job_cancel', '_ignitero_job_free', '_ignitero_job_busy', '_ignitero_string_free'}
if not required <= symbols: raise SystemExit('Missing native exports: ' + str(required - symbols))
if '_sqlite3_open' in symbols: raise SystemExit('Bundled SQLite is forbidden in the launcher archive.')
PYCODE
  ARCHIVES+=("$archive")
done
mkdir -p "$STAGE/include"
cp "$OCR_SOURCE/crates/ocrus-ffi/include/ocrus.h" "$STAGE/include/"
cp "$ROOT/Native/LauncherBridge/include/ignitero_tools.h" "$STAGE/include/"
cat > "$STAGE/include/module.modulemap" <<'MODULE'
module IgniteroNative {
  header "ocrus.h"
  header "ignitero_tools.h"
  link "sqlite3"
  link "c++"
  link "iconv"
  link "resolv"
  link framework "Accelerate"
  link framework "Security"
  link framework "CoreFoundation"
  link framework "SystemConfiguration"
  export *
}
MODULE
lipo -create "${ARCHIVES[@]}" -output "$STAGE/libIgniteroNative.a"
rm -rf "$OUTPUT"
xcodebuild -create-xcframework -library "$STAGE/libIgniteroNative.a" -headers "$STAGE/include" -output "$OUTPUT"
