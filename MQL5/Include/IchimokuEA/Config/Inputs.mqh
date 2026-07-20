//+------------------------------------------------------------------+
//| Inputs.mqh                                                        |
//| IchimokuEA — all input parameters grouped by category            |
//+------------------------------------------------------------------+
#ifndef ICHIMOKUEA_INPUTS_MQH
#define ICHIMOKUEA_INPUTS_MQH

//--- EA Mode
sinput group           "=== EA Mode ==="
input int    InpEAMode             = 0;       // EA Mode: 0=Trend/Swing, 1=Scalp
input int    InpMaxPositions       = 3;       // Max simultaneous open positions

//--- Ichimoku Signal
sinput group           "=== Ichimoku Signal ==="
input ENUM_TIMEFRAMES InpTimeframe = PERIOD_M15; // Chart timeframe
input int    InpTenkan             = 9;       // Tenkan-sen period
input int    InpKijun              = 26;      // Kijun-sen period
input int    InpSenkouB            = 52;      // Senkou Span B period
input int    InpDisplacement       = 26;      // Cloud displacement
input double InpNearPct            = 0.01;    // Near/far cloud threshold (1%=0.01)

//--- Phase 1 Signal Filters
sinput group           "=== Signal Filters (Phase 1) ==="
input int    InpFreshnessBarLimit      = 3;      // TK cross freshness: allow entry N bars after cross (0=off)
input bool   InpRequireFutureCloudAgree= true;   // Require future cloud to agree with trade direction
input double InpADXMinimum            = 0.0;    // Minimum ADX for trend strength (0=off, suggested 25)
input double InpATRMinimum            = 0.0;    // Minimum ATR in points (0=off, avoids low volatility)
input int    InpMaxSpreadPoints        = 0;      // Maximum spread in points (0=off, suggested 50)
input bool   InpSessionFilterEnabled   = false;  // Restrict entries to London + LDN/NY session only

//--- Phase 2 Kijun Pullback Module
sinput group           "=== Kijun Pullback Module (Phase 2) ==="
input bool   InpKijunPullbackModule = false;  // Enable Kijun Pullback continuation entry (Module 2)
input int    InpKPMinTrendBars      = 3;      // Min bars price must be outside cloud before KP entry
input double InpKPKijunZonePct      = 0.005;  // Max distance from Kijun as % of price (0.5%=0.005)

//--- Phase 3 Kumo Breakout Module
sinput group           "=== Kumo Breakout Module (Phase 3) ==="
input bool   InpKumoBreakModule    = false;   // Enable Fresh Kumo Breakout entry (Module 3)
input int    InpKBFreshnessLimit   = 3;       // Max bars since cloud breakout (1-5)
input int    InpKBATRLookback      = 3;       // ATR expanding check: ATR[1] > ATR[N bars ago]
input int    InpStopBasis          = 3;       // Stop basis: 0=Cloud 1=Kijun 2=ATR 3=Combined
input double InpStopATRMult        = 1.5;     // ATR multiplier for stop distance
input double InpStopBufferPts      = 10.0;    // Buffer points beyond cloud/Kijun
input double InpMaxStopRMult       = 3.0;     // Skip trade if stop > N x ATR

//--- Trade Management
sinput group           "=== Trade Management ==="
input double InpBreakEvenAtR       = 1.0;     // Move SL to BE when profit reaches NR
input bool   InpProfitLock         = false;   // Enable profit lock (dollar-tier SL tightening after BE)
input double InpProfitTargetR      = 1.5;     // TP as R multiple (0=trail only)
input double InpPartialClosePct    = 50.0;    // % of position to close at TP (0=close all)
input bool   InpKijunTrail         = true;    // Trail SL to Kijun-sen after BE
input bool   InpCloudExit          = true;    // Exit if price closes inside cloud
input int    InpTimeExitCandles    = 15;      // Exit after N candles if no progress (0=off)

//--- Equity Profit Lock
sinput group           "=== Equity Profit Lock ==="
input bool   InpEquityProfitLock   = false;   // Enable equity-based profit lock (activates immediately, no BE required)
input double InpEPLTriggerPct      = 0.02;    // Trigger when profit reaches X% of equity (0.02 = 0.02%)
input double InpEPLLockPct         = 87.5;    // Lock this % of current profit continuously (87.5 = lock 87.5%)

//--- Scalp Mode
sinput group           "=== Scalp Mode (InpEAMode=1) ==="
input int    InpScalpTimeExitCandles = 10;    // Scalp: time exit after N candles
input double InpScalpProfitTargetR   = 1.5;  // Scalp: TP R multiple

//--- Position Sizing
sinput group           "=== Position Sizing ==="
input int    InpSizeMode           = 0;       // 0=Risk% per trade, 1=Fixed lot
input double InpRiskPercent        = 1.0;     // Base risk per trade as % of equity
input double InpFixedLot           = 0.01;    // Fixed lot size (InpSizeMode=1)
input double InpMaxLot             = 10.0;    // Maximum lot size cap

//--- Dynamic Sizing (Anti-Martingale)
sinput group           "=== Dynamic Sizing (Anti-Martingale) ==="
input bool   InpDynamicSizing      = false;   // Enable dynamic sizing (anti-martingale)
input double InpSizeStepR          = 0.25;    // Risk increase per consecutive win (e.g. 0.25 = +25% per win)
input int    InpResetAfterNLosses  = 2;       // Reset to base size after N consecutive losses

//--- Execution
sinput group           "=== Execution ==="
input int    InpMagicNumber        = 20260710; // Magic number
input int    InpDeviationPoints    = 20;      // Max slippage in points
input int    InpMaxRetries         = 3;       // Max order retry attempts
input string InpTradeComment       = "IchimokuEA"; // Order comment prefix

//--- Logging
sinput group           "=== Logging ==="
input bool   InpShowDashboard      = true;    // Show floating draggable dashboard on chart
input bool   InpLogToCSV           = true;    // Write trade log to CSV
input bool   InpDiagnosticLog      = false;   // Write diagnostic heartbeat to CSV
input string InpCSVPrefix          = "IchimokuEA"; // CSV filename prefix

#endif // ICHIMOKUEA_INPUTS_MQH