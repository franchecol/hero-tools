#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
ROOT_DIR=$(cd -- "${SCRIPT_DIR}/.." && pwd)
LOCK_FILE="${SCRIPT_DIR}/occamy-m0.lock.env"
PYTHON_REQUIREMENTS="${SCRIPT_DIR}/requirements-occamy-m0.txt"
M1_LOCK_FILE="${SCRIPT_DIR}/occamy-m1.lock.env"

[[ -f "${LOCK_FILE}" ]] || {
  printf '[occamy-minimal] ERROR: missing lock file: %s\n' "${LOCK_FILE}" >&2
  exit 1
}
# shellcheck disable=SC1090
source "${LOCK_FILE}"

SIM_DIR="${ROOT_DIR}/platforms/occamy/target/sim"
DEVICE_RUNTIME_DIR="${SIM_DIR}/sw/device/runtime"
DEVICE_MATH_DIR="${SIM_DIR}/sw/device/math"
VENV_DIR="${ROOT_DIR}/.venv-occamy"
USER_BIN_DIR="${HOME}/bin"
HERO_INSTALL_DIR="${HERO_INSTALL:-${ROOT_DIR}/install}"
CANONICAL_RISCV_PREFIX="riscv64-unknown-elf-"
RISCV_SRC_PREFIX=""
VLT_JOBS="${VLT_JOBS:-1}"
VLT_TRACE="${VLT_TRACE:-0}"
VLT_PROF="${VLT_PROF:-0}"
VLT_OUTPUT_SPLIT="${VLT_OUTPUT_SPLIT:-5000}"
VLT_OUTPUT_SPLIT_CFUNCS="${VLT_OUTPUT_SPLIT_CFUNCS:-5000}"
VLT_CC="${VLT_CC:-cc}"
VLT_CXX="${VLT_CXX:-c++}"
M0_STRICT_VERSIONS="${M0_STRICT_VERSIONS:-1}"
M0_ALLOW_UNPINNED="${M0_ALLOW_UNPINNED:-0}"
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

check_version() {
  local name="$1"
  local expected="$2"
  local actual="$3"

  if [[ "${actual}" == "${expected}" ]]; then
    log "${name}: ${actual}"
  elif [[ "${M0_STRICT_VERSIONS}" == "1" ]]; then
    die "${name} version mismatch: expected '${expected}', got '${actual}'. Set M0_STRICT_VERSIONS=0 to test an unverified version."
  else
    log "WARNING: ${name} version is unverified: expected '${expected}', got '${actual}'"
  fi
}

check_sha256() {
  local name="$1"
  local expected="$2"
  local path="$3"
  local actual

  actual=$(sha256sum "${path}" | awk '{print $1}')
  [[ "${actual}" == "${expected}" ]] || \
    die "${name} checksum mismatch: expected ${expected}, got ${actual} (${path})"
  log "${name} checksum: ${actual}"
}

verify_m1_sources() {
  [[ "${APP_MODE}" == "roundtrip" ]] || return 0
  [[ -f "${M1_LOCK_FILE}" ]] || die "missing M1 lock file: ${M1_LOCK_FILE}"

  # shellcheck disable=SC1090
  source "${M1_LOCK_FILE}"

  check_sha256 "M1 device Makefile" "${OCCAMY_M1_DEVICE_MAKEFILE_SHA256}" \
    "${DEVICE_APP_DIR}/Makefile"
  check_sha256 "M1 device source" "${OCCAMY_M1_DEVICE_SOURCE_SHA256}" \
    "${DEVICE_APP_DIR}/src/roundtrip.S"
  check_sha256 "M1 host Makefile" "${OCCAMY_M1_HOST_MAKEFILE_SHA256}" \
    "${HOST_APP_DIR}/Makefile"
  check_sha256 "M1 host source" "${OCCAMY_M1_HOST_SOURCE_SHA256}" \
    "${HOST_APP_DIR}/src/roundtrip.c"
}

