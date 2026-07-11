//+------------------------------------------------------------------+
//| TradeTypes.mqh                                                    |
//| IchimokuEA — shared structs for trade management                 |
//+------------------------------------------------------------------+
#ifndef ICHIMOKUEA_TRADETYPES_MQH
#define ICHIMOKUEA_TRADETYPES_MQH

//--- position context passed to all management modules
struct IchiTradeContext
{
   ulong  ticket;
   int    type;          // +1=buy, -1=sell
   double entry;         // open price
   double currentPrice;  // current bid/ask
   double currentSL;     // current stop loss
   double currentTP;     // current take profit
   double volume;        // current volume
   double initialRisk;   // entry-to-initial-SL distance in price
   double initialVolume; // volume at entry (for partial close tracking)
   bool   beDone;        // breakeven already applied
   bool   partialDone;   // partial close already done
   int    barsOpen;      // number of bars since entry
   string symbol;
};

//--- action returned by management modules
struct IchiTradeAction
{
   bool   modifySL;
   double newSL;
   bool   closePartial;
   double closeVolume;
   bool   closeAll;
   string reason;

   void Clear()
   {
      modifySL     = false;
      newSL        = 0.0;
      closePartial = false;
      closeVolume  = 0.0;
      closeAll     = false;
      reason       = "";
   }
};

//--- position registry record
struct IchiPositionRecord
{
   ulong  ticket;
   double initialRisk;    // price distance entry→initial SL
   double initialVolume;
   double entryPrice;
   bool   beDone;
   bool   partialDone;
};

#endif // ICHIMOKUEA_TRADETYPES_MQH
