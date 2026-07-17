//+------------------------------------------------------------------+
//| SymbolInspect.mq5                                                 |
//| Prints contract size, tick value, tick size, point, volume info  |
//| for the current chart symbol — run on XAUUSD_i chart             |
//+------------------------------------------------------------------+
#property script_show_inputs

input string InpSymbol = "XAUUSD_i"; // Symbol to inspect

void OnStart()
{
   const string sym = InpSymbol;

   Print("========================================");
   Print("Symbol Inspection: ", sym);
   Print("========================================");

   // Basic contract info
   PrintFormat("Contract size:    %.5f", SymbolInfoDouble(sym, SYMBOL_TRADE_CONTRACT_SIZE));
   PrintFormat("Tick size:        %.5f", SymbolInfoDouble(sym, SYMBOL_TRADE_TICK_SIZE));
   PrintFormat("Tick value:       %.5f", SymbolInfoDouble(sym, SYMBOL_TRADE_TICK_VALUE));
   PrintFormat("Point:            %.5f", SymbolInfoDouble(sym, SYMBOL_POINT));
   PrintFormat("Digits:           %d",   (int)SymbolInfoInteger(sym, SYMBOL_DIGITS));

   // Volume info
   PrintFormat("Volume min:       %.5f", SymbolInfoDouble(sym, SYMBOL_VOLUME_MIN));
   PrintFormat("Volume max:       %.5f", SymbolInfoDouble(sym, SYMBOL_VOLUME_MAX));
   PrintFormat("Volume step:      %.5f", SymbolInfoDouble(sym, SYMBOL_VOLUME_STEP));

   // Spread and stops
   PrintFormat("Spread (points):  %d",   (int)SymbolInfoInteger(sym, SYMBOL_SPREAD));
   PrintFormat("Stops level:      %d",   (int)SymbolInfoInteger(sym, SYMBOL_TRADE_STOPS_LEVEL));

   // Current prices
   PrintFormat("Bid:              %.5f", SymbolInfoDouble(sym, SYMBOL_BID));
   PrintFormat("Ask:              %.5f", SymbolInfoDouble(sym, SYMBOL_ASK));

   // Dollar per point calculation
   const double tickVal  = SymbolInfoDouble(sym, SYMBOL_TRADE_TICK_VALUE);
   const double tickSize = SymbolInfoDouble(sym, SYMBOL_TRADE_TICK_SIZE);
   const double dpp      = (tickSize > 0) ? tickVal / tickSize : 0;
   PrintFormat("Dollar per point: %.5f (per 1 lot)", dpp);

   // Risk calculation example
   const double equity    = AccountInfoDouble(ACCOUNT_EQUITY);
   const double riskMoney = equity * 0.01; // 1% risk
   const double stopDist  = 10.0;          // 10 point example stop
   const double rawLot    = (dpp > 0 && stopDist > 0) ? riskMoney / (stopDist * dpp) : 0;
   PrintFormat("Example: 1%% of %.2f equity = %.2f risk money", equity, riskMoney);
   PrintFormat("Example: 10pt stop → raw lot = %.4f", rawLot);

   // Verify against the actual trade that fired
   const double actualEntry = 4031.43;
   const double actualStop  = 4023.47;
   const double actualLot   = 1.28;
   const double actualDist  = MathAbs(actualEntry - actualStop);
   const double impliedRisk = actualDist * dpp * actualLot;
   Print("========================================");
   Print("Verification against actual trade:");
   PrintFormat("Entry=%.5f Stop=%.5f Lot=%.2f", actualEntry, actualStop, actualLot);
   PrintFormat("Stop distance:    %.5f points", actualDist);
   PrintFormat("Implied risk:     $%.2f (at %.2f lots)", impliedRisk, actualLot);
   PrintFormat("If loss was $1084.16, actual move = %.2f points",
               1084.16 / (dpp * actualLot));
   Print("========================================");
}
