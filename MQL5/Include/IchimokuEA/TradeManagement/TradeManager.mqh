//+------------------------------------------------------------------+
//| TradeManager.mqh                                                  |
//| IchimokuEA — orchestrates all exit/management logic per position  |
//|                                                                   |
//| Evaluation sequence per position per bar:                         |
//|   1. Emergency: price closed inside cloud → close all            |
//|   2. Time exit: barsOpen >= threshold → close all                |
//|   3. Breakeven: profit >= 1R → move SL to entry                  |
//|   4. Profit lock: dollar-tier based SL tightening (optional)     |
//|   5. Partial close: profit >= InpProfitTargetR → close N%        |
//|   6. Kijun trail: after BE, trail SL to Kijun-sen                |
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
   CIchimokuSignal *m_signal;

   double ProfitInR(const IchiTradeContext &c) const
   {
      if(c.initialRisk <= 0.0) return 0.0;
      const double priceMoved = (c.type > 0)
                                 ? (c.currentPrice - c.entry)
                                 : (c.entry - c.currentPrice);
      return priceMoved / c.initialRisk;
   }

   bool IsImprovement(const int type, const double newSL, const double currentSL) const
   {
      if(currentSL == 0.0) return true;
      if(type > 0) return newSL > currentSL;
      return newSL < currentSL;
   }

   //-------------------------------------------------------------------
   // ProfitLockPct — discrete tier system (matches DynamicProfitLock)
   //-------------------------------------------------------------------
   double ProfitLockPct(const double profit) const
   {
      if(profit <   50.0) return 0.30;
      if(profit <  200.0) return 0.50;
      if(profit <  500.0) return 0.70;
      if(profit < 1000.0) return 0.80;
      return 0.90;
   }

   //-------------------------------------------------------------------
   // ComputeProfitLockSL — SL price that protects lockPct of profit
   //-------------------------------------------------------------------
   double ComputeProfitLockSL(const IchiTradeContext &c,
                                const double profit,
                                const double lockPct) const
   {
      const double tickSize  = SymbolInfoDouble(c.symbol, SYMBOL_TRADE_TICK_SIZE);
      const double tickValue = SymbolInfoDouble(c.symbol, SYMBOL_TRADE_TICK_VALUE);
      if(tickSize <= 0.0 || tickValue <= 0.0 || c.volume <= 0.0) return 0.0;

      const double dollarPerPoint = (tickValue / tickSize) * c.volume;
      if(dollarPerPoint <= 0.0) return 0.0;

      const double protectAmount = profit * lockPct;
      const double priceDist     = protectAmount / dollarPerPoint;

      const double sl = (c.type > 0)
                         ? (c.entry + priceDist)   // BUY: lock SL above entry
                         : (c.entry - priceDist);  // SELL: lock SL below entry

      return NormalizeDouble(sl, (int)SymbolInfoInteger(c.symbol, SYMBOL_DIGITS));
   }

