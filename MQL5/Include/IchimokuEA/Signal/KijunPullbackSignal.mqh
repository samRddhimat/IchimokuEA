//+------------------------------------------------------------------+
//| KijunPullbackSignal.mqh                                           |
//| IchimokuEA — Phase 2: Kijun Pullback continuation entry          |
//|                                                                   |
//| Fires when the trend is already established and price pulls back  |
//| to the Kijun-sen, then resumes — no TK cross required.           |
//|                                                                   |
//| Entry conditions (ALL required):                                  |
//|   1. Price outside cloud (trend established)                      |
//|   2. Price above cloud for N bars (InpKPMinTrendBars, default 3) |
//|   3. Tenkan above Kijun (trend intact — no cross reversal)       |
//|   4. Price pulls back within InpKPKijunZonePct of Kijun          |
//|   5. Current bar closes back beyond Tenkan (pullback held)        |
//|   6. Chikou in free space                                         |
//|   7. Phase 1 filters: session, spread, ATR, ADX (if enabled)     |
//|                                                                   |
//| Comment tag: M2_KP (distinguishes from M1 TK cross entries)      |
//| Enable/disable: InpKijunPullbackModule=true/false                 |
//+------------------------------------------------------------------+
#ifndef ICHIMOKUEA_KIJUNPULLBACK_MQH
#define ICHIMOKUEA_KIJUNPULLBACK_MQH

#include <IchimokuEA/Config/Inputs.mqh>
#include <IchimokuEA/Signal/IchimokuSignal.mqh>

class CKijunPullbackSignal
{
private:
   int      m_handle;     // shared Ichimoku handle from CIchimokuSignal
   int      m_atrHandle;
   int      m_adxHandle;
   string   m_symbol;
   int      m_displacement;
   datetime m_lastBar;    // new-bar gate

   //-------------------------------------------------------------------
   // Count bars price has been outside cloud in given direction
   //-------------------------------------------------------------------
   int BarsOutsideCloud(const bool aboveCloud) const
   {
      double sA[], sB[];
      ArraySetAsSeries(sA, true);
      ArraySetAsSeries(sB, true);
      if(CopyBuffer(m_handle, 2, 1, InpKPMinTrendBars+2, sA) < InpKPMinTrendBars) return 0;
      if(CopyBuffer(m_handle, 3, 1, InpKPMinTrendBars+2, sB) < InpKPMinTrendBars) return 0;

      int count = 0;
      for(int i = 0; i < InpKPMinTrendBars; i++)
      {
         const double top = MathMax(sA[i], sB[i]);
         const double bot = MathMin(sA[i], sB[i]);
         const double cl  = iClose(m_symbol, InpTimeframe, i+1);
         if(aboveCloud && cl > top) count++;
         else if(!aboveCloud && cl < bot) count++;
         else break; // streak broken
      }
      return count;
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
      if(bullish)  return chikou[0] > chTop;
      return chikou[0] < chBot;
   }

   //-------------------------------------------------------------------
   // Session filter (same as IchimokuSignal)
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
   // ATR filter
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

public:
   CKijunPullbackSignal()
      : m_handle(INVALID_HANDLE),
        m_atrHandle(INVALID_HANDLE),
        m_adxHandle(INVALID_HANDLE),
        m_lastBar(0),
        m_displacement(26) {}

   //-------------------------------------------------------------------
   // Init — takes shared handle from CIchimokuSignal
   //-------------------------------------------------------------------
   bool Init(const string symbol, const int ichiHandle,
             const int atrHandle, const int adxHandle,
             const int displacement)
   {
      m_symbol       = symbol;
      m_handle       = ichiHandle;   // shared — do NOT release
      m_atrHandle    = atrHandle;    // shared — do NOT release
      m_adxHandle    = adxHandle;    // shared — do NOT release
      m_displacement = displacement;
      return (m_handle != INVALID_HANDLE);
   }

   void Deinit() { /* handles owned by CIchimokuSignal — don't release here */ }

