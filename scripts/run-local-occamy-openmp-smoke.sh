#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
ROOT_DIR=$(cd -- "${SCRIPT_DIR}/.." && pwd)
APP_DIR="${ROOT_DIR}/apps/omp/basic/offload_benchmark"
APP_ELF="${APP_DIR}/offload_benchmark_occamy.elf"
DEVICE_RUNTIME_DIR="${ROOT_DIR}/platforms/occamy/target/sim/sw/device/apps/libomptarget_device"
SMOKE_LOG="${ROOT_DIR}/output/occamy-openmp-smoke.log"
FAKE_DRIVER_SRC="${ROOT_DIR}/sw/libhero/sim/occamy_fake_driver.c"
FAKE_DRIVER_SO="${ROOT_DIR}/output/occamy-openmp-smoke/liboccamy_fake_driver.so"
CAPTURE_PATH="${ROOT_DIR}/output/occamy-openmp-smoke/launches.jsonl"
SNAPSHOT_DIR="${ROOT_DIR}/output/occamy-openmp-smoke/snapshots"
USER_TIMEOUT_SECONDS="${TIMEOUT_SECONDS:-}"
TIMEOUT_SECONDS="${TIMEOUT_SECONDS:-30}"
QEMU_RISCV64="${QEMU_RISCV64:-qemu-riscv64}"
DO_BUILD=0
USE_FAKE_DRIVER=0
USE_FAKE_COMPLETE=0
CAPTURE_LAUNCH=0
CAPTURE_SNAPSHOT=0
DEVICE_NODE="${OCCAMY_DEVICE_NODE:-/dev/occamydev--1}"

log() {
  printf '[occamy-openmp-smoke] %s\n' "$*"
}

die() {
  printf '[occamy-openmp-smoke] ERROR: %s\n' "$*" >&2
  exit 1
}

need_cmd() {
  command -v "$1" >/dev/null 2>&1 || die "missing command: $1"
}

usage() {
  cat <<'EOF'
Usage: scripts/run-local-occamy-openmp-smoke.sh [--build]
       scripts/run-local-occamy-openmp-smoke.sh [--build] --fake-driver
       scripts/run-local-occamy-openmp-smoke.sh [--build] --fake-complete
       scripts/run-local-occamy-openmp-smoke.sh [--build] --capture-launch
       scripts/run-local-occamy-openmp-smoke.sh [--build] --capture-snapshot

Runs the HeroSDK/OpenMP Occamy benchmark host ELF under qemu-riscv64.

This is an M3 smoke test, not full heterogeneous execution:
  - success means the RISC-V Linux ELF starts and reaches the HeroSDK
    libomptarget/libhero runtime path
  - the expected current stop point is the missing Occamy Linux device node
    /dev/occamydev--1

Options:
  --build        Rebuild the HeroSDK/OpenMP software artifacts before running.
  --fake-driver  Use a RISC-V LD_PRELOAD shim for the Occamy driver ABI.
  --fake-complete
                 Also fake MBOX_DEVICE_DONE responses for target launches.
  --capture-launch
                 Fake completion and write JSONL launch/memory snapshots.
  --capture-snapshot
                 Also dump trimmed fake-region binaries for replay work.
EOF
}

parse_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --build)
        DO_BUILD=1
        shift
        ;;
      --fake-driver)
        USE_FAKE_DRIVER=1
        shift
        ;;
      --fake-complete)
        USE_FAKE_DRIVER=1
        USE_FAKE_COMPLETE=1
        shift
        ;;
      --capture-launch)
        USE_FAKE_DRIVER=1
        USE_FAKE_COMPLETE=1
        CAPTURE_LAUNCH=1
        shift
        ;;
      --capture-snapshot)
        USE_FAKE_DRIVER=1
        USE_FAKE_COMPLETE=1
        CAPTURE_LAUNCH=1
        CAPTURE_SNAPSHOT=1
        shift
        ;;
      -h|--help)
        usage
        exit 0
        ;;
      *)
        die "unknown argument: $1"
        ;;
    esac
  done
}

