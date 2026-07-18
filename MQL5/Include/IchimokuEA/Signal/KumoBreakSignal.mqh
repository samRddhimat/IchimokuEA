//+------------------------------------------------------------------+
//| KumoBreakSignal.mqh                                               |
//| IchimokuEA — Phase 3: Fresh Kumo Breakout entry module           |
//|                                                                   |
//| Fires when price has JUST broken out of the cloud — within       |
//| InpKBFreshnessLimit bars — with expanding ATR confirming         |
//| momentum. Captures early trend inception moves.                   |
//|                                                                   |
//| Entry conditions (ALL required):                                  |
//|   1. Price closed beyond cloud within last N bars (fresh break)  |
//|   2. TK cross is recent (within InpFreshnessBarLimit bars)       |
//|   3. Chikou in free space                                         |
//|   4. Future cloud agrees with breakout direction                  |
//|   5. ATR expanding — bar[1] ATR > bar[InpKBATRLookback] ATR     |
//|   6. Phase 1 filters: session, spread, ATR min, ADX (if enabled) |
//|                                                                   |
//| Comment tag: M3_KB (distinguishes from M1 TK and M2 KP entries) |
//| Enable/disable: InpKumoBreakModule=true/false                     |
//| Stop: cloud boundary (same as M1 and M2)                         |
//+------------------------------------------------------------------+
#ifndef ICHIMOKUEA_KUMOBREAK_MQH
#define ICHIMOKUEA_KUMOBREAK_MQH

#include <IchimokuEA/Config/Inputs.mqh>
#include <IchimokuEA/Signal/IchimokuSignal.mqh>

class CKumoBreakSignal
{
private:
   int      m_handle;
   int      m_atrHandle;
   int      m_adxHandle;
   string   m_symbol;
   int      m_displacement;
   datetime m_lastBar;

   // Track when breakout occurred
   datetime m_breakoutBar;    // bar time of last confirmed cloud breakout
   bool     m_breakoutBull;   // true=bullish breakout, false=bearish

   //-------------------------------------------------------------------
   // Session filter
   //-------------------------------------------------------------------
   bool IsAllowedSession() const
   {
      if(!InpSessionFilterEnabled) return true;
      MqlDateTime dt;
      TimeToStruct(TimeCurrent(), dt);
      const int h = dt.hour;
      return (h >= 7 && h < 16);
   }

   //-------------------------------------------------------------------
   // Spread filter
   //-------------------------------------------------------------------
   bool SpreadOk() const
   {
      if(InpMaxSpreadPoints <= 0) return true;
      return SymbolInfoInteger(m_symbol, SYMBOL_SPREAD) <= InpMaxSpreadPoints;
   }

   //-------------------------------------------------------------------
   // ATR minimum filter
   //-------------------------------------------------------------------
   bool ATROk() const
   {
      if(InpATRMinimum <= 0.0 || m_atrHandle == INVALID_HANDLE) return true;
      double buf[];
      ArraySetAsSeries(buf, true);
      if(CopyBuffer(m_atrHandle, 0, 1, 1, buf) < 1) return true;
      return buf[0] >= InpATRMinimum;
   }

   //-------------------------------------------------------------------
   // ADX filter
   //-------------------------------------------------------------------
   bool ADXOk() const
   {
      if(InpADXMinimum <= 0.0 || m_adxHandle == INVALID_HANDLE) return true;
      double buf[];
      ArraySetAsSeries(buf, true);
      if(CopyBuffer(m_adxHandle, 0, 1, 1, buf) < 1) return true;
      return buf[0] >= InpADXMinimum;
   }

   //-------------------------------------------------------------------
   // ATR expanding check — momentum confirmation
   // Returns true if ATR[1] > ATR[InpKBATRLookback]
   //-------------------------------------------------------------------
   bool ATRExpanding() const
   {
      if(m_atrHandle == INVALID_HANDLE) return true; // no handle = skip
      if(InpKBATRLookback <= 0) return true;
      double buf[];
      ArraySetAsSeries(buf, true);
      const int needed = InpKBATRLookback + 2;
      if(CopyBuffer(m_atrHandle, 0, 1, needed, buf) < needed) return true;
      return buf[0] > buf[InpKBATRLookback - 1];
   }

