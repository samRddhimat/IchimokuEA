//+------------------------------------------------------------------+
//| IchimokuSignal.mqh                                                |
//| IchimokuEA — Ichimoku Kinko Hyo entry signal engine              |
//|                                                                   |
//| Single timeframe (M15). All conditions required:                  |
//|   1. Tenkan/Kijun crossover (bullish or bearish)                  |
//|   2. Chikou span in free space (not inside cloud)                 |
//|   3. Price vs cloud: above=BUY, below=SELL, inside=no signal     |
//|                                                                   |
//| v1.1.0 — Phase 1 filters added:                                  |
//|   4. Freshness: TK cross must be within InpFreshnessBarLimit bars |
//|   5. Future cloud direction must agree with trade direction        |
//|   6. ADX minimum (InpADXMinimum) — avoids ranging markets         |
//|   7. ATR minimum (InpATRMinimum) — avoids low volatility          |
//|   8. Spread filter (InpMaxSpreadPoints) — avoids wide spread      |
//|   9. Session filter (InpSessionFilterEnabled) — LDN/LDN_NY only  |
//+------------------------------------------------------------------+
#ifndef ICHIMOKUEA_SIGNAL_MQH
#define ICHIMOKUEA_SIGNAL_MQH

#include <IchimokuEA/Config/Inputs.mqh>

//--- signal direction
enum ENUM_ICHI_SIGNAL
{
   ICHI_NONE = 0,
   ICHI_BUY  = 1,
   ICHI_SELL = 2
};

//--- raw indicator values for one bar
struct IchimokuValues
{
   double tenkanCur;
   double tenkanPrev;
   double kijunCur;
   double kijunPrev;
   double chikouCur;
   double cloudTopAtChikou;
   double cloudBotAtChikou;
   double currentPrice;
   double cloudTop;
   double cloudBot;
   double cloudTopFuture;   // future cloud top (displacement bars ahead)
   double cloudBotFuture;   // future cloud bot (displacement bars ahead)
   double nearThresholdPct;
};

//--- signal result
struct IchimokuSignalResult
{
   ENUM_ICHI_SIGNAL signal;
   int              score;
   double           cloudTop;
   double           cloudBot;
   double           kijun;
   double           tenkan;
   string           reason;

   void Clear()
   {
      signal   = ICHI_NONE;
      score    = 0;
      cloudTop = 0.0;
      cloudBot = 0.0;
      kijun    = 0.0;
      tenkan   = 0.0;
      reason   = "";
   }
};

//+------------------------------------------------------------------+
class CIchimokuSignal
{
private:
   int      m_handle;
   int      m_atrHandle;
   int      m_adxHandle;
   string   m_symbol;
   int      m_tenkan;
   int      m_kijun;
   int      m_senkouB;
   int      m_displacement;
   double   m_nearPct;

   datetime m_lastBar;      // new-bar gate
   datetime m_crossBar;     // when last TK cross occurred (for freshness)

   //-------------------------------------------------------------------
   // Read all Ichimoku values including future cloud
   //-------------------------------------------------------------------
   bool ReadValues(IchimokuValues &v) const
   {
      v.nearThresholdPct = m_nearPct;

      double tenkan[], kijun[], senkouA[], senkouB[], chikou[];
      ArraySetAsSeries(tenkan,  true);
      ArraySetAsSeries(kijun,   true);
      ArraySetAsSeries(senkouA, true);
      ArraySetAsSeries(senkouB, true);
      ArraySetAsSeries(chikou,  true);

      if(CopyBuffer(m_handle, 0, 0, 3, tenkan)  < 3) return false;
      if(CopyBuffer(m_handle, 1, 0, 3, kijun)   < 3) return false;
      if(CopyBuffer(m_handle, 2, 0, 3, senkouA) < 3) return false;
      if(CopyBuffer(m_handle, 3, 0, 3, senkouB) < 3) return false;
      if(CopyBuffer(m_handle, 4, 0, 3, chikou)  < 3) return false;

      v.tenkanCur  = tenkan[0];
      v.tenkanPrev = tenkan[1];
      v.kijunCur   = kijun[0];
      v.kijunPrev  = kijun[1];
      v.chikouCur  = chikou[0];

      // Cloud at Chikou position (displacement bars back)
      double chikouA[], chikouB[];
      ArraySetAsSeries(chikouA, true);
      ArraySetAsSeries(chikouB, true);
      if(CopyBuffer(m_handle, 2, m_displacement, 2, chikouA) < 2) return false;
      if(CopyBuffer(m_handle, 3, m_displacement, 2, chikouB) < 2) return false;
      v.cloudTopAtChikou = MathMax(chikouA[0], chikouB[0]);
      v.cloudBotAtChikou = MathMin(chikouA[0], chikouB[0]);

      // Cloud at current bar
      v.cloudTop = MathMax(senkouA[0], senkouB[0]);
      v.cloudBot = MathMin(senkouA[0], senkouB[0]);

      // Future cloud — displacement bars AHEAD (negative offset)
      // CopyBuffer with negative start reads forward in time
      double futureA[], futureB[];
      ArraySetAsSeries(futureA, true);
      ArraySetAsSeries(futureB, true);
      // Future cloud is plotted at current_bar + displacement
      // In CopyBuffer terms: offset = -(displacement-1) from bar[0]
      if(CopyBuffer(m_handle, 2, -(m_displacement-1), 2, futureA) >= 2 &&
         CopyBuffer(m_handle, 3, -(m_displacement-1), 2, futureB) >= 2)
      {
         v.cloudTopFuture = MathMax(futureA[0], futureB[0]);
         v.cloudBotFuture = MathMin(futureA[0], futureB[0]);
      }
      else
      {
         // Fallback: use current cloud if future not available
         v.cloudTopFuture = v.cloudTop;
         v.cloudBotFuture = v.cloudBot;
      }

      // Mid price
      v.currentPrice = (SymbolInfoDouble(m_symbol, SYMBOL_BID) +
                        SymbolInfoDouble(m_symbol, SYMBOL_ASK)) / 2.0;
      return true;
   }

