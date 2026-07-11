//+------------------------------------------------------------------+
//| OrderExecutor.mqh                                                 |
//| IchimokuEA — market execution with retries, hedging mode         |
//+------------------------------------------------------------------+
#ifndef ICHIMOKUEA_ORDEREXECUTOR_MQH
#define ICHIMOKUEA_ORDEREXECUTOR_MQH

#include <Trade/Trade.mqh>
#include <IchimokuEA/Config/Inputs.mqh>

class COrderExecutor
{
private:
   CTrade m_trade;

   double NormalizeVolume(const string symbol, double v) const
   {
      const double mn   = SymbolInfoDouble(symbol, SYMBOL_VOLUME_MIN);
      const double mx   = SymbolInfoDouble(symbol, SYMBOL_VOLUME_MAX);
      double       step = SymbolInfoDouble(symbol, SYMBOL_VOLUME_STEP);
      if(step <= 0.0) step = 0.01;
      v = MathFloor(v / step) * step;
      if(v < mn) return 0.0;
      if(v > mx) v = mx;
      return v;
   }

   double NormalizePrice(const string symbol, const double p) const
   {
      return NormalizeDouble(p, (int)SymbolInfoInteger(symbol, SYMBOL_DIGITS));
   }

   double NormalizeStop(const string symbol, double sl,
                         const double price, const bool isBuy) const
   {
      if(sl <= 0.0) return 0.0;
      const double point   = SymbolInfoDouble(symbol, SYMBOL_POINT);
      const long   stops   = SymbolInfoInteger(symbol, SYMBOL_TRADE_STOPS_LEVEL);
      const double minDist = stops * point;
      if(isBuy) { if(price - sl < minDist) sl = price - minDist; }
      else      { if(sl - price < minDist) sl = price + minDist; }
      return NormalizePrice(symbol, sl);
   }

public:
   void Init()
   {
      m_trade.SetExpertMagicNumber(InpMagicNumber);
      m_trade.SetDeviationInPoints(InpDeviationPoints);
      m_trade.LogLevel(LOG_LEVEL_ERRORS);
   }

   bool IsHedging() const
   {
      return (ENUM_ACCOUNT_MARGIN_MODE)AccountInfoInteger(ACCOUNT_MARGIN_MODE)
             == ACCOUNT_MARGIN_MODE_RETAIL_HEDGING;
   }

   ulong Open(const string symbol, const bool isBuy, double volume,
              const double sl, const double tp, const string comment)
   {
      m_trade.SetTypeFillingBySymbol(symbol);
      volume = NormalizeVolume(symbol, volume);
      if(volume <= 0.0) { Print("OrderExecutor: volume below minimum"); return 0; }

      for(int attempt = 0; attempt <= InpMaxRetries; attempt++)
      {
         const double price = isBuy ? SymbolInfoDouble(symbol, SYMBOL_ASK)
                                    : SymbolInfoDouble(symbol, SYMBOL_BID);
         const double slN   = NormalizeStop(symbol, sl, price, isBuy);
         const double tpN   = (tp > 0.0) ? NormalizePrice(symbol, tp) : 0.0;

         const bool ok = isBuy ? m_trade.Buy(volume, symbol, price, slN, tpN, comment)
                               : m_trade.Sell(volume, symbol, price, slN, tpN, comment);
         const uint rc = m_trade.ResultRetcode();

         if(ok && (rc == TRADE_RETCODE_DONE || rc == TRADE_RETCODE_DONE_PARTIAL ||
                   rc == TRADE_RETCODE_PLACED))
            return m_trade.ResultOrder();

         if(rc == TRADE_RETCODE_REQUOTE || rc == TRADE_RETCODE_PRICE_CHANGED ||
            rc == TRADE_RETCODE_PRICE_OFF)
         { Sleep(100); continue; }

         Print("OrderExecutor: OPEN_FAIL retcode=", rc);
         return 0;
      }
      Print("OrderExecutor: retries exhausted");
      return 0;
   }

   bool ModifyStop(const ulong ticket, const double newSL)
   {
      if(!PositionSelectByTicket(ticket)) return false;
      const string symbol = PositionGetString(POSITION_SYMBOL);
      const bool   isBuy  = (PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY);
      const double price  = isBuy ? SymbolInfoDouble(symbol, SYMBOL_BID)
                                  : SymbolInfoDouble(symbol, SYMBOL_ASK);
      const double slN    = NormalizeStop(symbol, newSL, price, isBuy);
      const double tp     = PositionGetDouble(POSITION_TP);
      return m_trade.PositionModify(ticket, slN, tp);
   }

   bool ClosePartial(const ulong ticket, double volume)
   {
      if(!PositionSelectByTicket(ticket)) return false;
      const string symbol  = PositionGetString(POSITION_SYMBOL);
      volume = NormalizeVolume(symbol, volume);
      if(volume <= 0.0) return false;
      const double current = PositionGetDouble(POSITION_VOLUME);
      if(volume >= current) return m_trade.PositionClose(ticket);
      return m_trade.PositionClosePartial(ticket, volume);
   }

   bool CloseAll(const string symbol)
   {
      bool allClosed = true;
      for(int i = PositionsTotal() - 1; i >= 0; i--)
      {
         const ulong t = PositionGetTicket(i);
         if(t == 0) continue;
         if(PositionGetInteger(POSITION_MAGIC) != InpMagicNumber) continue;
         if(PositionGetString(POSITION_SYMBOL) != symbol) continue;
         if(!m_trade.PositionClose(t)) allClosed = false;
      }
      return allClosed;
   }
};

#endif // ICHIMOKUEA_ORDEREXECUTOR_MQH
