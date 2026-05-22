################################################################################
#
# soapysdr
#
################################################################################

SOAPYSDR_VERSION = soapy-sdr-0.8.1
SOAPYSDR_SITE = https://github.com/pothosware/SoapySDR.git
SOAPYSDR_SITE_METHOD = git
SOAPYSDR_LICENSE = BSL-1.0
SOAPYSDR_LICENSE_FILES = LICENSE_1_0.txt
SOAPYSDR_INSTALL_STAGING = YES
SOAPYSDR_DEPENDENCIES = host-pkgconf

SOAPYSDR_CONF_OPTS = 
	-DSOAPY_SDR_EXTVER=buildroot 
	-DENABLE_DOCS=OFF 
	-DENABLE_PYTHON=OFF 
	-DENABLE_PYTHON3=OFF 
	-DENABLE_TESTS=OFF

ifeq ($(BR2_PACKAGE_SOAPYSDR_UTIL),y)
SOAPYSDR_CONF_OPTS += -DENABLE_APPS=ON
else
SOAPYSDR_CONF_OPTS += -DENABLE_APPS=OFF
endif

$(eval $(cmake-package))