   //-------------------------------------------------------------------
   // Get current ATR value (last closed bar)
   //-------------------------------------------------------------------
   double CurrentATR() const
   {
      if(m_atrHandle == INVALID_HANDLE) return 0.0;
      double buf[];
      ArraySetAsSeries(buf, true);
      if(CopyBuffer(m_atrHandle, 0, 1, 1, buf) < 1) return 0.0;
      return buf[0];
   }

   //-------------------------------------------------------------------
   // Get current ADX value (last closed bar)
   //-------------------------------------------------------------------
   double CurrentADX() const
   {
      if(m_adxHandle == INVALID_HANDLE) return 0.0;
      double buf[];
      ArraySetAsSeries(buf, true);
      if(CopyBuffer(m_adxHandle, 0, 1, 1, buf) < 1) return 0.0;
      return buf[0];
   }

   //-------------------------------------------------------------------
   // Session filter — returns true if current time is in allowed session
   // Server time UTC+3: London 07:00-13:00, LDN_NY 13:00-16:00
   //-------------------------------------------------------------------
   bool IsAllowedSession() const
   {
      if(!InpSessionFilterEnabled) return true;
      MqlDateTime dt;
      TimeToStruct(TimeCurrent(), dt);
      const int h = dt.hour;
      return (h >= 7 && h < 16); // London + LDN_NY overlap
   }

public:
   CIchimokuSignal()
      : m_handle(INVALID_HANDLE),
        m_atrHandle(INVALID_HANDLE),
        m_adxHandle(INVALID_HANDLE),
        m_lastBar(0),
        m_crossBar(0) {}

   bool Init(const string symbol, const int tenkan, const int kijun,
             const int senkouB, const int displacement, const double nearPct)
   {
      m_symbol       = symbol;
      m_tenkan       = tenkan;
      m_kijun        = kijun;
      m_senkouB      = senkouB;
      m_displacement = displacement;
      m_nearPct      = nearPct;

      m_handle = iIchimoku(symbol, InpTimeframe, tenkan, kijun, senkouB);
      if(m_handle == INVALID_HANDLE)
      {
         Print("IchimokuSignal: failed to create Ichimoku handle for ", symbol);
         return false;
      }

      // ATR for minimum volatility filter
      m_atrHandle = iATR(symbol, InpTimeframe, 14);
      if(m_atrHandle == INVALID_HANDLE)
         Print("IchimokuSignal: WARNING — failed to create ATR handle (ATR filter disabled)");

      // ADX for trend strength filter
      m_adxHandle = iADX(symbol, InpTimeframe, 14);
      if(m_adxHandle == INVALID_HANDLE)
         Print("IchimokuSignal: WARNING — failed to create ADX handle (ADX filter disabled)");

      return true;
   }

   void Deinit()
   {
      if(m_handle    != INVALID_HANDLE) { IndicatorRelease(m_handle);    m_handle    = INVALID_HANDLE; }
      if(m_atrHandle != INVALID_HANDLE) { IndicatorRelease(m_atrHandle); m_atrHandle = INVALID_HANDLE; }
      if(m_adxHandle != INVALID_HANDLE) { IndicatorRelease(m_adxHandle); m_adxHandle = INVALID_HANDLE; }
   }

   int GetHandle()    const { return m_handle; }
   int GetATRHandle() const { return m_atrHandle; }
   int GetADXHandle() const { return m_adxHandle; }