   //-------------------------------------------------------------------
   // Chikou free space check
   //-------------------------------------------------------------------
   bool ChikouFree(const bool bullish) const
   {
      double chikou[], chSA[], chSB[];
      ArraySetAsSeries(chikou, true);
      ArraySetAsSeries(chSA,   true);
      ArraySetAsSeries(chSB,   true);
      if(CopyBuffer(m_handle, 4, 0, 2, chikou) < 2) return false;
      if(CopyBuffer(m_handle, 2, m_displacement, 2, chSA) < 2) return false;
      if(CopyBuffer(m_handle, 3, m_displacement, 2, chSB) < 2) return false;
      const double chTop = MathMax(chSA[0], chSB[0]);
      const double chBot = MathMin(chSA[0], chSB[0]);
      if(bullish) return chikou[0] > chTop;
      return chikou[0] < chBot;
   }

   //-------------------------------------------------------------------
   // Future cloud direction check
   //-------------------------------------------------------------------
   bool FutureCloudAgrees(const bool bullish) const
   {
      double futA[], futB[];
      ArraySetAsSeries(futA, true);
      ArraySetAsSeries(futB, true);
      if(CopyBuffer(m_handle, 2, -(m_displacement-1), 2, futA) < 2) return true;
      if(CopyBuffer(m_handle, 3, -(m_displacement-1), 2, futB) < 2) return true;
      if(bullish) return futA[0] > futB[0];  // Span A above Span B = bullish
      return futA[0] < futB[0];              // Span A below Span B = bearish
   }

   //-------------------------------------------------------------------
   // Detect cloud breakout on bar[i] (1 = last closed bar)
   // Returns: 1=bullish break, -1=bearish break, 0=no break
   //-------------------------------------------------------------------
   int DetectBreakout(const int barIndex) const
   {
      double sA[], sB[];
      ArraySetAsSeries(sA, true);
      ArraySetAsSeries(sB, true);
      const int needed = barIndex + 3;
      if(CopyBuffer(m_handle, 2, 0, needed, sA) < needed) return 0;
      if(CopyBuffer(m_handle, 3, 0, needed, sB) < needed) return 0;

      const double cloudTop  = MathMax(sA[barIndex],   sB[barIndex]);
      const double cloudBot  = MathMin(sA[barIndex],   sB[barIndex]);
      const double prevTop   = MathMax(sA[barIndex+1], sB[barIndex+1]);
      const double prevBot   = MathMin(sA[barIndex+1], sB[barIndex+1]);

      const double closeNow  = iClose(m_symbol, InpTimeframe, barIndex);
      const double closePrev = iClose(m_symbol, InpTimeframe, barIndex+1);

      // Bullish breakout: previous close at/below cloud top, current close above
      if(closeNow > cloudTop && closePrev <= prevTop) return 1;
      // Bearish breakout: previous close at/above cloud bot, current close below
      if(closeNow < cloudBot && closePrev >= prevBot) return -1;

      return 0;
   }

   //-------------------------------------------------------------------
   // Bars since last TK cross (for freshness check)
   //-------------------------------------------------------------------
   int BarsSinceTKCross(const bool bullish) const
   {
      double tenkan[], kijun[];
      ArraySetAsSeries(tenkan, true);
      ArraySetAsSeries(kijun,  true);
      const int needed = InpFreshnessBarLimit + 5;
      if(CopyBuffer(m_handle, 0, 0, needed, tenkan) < needed) return 999;
      if(CopyBuffer(m_handle, 1, 0, needed, kijun)  < needed) return 999;

      for(int i = 1; i < needed - 1; i++)
      {
         bool cross = bullish
                      ? (tenkan[i] > kijun[i] && tenkan[i+1] <= kijun[i+1])
                      : (tenkan[i] < kijun[i] && tenkan[i+1] >= kijun[i+1]);
         if(cross) return i;
      }
      return 999; // no recent cross
   }

public:
   CKumoBreakSignal()
      : m_handle(INVALID_HANDLE),
        m_atrHandle(INVALID_HANDLE),
        m_adxHandle(INVALID_HANDLE),
        m_lastBar(0),
        m_breakoutBar(0),
        m_breakoutBull(false),
        m_displacement(26) {}

   //-------------------------------------------------------------------
   // Init — shares handles from CIchimokuSignal
   //-------------------------------------------------------------------
   bool Init(const string symbol, const int ichiHandle,
             const int atrHandle, const int adxHandle,
             const int displacement)
   {
      m_symbol       = symbol;
      m_handle       = ichiHandle;
      m_atrHandle    = atrHandle;
      m_adxHandle    = adxHandle;
      m_displacement = displacement;
      return (m_handle != INVALID_HANDLE);
   }

   void Deinit() { /* handles owned by CIchimokuSignal */ }

