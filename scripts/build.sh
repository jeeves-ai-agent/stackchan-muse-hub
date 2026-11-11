#!/usr/bin/env bash
# Build / package the GOB52 EvenG2-Muse-Hub-M5 hub firmware for M5Stack CoreS3 (StackChan).
#
#   scripts/build.sh build     # apply hub patches, then build into build/cores3
#   scripts/build.sh package   # collect binaries into dist/cores3-hub-package
#
# Environment:
#   IDF_PATH  ESP-IDF v6.0.3 checkout (default: /home/ubuntu/esp/esp-idf-v6)
#
# sdkconfig defaults only seed a new sdkconfig. After changing
# config/sdkconfig.cores3 or sdkconfig.local, remove build/cores3/sdkconfig and rebuild.
set -euo pipefail

cmd=${1:-}

repo_dir=$(cd "$(dirname "$0")/.." && pwd)
project_dir=$repo_dir/hub/hub
sdk_dir=$project_dir/third_party/muse-gadget-sdk
build_dir=$repo_dir/build/cores3
dist_dir=$repo_dir/dist/cores3-hub-package
local_cfg=$repo_dir/sdkconfig.local

die() { echo "error: $*" >&2; exit 1; }

do_build() {
    export IDF_PATH=${IDF_PATH:-/home/ubuntu/esp/esp-idf-v6}
    [ -f "$IDF_PATH/export.sh" ] || die "ESP-IDF not found: $IDF_PATH/export.sh"
    [ -f "$sdk_dir/esp32/cmake/project.cmake" ] || die "SDK not found; run: git submodule update --init --recursive"
    [ -f "$project_dir/CMakeLists.txt" ] || die "hub project not found: $project_dir"
    [ -f "$local_cfg" ] || die "sdkconfig.local not found at $local_cfg (must define CONFIG_HUB_RELAY_TOKEN)"

    # export.sh looks for a venv named after the python3 on PATH; if that one
    # doesn't exist, fall back to the single installed idf6.0 venv.
    if [ -z "${IDF_PYTHON_ENV_PATH:-}" ]; then
        local envs=("${IDF_TOOLS_PATH:-$HOME/.espressif}"/python_env/idf6.0_py*_env)
        if [ "${#envs[@]}" -eq 1 ] && [ -x "${envs[0]}/bin/python" ]; then
            export IDF_PYTHON_ENV_PATH=${envs[0]}
        fi
    fi

    # export.sh is not written for `set -u`.
    set +u
    # shellcheck disable=SC1091
    . "$IDF_PATH/export.sh" >/dev/null
    set -u

    "$project_dir/tools/apply_patches.sh"

    local defaults
    defaults="$sdk_dir/esp32/sdkconfig.defaults"
    defaults+=";$sdk_dir/esp32/devices/sdkconfig.muse"
    defaults+=";$sdk_dir/esp32/devices/sdkconfig.muse-m5stack-cores3"
    defaults+=";$repo_dir/config/sdkconfig.cores3"
    defaults+=";$local_cfg"

    mkdir -p "$build_dir"
    idf.py -C "$project_dir" -B "$build_dir" -DIDF_TARGET=esp32s3 \
        -DSDKCONFIG="$build_dir/sdkconfig" \
        -DSDKCONFIG_DEFAULTS="$defaults" build
}

do_package() {
    local files=(
        "$build_dir/bootloader/bootloader.bin"
        "$build_dir/partition_table/partition-table.bin"
        "$build_dir/ota_data_initial.bin"
        "$build_dir/muse-gadget.bin"
    )
    local f
    for f in "${files[@]}"; do
        [ -f "$f" ] || die "missing $f; run: scripts/build.sh build"
    done

    rm -rf "$dist_dir"
    mkdir -p "$dist_dir"
    cp "${files[@]}" "$dist_dir/"

    (cd "$dist_dir" && sha256sum bootloader.bin muse-gadget.bin ota_data_initial.bin partition-table.bin > SHA256SUMS)

    cat > "$dist_dir/flash.sh" <<'EOF'
#!/usr/bin/env bash
# Mac: ./flash.sh [--erase] /dev/cu.usbmodemXXXX   (requires: pip install esptool)
#   --erase  erase the whole flash first (wipes NVS: pairing, Wi-Fi, SDK token)
# CoreS3: if esptool can't connect, hold RST for 3 s (green LED) to enter the bootloader.
set -euo pipefail
erase=0
if [ "${1:-}" = "--erase" ]; then erase=1; shift; fi
port=${1:?usage: ./flash.sh [--erase] PORT}
cd "$(dirname "$0")"
shasum -a 256 -c SHA256SUMS
if [ "$erase" = 1 ]; then
  python3 -m esptool --chip esp32s3 -p "$port" -b 460800 --before default-reset --after no-reset erase-flash
fi
python3 -m esptool --chip esp32s3 -p "$port" -b 460800 --before default-reset --after hard-reset write-flash \
  --flash-mode dio --flash-size 16MB --flash-freq 80m \
  0x0 bootloader.bin 0x10000 partition-table.bin 0x1d000 ota_data_initial.bin 0x20000 muse-gadget.bin
EOF
    chmod +x "$dist_dir/flash.sh"
    echo "packaged: $dist_dir"
}

case $cmd in
    build)   do_build ;;
    package) do_package ;;
    *) echo "usage: $0 build|package" >&2; exit 1 ;;
esac
