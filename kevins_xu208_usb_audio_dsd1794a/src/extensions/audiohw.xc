// Copyright (c) 2012-2026, XMOS Ltd, All rights reserved
#include <assert.h>
#include <xs1.h>
#include <platform.h>
#include "xua_conf.h"
#include "i2c.h"
#include "print.h"
#include "dsd_support.h"

/* .xn 里定义的 4位宽 晶振控制端口 (对应 X0D16~19) */
out port p_clk_en = PORT_CLK_EN;
out port p_mode_sel = PORT_MODE_SEL;
out port p_clk_fmt = PORT_CLK_FORMAT;
port p_i2c = PORT_I2C;
// port p_dac_rst_n = PORT_DAC_RST_N;
// port p_i2c = on tile[0]:PORT_I2C;

#define DSD1794A_I2C_ADDR   (0x4C)

#define DSD1794_REG_18      (0x12)
#define DSD1794_REG_19      (0x13)
#define DSD1794_REG_20      (0x14)

#define DAC_REGREAD(reg, data) {data[0] = i2c.read_reg(DSD1794A_I2C_ADDR, reg, result);}
#define DAC_REGWRITE(reg, val) {result = i2c.write_reg(DSD1794A_I2C_ADDR, reg, val);}
// #define DAC_REGWRITE(reg, val) {result = i2c.write_reg16_addr8(DSD1794A_I2C_ADDR, reg, val);}

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

    /* 开机默认初始化：默认使能 45.1584MHz 晶振 */
    /* 对应原厂图：4D0(X0D16) = 1, 4D1(X0D17) = 0 -> 二进制 0001 */
    p_clk_en <: 0x01; 
    wait_us(20000); 

    /* 开机默认初始化：44.1kHz PCM SINGLE MODE */
    // SINGLE MODE (4E0=1, 4E1=0)
    p_mode_sel   <: 0x01;
    // 441 MODE + PCM MODE (4F0=0, 4F1=0)
    p_clk_fmt <: 0x00; 
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

    unsigned mode_val = 0x01; // P1, P2 倍频控制 (4E0, 4E1)
    unsigned clk_fmt_val = 0x00; // P3, P4 基准与格式 (4F0, 4F1)

    if (mClk == MCLK_441) {
        p_clk_en <: 0x01;
    } else {
        p_clk_en <: 0x02;
    }
    wait_us(20000);

    /* ========================================================================= */
    /* 分支 A：当前进入 DSD 播放模式 */
    /* ========================================================================= */
    if ((dsdMode == DSD_MODE_NATIVE) || (dsdMode == DSD_MODE_DOP))
    {
        // 1. 趁着硬件时钟开关还没动作，立刻发送 16位的 0x1440 进行 PCM 下的软重置
        DAC_REGWRITE(DSD1794_REG_20, DSD1794_VAL_SRST); 
        wait_us(10000);

        // 2. 告诉芯片我们要正式开启 DSD 模式 (发送 0x1420)
        DAC_REGWRITE(DSD1794_REG_20, DSD1794_VAL_DSD); 
        wait_us(2000); 

        // 3. 配置 DSD 模式下的模拟 FIR 滤波器 
        DAC_REGWRITE(DSD1794_REG_18, DSD1794_VAL_DMF_DSD); 
        wait_us(2000);

        // 4. 软件指令下发完毕后，立刻将 74LVC1G3157 硬件开关拉高 (0x02)
        // 使 DSD1794A 的 PBCK/PLRCK 硬件引脚安全接地
        clk_fmt_val = 0x02;
        p_clk_fmt <: clk_fmt_val;
        wait_us(1000);

        // 5. 判断具体是 DSD64 还是 DSD128 
        if (samFreq > 300000) { mode_val = 0x02; } 
        else { mode_val = 0x01; }
        p_mode_sel <: mode_val;
        wait_us(2000);
    }
    /* ========================================================================= */
    /* 分支 B：当前进入普通的 PCM 播放模式 */
    /* ========================================================================= */
    else 
    {
        // 1. 首先释放 74LVC1G3157 开关 (0x00)，恢复硬件时钟输入到 DSD1794A
        clk_fmt_val = 0x00;
        p_clk_fmt <: clk_fmt_val;
        wait_us(1000); 

        // 2. 时钟通路已经接通了，立刻写入 0x1440 对 PCM 状态机执行干净的软重置
        DAC_REGWRITE(DSD1794_REG_20, DSD1794_VAL_SRST);
        wait_us(10000);

        // // 3. 重置完后，确保寄存器 20 清除重置位并彻底呆在 PCM 模式下 (写入 0x1400)
        // DAC_REGWRITE(DSD1794_REG_20, DSD1794_VAL_PCM);
        // wait_us(2000);

        /* 4. 精确计算 PCM 的倍频模式 (SINGLE/DOUBLE/QUAD) */
        if (samFreq == 176400 || samFreq == 192000) { mode_val = 0x03; } 
        else if (samFreq == 88200 || samFreq == 96000) { mode_val = 0x02; } 
        else { mode_val = 0x01; }
        p_mode_sel <: mode_val;
        wait_us(2000);

        /* 5. 精确计算 PCM 的时钟基准 (441k系 或 48k系) */
        if (samFreq % 48000 == 0) { clk_fmt_val |= 0x01; }
        p_clk_fmt <: clk_fmt_val;
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