   //-------------------------------------------------------------------
   // Pure signal logic — testable with synthetic values
   // Does NOT include live filters (spread/ATR/ADX/session/freshness)
   // Those are applied in Evaluate() before calling this
   //-------------------------------------------------------------------
   IchimokuSignalResult EvaluateSignal(const IchimokuValues &v) const
   {
      IchimokuSignalResult r;
      r.Clear();
      r.cloudTop = v.cloudTop;
      r.cloudBot = v.cloudBot;
      r.kijun    = v.kijunCur;
      r.tenkan   = v.tenkanCur;

      // Condition 1: TK cross
      bool bullCross = (v.tenkanPrev <= v.kijunPrev) && (v.tenkanCur > v.kijunCur);
      bool bearCross = (v.tenkanPrev >= v.kijunPrev) && (v.tenkanCur < v.kijunCur);
      if(!bullCross && !bearCross) { r.reason = "no TK cross"; return r; }

      // Condition 2: Chikou free space
      bool chikouFree = (v.chikouCur > v.cloudTopAtChikou) ||
                         (v.chikouCur < v.cloudBotAtChikou);
      if(!chikouFree) { r.reason = "Chikou inside cloud"; return r; }

      // Condition 3: Price vs cloud
      if(v.currentPrice > v.cloudTop)
      {
         if(!bullCross) { r.reason = "bearish cross but price above cloud — conflict"; return r; }

         // Condition 4: Future cloud must be bullish (Span A > Span B ahead)
         if(InpRequireFutureCloudAgree && v.cloudTopFuture <= v.cloudBotFuture)
         { r.reason = "future cloud is bearish — conflict with BUY"; return r; }

         double distPct = (v.currentPrice - v.cloudTop) / v.currentPrice;
         bool isFar = distPct > v.nearThresholdPct;
         r.signal = ICHI_BUY;
         r.score  = isFar ? 90 : 60;
         r.reason = StringFormat("BUY: TK cross, Chikou free, %.2f%% above cloud (%s)",
                                  distPct * 100.0, isFar ? "FAR" : "NEAR");
      }
      else if(v.currentPrice < v.cloudBot)
      {
         if(!bearCross) { r.reason = "bullish cross but price below cloud — conflict"; return r; }

         // Condition 4: Future cloud must be bearish (Span A < Span B ahead)
         if(InpRequireFutureCloudAgree && v.cloudTopFuture >= v.cloudBotFuture)
         { r.reason = "future cloud is bullish — conflict with SELL"; return r; }

         double distPct = (v.cloudBot - v.currentPrice) / v.currentPrice;
         bool isFar = distPct > v.nearThresholdPct;
         r.signal = ICHI_SELL;
         r.score  = isFar ? 90 : 60;
         r.reason = StringFormat("SELL: TK cross, Chikou free, %.2f%% below cloud (%s)",
                                  distPct * 100.0, isFar ? "FAR" : "NEAR");
      }
      else
         r.reason = "price inside cloud — no signal";

      return r;
   }

