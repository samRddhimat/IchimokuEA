//+------------------------------------------------------------------+
//| Inputs.mqh                                                        |
//| IchimokuEA — all input parameters grouped by category            |
//+------------------------------------------------------------------+
#ifndef ICHIMOKUEA_INPUTS_MQH
#define ICHIMOKUEA_INPUTS_MQH

//--- EA Mode
sinput group           "=== EA Mode ==="
input int    InpEAMode             = 0;       // EA Mode: 0=Trend/Swing, 1=Scalp

//--- Ichimoku Signal
sinput group           "=== Ichimoku Signal ==="
input ENUM_TIMEFRAMES InpTimeframe = PERIOD_M15; // Chart timeframe
input int    InpTenkan             = 9;       // Tenkan-sen period
input int    InpKijun              = 26;      // Kijun-sen period
input int    InpSenkouB            = 52;      // Senkou Span B period
input int    InpDisplacement       = 26;      // Cloud displacement
input double InpNearPct            = 0.01;    // Near/far cloud threshold (1%=0.01)

//--- Stop Loss
sinput group           "=== Stop Loss ==="
input int    InpStopBasis          = 3;       // Stop basis: 0=Cloud 1=Kijun 2=ATR 3=Combined
input double InpStopATRMult        = 1.5;     // ATR multiplier for stop distance
input double InpStopBufferPts      = 10.0;    // Buffer points beyond cloud/Kijun
input double InpMaxStopRMult       = 3.0;     // Skip trade if stop > N x ATR

//--- Trade Management
sinput group           "=== Trade Management ==="
input double InpBreakEvenAtR       = 1.0;     // Move SL to BE when profit reaches NR
input bool   InpProfitLock         = false;   // Enable profit lock (dollar-tier SL tightening)
input double InpProfitTargetR      = 1.5;     // TP as R multiple (0=trail only)
input double InpPartialClosePct    = 50.0;    // % of position to close at TP (0=close all)
input bool   InpKijunTrail         = true;    // Trail SL to Kijun-sen after BE
input bool   InpCloudExit          = true;    // Exit if price closes inside cloud
input int    InpTimeExitCandles    = 15;      // Exit after N candles if no progress (0=off)

//--- Scalp Mode
sinput group           "=== Scalp Mode (InpEAMode=1) ==="
input int    InpScalpTimeExitCandles = 10;    // Scalp: time exit after N candles
input double InpScalpProfitTargetR   = 1.5;  // Scalp: TP R multiple

//--- Position Sizing
sinput group           "=== Position Sizing ==="
input int    InpSizeMode           = 0;       // 0=Risk% per trade, 1=Fixed lot
input double InpRiskPercent        = 1.0;     // Risk per trade as % of equity
input double InpFixedLot           = 0.01;    // Fixed lot size (InpSizeMode=1)
input double InpMaxLot             = 10.0;    // Maximum lot size cap

//--- Execution
sinput group           "=== Execution ==="
input int    InpMagicNumber        = 20260710; // Magic number
input int    InpDeviationPoints    = 20;      // Max slippage in points
input int    InpMaxRetries         = 3;       // Max order retry attempts
input string InpTradeComment       = "IchimokuEA"; // Order comment prefix

//--- Logging
sinput group           "=== Logging ==="
input bool   InpLogToCSV           = true;    // Write trade log to CSV
input bool   InpDiagnosticLog      = false;   // Write diagnostic heartbeat to CSV
input string InpCSVPrefix          = "IchimokuEA"; // CSV filename prefix

#endif // ICHIMOKUEA_INPUTS_MQH