source_hero_env() {
  local gcc_path=""
  local sysroot_path=""

  cd "${ROOT_DIR}"
  export HERO_ROOT="${ROOT_DIR}"
  export CVA6_SDK="${ROOT_DIR}/cva6-sdk"
  export HERO_INSTALL="${ROOT_DIR}/install"
  export RISCV="${CVA6_SDK}/buildroot/output/host"

  if [[ -z "${HERO_LINUX_TUPLE:-}" ]]; then
    gcc_path=$(find "${RISCV}/bin" -maxdepth 1 -type f \
      \( -name 'riscv64-buildroot-linux-*-gcc' -o -name 'riscv64-buildroot-linux-*-gcc.br_real' \) \
      2>/dev/null | sort | head -n 1)
    if [[ -n "${gcc_path}" ]]; then
      HERO_LINUX_TUPLE=$(basename "${gcc_path}" | sed -E 's/-gcc(\.br_real)?$//')
    else
      sysroot_path=$(find "${RISCV}" -maxdepth 2 -type d \
        -path '*/riscv64-buildroot-linux-*/sysroot' 2>/dev/null | sort | head -n 1)
      if [[ -n "${sysroot_path}" ]]; then
        HERO_LINUX_TUPLE=$(basename "$(dirname "${sysroot_path}")")
      else
        HERO_LINUX_TUPLE="riscv64-buildroot-linux-gnu"
      fi
    fi
    export HERO_LINUX_TUPLE
  fi

  export RV64_SYSROOT="${RV64_SYSROOT:-${RISCV}/${HERO_LINUX_TUPLE}/sysroot}"
  export HERO_LINUX_SYSROOT="${RV64_SYSROOT}"
  export HERO_LINUX_CROSS_COMPILE="${RISCV}/bin/${HERO_LINUX_TUPLE}-"
  export HERO_LINUX_LD="${HERO_LINUX_CROSS_COMPILE}ld"
  export HERO_LINUX_OBJDUMP="${HERO_LINUX_CROSS_COMPILE}objdump"
  export CROSS_COMPILE="${HERO_LINUX_CROSS_COMPILE}"
  export OCCAMY_ROOT="${ROOT_DIR}/platforms/occamy"
  export PATH="${RISCV}/bin:${HERO_INSTALL}/bin:${PATH}"

  [[ -n "${RV64_SYSROOT:-}" ]] || die "RV64_SYSROOT could not be detected"
  [[ -d "${RV64_SYSROOT}" ]] || die "missing RISC-V Linux sysroot: ${RV64_SYSROOT}"
}

build_artifacts() {
  log "building HeroSDK/OpenMP host runtime"
  make HERO_HOST=cva6 HERO_DEVICE=occamy hero-sw-all

  log "building Occamy device-side libomptarget runtime"
  make -C "${DEVICE_RUNTIME_DIR}" all

  log "building offload_benchmark for Occamy"
  make -C "${APP_DIR}" DEVICES=occamy
}

build_fake_driver() {
  local compiler="${HERO_LINUX_CROSS_COMPILE}gcc"

  [[ -f "${FAKE_DRIVER_SRC}" ]] || die "missing fake driver source: ${FAKE_DRIVER_SRC}"
  [[ -x "${compiler}" ]] || die "missing RISC-V Linux compiler: ${compiler}"

  mkdir -p "$(dirname -- "${FAKE_DRIVER_SO}")"

  if [[ ! -f "${FAKE_DRIVER_SO}" || "${FAKE_DRIVER_SRC}" -nt "${FAKE_DRIVER_SO}" ]]; then
    log "building RISC-V fake Occamy driver shim"
    "${compiler}" --sysroot="${RV64_SYSROOT}" -shared -fPIC -O2 -Wall -Wextra \
      -o "${FAKE_DRIVER_SO}" "${FAKE_DRIVER_SRC}" -ldl
  fi
}

