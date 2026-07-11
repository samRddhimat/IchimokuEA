//+------------------------------------------------------------------+
//| StopCalculator.mqh                                                |
//| IchimokuEA — computes initial stop distance using cloud/kijun/   |
//| ATR or combined (max of all three), with a small buffer.         |
//|                                                                   |
//| Stop basis (InpStopBasis):                                        |
//|   0 = Cloud boundary ± InpStopBufferPts                          |
//|   1 = Kijun-sen ± InpStopBufferPts                              |
//|   2 = ATR × InpStopATRMult                                       |
//|   3 = Combined: max(cloud stop, kijun stop, ATR stop)            |
//|                                                                   |
//| Returns stop PRICE (not distance) — 0.0 if computation fails.    |
//| Caller checks InpMaxStopRMult to decide whether to skip trade.   |
//+------------------------------------------------------------------+
#ifndef ICHIMOKUEA_STOPCALCULATOR_MQH
#define ICHIMOKUEA_STOPCALCULATOR_MQH

#include <IchimokuEA/Config/Inputs.mqh>

class CStopCalculator
{
private:
   int    m_atrHandle;
   string m_symbol;

   double CurrentATR() const
   {
      if(m_atrHandle == INVALID_HANDLE) return 0.0;
      double buf[];
      ArraySetAsSeries(buf, true);
      if(CopyBuffer(m_atrHandle, 0, 0, 2, buf) < 2) return 0.0;
      return buf[1]; // last closed bar's ATR
   }

   double NormalizePrice(const double price) const
   {
      return NormalizeDouble(price, (int)SymbolInfoInteger(m_symbol, SYMBOL_DIGITS));
   }

public:
   CStopCalculator() : m_atrHandle(INVALID_HANDLE) {}

   bool Init(const string symbol)
   {
      m_symbol    = symbol;
      m_atrHandle = iATR(symbol, InpTimeframe, 14);
      if(m_atrHandle == INVALID_HANDLE)
      {
         Print("StopCalculator: failed to create ATR handle");
         return false;
      }
      return true;
   }

   void Deinit()
   {
      if(m_atrHandle != INVALID_HANDLE) IndicatorRelease(m_atrHandle);
      m_atrHandle = INVALID_HANDLE;
   }

   //-------------------------------------------------------------------
   // ComputeStopPrice
   // entryPrice : expected fill price
   // isBuy      : trade direction
   // cloudTop   : cloud top at entry bar (from IchimokuSignalResult)
   // cloudBot   : cloud bottom at entry bar
   // kijun      : Kijun-sen at entry bar
   // Returns stop price (0.0 on failure)
   //-------------------------------------------------------------------
   double ComputeStopPrice(const double entryPrice,
                            const bool   isBuy,
                            const double cloudTop,
                            const double cloudBot,
                            const double kijun) const
   {
      const double point  = SymbolInfoDouble(m_symbol, SYMBOL_POINT);
      const double buffer = InpStopBufferPts * point;
      const double atr    = CurrentATR();

      // Cloud stop — stop just beyond the relevant cloud boundary
      double cloudStop = 0.0;
      if(isBuy)
         cloudStop = cloudBot - buffer;   // BUY: stop below cloud bottom
      else
         cloudStop = cloudTop + buffer;   // SELL: stop above cloud top

      // Kijun stop — stop just beyond Kijun-sen
      double kijunStop = 0.0;
      if(kijun > 0.0)
      {
         if(isBuy)  kijunStop = kijun - buffer;
         else       kijunStop = kijun + buffer;
      }

      // ATR stop
      double atrStop = 0.0;
      if(atr > 0.0)
      {
         const double atrDist = atr * InpStopATRMult;
         if(isBuy)  atrStop = entryPrice - atrDist;
         else       atrStop = entryPrice + atrDist;
      }

      // Select stop based on InpStopBasis
      double stopPrice = 0.0;
      switch(InpStopBasis)
      {
         case 0: stopPrice = cloudStop;  break;
         case 1: stopPrice = kijunStop;  break;
         case 2: stopPrice = atrStop;    break;
         case 3: // Combined: most conservative stop (furthest from entry)
            if(isBuy)
               stopPrice = MathMin(cloudStop, MathMin(kijunStop > 0 ? kijunStop : cloudStop,
                                                       atrStop > 0 ? atrStop : cloudStop));
            else
               stopPrice = MathMax(cloudStop, MathMax(kijunStop > 0 ? kijunStop : cloudStop,
                                                       atrStop > 0 ? atrStop : cloudStop));
            break;
         default: stopPrice = cloudStop; break;
      }

      if(stopPrice <= 0.0) return 0.0;
      return NormalizePrice(stopPrice);
   }

   //-------------------------------------------------------------------
   // StopDistanceInR
   // Returns how many R the stop distance represents relative to
   // InpRiskPercent-based sizing. Used to check InpMaxStopRMult.
   // Simple check: if stop distance > InpMaxStopRMult × ATR, skip.
   //-------------------------------------------------------------------
   bool IsStopAcceptable(const double entryPrice, const double stopPrice) const
   {
      if(stopPrice <= 0.0) return false;
      const double stopDist = MathAbs(entryPrice - stopPrice);
      const double atr      = CurrentATR();
      if(atr <= 0.0) return true; // can't check, allow

      // Reject if stop distance exceeds InpMaxStopRMult × ATR
      return stopDist <= (atr * InpMaxStopRMult);
   }

   double GetATR() const { return CurrentATR(); }
};

#endif // ICHIMOKUEA_STOPCALCULATOR_MQH
