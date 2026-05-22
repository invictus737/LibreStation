#!/bin/sh
# args from BR2_ROOTFS_POST_SCRIPT_ARGS
# $2    board name
. ${BR2_CONFIG}
set -e

INSTALL=install

# Add a console on tty1
grep -qE '^ttyGS0::' ${TARGET_DIR}/etc/inittab || \
sed -i '/GENERIC_SERIAL/a\
ttyGS0::respawn:/sbin/getty -L ttyGS0 0 vt100 # USB console' ${TARGET_DIR}/etc/inittab

grep -qE '^::sysinit:/bin/mount -t debugfs' ${TARGET_DIR}/etc/inittab || \
sed -i '/hostname/a\
::sysinit:/bin/mount -t debugfs none /sys/kernel/debug/' ${TARGET_DIR}/etc/inittab

sed -i -e '/::sysinit:\/bin\/hostname -F \/etc\/hostname/d' ${TARGET_DIR}/etc/inittab

grep -q mtd2 ${TARGET_DIR}/etc/fstab || echo "mtd2 /mnt/jffs2 jffs2 rw,noatime 0 0" >> ${TARGET_DIR}/etc/fstab

BOARD_DIR="$(dirname $0)"
BOARD_NAME="$(basename ${BOARD_DIR})"
GENIMAGE_CFG="${BOARD_DIR}/genimage-msd.cfg"
GENIMAGE_TMP="${BUILD_DIR}/genimage.tmp"
GCC_VERSION=$(${BR2_TOOLCHAIN_EXTERNAL_PREFIX}-gcc --version | head -1 | sed 's/.*(\(.*\))/\1/')
BIN_VERSION=$(${BR2_TOOLCHAIN_EXTERNAL_PREFIX}-as --version | head -1 | sed 's/.*(\(.*\))/\1/')
GCC_TRIPLE=$(${BR2_TOOLCHAIN_EXTERNAL_PREFIX}-gcc -v -c  2>&1 | sed 's/ /\n/g' | grep -e "--target" | awk -F= '{print $2}')
if [ "$BR2_TARGET_GENERIC_ROOT_PASSWD" = "analog" ] ; then
	ROOTPASSWD=$BR2_TARGET_GENERIC_ROOT_PASSWD;
else
	ROOTPASSWD="********"
fi

sed -e "s/#GCC_TRIPLE#/$GCC_TRIPLE/g" -e "s/#GCC_VERSION#/$GCC_VERSION/g" -e "s/#BIN_VERSION#/$BIN_VERSION/g" ${BOARD_DIR}/index.html -e "s/#ROOTPASSWORD#/$ROOTPASSWD/g" > ${BOARD_DIR}/msd/index.html

rm -rf "${GENIMAGE_TMP}"

genimage                           \
	--rootpath "${TARGET_DIR}"     \
	--tmppath "${GENIMAGE_TMP}"    \
	--inputpath "${BOARD_DIR}/msd"  \
	--outputpath "${TARGET_DIR}/opt/" \
	--config "${GENIMAGE_CFG}"

rm -f ${TARGET_DIR}/opt/boot.vfat
rm -f ${TARGET_DIR}/etc/init.d/S99iiod
rm -Rf ${TARGET_DIR}/etc/dropbear

mkdir -p ${TARGET_DIR}/www/img
mkdir -p ${TARGET_DIR}/etc/wpa_supplicant/
mkdir -p ${TARGET_DIR}/mnt/jffs2
mkdir -p ${TARGET_DIR}/mnt/msd
mkdir -p ${TARGET_DIR}/etc/dropbear
mkdir -p ${TARGET_DIR}/etc/ssl/certs
date -u +%s > ${TARGET_DIR}/etc/build_epoch
echo "EET-2EEST,M3.5.0/3,M10.5.0/4" > ${TARGET_DIR}/etc/TZ
if [ -f /etc/ssl/certs/ca-certificates.crt ]; then ${INSTALL} -D -m 0644 /etc/ssl/certs/ca-certificates.crt ${TARGET_DIR}/etc/ssl/certs/ca-certificates.crt; fi