verify_reproducible_environment() {
  local occamy_head

  [[ -f "${PYTHON_REQUIREMENTS}" ]] || \
    die "missing pinned Python requirements: ${PYTHON_REQUIREMENTS}"

  occamy_head=$(git -C "${ROOT_DIR}/platforms/occamy" rev-parse HEAD)
  if [[ "${occamy_head}" != "${OCCAMY_M0_COMMIT}" && "${M0_ALLOW_UNPINNED}" != "1" ]]; then
    die "Occamy HEAD is ${occamy_head}, expected ${OCCAMY_M0_COMMIT}. Run the bootstrap from a clean checkout or set M0_ALLOW_UNPINNED=1."
  fi

  check_version "Python" "${OCCAMY_M0_PYTHON_VERSION}" "$(python -c 'import platform; print(platform.python_version())')"
  check_version "Bender" "${OCCAMY_M0_BENDER_VERSION}" "$(bender --version)"
  check_version "Verilator" "${OCCAMY_M0_VERILATOR_VERSION}" "$(verilator --version | head -n 1)"
  check_version "host GCC" "${OCCAMY_M0_HOST_GCC_VERSION}" "$("${VLT_CC}" --version | head -n 1)"
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

  check_version "Occamy virtualenv Python" "${OCCAMY_M0_PYTHON_VERSION}" \
    "$(python -c 'import platform; print(platform.python_version())')"

  log "synchronizing pinned Python build dependencies"
  python -m pip install --disable-pip-version-check --no-deps \
    --requirement "${PYTHON_REQUIREMENTS}"

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
  log "using $(verilator --version | head -n 1) with VLT_JOBS=${VLT_JOBS}, VLT_TRACE=${VLT_TRACE}, VLT_PROF=${VLT_PROF}"
  log "using Verilator output split: VLT_OUTPUT_SPLIT=${VLT_OUTPUT_SPLIT}, VLT_OUTPUT_SPLIT_CFUNCS=${VLT_OUTPUT_SPLIT_CFUNCS}"
  log "using simulator C/C++ compilers: CC=${VLT_CC}, CXX=${VLT_CXX}"
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
  need_cmd "${CANONICAL_RISCV_PREFIX}nm"
  check_version "RISC-V GCC" "${OCCAMY_M0_RISCV_GCC_VERSION}" \
    "$("${CANONICAL_RISCV_PREFIX}gcc" --version | head -n 1)"
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
    VLT_JOBS="${VLT_JOBS}" \
    VLT_TRACE="${VLT_TRACE}" \
    VLT_PROF="${VLT_PROF}" \
    VLT_OUTPUT_SPLIT="${VLT_OUTPUT_SPLIT}" \
    VLT_OUTPUT_SPLIT_CFUNCS="${VLT_OUTPUT_SPLIT_CFUNCS}" \
    CC="${VLT_CC}" \
    CXX="${VLT_CXX}" \
    CXXFLAGS='-include cstdint -fcoroutines' \
    bin/occamy_top.vlt
}

