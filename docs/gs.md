# Getting Started

The central components of HeroSDK are the GCC/LLVM toolchains, and the Linux image for CVA6, we will start by compiling them.

## Prior notes

```bash
# Before starting make sure you set up your environment on every terminal you use!
source scripts/setenv.sh
# Set up your FPGA specific variables too
source scripts/[your_fpga].sh
```

```bash
# Before starting make sure you are on the correct branch (the CVA6-SDK is platform-specific at the moment)
# You can choose between carfield/main and occamy/main
git checkout [platform]/main
git submodule update --init --recursive
# If you have old builds from other branches in the CVA6-sdk, it may worth deep cleaning it
cd cva6-sdk
git clean -fdx
git submodule foreach "git clean -fdx"
```

## Building the toolchains

### Building the GCC toolchain (riscv64-linux-gcc)

You will first need to build the RISCV64 Linux GCC compiler. This GCC compiler is used to compile the kernel and
Linux modules. It will also provide a RISCV64 standard library to be used later by the LLVM toolchain when compiler
Linux userspace applications.

```bash
make hero-tc-gcc
```

__Note:__ this command will just enter the CVA6-sdk which contains the configuration files to build the toolchain with Buildroot. It is equivalent to do:
```bash
make -C cva6-sdk all
```
(See the CVA6-sdk readme and Makefile for more infos)

You should now have the GCC toolchain installed in `cva6-sdk/buildroot/output/host/`

```bash
$ ls cva6-sdk/buildroot/output/host/    
bin  etc  include  lib  lib64  libexec  riscv64-buildroot-linux-gnu  sbin  share  usr
```

### Building the LLVM toolchain (riscv64-linux-clang) (riscv64-elf-clang) (riscv32-elf-clang)

In order to build heterogeneous applications, you need to build the multiarch LLVM compiler. This toolchain is based on LLVM15 and contains support for
the following extensions:

- Snitch: xssr xdma xfrep xmempool
- Smallfloat: ...
- Pulp: xpulpv

(See `toolchain/llvm-project/llvm/lib/Support/RISCVISAInfo.cpp`)

We will also build a C newlib for all the supported architecture (this will take multiple GB on disk).

```bash
make hero-tc-llvm
```

You should now have the LLVM toolchain installed in `install`

```bash
$ ls install 
bin  include  lib  libexec  rv32imafd-ilp32d  rv32imafdvzfh-ilp32d  rv32ima-ilp32  rv64g-lp64d  share
```


## Building the Linux image

You will now build the Linux image with the CVA6-SDK.

```bash
make hero-cva6-sdk-all
```

This will create multiple files in `cva6-sdk/install64` including:

- fw_payload.bin: OpenSBI with U-boot as a payload
- uImage: A Linux image ready to be read by u-boot (from a flash/file server)
- vmlinux: An intermediate result of the uImage, this can be used to obtain debug symbols


## Building the runtimes for Linux

The command below will compile the libhero (bridging between the hardware drivers and the OpenMP runtime), the libllvm (required for the OpenMP target runtime), and the the OpenMP target host runtime itself.
All these libraries are compiled for the host (RV64) using the GCC compiler previously built.

```bash
make HERO_HOST=cva6 HERO_DEVICE=[platform] hero-sw-all
```

## Start your platform on an FPGA

Go to [Targets](platforms/index.md) and pick the architecture you want to use.
