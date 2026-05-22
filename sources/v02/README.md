# LibreStation v02 Source Overlay

This directory captures the source-side changes used for the LibreStation v02
firmware artifacts committed on `main` and tagged as `v02`.

Base revisions used on the build host:

- `plutosdr-fw`: `0359a0b9a474567ab658619f3edf53ac65594f5a`
- `buildroot`: `f70f4aff40bcc16e3d9a920984d034ad108f4993`
- `linux`: `e14e351533f934047ba0473e836e561682ec67fe`
- `u-boot-xlnx`: `90401ce9ce029e5563f4dface63914d42badf5bc`
- `hdl`: `1978df2985ce230f3a50b717accd7066609866ec`

Contents:

- `patches/` contains tracked-file diffs against the base trees.
- `plutosdr-fw/` contains top-level LibreStation build files and scripts.
- `buildroot/` contains the Libre board overlay, SDR gadget packages, SoapySDR
  packages, and Libre defconfig.
- `linux/` contains the Libre DTS/DTSI, kernel defconfig, and final Kconfig
  files used for the build.
- `u-boot-xlnx/` contains the Libre U-Boot defconfig, DTS, and final config
  header.
- `hdl/projects/libre/` contains the small source files for the Libre HDL
  project.
- `hdl-quantulum/` contains the timestamp HDL helper cores.

The generated Vivado project output under `hdl/projects/libre/libre.*` was not
committed. It is build output and was about 190 MB on the build host. The
released bitstream is included separately under `firmware/sdimg/system_top.bit`.