   //-------------------------------------------------------------------
   // Evaluate — new-bar gated
   // Returns IchimokuSignalResult with signal + reason
   // score is always 70 (between near=60 and far=90)
   //-------------------------------------------------------------------
   IchimokuSignalResult Evaluate()
   {
      IchimokuSignalResult r;
      r.Clear();

      if(!InpKijunPullbackModule)
      { r.reason = "KP module disabled"; return r; }

      // Bar gate
      const datetime curBar = iTime(m_symbol, InpTimeframe, 0);
      if(curBar == m_lastBar) { r.reason = "same bar"; return r; }
      m_lastBar = curBar;

      // Phase 1 filters
      if(!IsAllowedSession()) { r.reason = "KP: outside session"; return r; }
      if(!SpreadOk())         { r.reason = "KP: spread too wide"; return r; }
      if(!ATROk())            { r.reason = "KP: ATR too low"; return r; }
      if(!ADXOk())            { r.reason = "KP: ADX too low"; return r; }

      // Read current indicator values
      double tenkan[], kijun[], senkouA[], senkouB[];
      ArraySetAsSeries(tenkan,  true);
      ArraySetAsSeries(kijun,   true);
      ArraySetAsSeries(senkouA, true);
      ArraySetAsSeries(senkouB, true);

      if(CopyBuffer(m_handle, 0, 0, 3, tenkan)  < 3) { r.reason = "KP: data unavailable"; return r; }
      if(CopyBuffer(m_handle, 1, 0, 3, kijun)   < 3) { r.reason = "KP: data unavailable"; return r; }
      if(CopyBuffer(m_handle, 2, 0, 3, senkouA) < 3) { r.reason = "KP: data unavailable"; return r; }
      if(CopyBuffer(m_handle, 3, 0, 3, senkouB) < 3) { r.reason = "KP: data unavailable"; return r; }

      const double cloudTop = MathMax(senkouA[0], senkouB[0]);
      const double cloudBot = MathMin(senkouA[0], senkouB[0]);
      const double price    = (SymbolInfoDouble(m_symbol, SYMBOL_BID) +
                               SymbolInfoDouble(m_symbol, SYMBOL_ASK)) / 2.0;
      const double kijunCur = kijun[0];
      const double tenkanCur= tenkan[0];

      // Populate result cloud/kijun values for stop calculation
      r.cloudTop = cloudTop;
      r.cloudBot = cloudBot;
      r.kijun    = kijunCur;
      r.tenkan   = tenkanCur;

      // ── BUY setup ─────────────────────────────────────────────────
      if(price > cloudTop && tenkanCur > kijunCur)
      {
         // Condition 1: trend established — N bars above cloud
         if(BarsOutsideCloud(true) < InpKPMinTrendBars)
         { r.reason = "KP: uptrend not established yet"; return r; }

         // Condition 2: price within KP zone of Kijun
         const double distToKijun = (price - kijunCur) / price;
         if(distToKijun > InpKPKijunZonePct)
         { r.reason = StringFormat("KP: price too far from Kijun (%.2f%% > %.2f%%)",
                                    distToKijun*100, InpKPKijunZonePct*100); return r; }

         // Condition 3: closed bar above Tenkan (pullback held, resuming)
         const double lastClose = iClose(m_symbol, InpTimeframe, 1);
         if(lastClose < tenkanCur)
         { r.reason = "KP: last close below Tenkan — pullback not held"; return r; }

         // Condition 4: Chikou free
         if(!ChikouFree(true))
         { r.reason = "KP: Chikou not free above cloud"; return r; }

         r.signal = ICHI_BUY;
         r.score  = 70;
         r.reason = StringFormat("M2_KP BUY: trend %d bars, kijun dist=%.2f%%",
                                  BarsOutsideCloud(true), distToKijun*100);
         return r;
      }

      // ── SELL setup ────────────────────────────────────────────────
      if(price < cloudBot && tenkanCur < kijunCur)
      {
         // Condition 1: trend established
         if(BarsOutsideCloud(false) < InpKPMinTrendBars)
         { r.reason = "KP: downtrend not established yet"; return r; }

         // Condition 2: price within KP zone of Kijun
         const double distToKijun = (kijunCur - price) / price;
         if(distToKijun > InpKPKijunZonePct)
         { r.reason = StringFormat("KP: price too far from Kijun (%.2f%% > %.2f%%)",
                                    distToKijun*100, InpKPKijunZonePct*100); return r; }

         // Condition 3: closed bar below Tenkan (pullback held, resuming)
         const double lastClose = iClose(m_symbol, InpTimeframe, 1);
         if(lastClose > tenkanCur)
         { r.reason = "KP: last close above Tenkan — pullback not held"; return r; }

         // Condition 4: Chikou free
         if(!ChikouFree(false))
         { r.reason = "KP: Chikou not free below cloud"; return r; }

         r.signal = ICHI_SELL;
         r.score  = 70;
         r.reason = StringFormat("M2_KP SELL: trend %d bars, kijun dist=%.2f%%",
                                  BarsOutsideCloud(false), distToKijun*100);
         return r;
      }

      // Price inside cloud or TK misaligned
      if(price >= cloudBot && price <= cloudTop)
         r.reason = "KP: price inside cloud";
      else
         r.reason = "KP: TK not aligned with trend direction";

      return r;
   }
};

#endif // ICHIMOKUEA_KIJUNPULLBACK_MQH
