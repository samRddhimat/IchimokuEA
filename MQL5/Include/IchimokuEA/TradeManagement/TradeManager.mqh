//+------------------------------------------------------------------+
//| TradeManager.mqh                                                  |
//| IchimokuEA — orchestrates all exit/management logic per position  |
//|                                                                   |
//| Evaluation sequence per position per bar:                         |
//|   1. Emergency: price closed inside cloud → close all            |
//|   2. Time exit: barsOpen >= threshold → close all                |
//|   3. Breakeven: profit >= 1R → move SL to entry                  |
//|   4. Partial close: profit >= InpProfitTargetR → close N%        |
//|   5. Kijun trail: after BE, trail SL to Kijun-sen                |
//|                                                                   |
//| Returns one IchiTradeAction per call — caller applies it.        |
//+------------------------------------------------------------------+
#ifndef ICHIMOKUEA_TRADEMANAGER_MQH
#define ICHIMOKUEA_TRADEMANAGER_MQH

#include <IchimokuEA/Config/Inputs.mqh>
#include <IchimokuEA/TradeManagement/TradeTypes.mqh>
#include <IchimokuEA/Signal/IchimokuSignal.mqh>

class CTradeManager
{
private:
   CIchimokuSignal *m_signal; // borrowed pointer — for Kijun trail + cloud exit

   //-------------------------------------------------------------------
   // Current profit in R multiples
   //-------------------------------------------------------------------
   double ProfitInR(const IchiTradeContext &c) const
   {
      if(c.initialRisk <= 0.0) return 0.0;
      const double priceMoved = (c.type > 0)
                                 ? (c.currentPrice - c.entry)
                                 : (c.entry - c.currentPrice);
      return priceMoved / c.initialRisk;
   }

   //-------------------------------------------------------------------
   // Is new SL an improvement (never loosen)
   //-------------------------------------------------------------------
   bool IsImprovement(const int type, const double newSL, const double currentSL) const
   {
      if(currentSL == 0.0) return true;
      if(type > 0) return newSL > currentSL;
      return newSL < currentSL;
   }

public:
   CTradeManager() : m_signal(NULL) {}

   void Init(CIchimokuSignal *signal) { m_signal = signal; }

   //-------------------------------------------------------------------
   // Evaluate — main entry point, called once per bar per position
   //-------------------------------------------------------------------
   IchiTradeAction Evaluate(const IchiTradeContext &c) const
   {
      IchiTradeAction a;
      a.Clear();

      const double profitR = ProfitInR(c);

      // 1. Emergency cloud exit — price closed inside cloud
      // Only applies when position is in profit (protect gains, not cut early)
      if(InpCloudExit && m_signal != NULL && profitR > 0.0)
      {
         if(m_signal.PriceInsideCloud())
         {
            a.closeAll = true;
            a.reason   = StringFormat("cloud exit: price closed inside cloud at %.2fR", profitR);
            return a;
         }
      }

      // 2. Time exit — position stalled, no meaningful progress
      const int timeLimit = (InpEAMode == 1) ? InpScalpTimeExitCandles : InpTimeExitCandles;
      if(timeLimit > 0 && c.barsOpen >= timeLimit && profitR < 0.5)
      {
         a.closeAll = true;
         a.reason   = StringFormat("time exit: %d bars open, only %.2fR profit", c.barsOpen, profitR);
         return a;
      }

      // 3. Breakeven — move SL to entry when profit >= InpBreakEvenAtR
      if(!c.beDone && profitR >= InpBreakEvenAtR)
      {
         const double point  = SymbolInfoDouble(c.symbol, SYMBOL_POINT);
         const double beSL   = (c.type > 0)
                                ? (c.entry + point) // 1 point above entry for buy
                                : (c.entry - point);
         if(IsImprovement(c.type, beSL, c.currentSL))
         {
            a.modifySL = true;
            a.newSL    = NormalizeDouble(beSL, (int)SymbolInfoInteger(c.symbol, SYMBOL_DIGITS));
            a.reason   = StringFormat("breakeven at %.2fR", profitR);
            return a;
         }
      }

      // 4. Partial close — take profit at InpProfitTargetR
      const double targetR = (InpEAMode == 1) ? InpScalpProfitTargetR : InpProfitTargetR;
      if(targetR > 0.0 && !c.partialDone && profitR >= targetR && InpPartialClosePct > 0.0)
      {
         const double closeVol = NormalizeDouble(
            c.initialVolume * (InpPartialClosePct / 100.0),
            2);
         if(closeVol > 0.0 && closeVol < c.volume)
         {
            a.closePartial = true;
            a.closeVolume  = closeVol;
            a.reason       = StringFormat("partial close %.0f%% at %.2fR", InpPartialClosePct, profitR);
            return a;
         }
         else if(closeVol >= c.volume)
         {
            // Close all if partial would exceed remaining volume
            a.closeAll = true;
            a.reason   = StringFormat("full close at TP %.2fR", profitR);
            return a;
         }
      }

      // 5. Kijun trail — after BE, trail SL to current Kijun
      if(InpKijunTrail && c.beDone && m_signal != NULL)
      {
         const double kijun = m_signal.CurrentKijun();
         if(kijun > 0.0)
         {
            const double point    = SymbolInfoDouble(c.symbol, SYMBOL_POINT);
            const double kijunSL  = (c.type > 0)
                                     ? (kijun - InpStopBufferPts * point)
                                     : (kijun + InpStopBufferPts * point);
            const double kijunSLN = NormalizeDouble(kijunSL,
                                     (int)SymbolInfoInteger(c.symbol, SYMBOL_DIGITS));

            if(IsImprovement(c.type, kijunSLN, c.currentSL))
            {
               a.modifySL = true;
               a.newSL    = kijunSLN;
               a.reason   = StringFormat("Kijun trail: kijun=%.5f newSL=%.5f", kijun, kijunSLN);
               return a;
            }
         }
      }

      return a; // no action this bar
   }
};

#endif // ICHIMOKUEA_TRADEMANAGER_MQH