${INSTALL} -D -m 0755 ${BOARD_DIR}/update.sh ${TARGET_DIR}/sbin/
${INSTALL} -D -m 0755 ${BOARD_DIR}/update_frm.sh ${TARGET_DIR}/sbin/
${INSTALL} -D -m 0755 ${BOARD_DIR}/udc_handle_suspend.sh ${TARGET_DIR}/sbin/
${INSTALL} -D -m 0755 ${BOARD_DIR}/S10mdev ${TARGET_DIR}/etc/init.d/
${INSTALL} -D -m 0755 ${BOARD_DIR}/S15watchdog ${TARGET_DIR}/etc/init.d/
${INSTALL} -D -m 0755 ${BOARD_DIR}/S20urandom ${TARGET_DIR}/etc/init.d/
${INSTALL} -D -m 0755 ${BOARD_DIR}/S21misc ${TARGET_DIR}/etc/init.d/
${INSTALL} -D -m 0755 ${BOARD_DIR}/S23udc ${TARGET_DIR}/etc/init.d/
${INSTALL} -D -m 0755 ${BOARD_DIR}/S38storage ${TARGET_DIR}/etc/init.d/
${INSTALL} -D -m 0755 ${BOARD_DIR}/S40network ${TARGET_DIR}/etc/init.d/
${INSTALL} -D -m 0755 ${BOARD_DIR}/S41network ${TARGET_DIR}/etc/init.d/
${INSTALL} -D -m 0755 ${BOARD_DIR}/S42timesync ${TARGET_DIR}/etc/init.d/
${INSTALL} -D -m 0755 ${BOARD_DIR}/S45msd ${TARGET_DIR}/etc/init.d/
${INSTALL} -D -m 0755 ${BOARD_DIR}/S55sdr_ip_gadget ${TARGET_DIR}/etc/init.d/
${INSTALL} -D -m 0644 ${BOARD_DIR}/fw_env.config ${TARGET_DIR}/etc/
${INSTALL} -D -m 0644 ${BOARD_DIR}/VERSIONS ${TARGET_DIR}/opt/
${INSTALL} -D -m 0755 ${BOARD_DIR}/device_reboot ${TARGET_DIR}/usr/sbin/
${INSTALL} -D -m 0755 ${BOARD_DIR}/device_passwd ${TARGET_DIR}/usr/sbin/
${INSTALL} -D -m 0600 ${BOARD_DIR}/authorized_keys ${TARGET_DIR}/root/.ssh/authorized_keys
${INSTALL} -D -m 0755 ${BOARD_DIR}/device_persistent_keys ${TARGET_DIR}/usr/sbin/
${INSTALL} -D -m 0755 ${BOARD_DIR}/device_format_jffs2 ${TARGET_DIR}/usr/sbin/
${INSTALL} -D -m 0644 ${BOARD_DIR}/motd ${TARGET_DIR}/etc/
${INSTALL} -D -m 0755 ${BOARD_DIR}/test_ensm_pinctrl.sh ${TARGET_DIR}/usr/sbin/
${INSTALL} -D -m 0644 ${BOARD_DIR}/device_config ${TARGET_DIR}/etc/
${INSTALL} -D -m 0644 ${BOARD_DIR}/mdev.conf ${TARGET_DIR}/etc/
${INSTALL} -D -m 0755 ${BOARD_DIR}/automounter.sh ${TARGET_DIR}/lib/mdev/automounter.sh
${INSTALL} -D -m 0755 ${BOARD_DIR}/ifupdown.sh ${TARGET_DIR}/lib/mdev/ifupdown.sh
${INSTALL} -D -m 0644 ${BOARD_DIR}/input-event-daemon.conf ${TARGET_DIR}/etc/

${INSTALL} -D -m 0644 ${BOARD_DIR}/msd/img/* ${TARGET_DIR}/www/img/
${INSTALL} -D -m 0644 ${BOARD_DIR}/msd/*.html ${TARGET_DIR}/www/

${INSTALL} -D -m 0755 ${BOARD_DIR}/wpa_supplicant/* ${TARGET_DIR}/etc/wpa_supplicant/

ln -sf ../../wpa_supplicant/ifupdown.sh ${TARGET_DIR}/etc/network/if-up.d/wpasupplicant
ln -sf ../../wpa_supplicant/ifupdown.sh ${TARGET_DIR}/etc/network/if-down.d/wpasupplicant
ln -sf ../../wpa_supplicant/ifupdown.sh ${TARGET_DIR}/etc/network/if-pre-up.d/wpasupplicant
ln -sf ../../wpa_supplicant/ifupdown.sh ${TARGET_DIR}/etc/network/if-post-down.d/wpasupplicant

ln -sf device_reboot ${TARGET_DIR}/usr/sbin/pluto_reboot


# LibreStation shell defaults
cat > "${TARGET_DIR}/etc/profile" <<'PROFILE'
export PATH=/bin:/sbin:/usr/bin:/usr/sbin:/usr/local/bin:/usr/local/sbin
export PS1='LibreStation# '
export HISTFILE=/root/.bash_history
export EDITOR='/bin/nano'
PROFILE
if [ -x "${TARGET_DIR}/bin/bash" ] && [ -f "${TARGET_DIR}/etc/passwd" ]; then
    sed -i 's#^root:[^:]*:0:0:[^:]*:/root:/bin/[^:]*#root:x:0:0:root:/root:/bin/bash#' "${TARGET_DIR}/etc/passwd"
fi

# LibreStation login banner, written last so Buildroot/board defaults cannot override it.
cat > "${TARGET_DIR}/etc/issue" <<'BANNER'
Welcome to LibreStation by YO3TCO
BANNER

cat > "${TARGET_DIR}/etc/motd" <<'BANNER'
Welcome to LibreStation by YO3TCO:
  _      _ _              _____ _        _   _
 | |    (_) |            / ____| |      | | (_)
 | |     _| |__  _ __ __| (___ | |_ __ _| |_ _  ___  _ __
 | |    | | '_ \| '__/ _ \\___ \| __/ _` | __| |/ _ \| '_ \
 | |____| | |_) | | |  __/____) | || (_| | |_| | (_) | | | |
 |______|_|_.__/|_|  \___|_____/ \__\__,_|\__|_|\___/|_| |_|

LibreSDR v0.2 timestamp firmware
Zynq-7020 / AD9363 / 2R2T hardware / Chris YO3TCO
BANNER

if [ -f "${TARGET_DIR}/usr/lib/os-release" ]; then
    sed -i 's/-dirty//g' "${TARGET_DIR}/usr/lib/os-release"
fi
