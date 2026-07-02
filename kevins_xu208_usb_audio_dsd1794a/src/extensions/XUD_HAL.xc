// Copyright 2026 XMOS LIMITED.
// This Software is subject to the terms of the XMOS Public Licence: Version 1.
// #include <xs1.h>
// #include <platform.h>

// in port p_vbus_stats = XS1_PORT_1D;

// extern "C" {
//     // 2. 实现 lib_xud 动态回调，告别硬编码 return 1
//     unsigned int XUD_HAL_GetVBusState(void) 
//     {
//         unsigned vBusState;
        
//         // 3. 读取 47 脚的真实分压电平
//         p_vbus_stats :> vBusState;
        
//         // 4. 返回 1 (有手机/主机插入) 或 0 (已断开)
//         return vBusState; 
//     }
// }
