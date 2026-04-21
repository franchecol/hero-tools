#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
ROOT_DIR=$(cd -- "${SCRIPT_DIR}/.." && pwd)
SIM_DIR="${ROOT_DIR}/platforms/occamy/target/sim"
DEVICE_RUNTIME_DIR="${SIM_DIR}/sw/device/runtime"
DEVICE_MATH_DIR="${SIM_DIR}/sw/device/math"
VENV_DIR="${ROOT_DIR}/.venv-occamy"
USER_BIN_DIR="${HOME}/bin"
HERO_INSTALL_DIR="${HERO_INSTALL:-${ROOT_DIR}/install}"
CANONICAL_RISCV_PREFIX="riscv64-unknown-elf-"
RISCV_SRC_PREFIX=""
APP_MODE="${1:-minimal_irq}"
DEVICE_APP_DIR=""
HOST_APP_DIR=""
HOST_ELF=""
DEVICE_BIN=""
DEVICE_SYMBOL_ELF=""
DEVICE_TARGET_FN=""
VERIFY_SCRIPT=""

log() {
  printf '[occamy-minimal] %s\n' "$*"
}

die() {
  printf '[occamy-minimal] ERROR: %s\n' "$*" >&2
  exit 1
}

need_cmd() {
  command -v "$1" >/dev/null 2>&1 || die "missing command: $1"
}

configure_mode() {
  case "${APP_MODE}" in
    minimal_irq)
      DEVICE_APP_DIR="${SIM_DIR}/sw/device/apps/minimal_irq"
      HOST_APP_DIR="${SIM_DIR}/sw/host/apps/offload"
      HOST_ELF="${HOST_APP_DIR}/build/offload-minimal_irq.elf"
      DEVICE_BIN="${DEVICE_APP_DIR}/build/minimal_irq.bin"
      DEVICE_SYMBOL_ELF="${DEVICE_APP_DIR}/build/minimal_irq.elf"
      ;;
    roundtrip)
      DEVICE_APP_DIR="${SIM_DIR}/sw/device/apps/roundtrip"
      HOST_APP_DIR="${SIM_DIR}/sw/host/apps/roundtrip"
      HOST_ELF="${HOST_APP_DIR}/build/roundtrip.elf"
      DEVICE_BIN="${DEVICE_APP_DIR}/build/roundtrip.bin"
      DEVICE_SYMBOL_ELF="${DEVICE_APP_DIR}/build/roundtrip.elf"
      ;;
    axpy)
      DEVICE_APP_DIR="${SIM_DIR}/sw/device/apps/blas/axpy"
      HOST_APP_DIR="${SIM_DIR}/sw/host/apps/offload"
      HOST_ELF="${HOST_APP_DIR}/build/offload-axpy.elf"
      DEVICE_BIN="${DEVICE_APP_DIR}/build/axpy.bin"
      DEVICE_SYMBOL_ELF="${DEVICE_APP_DIR}/build/axpy.elf"
      VERIFY_SCRIPT="${ROOT_DIR}/platforms/occamy/deps/snitch_cluster/sw/blas/axpy/verify.py"
      ;;
    omp_mailbox)
      DEVICE_APP_DIR="${SIM_DIR}/sw/device/apps/omp_mailbox"
      HOST_APP_DIR="${SIM_DIR}/sw/host/apps/omp_mailbox"
      HOST_ELF="${HOST_APP_DIR}/build/omp_mailbox.elf"
      DEVICE_BIN="${DEVICE_APP_DIR}/build/omp_mailbox.bin"
      DEVICE_SYMBOL_ELF="${DEVICE_APP_DIR}/build/omp_mailbox.elf"
      ;;
    *)
      die "unsupported mode: ${APP_MODE} (expected minimal_irq, roundtrip, axpy, or omp_mailbox)"
      ;;
  esac
}

normalize_tool_prefix() {
  local prefix="${1}"
  [[ -n "${prefix}" && "${prefix}" != *- ]] && prefix="${prefix}-"
  printf '%s\n' "${prefix}"
}

