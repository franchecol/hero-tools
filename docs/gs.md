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



## Buiding the host software

From now, you will need to select a platform to continue with, the platform is decided by the following variables:
- HERO_HOST can be
  - cva6
  - sg2042
- HERO_DEVICE can be
  - occamy_snitch_cluster
  - carfield_snitch_cluster
  - carfield_spatz_cluster
  - carfield_safety_island

### Building the Linux kernel module

The kernel modules are located in `sw/hero-driver`. The modules are shared for a platform. For instance, Carfield has a unique module that maps every island. If any island is not actually on-chip (on-FPGA) it will detect it and won't map it.

To build a kernel module do:

```bash
# Make sure that you have BR_LINUX_DIR set, otherwise re-source setenv.sh
source scripts/setenv.sh
echo $BR_LINUX_DIR

# Go the the module's source and compile it
cd sw/hero-driver/carfield
make

# Now you can copy your module into your Linux image rootfs
cp *.ko $HERO_ROOT/cva6-sdk/rootfs/root/

```

__Note:__ Everytime your change the rootfs, you must update the Linux image like so:

```bash
cd $HERO_ROOT/cva6-sdk
make clean images
# Your new image is in install64/uImage
```


### Building the runtimes for the host

Now that you have the kernel module, you will need to build the host libraries that allow offloading.
- libhero: It bridges between the hardware drivers and the OpenMP runtime. You can find its code in `sw/libhero`,
- libomp: The OpenMP runtime. It is built in `sw/libomp` but its sources are in `toolchain/llvm-project/openmp`
- libllvm: Auxiliaries libraries needed by the OpenMP runtime. It is built in `sw/libllvm`. You can find its code in `toolchain/llvm-project/llvm`

All these libraries are compiled for the host (RV64) using the GCC compiler you previously built.

You can compile all at once:

```bash
make HERO_HOST=[host] HERO_DEVICE=[device] hero-sw-all
```

Similarly, you can deploy the libraries to the `rootfs`:

```bash
make HERO_HOST=[host] HERO_DEVICE=[device] hero-sw-all hero-sw-deploy
# Now you need to rebuild your Linux image
```

## Buiding the device software

The device software does not reside in this repository but directly with the hardware.
To build the device library, this repo will the hardware repos based on `platforms/platforms.mk`.

For instance, you can build the device software for Carfield Snitch using

```bash
make hero-carfield-snitch-sw-all
```

Go to [Targets](platforms/index.md) for more informations.

## Building the application

Since now, you have built:

- The GCC compiler for CVA6
- The Linux image for CVA6
- The kernel module to map the system's address map
- The host libraries (libllvm, libomp, libhero)
- The device library

You can go and build an example application in `apps`.

```bash
cd apps/omp/basic/offload_benchmark
# Attention to add the "all"
make HERO_HOST=cva6 HERO_DEVICE=carfield_snitch_cluster all
```
