// // Copyright 2026 XMOS LIMITED.
// // This Software is subject to the terms of the XMOS Public Licence: Version 1.
// #include <xs1.h>
// #include <platform.h>

// // 1. 声明外部已经由 lib_xud 定义好的物理端口，避免 duplicate 报错
// // extern in port flag0_port;

// extern "C" {
//     // 2. 加上 extern "C" 确保 lib_xud 底层能正常识别和链接
//     unsigned int XUD_HAL_GetVBusState(void) 
//     {
//         // unsigned int vBus;
        
//         // // 3. 直接读取 lib_xud 自带的这个端口
//         // flag0_port :> vBus;
        
//         // return vBus;
//         return 1; // 强行让协议栈认为 VBUS 永远在线，直接启动 USB PHY 握手
//     }
// }


// Copyright 2026 XMOS LIMITED.
// This Software is subject to the terms of the XMOS Public Licence: Version 1.
#include <xs1.h>
#include <platform.h>

// 1. 显式绑定到 13 脚对应的物理 1 位端口 XS1_PORT_1D
in port p_real_vbus = XS1_PORT_1D;

extern "C" {
    // 2. 实现 lib_xud 动态回调，告别硬编码 return 1
    unsigned int XUD_HAL_GetVBusState(void) 
    {
        unsigned int vBusState;
        
        // 3. 读取 13 脚的真实分压电平
        p_real_vbus :> vBusState;
        
        // 4. 返回 1 (有手机/主机插入) 或 0 (已断开)
        return vBusState; 
    }
}
