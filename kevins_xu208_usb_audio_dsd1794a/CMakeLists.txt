cmake_minimum_required(VERSION 3.21)
include($ENV{XMOS_CMAKE_PATH}/xcommon.cmake)
project(kevins_xu208_usb_audio)

set(APP_HW_TARGET XU208-128-QF48-C10.xn)
include(${CMAKE_CURRENT_LIST_DIR}/../deps.cmake)

# 3. 核心配置：添加你的自定义 Zbit Flash 规格文件与 QSPI 烧录参数
set(MY_FLASH_SPEC "${CMAKE_CURRENT_SOURCE_DIR}/zbit_flash.spec")
set(XFLASH_FLAGS "${XFLASH_FLAGS} --spec ${MY_FLASH_SPEC} --quad-spi-select")

# 4. 优化编译参数：去掉原版的板级宏（BOARD_SUPPORT_BOARD），改用自定义配置
set(SW_USB_AUDIO_FLAGS 
    ${EXTRA_BUILD_FLAGS} 
    -O3               # 开启最高等级代码尺寸与速度优化
    -report           # 编译后在控制台打印内存与线程资源报告
    -lquadflash       # 链接 QSPI Flash 驱动库
    -g 
    -Wall 
    -fxscope
    -D_BOARD_SUPPORT_BOARD_H_ # 2. 注入此宏，强制阻断官方 Board Support 头文件的自动加载
)

set(APP_COMPILER_FLAGS_xu208_stereo ${SW_USB_AUDIO_FLAGS} -DI2S_CHANS_DAC=2 -DI2S_CHANS_ADC=0 -DNUM_USB_CHAN_OUT=2 -DNUM_USB_CHAN_IN=0 -DMIDI=0 -DXUA_SPDIF_TX_EN=0 -DXUA_SPDIF_RX_EN=0 -DADAT_TX=0 -DADAT_RX=0 -DDSD_CHANS_DAC=2 -DNATIVE_DSD=1 -DMAX_FREQ=192000 -DUSB_TILE=tile[0])

include(${CMAKE_CURRENT_LIST_DIR}/configs_partial.cmake)
include(${CMAKE_CURRENT_LIST_DIR}/configs_build.cmake)
include(${CMAKE_CURRENT_LIST_DIR}/configs_test.cmake)

set(APP_INCLUDES src src/core src/extensions)
set(XMOS_SANDBOX_DIR ${CMAKE_CURRENT_LIST_DIR}/../..)

XMOS_REGISTER_APP()