   //-------------------------------------------------------------------
   // Evaluate — new-bar gated
   //-------------------------------------------------------------------
   IchimokuSignalResult Evaluate()
   {
      IchimokuSignalResult r;
      r.Clear();

      if(!InpKumoBreakModule)
      { r.reason = "KB module disabled"; return r; }

      // Bar gate
      const datetime curBar = iTime(m_symbol, InpTimeframe, 0);
      if(curBar == m_lastBar) { r.reason = "same bar"; return r; }
      m_lastBar = curBar;

      // Phase 1 filters
      if(!IsAllowedSession()) { r.reason = "KB: outside session"; return r; }
      if(!SpreadOk())         { r.reason = "KB: spread too wide"; return r; }
      if(!ATROk())            { r.reason = "KB: ATR too low"; return r; }
      if(!ADXOk())            { r.reason = "KB: ADX too low"; return r; }

      // ── Step 1: Scan for fresh cloud breakout within freshness window ──
      // Check last InpKBFreshnessLimit bars for a breakout event
      int breakDir   = 0;
      int breakBars  = 999;

      for(int i = 1; i <= InpKBFreshnessLimit; i++)
      {
         const int dir = DetectBreakout(i);
         if(dir != 0)
         {
            breakDir  = dir;
            breakBars = i;
            break; // take most recent breakout
         }
      }

      if(breakDir == 0)
      { r.reason = StringFormat("KB: no fresh cloud breakout (checked %d bars)", InpKBFreshnessLimit); return r; }

      const bool isBull = (breakDir == 1);

      // ── Step 2: Current price still outside cloud ──────────────────
      double sA[], sB[];
      ArraySetAsSeries(sA, true);
      ArraySetAsSeries(sB, true);
      if(CopyBuffer(m_handle, 2, 0, 3, sA) < 3) { r.reason = "KB: data unavailable"; return r; }
      if(CopyBuffer(m_handle, 3, 0, 3, sB) < 3) { r.reason = "KB: data unavailable"; return r; }

      const double cloudTop = MathMax(sA[0], sB[0]);
      const double cloudBot = MathMin(sA[0], sB[0]);
      const double price    = (SymbolInfoDouble(m_symbol, SYMBOL_BID) +
                               SymbolInfoDouble(m_symbol, SYMBOL_ASK)) / 2.0;

      r.cloudTop = cloudTop;
      r.cloudBot = cloudBot;

      if(isBull && price <= cloudTop)
      { r.reason = "KB: price re-entered cloud after bullish break"; return r; }
      if(!isBull && price >= cloudBot)
      { r.reason = "KB: price re-entered cloud after bearish break"; return r; }

      // ── Step 3: TK cross is recent ────────────────────────────────
      if(InpFreshnessBarLimit > 0)
      {
         const int crossBars = BarsSinceTKCross(isBull);
         if(crossBars > InpFreshnessBarLimit)
         {
            r.reason = StringFormat("KB: TK cross not recent (%d bars ago, limit=%d)",
                                     crossBars, InpFreshnessBarLimit);
            return r;
         }
      }

      // ── Step 4: Chikou free ───────────────────────────────────────
      if(!ChikouFree(isBull))
      { r.reason = "KB: Chikou not in free space"; return r; }

      // ── Step 5: Future cloud agrees ───────────────────────────────
      if(InpRequireFutureCloudAgree && !FutureCloudAgrees(isBull))
      { r.reason = "KB: future cloud disagrees with breakout direction"; return r; }

      // ── Step 6: ATR expanding (momentum confirmation) ─────────────
      if(!ATRExpanding())
      { r.reason = "KB: ATR not expanding — low momentum breakout"; return r; }

      // ── Signal fires ─────────────────────────────────────────────
      // Score: 90 if price is well beyond cloud, 70 if close to boundary
      double distPct = isBull
                       ? (price - cloudTop) / price
                       : (cloudBot - price) / price;
      const int score = (distPct > InpNearPct) ? 90 : 70;

      r.signal = isBull ? ICHI_BUY : ICHI_SELL;
      r.score  = score;
      r.kijun  = 0.0; // not used for KB stop — cloud stop used
      r.reason = StringFormat("M3_KB %s: breakout %d bars ago, ATR expanding, dist=%.2f%% score=%d",
                               isBull ? "BUY" : "SELL",
                               breakBars, distPct * 100.0, score);
      return r;
   }
};

#endif // ICHIMOKUEA_KUMOBREAK_MQH
