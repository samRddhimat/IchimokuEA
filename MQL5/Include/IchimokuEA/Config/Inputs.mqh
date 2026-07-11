//+------------------------------------------------------------------+
//| Inputs.mqh                                                        |
//| IchimokuEA — single source of truth for all input parameters     |
//+------------------------------------------------------------------+
#ifndef ICHIMOKUEA_INPUTS_MQH
#define ICHIMOKUEA_INPUTS_MQH

//--- EA mode
input int    InpEAMode             = 0;       // EA Mode: 0=Trend/Swing, 1=Scalp

//--- Signal
input ENUM_TIMEFRAMES InpTimeframe = PERIOD_M15; // Chart timeframe
input int    InpTenkan             = 9;       // Tenkan-sen period
input int    InpKijun              = 26;      // Kijun-sen period
input int    InpSenkouB            = 52;      // Senkou Span B period
input int    InpDisplacement       = 26;      // Cloud displacement
input double InpNearPct            = 0.01;    // Near/far cloud threshold (1%=0.01)

//--- Stop loss
input int    InpStopBasis          = 3;       // Stop basis: 0=Cloud 1=Kijun 2=ATR 3=Combined(max)
input double InpStopATRMult        = 1.5;     // ATR multiplier for stop distance
input double InpStopBufferPts      = 10.0;    // Buffer points beyond cloud/Kijun for stop
input double InpMaxStopRMult       = 3.0;     // Skip trade if stop > N × planned risk

//--- Trade management (shared)
input double InpBreakEvenAtR       = 1.0;     // Move SL to BE when profit reaches NR
input double InpProfitTargetR      = 1.5;     // TP as R multiple (0=trail only, no fixed TP)
input double InpPartialClosePct    = 50.0;    // % of position to close at TP (0=close all)
input bool   InpKijunTrail         = true;    // Trail SL to Kijun-sen after BE
input bool   InpCloudExit          = true;    // Exit if price closes inside cloud
input int    InpTimeExitCandles    = 15;      // Exit after N candles if no progress (0=off)

//--- Scalp mode specific
input int    InpScalpTimeExitCandles = 10;    // Scalp: time exit after N candles
input double InpScalpProfitTargetR   = 1.5;  // Scalp: TP R multiple

//--- Position sizing
input int    InpSizeMode           = 0;       // 0=Risk% per trade, 1=Fixed lot
input double InpRiskPercent        = 1.0;     // Risk per trade as % of equity
input double InpFixedLot           = 0.01;    // Fixed lot size (when InpSizeMode=1)
input double InpMaxLot             = 10.0;    // Maximum lot size cap

//--- Execution
input int    InpMagicNumber        = 20260710; // Magic number
input int    InpDeviationPoints    = 20;      // Max slippage in points
input int    InpMaxRetries         = 3;       // Max order retry attempts

//--- Logging
input bool   InpLogToCSV           = true;    // Write trade log to CSV
input bool   InpDiagnosticLog      = false;   // Write diagnostic heartbeat to CSV
input string InpCSVPrefix          = "IchimokuEA"; // CSV filename prefix
input string InpTradeComment       = "IchimokuEA"; // Order comment prefix

#endif // ICHIMOKUEA_INPUTS_MQH