get_symbol_addr() {
  local nm_bin="$1"
  local elf="$2"
  local symbol="$3"

  "${nm_bin}" -n "${elf}" | awk -v symbol="${symbol}" '
    $NF == symbol && !found {
      value = "0x" $1
      found = 1
    }
    END { print value }
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
    local snitch_base=""
    local device_store_offset=""
    local device_store_pc=""
    local host_clear_pc=""
    local host_exit_pc=""

    snitch_base=$(get_symbol_addr "${CANONICAL_RISCV_PREFIX}nm" "${HOST_ELF}" snitch_main)
    [[ -n "${snitch_base}" ]] || die "could not locate snitch_main in ${HOST_ELF}"

    device_store_offset=$("${CANONICAL_RISCV_PREFIX}objdump" -d "${DEVICE_SYMBOL_ELF}" | awk '
      /sw[[:space:]]+t2,0\(t1\).*4000000/ && !found {
        sub(/:$/, "", $1)
        value = "0x" $1
        found = 1
      }
      END { print value }
    ')
    [[ -n "${device_store_offset}" ]] || \
      die "could not locate the device host-interrupt store in ${DEVICE_SYMBOL_ELF}"
    device_store_pc=$(printf '0x%x\n' $((snitch_base + device_store_offset)))

    host_clear_pc=$("${CANONICAL_RISCV_PREFIX}objdump" -d "${HOST_ELF}" | awk '
      /sw[[:space:]]+zero,0\(a4\).*4000000/ && !found {
        sub(/:$/, "", $1)
        value = "0x" $1
        found = 1
      }
      END { print value }
    ')
    [[ -n "${host_clear_pc}" ]] || \
      die "could not locate the host SW-interrupt clear store in ${HOST_ELF}"

    host_exit_pc=$("${CANONICAL_RISCV_PREFIX}objdump" -d "${HOST_ELF}" | awk '
      /sw[[:space:]]+a0,0\(t0\)/ && !found {
        sub(/:$/, "", $1)
        value = "0x" $1
        found = 1
      }
      END { print value }
    ')
    [[ -n "${host_exit_pc}" ]] || \
      die "could not locate the tohost exit store in ${HOST_ELF}"

    rg -q "${device_store_pc}.*DASM\\(00732023\\).*opa': 0x4000000.*gpr_rdata_1': 0x1" "${dev_trace}" || \
      die "device trace does not show the host interrupt store at ${device_store_pc}"
    rg -q "${host_clear_pc}.*DASM\\(00072023\\)" "${host_trace}" || \
      die "host trace does not show the SW-interrupt clear store at ${host_clear_pc}"
    rg -q "${host_exit_pc}.*DASM\\(00a2a023\\)" "${host_trace}" || \
      die "host trace does not show the tohost exit store at ${host_exit_pc}"
  elif [[ "${APP_MODE}" == "roundtrip" ]]; then
    local snitch_base=""
    local device_data_store_offset=""
    local device_data_store_pc=""
    local device_irq_store_offset=""
    local device_irq_store_pc=""
    local host_clear_pc=""
    local host_exit_pc=""
    local host_failure_pc=""
    local word_index=""
    local word_addr=""
    local word_value=""

    # shellcheck disable=SC1090
    source "${M1_LOCK_FILE}"

    roundtrip_base=$(get_symbol_addr "${CANONICAL_RISCV_PREFIX}nm" "${HOST_ELF}" roundtrip_buffer)
    [[ -n "${roundtrip_base}" ]] || die "could not locate roundtrip_buffer in ${HOST_ELF}"

    snitch_base=$(get_symbol_addr "${CANONICAL_RISCV_PREFIX}nm" "${HOST_ELF}" snitch_main)
    [[ -n "${snitch_base}" ]] || die "could not locate snitch_main in ${HOST_ELF}"

    device_data_store_offset=$("${CANONICAL_RISCV_PREFIX}objdump" -d "${DEVICE_SYMBOL_ELF}" | awk '
      /sw[[:space:]]+t6,0\(t3\)/ && !found {
        sub(/:$/, "", $1)
        value = "0x" $1
        found = 1
      }
      END { print value }
    ')
    [[ -n "${device_data_store_offset}" ]] || \
      die "could not locate the M1 data store in ${DEVICE_SYMBOL_ELF}"
    device_data_store_pc=$(printf '0x%x\n' $((snitch_base + device_data_store_offset)))

    device_irq_store_offset=$("${CANONICAL_RISCV_PREFIX}objdump" -d "${DEVICE_SYMBOL_ELF}" | awk '
      /sw[[:space:]]+t2,0\(t1\).*4000000/ && !found {
        sub(/:$/, "", $1)
        value = "0x" $1
        found = 1
      }
      END { print value }
    ')
    [[ -n "${device_irq_store_offset}" ]] || \
      die "could not locate the M1 interrupt store in ${DEVICE_SYMBOL_ELF}"
    device_irq_store_pc=$(printf '0x%x\n' $((snitch_base + device_irq_store_offset)))

    host_clear_pc=$("${CANONICAL_RISCV_PREFIX}objdump" -d "${HOST_ELF}" | awk '
      /sw[[:space:]]+zero,0\(a4\).*4000000/ && !found {
        sub(/:$/, "", $1)
        value = "0x" $1
        found = 1
      }
      END { print value }
    ')
    [[ -n "${host_clear_pc}" ]] || \
      die "could not locate the host SW-interrupt clear store in ${HOST_ELF}"

    host_exit_pc=$("${CANONICAL_RISCV_PREFIX}objdump" -d "${HOST_ELF}" | awk '
      /sw[[:space:]]+a0,0\(t0\)/ && !found {
        sub(/:$/, "", $1)
        value = "0x" $1
        found = 1
      }
      END { print value }
    ')
    [[ -n "${host_exit_pc}" ]] || die "could not locate the tohost store in ${HOST_ELF}"

    host_failure_pc=$("${CANONICAL_RISCV_PREFIX}objdump" -d "${HOST_ELF}" | awk '
      /<main>:/ {
        in_main = 1
        next
      }
      in_main && /^$/ {
        in_main = 0
      }
      in_main && /li[[:space:]]+a0,1/ && !found {
        sub(/:$/, "", $1)
        value = "0x" $1
        found = 1
      }
      END { print value }
    ')
    [[ -n "${host_failure_pc}" ]] || \
      die "could not locate the M1 validation failure path in ${HOST_ELF}"

    for ((word_index = 0; word_index < OCCAMY_M1_WORDS; ++word_index)); do
      word_addr=$(printf '0x%x\n' $((roundtrip_base + word_index * 4)))
      word_value=$(printf '0x%x\n' $((word_index + 1)))
      rg -q "${device_data_store_pc}.*DASM\\(01fe2023\\).*opa': ${word_addr}.*gpr_rdata_1': ${word_value}" "${dev_trace}" || \
        die "device trace does not show M1 word ${word_index} written as ${word_value} at ${word_addr}"
    done

    rg -q "${device_irq_store_pc}.*DASM\\(00732023\\).*opa': 0x4000000.*gpr_rdata_1': 0x1" "${dev_trace}" || \
      die "device trace does not show the M1 completion interrupt"
    rg -q "${host_clear_pc}.*DASM\\(00072023\\)" "${host_trace}" || \
      die "host trace does not show the M1 interrupt clear"
    if rg -q "${host_failure_pc}" "${host_trace}"; then
      die "host trace entered the M1 buffer-validation failure path at ${host_failure_pc}"
    fi
    rg -q "${host_exit_pc}.*DASM\\(00a2a023\\)" "${host_trace}" || \
      die "host trace does not show the M1 tohost exit"
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

  if [[ "${APP_MODE}" != "minimal_irq" && "${APP_MODE}" != "roundtrip" ]]; then
    rg -q '0x80000068.*00a2a023' "${host_trace}" || \
      die "host trace does not show the tohost exit write"
  fi
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
  need_cmd sha256sum

  configure_mode

  [[ -d "${SIM_DIR}" ]] || die "missing Occamy simulator directory: ${SIM_DIR}"
  [[ -f "${DEVICE_APP_DIR}/Makefile" ]] || \
    die "missing ${APP_MODE} device payload sources in ${DEVICE_APP_DIR}; run ./scripts/bootstrap-local-occamy-minimal.sh to clone/check the expected Occamy branch"

  cd "${ROOT_DIR}"

  verify_reproducible_environment
  verify_m1_sources
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