public:
   CTradeManager() : m_signal(NULL) {}

   void Init(CIchimokuSignal *signal) { m_signal = signal; }

   IchiTradeAction Evaluate(const IchiTradeContext &c) const
   {
      IchiTradeAction a;
      a.Clear();

      const double profitR = ProfitInR(c);

      // ── Equity Profit Lock (runs before BE — activates immediately) ──
      // Triggers as soon as profit reaches InpEPLTriggerPct% of equity
      // Trails continuously every tick locking InpEPLLockPct% of profit
      if(InpEquityProfitLock)
      {
         const double tickSize    = SymbolInfoDouble(c.symbol, SYMBOL_TRADE_TICK_SIZE);
         const double tickValue   = SymbolInfoDouble(c.symbol, SYMBOL_TRADE_TICK_VALUE);
         if(tickSize > 0.0 && tickValue > 0.0 && c.volume > 0.0)
         {
            const double priceMoved  = (c.type > 0)
                                        ? (c.currentPrice - c.entry)
                                        : (c.entry - c.currentPrice);
            const double dollarPerPt = (tickValue / tickSize) * c.volume;
            const double dollarPnL   = priceMoved * dollarPerPt;

            // Only act when profit is positive
            if(dollarPnL > 0.0)
            {
               const double equity    = AccountInfoDouble(ACCOUNT_EQUITY);
               const double trigger   = equity * (InpEPLTriggerPct / 100.0);

               if(dollarPnL >= trigger)
               {
                  // Lock InpEPLLockPct% of current dollar profit
                  const double protectAmt  = dollarPnL * (InpEPLLockPct / 100.0);
                  const double protectDist = protectAmt / dollarPerPt;
                  const double point       = SymbolInfoDouble(c.symbol, SYMBOL_POINT);

                  const double eplSL = (c.type > 0)
                                        ? NormalizeDouble(c.entry + protectDist,
                                           (int)SymbolInfoInteger(c.symbol, SYMBOL_DIGITS))
                                        : NormalizeDouble(c.entry - protectDist,
                                           (int)SymbolInfoInteger(c.symbol, SYMBOL_DIGITS));

                  if(eplSL > 0.0 && IsImprovement(c.type, eplSL, c.currentSL))
                  {
                     a.modifySL = true;
                     a.newSL    = eplSL;
                     a.reason   = StringFormat(
                        "EPL: profit=$%.2f trigger=$%.2f lock=%.1f%% protects=$%.2f newSL=%.5f",
                        dollarPnL, trigger, InpEPLLockPct, protectAmt, eplSL);
                     return a;
                  }
               }
            }
         }
      }

      // 1. Emergency cloud exit
      if(InpCloudExit && m_signal != NULL && profitR > 0.0)
      {
         if(m_signal.PriceInsideCloud())
         {
            a.closeAll = true;
            a.reason   = StringFormat("cloud exit: price inside cloud at %.2fR", profitR);
            return a;
         }
      }

      // 2. Time exit
      const int timeLimit = (InpEAMode == 1) ? InpScalpTimeExitCandles : InpTimeExitCandles;
      if(timeLimit > 0 && c.barsOpen >= timeLimit && profitR < 0.5)
      {
         a.closeAll = true;
         a.reason   = StringFormat("time exit: %d bars, %.2fR", c.barsOpen, profitR);
         return a;
      }

      // 3. Breakeven
      if(!c.beDone && profitR >= InpBreakEvenAtR)
      {
         const double point = SymbolInfoDouble(c.symbol, SYMBOL_POINT);
         const double beSL  = (c.type > 0) ? (c.entry + point) : (c.entry - point);
         if(IsImprovement(c.type, beSL, c.currentSL))
         {
            a.modifySL = true;
            a.newSL    = NormalizeDouble(beSL, (int)SymbolInfoInteger(c.symbol, SYMBOL_DIGITS));
            a.reason   = StringFormat("breakeven at %.2fR", profitR);
            return a;
         }
      }

      // 4. Profit lock — only after BE is done, only when enabled
      if(InpProfitLock && c.beDone)
      {
         // Current unrealized profit in dollars
         const double profit = (c.type > 0)
                                ? (c.currentPrice - c.entry)
                                : (c.entry - c.currentPrice);
         const double tickSize  = SymbolInfoDouble(c.symbol, SYMBOL_TRADE_TICK_SIZE);
         const double tickValue = SymbolInfoDouble(c.symbol, SYMBOL_TRADE_TICK_VALUE);
         const double dollarPnL = (tickSize > 0.0 && tickValue > 0.0)
                                   ? profit * (tickValue / tickSize) * c.volume
                                   : 0.0;

         if(dollarPnL > 0.0)
         {
            const double lockPct = ProfitLockPct(dollarPnL);
            const double lockSL  = ComputeProfitLockSL(c, dollarPnL, lockPct);
            if(lockSL > 0.0 && IsImprovement(c.type, lockSL, c.currentSL))
            {
               a.modifySL = true;
               a.newSL    = lockSL;
               a.reason   = StringFormat("profit lock: $%.2f lock=%.0f%% newSL=%.5f",
                                          dollarPnL, lockPct * 100.0, lockSL);
               return a;
            }
         }
      }

      // 5. Partial close at TP
      const double targetR = (InpEAMode == 1) ? InpScalpProfitTargetR : InpProfitTargetR;
      if(targetR > 0.0 && !c.partialDone && profitR >= targetR && InpPartialClosePct > 0.0)
      {
         const double closeVol = NormalizeDouble(
            c.initialVolume * (InpPartialClosePct / 100.0), 2);
         if(closeVol > 0.0 && closeVol < c.volume)
         {
            a.closePartial = true;
            a.closeVolume  = closeVol;
            a.reason       = StringFormat("partial %.0f%% at %.2fR", InpPartialClosePct, profitR);
            return a;
         }
         else if(closeVol >= c.volume)
         {
            a.closeAll = true;
            a.reason   = StringFormat("full close at TP %.2fR", profitR);
            return a;
         }
      }

      // 6. Kijun trail
      if(InpKijunTrail && c.beDone && m_signal != NULL)
      {
         const double kijun = m_signal.CurrentKijun();
         if(kijun > 0.0)
         {
            const double point   = SymbolInfoDouble(c.symbol, SYMBOL_POINT);
            const double kijunSL = (c.type > 0)
                                    ? (kijun - InpStopBufferPts * point)
                                    : (kijun + InpStopBufferPts * point);
            const double kijunSLN = NormalizeDouble(kijunSL,
                                     (int)SymbolInfoInteger(c.symbol, SYMBOL_DIGITS));
            if(IsImprovement(c.type, kijunSLN, c.currentSL))
            {
               a.modifySL = true;
               a.newSL    = kijunSLN;
               a.reason   = StringFormat("Kijun trail: %.5f", kijunSLN);
               return a;
            }
         }
      }

      return a;
   }
};


#endif // ICHIMOKUEA_TRADEMANAGER_MQH