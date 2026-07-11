//+------------------------------------------------------------------+
//| PositionSizing.mqh                                                |
//| IchimokuEA — position sizing: risk% per trade or fixed lot       |
//+------------------------------------------------------------------+
#ifndef ICHIMOKUEA_POSITIONSIZING_MQH
#define ICHIMOKUEA_POSITIONSIZING_MQH

#include <IchimokuEA/Config/Inputs.mqh>

class CPositionSizing
{
private:
   string m_symbol;

   double NormalizeVolume(const double vol) const
   {
      const double mn   = SymbolInfoDouble(m_symbol, SYMBOL_VOLUME_MIN);
      const double mx   = SymbolInfoDouble(m_symbol, SYMBOL_VOLUME_MAX);
      double       step = SymbolInfoDouble(m_symbol, SYMBOL_VOLUME_STEP);
      if(step <= 0.0) step = 0.01;
      double v = MathFloor(vol / step) * step;
      if(v < mn) return 0.0;
      if(v > mx) v = mx;
      if(v > InpMaxLot) v = InpMaxLot;
      return v;
   }

public:
   void Init(const string symbol) { m_symbol = symbol; }

   //-------------------------------------------------------------------
   // CalculateLot
   // equity     : account equity
   // entryPrice : expected fill price
   // stopPrice  : computed stop price
   // Returns lot size (0.0 if below minimum)
   //-------------------------------------------------------------------
   double CalculateLot(const double equity,
                        const double entryPrice,
                        const double stopPrice,
                        string &reason) const
   {
      if(InpSizeMode == 1)
      {
         // Fixed lot
         const double vol = NormalizeVolume(InpFixedLot);
         reason = StringFormat("fixed lot=%.2f", vol);
         return vol;
      }

      // Risk % based
      const double stopDist = MathAbs(entryPrice - stopPrice);
      if(stopDist <= 0.0)
      {
         reason = "stop distance=0";
         return 0.0;
      }

      const double tickSize  = SymbolInfoDouble(m_symbol, SYMBOL_TRADE_TICK_SIZE);
      const double tickValue = SymbolInfoDouble(m_symbol, SYMBOL_TRADE_TICK_VALUE);
      if(tickSize <= 0.0 || tickValue <= 0.0)
      {
         reason = "invalid tick data";
         return 0.0;
      }

      const double riskMoney      = equity * (InpRiskPercent / 100.0);
      const double dollarPerPoint = tickValue / tickSize;
      const double rawLot         = riskMoney / (stopDist * dollarPerPoint);
      const double vol            = NormalizeVolume(rawLot);

      reason = StringFormat("risk=%.1f%% equity=%.2f stop=%.5f lot=%.2f",
                             InpRiskPercent, equity, stopDist, vol);
      return vol;
   }
};

#endif // ICHIMOKUEA_POSITIONSIZING_MQH