check_artifacts() {
  [[ -x "${APP_ELF}" ]] || die "missing executable: ${APP_ELF} (run with --build first)"
  [[ -f "${ROOT_DIR}/sw/libhero/lib/libhero_occamy.so" ]] || die "missing libhero_occamy.so (run with --build first)"
  [[ -f "${ROOT_DIR}/sw/libomp/lib/libomp.so" ]] || die "missing libomp.so (run with --build first)"
  [[ -f "${ROOT_DIR}/sw/libomp/lib/libomptarget.so" ]] || die "missing libomptarget.so (run with --build first)"
  [[ -f "${ROOT_DIR}/sw/libomp/lib/libomptarget.rtl.herodev_occamy.so" ]] || \
    die "missing libomptarget.rtl.herodev_occamy.so (run with --build first)"
  [[ -e "${RV64_SYSROOT}/lib/ld-linux-riscv64-lp64d.so.1" ]] || \
    die "missing dynamic loader in sysroot: ${RV64_SYSROOT}/lib/ld-linux-riscv64-lp64d.so.1"
}

run_smoke() {
  local status
  local guest_lib_path
  local preload_path=""
  local launch_count

  need_cmd "${QEMU_RISCV64}"
  need_cmd timeout
  need_cmd python3

  if [[ ${USE_FAKE_DRIVER} -eq 1 ]]; then
    build_fake_driver
    preload_path="${FAKE_DRIVER_SO}"
  fi

  mkdir -p "$(dirname -- "${SMOKE_LOG}")"
  : > "${SMOKE_LOG}"
  if [[ ${CAPTURE_LAUNCH} -eq 1 ]]; then
    mkdir -p "$(dirname -- "${CAPTURE_PATH}")"
    : > "${CAPTURE_PATH}"
  fi
  if [[ ${CAPTURE_SNAPSHOT} -eq 1 ]]; then
    rm -rf "${SNAPSHOT_DIR}"
    mkdir -p "${SNAPSHOT_DIR}"
  fi

  guest_lib_path="${ROOT_DIR}/sw/libhero/lib:${ROOT_DIR}/sw/libomp/lib:${RV64_SYSROOT}/lib:${RV64_SYSROOT}/usr/lib"

  log "running ${APP_ELF}"
  log "writing log to ${SMOKE_LOG}"

  set +e
  python3 - "$QEMU_RISCV64" "$RV64_SYSROOT" "$APP_ELF" "$SMOKE_LOG" \
    "$TIMEOUT_SECONDS" "$guest_lib_path" "$preload_path" "$USE_FAKE_COMPLETE" \
    "$CAPTURE_LAUNCH" "$CAPTURE_PATH" "$CAPTURE_SNAPSHOT" "$SNAPSHOT_DIR" <<'PY'
import os
import subprocess
import sys

qemu, sysroot, app, log_path, timeout_s, lib_path, preload_path, fake_complete, capture_launch, capture_path, capture_snapshot, snapshot_dir = sys.argv[1:13]
env = os.environ.copy()
env.pop("LD_PRELOAD", None)
env.pop("LD_LIBRARY_PATH", None)
env["QEMU_LD_PREFIX"] = sysroot
libomptarget_debug = env.get("LIBOMPTARGET_DEBUG", "1")
libhero_log = env.get("LIBHERO_LOG", "4")

cmd = [
    qemu,
    "-L",
    sysroot,
    "-E",
    f"LD_LIBRARY_PATH={lib_path}",
    "-E",
    f"LIBOMPTARGET_DEBUG={libomptarget_debug}",
    "-E",
    f"LIBHERO_LOG={libhero_log}",
]
if preload_path:
    cmd.extend(["-E", f"LD_PRELOAD={preload_path}", "-E", "OCCAMY_FAKE_DRIVER=1"])
    if fake_complete == "1":
        cmd.extend(["-E", "OCCAMY_FAKE_DEVICE_COMPLETE=1"])
    if capture_launch == "1":
        cmd.extend(["-E", f"OCCAMY_FAKE_CAPTURE_LAUNCH={capture_path}"])
        if "OCCAMY_FAKE_CAPTURE_BYTES" in env:
            cmd.extend(["-E", f"OCCAMY_FAKE_CAPTURE_BYTES={env['OCCAMY_FAKE_CAPTURE_BYTES']}"])
        if capture_snapshot == "1":
            cmd.extend(["-E", f"OCCAMY_FAKE_CAPTURE_DIR={snapshot_dir}"])
cmd.append(app)
try:
    with open(log_path, "w", encoding="utf-8") as log:
        completed = subprocess.run(
            cmd,
            env=env,
            stdout=log,
            stderr=subprocess.STDOUT,
            timeout=int(timeout_s),
            check=False,
        )
    sys.exit(completed.returncode)
except subprocess.TimeoutExpired:
    sys.exit(124)
PY
  status=$?
  set -e

  if [[ ${status} -eq 124 ]]; then
    if [[ ${USE_FAKE_DRIVER} -eq 1 ]] &&
       grep -q "__tgt_rtl_run_target_region" "${SMOKE_LOG}"; then
      log "reached OpenMP target launch with the fake driver"
      log "current expected blocker: no Snitch-side runtime/mailbox response"
      exit 0
    fi
    die "smoke run timed out after ${TIMEOUT_SECONDS}s; see ${SMOKE_LOG}"
  fi

  if [[ ${status} -eq 0 ]]; then
    if [[ ${USE_FAKE_COMPLETE} -eq 1 ]]; then
      if [[ ${CAPTURE_LAUNCH} -eq 1 ]]; then
        [[ -s "${CAPTURE_PATH}" ]] || die "capture mode completed but wrote no launch snapshots"
        launch_count=$(python3 - "${CAPTURE_PATH}" <<'PY'
import json
import sys

count = 0
with open(sys.argv[1], "r", encoding="utf-8") as f:
    for line in f:
        if not line.strip():
            continue
        record = json.loads(line)
        assert record["start"] == "0x00000002"
        assert record["target_fn"].startswith("0x")
        assert record["arg_ptr"].startswith("0x")
        count += 1
print(count)
PY
)
        log "captured ${launch_count} OpenMP launch snapshots to ${CAPTURE_PATH}"
        if [[ ${CAPTURE_SNAPSHOT} -eq 1 ]]; then
          [[ -s "${SNAPSHOT_DIR}/snapshots.jsonl" ]] || \
            die "snapshot mode completed but wrote no snapshot manifest"
          log "captured replay snapshots to ${SNAPSHOT_DIR}"
        fi
      fi
      log "host OpenMP runtime completed with fake mailbox responses"
      log "target code and OpenMP map correctness are still not proven"
      exit 0
    fi
    log "program exited successfully; full M3 runtime execution may now be possible"
    exit 0
  fi

  if grep -q "Successfully loaded library 'libomptarget.rtl.herodev_occamy.so'" "${SMOKE_LOG}" &&
     grep -q "__tgt_rtl_init_device(1)" "${SMOKE_LOG}" &&
     [[ ! -e "${DEVICE_NODE}" ]]; then
    log "reached the HeroSDK OpenMP runtime path"
    log "current expected blocker: missing ${DEVICE_NODE} device interface"
    exit 0
  fi

  if [[ ${USE_FAKE_DRIVER} -eq 1 ]] &&
     grep -q "Successfully loaded library 'libomptarget.rtl.herodev_occamy.so'" "${SMOKE_LOG}" &&
     grep -q "__tgt_rtl_load_binary" "${SMOKE_LOG}"; then
    log "fake driver moved execution past device initialization"
    log "current blocker is beyond the Linux driver ABI; see ${SMOKE_LOG}"
    exit 0
  fi

  tail -n 40 "${SMOKE_LOG}" >&2 || true
  die "smoke run failed before the expected HeroSDK runtime boundary; see ${SMOKE_LOG}"
}

main() {
  parse_args "$@"
  if [[ ${USE_FAKE_DRIVER} -eq 1 && ${USE_FAKE_COMPLETE} -eq 0 && -z "${USER_TIMEOUT_SECONDS}" ]]; then
    TIMEOUT_SECONDS=6
  fi
  source_hero_env

  if [[ ${DO_BUILD} -eq 1 ]]; then
    build_artifacts
  fi

  check_artifacts
  run_smoke
}

main "$@"
