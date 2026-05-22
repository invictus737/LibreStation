# LibreStation by YO3TCO

LibreStation is a LibreSDR Rev.5 / HamGeek Zynq-7020 AD9363 firmware build focused on SDR timestamping support and practical recovery workflows.

## Hardware

- LibreSDR Rev.5 / HamGeek Zynq-7020
- 1 GB DDR
- AD9363 RF transceiver
- 2R2T hardware
- QSPI flash and SD card boot support

## Firmware

This repository contains a tested SD-card image payload and SPI update artifacts:

- `firmware/sdimg/` - files to place on the SD card boot partition
- `firmware/libre.frm` - SPI firmware/FIT update image
- `firmware/boot.frm` - SPI bootloader/environment update image
- `firmware/libre.itb` - FIT image containing FPGA, kernel, device tree, and ramdisk
- `sources/v02/` - source overlay and patches used for the v02 firmware build

Recommended recovery path: test via SD card first. The SD card is mounted automatically at `/mnt/storage`, where additional binaries such as `bluestation-bs` or `flowstation-bs` can be placed.

## Defaults

- Hostname: `LibreStation`
- SSH user: `root`
- Default IP: `192.168.1.10`
- Shell: `bash`
- Prompt: `LibreStation#`
- CPU/DDR target: stable LibreSDR overclock profile used for this build

## Credits

This work builds on:

- Analog Devices PlutoSDR firmware
- pgreenland/plutosdr-fw
- wahlm/plutosdr-fw-timestamp
- hz12opensource/libresdr

Signed,
Chris YO3TCO
