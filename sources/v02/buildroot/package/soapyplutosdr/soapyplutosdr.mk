################################################################################
#
# soapyplutosdr
#
################################################################################

SOAPYPLUTOSDR_VERSION = 2bbf77152d4e6d30c6630807fdfc8a869a528cf3
SOAPYPLUTOSDR_SITE = https://github.com/pgreenland/SoapyPlutoSDR.git
SOAPYPLUTOSDR_SITE_METHOD = git
SOAPYPLUTOSDR_LICENSE = LGPL-2.1
SOAPYPLUTOSDR_LICENSE_FILES = LICENSE
SOAPYPLUTOSDR_DEPENDENCIES = host-pkgconf soapysdr libiio libad9361-iio libusb

SOAPYPLUTOSDR_CONF_OPTS = \
	-DSoapySDR_DIR=$(STAGING_DIR)/usr/share/cmake/SoapySDR

$(eval $(cmake-package))
