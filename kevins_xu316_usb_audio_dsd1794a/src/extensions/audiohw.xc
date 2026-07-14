// Copyright (c) 2012-2026, XMOS Ltd, All rights reserved
#include <assert.h>
#include <xs1.h>
#include <platform.h>
#include "xua_conf.h"
#include "i2c.h"
#include "print.h"
#include "dsd_support.h"

on tile[XUA_XUD_TILE_NUM]: out port p_clk_en = PORT_CLK_EN; // 4F2, 4F3
on tile[XUA_AUDIO_IO_TILE_NUM]: out port p_ctrl_signals = PORT_DISPLAY_CTRL;
on tile[XUA_XUD_TILE_NUM]: out port p_dsd_mode = PORT_DSD_MODE;
on tile[XUA_XUD_TILE_NUM]: out port p_dac_rst_n = PORT_DAC_RST_N;
on tile[XUA_XUD_TILE_NUM]: port p_i2c = PORT_I2C;

#define DSD1794A_I2C_ADDR   (0x4C)

#define DSD1794_REG_18      (0x12)
#define DSD1794_REG_19      (0x13)
#define DSD1794_REG_20      (0x14)

#define DAC_REGREAD(reg, data) {data[0] = i2c.read_reg(DSD1794A_I2C_ADDR, reg, result);}
#define DAC_REGWRITE(reg, val) {result = i2c.write_reg(DSD1794A_I2C_ADDR, reg, val);}

#define DSD1794_OPE_EN      (0x00)  // The OPE bit is used to enable or disable the analog output for both channels.
#define DSD1794_OPE_DISABLE (0x10)  // Disabling the analog outputs forces them to the bipolar zero level (BPZ) even if digital audio data is present on the input.
#define DSD1794_VAL_PCM     (0x00)  // DSD = 0, 立体声 PCM 模式
#define DSD1794_VAL_DSD     (0x20)  // DSD = 1, 开启 DSD 接口模式
#define DSD1794_VAL_SRST    (0x40)  // The SRST bit is used to reset the DSD1794A to the initial system condition.
#define DSD1794_VAL_DMF_DSD (0x5C)  // FIR-4. For the DSD mode, analog FIR filter performance can be selected using this register.

/* ========================================================================= */
/* 0. 借鉴 JohnnyOpcode 的硬件 100MHz 内部定时器微秒延时函数 */
/* ========================================================================= */
static void wait_us(int microseconds)
{
    timer t;
    unsigned time;
    t :> time;
    t when timerafter(time + (microseconds * 100)) :> void;
}

/* ========================================================================= */
/* 1. 标准硬件初始化函数 */
/* ========================================================================= */
void AudioHwInit(void)
{
    // 开机重置DAC
    // p_dac_rst_n <: 0;

    /* 开机默认初始化：默认使能 22MHz 晶振 */
    // 4F2->22M, 4F3->24M : b0100
    p_clk_en <: 0x04;
    wait_us(20000); 

    /* 开机默认初始化：44.1kHz PCM SINGLE MODE */
    // SINGLE MODE (4D0=1, 4D1=0)
    // 441 MODE + PCM MODE (4D2=0, 4D3=0)
    p_ctrl_signals <: 0x01; 
    wait_us(5000);

    return;
}

void AudioHwConfig_Mute2(client interface i2c_master_if i2c)
{
    i2c_regop_res_t result;

    DAC_REGWRITE(DSD1794_REG_19, DSD1794_OPE_DISABLE);

    return;
}

/**
* @brief 时钟改变前触发：通过 I2C 开启 DSD1794A 内部的 256级数字软静音
*/
void AudioHwConfig_Mute(void)
{
    i2c_master_if i2c[1];
    par
    {
        i2c_master_single_port(i2c, 1, p_i2c, 10, 0, 1, 0);
        {
            AudioHwConfig_Mute2(i2c[0]);
            i2c[0].shutdown();
        }
    }

    return;
}

/* Configures the external audio hardware for the required sample frequency.
 * See gpio.h for I2C helper functions and gpio access
 */
