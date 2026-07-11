//+------------------------------------------------------------------+
//| IchimokuSignal.mqh                                                |
//| IchimokuEA — Ichimoku Kinko Hyo entry signal engine              |
//|                                                                   |
//| Single timeframe (M15). All three conditions required:            |
//|   1. Tenkan/Kijun crossover (bullish or bearish)                  |
//|   2. Chikou span in free space (not inside cloud)                 |
//|   3. Price vs cloud: above=BUY, below=SELL, inside=no signal     |
//|                                                                   |
//| Scoring: far from cloud (>InpNearPct) = 90, near = 60            |
//| Conflict (cross vs cloud disagree) = no signal                   |
//|                                                                   |
//| Standalone — no dependency on InstitutionalEA includes.           |
//| EvaluateSignal() takes injected IchimokuValues for unit testing.  |
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
   double nearThresholdPct;
};

//--- signal result
struct IchimokuSignalResult
{
   ENUM_ICHI_SIGNAL signal;
   int              score;    // 0, 60, or 90
   double           cloudTop; // cloud top at current bar (for stop calc)
   double           cloudBot; // cloud bot at current bar (for stop calc)
   double           kijun;    // kijun at current bar (for stop/trail calc)
   double           tenkan;   // tenkan at current bar
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
   int    m_handle;
   string m_symbol;
   int    m_tenkan;
   int    m_kijun;
   int    m_senkouB;
   int    m_displacement;
   double m_nearPct;

   datetime m_lastBar;   // new-bar gate

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

      // Cloud at Chikou position
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

      // Mid price
      v.currentPrice = (SymbolInfoDouble(m_symbol, SYMBOL_BID) +
                        SymbolInfoDouble(m_symbol, SYMBOL_ASK)) / 2.0;
      return true;
   }

public:
   CIchimokuSignal() : m_handle(INVALID_HANDLE), m_lastBar(0) {}

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
         Print("IchimokuSignal: failed to create handle for ", symbol);
         return false;
      }
      return true;
   }

   void Deinit()
   {
      if(m_handle != INVALID_HANDLE) IndicatorRelease(m_handle);
      m_handle = INVALID_HANDLE;
   }

   int GetHandle() const { return m_handle; }

   //-------------------------------------------------------------------
   // Pure logic — testable with synthetic values
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
         double distPct = (v.currentPrice - v.cloudTop) / v.currentPrice;
         bool isFar = distPct > v.nearThresholdPct;
         if(bullCross)
         {
            r.signal = ICHI_BUY;
            r.score  = isFar ? 90 : 60;
            r.reason = StringFormat("BUY: TK cross, Chikou free, %.2f%% above cloud (%s)",
                                     distPct * 100.0, isFar ? "FAR" : "NEAR");
         }
         else
            r.reason = "bearish cross but price above cloud — conflict";
      }
      else if(v.currentPrice < v.cloudBot)
      {
         double distPct = (v.cloudBot - v.currentPrice) / v.currentPrice;
         bool isFar = distPct > v.nearThresholdPct;
         if(bearCross)
         {
            r.signal = ICHI_SELL;
            r.score  = isFar ? 90 : 60;
            r.reason = StringFormat("SELL: TK cross, Chikou free, %.2f%% below cloud (%s)",
                                     distPct * 100.0, isFar ? "FAR" : "NEAR");
         }
         else
            r.reason = "bullish cross but price below cloud — conflict";
      }
      else
         r.reason = "price inside cloud — no signal";

      return r;
   }

   //-------------------------------------------------------------------
   // Live evaluation — new-bar gated
   //-------------------------------------------------------------------
   IchimokuSignalResult Evaluate()
   {
      IchimokuSignalResult r;
      r.Clear();

      const datetime curBar = iTime(m_symbol, InpTimeframe, 0);
      if(curBar == m_lastBar) { r.reason = "same bar"; return r; }
      m_lastBar = curBar;

      IchimokuValues v;
      if(!ReadValues(v)) { r.reason = "data unavailable"; return r; }
      return EvaluateSignal(v);
   }

   //-------------------------------------------------------------------
   // Get current Kijun value (for trailing stop updates, ungated)
   //-------------------------------------------------------------------
   double CurrentKijun() const
   {
      double kijun[];
      ArraySetAsSeries(kijun, true);
      if(CopyBuffer(m_handle, 1, 0, 2, kijun) < 2) return 0.0;
      return kijun[0];
   }

   //-------------------------------------------------------------------
   // Check if price has closed inside cloud (for cloud exit)
   //-------------------------------------------------------------------
   bool PriceInsideCloud() const
   {
      double senkouA[], senkouB[];
      ArraySetAsSeries(senkouA, true);
      ArraySetAsSeries(senkouB, true);
      if(CopyBuffer(m_handle, 2, 0, 2, senkouA) < 2) return false;
      if(CopyBuffer(m_handle, 3, 0, 2, senkouB) < 2) return false;

      const double cloudTop = MathMax(senkouA[1], senkouB[1]); // last CLOSED bar
      const double cloudBot = MathMin(senkouA[1], senkouB[1]);
      const double close    = iClose(m_symbol, InpTimeframe, 1); // last closed bar

      return (close < cloudTop && close > cloudBot);
   }
};

#endif // ICHIMOKUEA_SIGNAL_MQH