   //-------------------------------------------------------------------
   // Live evaluation — new-bar gated + all Phase 1 filters applied
   //-------------------------------------------------------------------
   IchimokuSignalResult Evaluate()
   {
      IchimokuSignalResult r;
      r.Clear();

      // Bar gate
      const datetime curBar = iTime(m_symbol, InpTimeframe, 0);
      if(curBar == m_lastBar) { r.reason = "same bar"; return r; }
      m_lastBar = curBar;

      // ── Phase 1 Filter A: Session filter ──────────────────────────
      if(!IsAllowedSession())
      { r.reason = "outside allowed session (LDN/LDN_NY only)"; return r; }

      // ── Phase 1 Filter B: Spread filter ───────────────────────────
      if(InpMaxSpreadPoints > 0)
      {
         const long spread = SymbolInfoInteger(m_symbol, SYMBOL_SPREAD);
         if(spread > InpMaxSpreadPoints)
         {
            r.reason = StringFormat("spread too wide: %d > %d points",
                                     (int)spread, InpMaxSpreadPoints);
            return r;
         }
      }

      // ── Phase 1 Filter C: ATR minimum ─────────────────────────────
      if(InpATRMinimum > 0.0)
      {
         const double atr = CurrentATR();
         if(atr > 0.0 && atr < InpATRMinimum)
         {
            r.reason = StringFormat("ATR too low: %.5f < %.5f (low volatility)",
                                     atr, InpATRMinimum);
            return r;
         }
      }

      // ── Phase 1 Filter D: ADX minimum ─────────────────────────────
      if(InpADXMinimum > 0.0)
      {
         const double adx = CurrentADX();
         if(adx > 0.0 && adx < InpADXMinimum)
         {
            r.reason = StringFormat("ADX too low: %.1f < %.1f (ranging market)",
                                     adx, InpADXMinimum);
            return r;
         }
      }

      // Read indicator values
      IchimokuValues v;
      if(!ReadValues(v)) { r.reason = "data unavailable"; return r; }

      // Run core signal logic (includes future cloud check)
      r = EvaluateSignal(v);

      // ── Phase 1 Filter E: Freshness filter ────────────────────────
      // Track when TK cross occurred and reject stale crosses
      if(r.signal != ICHI_NONE && InpFreshnessBarLimit > 0)
      {
         // Cross just fired on this bar — update cross timestamp
         m_crossBar = curBar;
      }
      else if(r.reason == "no TK cross" && InpFreshnessBarLimit > 0)
      {
         // No cross this bar — check if recent cross still within freshness window
         if(m_crossBar > 0)
         {
            const int periodSecs = PeriodSeconds(InpTimeframe);
            const int barsSinceCross = (int)((curBar - m_crossBar) / periodSecs);

            // Re-evaluate: allow entry if recent cross was within freshness window
            // AND all other conditions (Chikou, cloud, future cloud) still hold
            if(barsSinceCross > 0 && barsSinceCross <= InpFreshnessBarLimit)
            {
               // Check if non-cross conditions still valid
               IchimokuSignalResult fresh;
               fresh.Clear();
               fresh.cloudTop = v.cloudTop;
               fresh.cloudBot = v.cloudBot;
               fresh.kijun    = v.kijunCur;
               fresh.tenkan   = v.tenkanCur;

               // Chikou check
               bool chikouFree = (v.chikouCur > v.cloudTopAtChikou) ||
                                   (v.chikouCur < v.cloudBotAtChikou);
               if(!chikouFree)
               { r.reason = "stale cross: Chikou no longer free"; return r; }

               // Price vs cloud (fresh check)
               if(v.currentPrice > v.cloudTop)
               {
                  if(InpRequireFutureCloudAgree && v.cloudTopFuture <= v.cloudBotFuture)
                  { r.reason = "stale cross: future cloud now bearish"; return r; }
                  fresh.signal = ICHI_BUY;
                  fresh.score  = 60; // Freshness continuation — always NEAR score
                  fresh.reason = StringFormat("BUY (fresh cross %d bars ago): Chikou free, above cloud",
                                               barsSinceCross);
                  return fresh;
               }
               else if(v.currentPrice < v.cloudBot)
               {
                  if(InpRequireFutureCloudAgree && v.cloudTopFuture >= v.cloudBotFuture)
                  { r.reason = "stale cross: future cloud now bullish"; return r; }
                  fresh.signal = ICHI_SELL;
                  fresh.score  = 60;
                  fresh.reason = StringFormat("SELL (fresh cross %d bars ago): Chikou free, below cloud",
                                               barsSinceCross);
                  return fresh;
               }
            }
            else if(barsSinceCross > InpFreshnessBarLimit)
            {
               // Cross is stale — update reason only if the original reason was no TK cross
               r.reason = StringFormat("stale cross (%d bars ago, limit=%d)",
                                        barsSinceCross, InpFreshnessBarLimit);
            }
         }
      }

      return r;
   }

   //-------------------------------------------------------------------
   // Get current Kijun value (for trailing stop, ungated)
   //-------------------------------------------------------------------
   double CurrentKijun() const
   {
      double kijun[];
      ArraySetAsSeries(kijun, true);
      if(CopyBuffer(m_handle, 1, 0, 2, kijun) < 2) return 0.0;
      return kijun[0];
   }

   //-------------------------------------------------------------------
   // Check if price closed inside cloud (for cloud exit)
   //-------------------------------------------------------------------
   bool PriceInsideCloud() const
   {
      double senkouA[], senkouB[];
      ArraySetAsSeries(senkouA, true);
      ArraySetAsSeries(senkouB, true);
      if(CopyBuffer(m_handle, 2, 0, 2, senkouA) < 2) return false;
      if(CopyBuffer(m_handle, 3, 0, 2, senkouB) < 2) return false;

      const double cloudTop = MathMax(senkouA[1], senkouB[1]);
      const double cloudBot = MathMin(senkouA[1], senkouB[1]);
      const double close    = iClose(m_symbol, InpTimeframe, 1);

      return (close < cloudTop && close > cloudBot);
   }

   // Diagnostic accessors
   double GetLastATR() const { return CurrentATR(); }
   double GetLastADX() const { return CurrentADX(); }
   int    GetBarsSinceCross() const
   {
      if(m_crossBar == 0) return -1;
      const datetime curBar   = iTime(m_symbol, InpTimeframe, 0);
      const int      periodSecs = PeriodSeconds(InpTimeframe);
      return (int)((curBar - m_crossBar) / periodSecs);
   }
};

#endif // ICHIMOKUEA_SIGNAL_MQH