void AudioHwConfig2(unsigned samFreq, unsigned mClk, unsigned dsdMode,
    unsigned sampRes_DAC, unsigned sampRes_ADC, client interface i2c_master_if i2c)
{
    i2c_regop_res_t result;

    // P1, P2 倍频控制 (4D0, 4D1)
    // P3, P4 基准与格式 (4D2, 4D3)
    // b0001
    unsigned ctrl_signals = 0x01;
    // 缓存计算4D2的值
    unsigned mode_val = 0x00;

    // 4F2->22M, 4F3->24M
    if (mClk == MCLK_441) {
        // b0100
        p_clk_en <: 0x04;
    } else {
        // b1000
        p_clk_en <: 0x08;
    }
    wait_us(20000);

    /* ========================================================================= */
    /* 分支 A：当前进入 DSD 播放模式 */
    /* ========================================================================= */
    if ((dsdMode == DSD_MODE_NATIVE) || (dsdMode == DSD_MODE_DOP))
    {
        // 1. 趁着硬件时钟开关还没动作，立刻发送 16位的 0x1440 进行 PCM 下的软重置
        DAC_REGWRITE(DSD1794_REG_20, DSD1794_VAL_SRST); 
        wait_us(10);

        // 2. 告诉芯片我们要正式开启 DSD 模式 (发送 0x1420)
        DAC_REGWRITE(DSD1794_REG_20, DSD1794_VAL_DSD); 
        wait_us(100); 

        // 3. 配置 DSD 模式下的模拟 FIR 滤波器 
        DAC_REGWRITE(DSD1794_REG_18, DSD1794_VAL_DMF_DSD); 
        wait_us(100);

        // 4. 软件指令下发完毕后，立刻将 74LVC1G3157 硬件开关拉高 (P4->4D3)
        // 使 DSD1794A 的 PBK/PBCK/PLRCK 硬件引脚安全接地
        // | b1000
        ctrl_signals |= 0x08;
        wait_us(100);

        // 5. 判断具体是 DSD64 还是 DSD128 (P3->4D2)
        // DSD128: b0100; DSD64: b0000
        if (samFreq > 300000) { mode_val = 0x04; } 
        else { mode_val = 0x00; }
        ctrl_signals |= mode_val;
        p_ctrl_signals <: ctrl_signals;
        wait_us(100);
    }
    /* ========================================================================= */
    /* 分支 B：当前进入普通的 PCM 播放模式 */
    /* ========================================================================= */
    else 
    {
        // P3->4D2 P4->4D3
        // PCM: b0000
        ctrl_signals |= 0x00;
        wait_us(1000); 

        // 2. 时钟通路已经接通了，立刻写入 0x1440 对 PCM 状态机执行干净的软重置
        DAC_REGWRITE(DSD1794_REG_20, DSD1794_VAL_SRST);
        wait_us(10000);

        // // 3. 重置完后，确保寄存器 20 清除重置位并彻底呆在 PCM 模式下 (写入 0x1400)
        // DAC_REGWRITE(DSD1794_REG_20, DSD1794_VAL_PCM);
        // wait_us(2000);

        /* 4. 精确计算 PCM 的倍频模式 (SINGLE/DOUBLE/QUAD) */
        if (samFreq == 176400 || samFreq == 192000) { ctrl_signals |= 0x03; } 
        else if (samFreq == 88200 || samFreq == 96000) { ctrl_signals |= 0x02; } 
        else { ctrl_signals |= 0x01; }
        wait_us(2000);

        // 44.1k系: b0100; 48k系: b0000
        if (samFreq % 48000 == 0) { mode_val |= 0x04; }
        else { mode_val = 0x00; }
        ctrl_signals |= mode_val;
        p_ctrl_signals <: ctrl_signals;
        wait_us(1000);
    }

    return;
}

void AudioHwConfig(unsigned samFreq, unsigned mClk, unsigned dsdMode,
    unsigned sampRes_DAC, unsigned sampRes_ADC)
{
    i2c_master_if i2c[1];
    par
    {
        i2c_master_single_port(i2c, 1, p_i2c, 10, 0, 1, 0);
        {
            AudioHwConfig2(samFreq, mClk, dsdMode, sampRes_DAC, sampRes_ADC, i2c[0]);
            i2c[0].shutdown();
        }
    }

    return;
}

void AudioHwConfig_UnMute2(client interface i2c_master_if i2c)
{
    i2c_regop_res_t result;

    DAC_REGWRITE(DSD1794_REG_19, DSD1794_OPE_EN);

    return;
}

/**
* @brief 时钟完全稳定后触发：解除静音
*/
void AudioHwConfig_UnMute(void)
{
    wait_us(500); 
    
    i2c_master_if i2c[1];
    par
    {
        i2c_master_single_port(i2c, 1, p_i2c, 10, 0, 1, 0);
        {
            AudioHwConfig_UnMute2(i2c[0]);
            i2c[0].shutdown();
        }
    }

    return;
}