// Copyright (c) 2012-2026, XMOS Ltd, All rights reserved
#include <xs1.h>
#include <platform.h>
#include "xua_conf.h"
#include "print.h"

// /* .xn 里定义的 4位宽 晶振控制端口 (对应 X0D16~19) */
port p_clk_en = PORT_CLK_EN;
port p_mode_sel = PORT_MODE_SEL;
port p_clk_fmt = PORT_CLK_FORMAT;

// /* ========================================================================= */
// /* 0. 借鉴 JohnnyOpcode 的硬件 100MHz 内部定时器微秒延时函数 */
// /* ========================================================================= */
// static void wait_us(int microseconds)
// {
//     timer t;
//     unsigned time;
//     t :> time;
//     t when timerafter(time + (microseconds * 100)) :> void;
// }

/* ========================================================================= */
/* 1. 标准硬件初始化函数 */
/* ========================================================================= */
void AudioHwInit(void)
{
    // /* 开机默认初始化：默认使能 45.1584MHz 晶振 */
    // /* 对应原厂图：4D0(X0D16) = 1, 4D1(X0D17) = 0 -> 二进制 0001 */
    p_clk_en <: 0x01; 

    // /* 开机默认初始化：44.1kHz PCM SINGLE MODE */
    p_mode_sel   <: 0x01;  // SINGLE MODE (4E0=1, 4E1=0)
    p_clk_fmt <: 0x00;  // 441 MODE + PCM MODE (4F0=0, 4F1=0)

    // /* 借鉴：留出 20ms 给晶振起振并达到绝对稳定，完美消除开机爆音 */
    // wait_us(20000); 
}

void AudioHwConfig(unsigned samFreq, unsigned mClk, unsigned dsdMode, unsigned samRes_or_dsaBase, unsigned mClk_div)
{
    unsigned mode_val = 0x01; // 默认 SINGLE MODE
    unsigned clk_fmt_val = 0x00;

    // if (samFreq == 0)
    // {
    //     return;
    // }

    if (mClk == MCLK_441) {
        p_clk_en <: 0x01; // 激活 45.1584MHz 晶振
    } else {
        p_clk_en <: 0x02; // 激活 49.152MHz 晶振
    }

    // /* ------------------------------------------------------------- */
    // /* 逻辑 A：判断并输出 P1、P2 (4E0, 4E1) 的倍频模式 (SINGLE/DOUBLE/QUAD) */
    // /* ------------------------------------------------------------- */
    if (samFreq == 176400 || samFreq == 192000) 
    {
        mode_val = 0x03; // QUAD MODE (4E0=1, 4E1=1)
    } 
    else if (samFreq == 88200 || samFreq == 96000) 
    {
        mode_val = 0x02; // DOUBLE MODE (4E0=0, 4E1=1)
    } 
    else 
    {
        mode_val = 0x01; // SINGLE MODE (4E0=1, 4E1=0)
    }
    p_mode_sel <: mode_val;

    // /* ------------------------------------------------------------- */
    // /* 逻辑 B：判断并输出 P3、P4 (4F0, 4F1) 的时钟基准与音频格式 */
    // /* ------------------------------------------------------------- */
    // // 1. 先判断 P3 (4F0) 晶振基准
    if (samFreq % 48000 == 0) 
    {
        clk_fmt_val |= 0x01; // 48 MODE (4F0=1)
    } 
    else 
    {
        clk_fmt_val |= 0x00; // 441 MODE (4F0=0)
    }

    // // 2. 再判断 P4 (4F1) 编码格式 (PCM / DSD)
    // // dsdMode 的取值由 XMOS 底层自动判断：
    // // 0 = 当前电脑在放普通 PCM 音乐（I2S 格式）
    // // 1 = 当前电脑在放 Native DSD 或 DoP 音乐（DSD 格式）

    // // if (dsdMode == 1) {
    // //     /* 【定制代码】当前进入了 DSD 播放模式 */
    // //     // 1. 如果你的 DAC 芯片有独立的 DSD/PCM 切换引脚（例如某些芯片的 DSD_ON 脚）
    // //     //    在这里控制对应的 GPIO 拉高或拉低。
    // //     // 2. 如果你的 DAC 是通过 I2C 寄存器控制的，在这里通过 I2C 发送“进入 DSD 模式”的命令。
    // //     clk_fmt_val |= 0x02; // DSD MODE (4F1=1)
    // // } else {
    // //     /* 【定制代码】当前是普通的 PCM 播放模式 */
    // //     // 恢复 DAC 的 PCM 解码寄存器状态，或恢复对应的 GPIO 电平。
    // //     clk_fmt_val |= 0x00; // PCM MODE (4F1=0)
    // // }
    p_clk_fmt <: clk_fmt_val;

    // /* 借鉴：留出 20ms 给晶振起振并达到绝对稳定，完美消除开机爆音 */
    // wait_us(20000); 

    return;
}
