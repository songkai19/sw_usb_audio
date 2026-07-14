cmake_minimum_required(VERSION 3.21)
include($ENV{XMOS_CMAKE_PATH}/xcommon.cmake)
project(kevins_xu316_usb_audio)

set(APP_INCLUDES src src/core src/extensions)
set(XMOS_SANDBOX_DIR ${CMAKE_CURRENT_LIST_DIR}/../..)
set(APP_HW_TARGET XU316-1024-QF60B-C24.xn)
include(${CMAKE_CURRENT_LIST_DIR}/../deps.cmake)

set(APP_PCA_ENABLE OFF)
set(APP_DEPENDENT_MODULES "lib_gpio")

# 3. 核心配置：添加你的自定义 Zbit Flash 规格文件与 QSPI 烧录参数
set(MY_FLASH_SPEC "${CMAKE_CURRENT_SOURCE_DIR}/zbit_flash.spec")
set(XFLASH_FLAGS "${XFLASH_FLAGS} --spec ${MY_FLASH_SPEC} --quad-spi-select")

set(SW_USB_AUDIO_FLAGS ${EXTRA_BUILD_FLAGS} -O3
                                            -report
                                            -lquadflash
                                            -g
                                            -Wall
                                            -fxscope)

# Build config naming scheme:
#
# Audio Class:   1 or 2
# Sync Mode      A(sync) or S(ync)
# I2S            M(aster) or S(lave)
# Input          enabled: i (channelcount)
# Output         enabled: o (channelcount)
# MIDI           enabled: m, disabled: x
# SPDIF in       enabled: s, disabled: x
# SPDIF out      enabled: s, disabled: x
# ADAT in        enabled: a, disabled: x
# ADAT out       enabled: a, disabled: x
# DSD out        enabled: d, disabled: x
#
# e.g. 2AMi10o10xxsxxx: Audio class 2.0, Asynchronous, I2S Master, input and output enabled (10 channels each), no MIDI, SPDIF output, no SPDIF input, no ADAT
#
# Additional tags may be added to the end of the build config name to indicate special features or configurations.

#
# Tested build configs
#

# Audio Class 2, Async, I2S Master, 8xInput, 8xOutput
set(APP_COMPILER_FLAGS_2AMi0o2xxxxxd ${SW_USB_AUDIO_FLAGS})

XMOS_REGISTER_APP()