ensure_venv() {
  if [[ ! -d "${VENV_DIR}" ]]; then
    log "creating Python virtual environment at ${VENV_DIR}"
    python -m venv "${VENV_DIR}"
  fi

  # shellcheck disable=SC1091
  source "${VENV_DIR}/bin/activate"

  if ! python - <<'PY' >/dev/null 2>&1
import importlib
mods = ["hjson", "jsonref", "mako", "yaml", "tabulate", "jsonschema", "pkg_resources"]
for mod in mods:
    importlib.import_module(mod)
PY
  then
    log "installing Python build dependencies into ${VENV_DIR}"
    python -m pip install hjson jsonref mako pyyaml tabulate jsonschema "setuptools<81"
  fi

  if [[ "${APP_MODE}" == "axpy" ]]; then
    if ! python - <<'PY' >/dev/null 2>&1
import importlib
for mod in ("numpy", "elftools"):
    importlib.import_module(mod)
PY
    then
      log "installing axpy verification dependencies into ${VENV_DIR}"
      python -m pip install numpy pyelftools
    fi
  fi
}

resolve_verilator_root() {
  local candidate=""
  local verilator_bin=""
  local resolved_bin=""

  if [[ -n "${VERILATOR_ROOT:-}" ]]; then
    candidate="${VERILATOR_ROOT}"
  else
    candidate=$(verilator -V 2>/dev/null | awk -F'= ' '
      /VERILATOR_ROOT/ {
        gsub(/^[[:space:]]+|[[:space:]]+$/, "", $2)
        if ($2 != "") {
          root = $2
        }
      }
      END {
        print root
      }
    ')
  fi

  if [[ -z "${candidate}" ]]; then
    verilator_bin=$(command -v verilator)
    resolved_bin=$(readlink -f "${verilator_bin}" 2>/dev/null || printf '%s\n' "${verilator_bin}")
    for candidate in \
      "$(dirname -- "${resolved_bin}")/../share/verilator" \
      "$(dirname -- "${resolved_bin}")/../lib/verilator" \
      "/usr/share/verilator" \
      "/usr/local/share/verilator"; do
      if [[ -f "${candidate}/include/verilated.cpp" ]]; then
        break
      fi
    done
  fi

  [[ -n "${candidate}" ]] || die "could not determine VERILATOR_ROOT; set VERILATOR_ROOT=/path/to/share/verilator"
  [[ -f "${candidate}/include/verilated.cpp" ]] || \
    die "invalid VERILATOR_ROOT: ${candidate} (expected include/verilated.cpp below it)"

  export VERILATOR_ROOT
  VERILATOR_ROOT=$(cd -- "${candidate}" && pwd)
  export VLT_ROOT="${VERILATOR_ROOT}"

  log "using VERILATOR_ROOT=${VERILATOR_ROOT}"
}

find_riscv_tool_prefix() {
  local prefix
  local requested_prefix="${RISCV_TOOL_PREFIX:-}"
  local prefixes=()

  if [[ -n "${requested_prefix}" ]]; then
    prefix=$(normalize_tool_prefix "${requested_prefix}")
    command -v "${prefix}gcc" >/dev/null 2>&1 || \
      die "requested RISCV_TOOL_PREFIX does not provide ${prefix}gcc"
    printf '%s\n' "${prefix}"
    return 0
  fi

  prefixes=(
    "${CANONICAL_RISCV_PREFIX}"
    "riscv64-elf-"
    "riscv64-none-elf-"
  )

  for prefix in "${prefixes[@]}"; do
    if command -v "${prefix}gcc" >/dev/null 2>&1 && \
       command -v "${prefix}objcopy" >/dev/null 2>&1 && \
       command -v "${prefix}objdump" >/dev/null 2>&1 && \
       command -v "${prefix}readelf" >/dev/null 2>&1; then
      printf '%s\n' "${prefix}"
      return 0
    fi
  done

  return 1
}

ensure_riscv_aliases() {
  local tool
  local src

  RISCV_SRC_PREFIX=$(find_riscv_tool_prefix) || \
    die "could not find a supported bare-metal RISC-V tool prefix; tried riscv64-unknown-elf-, riscv64-elf-, and riscv64-none-elf-. Override with RISCV_TOOL_PREFIX=<prefix>"

  mkdir -p "${USER_BIN_DIR}"
  export PATH="${USER_BIN_DIR}:${PATH}"

  if [[ "${RISCV_SRC_PREFIX}" == "${CANONICAL_RISCV_PREFIX}" ]]; then
    log "using RISC-V tool prefix ${RISCV_SRC_PREFIX}"
  else
    log "mapping RISC-V tool prefix ${RISCV_SRC_PREFIX} to ${CANONICAL_RISCV_PREFIX} via ${USER_BIN_DIR}"
  fi

  for tool in addr2line ar as c++ c++filt cpp elfedit g++ gcc gcc-ar gcc-nm \
    gcc-ranlib gcov gcov-dump gcov-tool gprof ld ld.bfd lto-dump nm objcopy \
    objdump ranlib readelf size strings strip; do
    if [[ "${RISCV_SRC_PREFIX}" == "${CANONICAL_RISCV_PREFIX}" ]]; then
      continue
    fi
    src=$(command -v "${RISCV_SRC_PREFIX}${tool}" || true)
    if [[ -n "${src}" ]]; then
      ln -sf "${src}" "${USER_BIN_DIR}/${CANONICAL_RISCV_PREFIX}${tool}"
    fi
  done

  need_cmd "${CANONICAL_RISCV_PREFIX}gcc"
  need_cmd "${CANONICAL_RISCV_PREFIX}objcopy"
  need_cmd "${CANONICAL_RISCV_PREFIX}objdump"
  need_cmd "${CANONICAL_RISCV_PREFIX}readelf"
}

ensure_hero_install_env() {
  export HERO_INSTALL="${HERO_INSTALL_DIR}"

  if [[ -e "${HERO_INSTALL}/bin" && ! -d "${HERO_INSTALL}/bin" ]]; then
    die "HERO_INSTALL/bin exists but is not a directory (${HERO_INSTALL}/bin); the HeroSDK LLVM install is incomplete"
  fi

  if [[ -d "${HERO_INSTALL}/bin" ]]; then
    export PATH="${HERO_INSTALL}/bin:${PATH}"
  fi
}

ensure_hero_device_toolchain() {
  [[ "${APP_MODE}" == "axpy" || "${APP_MODE}" == "omp_mailbox" ]] || return 0

  ensure_hero_install_env

  [[ -d "${HERO_INSTALL}/bin" ]] || \
    die "${APP_MODE} requires the HeroSDK LLVM toolchain under ${HERO_INSTALL}; run: source scripts/setenv.sh && make hero-tc-llvm-axpy"
  command -v riscv32-unknown-elf-clang >/dev/null 2>&1 || \
    die "${APP_MODE} requires riscv32-unknown-elf-clang from the HeroSDK LLVM toolchain; run: source scripts/setenv.sh && make hero-tc-llvm-axpy"
  [[ -d "${HERO_INSTALL}/rv32imafd-ilp32d/riscv32-unknown-elf" ]] || \
    die "${APP_MODE} requires the rv32imafd-ilp32d device sysroot in ${HERO_INSTALL}; run: source scripts/setenv.sh && make hero-tc-llvm-axpy"

  if [[ "${APP_MODE}" == "axpy" ]]; then
    [[ -x "${VERIFY_SCRIPT}" ]] || [[ -f "${VERIFY_SCRIPT}" ]] || \
      die "missing axpy verify script: ${VERIFY_SCRIPT}"
  fi
}

verify_local_patch() {
  grep -q 'verilated_timing.o' "${SIM_DIR}/Makefile" || \
    die "missing expected Verilator compatibility fix in ${SIM_DIR}/Makefile; run ./scripts/bootstrap-local-occamy-minimal.sh"
  grep -q 'verilated_threads.o' "${SIM_DIR}/Makefile" || \
    die "missing expected Verilator compatibility fix in ${SIM_DIR}/Makefile; run ./scripts/bootstrap-local-occamy-minimal.sh"
}

build_simulator() {
  log "building reduced Occamy headers"
  make -C "${SIM_DIR}" CFG_OVERRIDE=cfg/single-cluster.hjson VERIBLE_FMT=true all-headers

  log "building Verilator simulator"
  make -C "${SIM_DIR}" CFG_OVERRIDE=cfg/single-cluster.hjson VERIBLE_FMT=true \
    VLT='verilator --timing -DASSERTS_OFF' \
    VERILATOR_ROOT="${VERILATOR_ROOT}" \
    VLT_ROOT="${VLT_ROOT}" \
    CXXFLAGS='-include cstdint -fcoroutines' \
    bin/occamy_top.vlt
}

get_symbol_addr() {
  local nm_bin="$1"
  local elf="$2"
  local symbol="$3"

  "${nm_bin}" -n "${elf}" | awk -v symbol="${symbol}" '
    $NF == symbol {
      print "0x" $1
      exit
    }
  '
}

write_device_origin() {
  local origin="$1"
  local origin_ld="${DEVICE_APP_DIR}/build/origin.ld"

  mkdir -p "${DEVICE_APP_DIR}/build"
  printf 'L3_ORIGIN = %s;\n' "${origin}" > "${origin_ld}"
}

finalize_omp_mailbox_host() {
  rm -f \
    "${HOST_APP_DIR}/build/omp_mailbox.elf" \
    "${HOST_APP_DIR}/build/omp_mailbox.dump" \
    "${HOST_APP_DIR}/build/omp_mailbox.dwarf"
  make -C "${HOST_APP_DIR}" finalize-build DEVICE_TARGET_FN="${DEVICE_TARGET_FN}"
}

build_selected_payload() {
  if [[ "${APP_MODE}" == "axpy" ]]; then
    log "cleaning ${APP_MODE} device payload"
    make -C "${DEVICE_APP_DIR}" clean

    log "cleaning ${APP_MODE} host application"
    make -C "${HOST_APP_DIR}" clean

    log "building device runtime library"
    make -C "${DEVICE_RUNTIME_DIR}" all

    log "building device math library"
    make -C "${DEVICE_MATH_DIR}" all

    log "building ${APP_MODE} host partial application"
    make -C "${HOST_APP_DIR}" partial-build DEVICE_APPS=blas/axpy

    log "building ${APP_MODE} device payload"
    make -C "${DEVICE_APP_DIR}" all

    log "finalizing ${APP_MODE} host application"
    make -C "${HOST_APP_DIR}" finalize-build DEVICE_APPS=blas/axpy
  elif [[ "${APP_MODE}" == "omp_mailbox" ]]; then
    log "cleaning ${APP_MODE} device payload"
    make -C "${DEVICE_APP_DIR}" clean

    log "cleaning ${APP_MODE} host application"
    make -C "${HOST_APP_DIR}" clean

    log "building device runtime library"
    make -C "${DEVICE_RUNTIME_DIR}" all

    log "building device math library"
    make -C "${DEVICE_MATH_DIR}" all

    log "building ${APP_MODE} host partial application"
    make -C "${HOST_APP_DIR}" partial-build

    local partial_snitch_main=""
    local final_snitch_main=""
    local expected_snitch_main=""
    local pass=""

    partial_snitch_main=$(get_symbol_addr "${CANONICAL_RISCV_PREFIX}nm" "${HOST_APP_DIR}/build/omp_mailbox.part.elf" snitch_main)
    [[ -n "${partial_snitch_main}" ]] || \
      die "could not locate snitch_main in ${HOST_APP_DIR}/build/omp_mailbox.part.elf"

    expected_snitch_main="${partial_snitch_main}"
    for pass in 1 2 3; do
      if [[ "${pass}" != "1" ]]; then
        log "relinking ${APP_MODE} device payload at snitch_main=${expected_snitch_main}"
        make -C "${DEVICE_APP_DIR}" clean
        write_device_origin "${expected_snitch_main}"
      else
        log "building ${APP_MODE} device payload"
      fi

      make -C "${DEVICE_APP_DIR}" all

      DEVICE_TARGET_FN=$(get_symbol_addr "${HERO_INSTALL}/bin/llvm-nm" "${DEVICE_SYMBOL_ELF}" omp_mailbox_target)
      [[ -n "${DEVICE_TARGET_FN}" ]] || \
        die "could not locate omp_mailbox_target in ${DEVICE_SYMBOL_ELF}"
      log "using omp_mailbox_target=${DEVICE_TARGET_FN}"

      log "finalizing ${APP_MODE} host application"
      finalize_omp_mailbox_host
      final_snitch_main=$(get_symbol_addr "${CANONICAL_RISCV_PREFIX}nm" "${HOST_ELF}" snitch_main)
      [[ -n "${final_snitch_main}" ]] || \
        die "could not locate snitch_main in ${HOST_ELF}"

      if [[ "${final_snitch_main}" == "${expected_snitch_main}" ]]; then
        break
      fi

      log "host final snitch_main moved from ${expected_snitch_main} to ${final_snitch_main}"
      expected_snitch_main="${final_snitch_main}"
    done

    [[ "${final_snitch_main}" == "${expected_snitch_main}" ]] || \
      die "could not stabilize omp_mailbox snitch_main address after 3 passes"
  else
    log "building ${APP_MODE} device payload"
    make -C "${DEVICE_APP_DIR}" clean
    make -C "${DEVICE_APP_DIR}" all

    log "building ${APP_MODE} host application"
    make -C "${HOST_APP_DIR}" clean
  fi

  if [[ "${APP_MODE}" == "minimal_irq" ]]; then
    make -C "${HOST_APP_DIR}" DEVICE_APPS=minimal_irq
    make -C "${HOST_APP_DIR}" finalize-build DEVICE_APPS=minimal_irq
  elif [[ "${APP_MODE}" == "roundtrip" ]]; then
    make -C "${HOST_APP_DIR}" finalize-build
  fi
}

run_simulation() {
  local sim_bin="${SIM_DIR}/bin/occamy_top.vlt"

  [[ -x "${sim_bin}" ]] || die "simulator missing: ${sim_bin}"
  [[ -f "${HOST_ELF}" ]] || die "host ELF missing: ${HOST_ELF}"

  rm -f "${SIM_DIR}/uart0.log" "${SIM_DIR}/trace_hart_00.dasm"
  rm -f "${SIM_DIR}/logs/trace_hart_0000"*.dasm

  log "running ${APP_MODE} heterogeneous simulation"
  (
    cd "${SIM_DIR}"
    "${sim_bin}" "${HOST_ELF}"
  )
}

run_and_verify_axpy() {
  local sim_bin="${SIM_DIR}/bin/occamy_top.vlt"

  [[ -x "${sim_bin}" ]] || die "simulator missing: ${sim_bin}"
  [[ -f "${HOST_ELF}" ]] || die "host ELF missing: ${HOST_ELF}"
  [[ -f "${DEVICE_SYMBOL_ELF}" ]] || die "device ELF missing: ${DEVICE_SYMBOL_ELF}"

  rm -f "${SIM_DIR}/uart0.log" "${SIM_DIR}/trace_hart_00.dasm"
  rm -f "${SIM_DIR}/logs/trace_hart_0000"*.dasm

  log "running ${APP_MODE} verification harness"
  (
    cd "${SIM_DIR}"
    python "${VERIFY_SCRIPT}" --symbols-bin "${DEVICE_SYMBOL_ELF}" "${sim_bin}" "${HOST_ELF}"
  )
}

verify_traces() {
  local host_trace="${SIM_DIR}/trace_hart_00.dasm"
  local dev_trace="${SIM_DIR}/logs/trace_hart_00001.dasm"
  local roundtrip_base=""

  [[ -f "${host_trace}" ]] || die "missing host trace: ${host_trace}"
  [[ -f "${dev_trace}" ]] || die "missing device trace: ${dev_trace}"

  if [[ "${APP_MODE}" == "minimal_irq" ]]; then
    rg -q '0x80000524.*00732023' "${dev_trace}" || \
      die "device trace does not show the host interrupt store"
    rg -q '0x80000464.*04000737' "${host_trace}" || \
      die "host trace does not show the host SW interrupt clear path"
  elif [[ "${APP_MODE}" == "roundtrip" ]]; then
    roundtrip_base=$("${CANONICAL_RISCV_PREFIX}nm" -n "${HOST_ELF}" | awk '
      $NF == "roundtrip_buffer" {
        print $1
        exit
      }
    ')
    [[ -n "${roundtrip_base}" ]] || die "could not locate roundtrip_buffer in ${HOST_ELF}"
    roundtrip_base=$(printf '0x%x\n' "0x${roundtrip_base}")

    rg -q "DASM\\(00732023\\).*opa': 0x4000000" "${dev_trace}" || \
      die "device trace does not show the host interrupt store"
    rg -q "opa': ${roundtrip_base}" "${dev_trace}" || \
      die "device trace does not show stores into ${roundtrip_base}"
    rg -q '0x80000068.*00a2a023' "${host_trace}" || \
      die "host trace does not show the tohost exit write"
  elif [[ "${APP_MODE}" == "omp_mailbox" ]]; then
    local args_base=""
    local args_result_addr=""
    local target_addr=""

    args_base=$("${CANONICAL_RISCV_PREFIX}nm" -n "${HOST_ELF}" | awk '
      $NF == "omp_mailbox_args" {
        print $1
        exit
      }
    ')
    [[ -n "${args_base}" ]] || die "could not locate omp_mailbox_args in ${HOST_ELF}"
    args_result_addr=$(printf '0x%x\n' $((0x${args_base} + 4)))

    target_addr=$("${HERO_INSTALL}/bin/llvm-nm" -n "${DEVICE_SYMBOL_ELF}" | awk '
      $NF == "omp_mailbox_target" {
        print "0x" $1
        exit
      }
    ')
    [[ -n "${target_addr}" ]] || \
      die "could not locate omp_mailbox_target in ${DEVICE_SYMBOL_ELF}"

    rg -q "${target_addr}" "${dev_trace}" || \
      die "device trace does not show execution at ${target_addr}"
    rg -q "is_store': 0x1.*writeback': ${args_result_addr}.*gpr_rdata_1': 0x12345679" "${dev_trace}" || \
      die "device trace does not show target stores 0x12345679 into ${args_result_addr}"
  fi

  rg -q '0x80000068.*00a2a023' "${host_trace}" || \
    die "host trace does not show the tohost exit write"
}

main() {
  need_cmd python
  need_cmd make
  need_cmd rg
  need_cmd bender
  need_cmd verilator
  need_cmd dtc
  need_cmd bc
  need_cmd gcc
  need_cmd g++
  need_cmd c++
  need_cmd ar
  need_cmd ld

  configure_mode

  [[ -d "${SIM_DIR}" ]] || die "missing Occamy simulator directory: ${SIM_DIR}"
  [[ -f "${DEVICE_APP_DIR}/Makefile" ]] || \
    die "missing ${APP_MODE} device payload sources in ${DEVICE_APP_DIR}; run ./scripts/bootstrap-local-occamy-minimal.sh to clone/check the expected Occamy branch"

  cd "${ROOT_DIR}"

  ensure_venv
  ensure_hero_device_toolchain
  resolve_verilator_root
  ensure_riscv_aliases
  verify_local_patch
  build_simulator
  build_selected_payload

  if [[ "${APP_MODE}" == "axpy" ]]; then
    run_and_verify_axpy
  else
    run_simulation
    verify_traces
  fi

  log "success"
  log "mode: ${APP_MODE}"
  log "host ELF: ${HOST_ELF}"
  log "device binary: ${DEVICE_BIN}"
  log "host trace: ${SIM_DIR}/trace_hart_00.dasm"
  log "device trace: ${SIM_DIR}/logs/trace_hart_00001.dasm"
}

main "$@"
