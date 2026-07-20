//+------------------------------------------------------------------+
//| ExportBacktestDeals.mq5                                           |
//| IchimokuEA — Export Strategy Tester deal history to CSV          |
//|                                                                   |
//| HOW TO USE:                                                       |
//|   1. Run your backtest in Strategy Tester                        |
//|   2. When backtest completes, go to MT5 main chart window        |
//|   3. In Navigator → Scripts → drag this script onto any chart    |
//|   4. Set date range to match your backtest period                |
//|   5. Click OK — CSV file written to MQL5\Files\                  |
//|                                                                   |
//| Output file: BacktestDeals_YYYYMMDD_HHMMSS.csv                   |
//| Location: MT5 Data Folder\MQL5\Files\                            |
//|                                                                   |
//| Columns:                                                          |
//|   Ticket, Time, Symbol, Direction, Type, Volume, Price,          |
//|   SL, TP, Profit, Swap, Commission, Balance, Comment, Magic      |
//+------------------------------------------------------------------+
#property script_show_inputs
#property description "Export Strategy Tester deal history to CSV"

input datetime InpFromDate  = D'2026.01.01 00:00'; // From date
input datetime InpToDate    = D'2026.07.09 23:59'; // To date
input long     InpMagic     = 0;                   // Magic number filter (0 = all)
input string   InpSymbol    = "";                  // Symbol filter (empty = all)
input bool     InpSkipDeposits = true;             // Skip balance/deposit entries

void OnStart()
{
   // Select history range
   if(!HistorySelect(InpFromDate, InpToDate))
   {
      Print("ExportDeals: HistorySelect failed");
      return;
   }

   const int total = HistoryDealsTotal();
   if(total == 0)
   {
      Print("ExportDeals: no deals found in selected range");
      return;
   }

   // Build filename with timestamp
   MqlDateTime dt;
   TimeToStruct(TimeCurrent(), dt);
   const string fname = StringFormat("BacktestDeals_%04d%02d%02d_%02d%02d%02d.csv",
                                      dt.year, dt.mon, dt.day,
                                      dt.hour, dt.min, dt.sec);

   const int fh = FileOpen(fname, FILE_WRITE | FILE_CSV | FILE_ANSI |
                            FILE_SHARE_READ | FILE_SHARE_WRITE);
   if(fh == INVALID_HANDLE)
   {
      Print("ExportDeals: cannot create file ", fname);
      return;
   }

   // Header row
   FileWrite(fh,
      "Ticket", "Time", "Symbol", "Direction", "Entry/Exit",
      "Volume", "Price", "SL", "TP",
      "Profit", "Swap", "Commission", "NetProfit",
      "Balance", "Comment", "Magic");

   int exported = 0;
   int skipped  = 0;
   double runningBalance = 0;

   for(int i = 0; i < total; i++)
   {
      const ulong ticket = HistoryDealGetTicket(i);
      if(ticket == 0) continue;

      const string sym     = HistoryDealGetString(ticket,  DEAL_SYMBOL);
      const long   magic   = HistoryDealGetInteger(ticket, DEAL_MAGIC);
      const long   type    = HistoryDealGetInteger(ticket, DEAL_TYPE);
      const long   entry   = HistoryDealGetInteger(ticket, DEAL_ENTRY);
      const double profit  = HistoryDealGetDouble(ticket,  DEAL_PROFIT);
      const double swap    = HistoryDealGetDouble(ticket,  DEAL_SWAP);
      const double comm    = HistoryDealGetDouble(ticket,  DEAL_COMMISSION);
      const double vol     = HistoryDealGetDouble(ticket,  DEAL_VOLUME);
      const double price   = HistoryDealGetDouble(ticket,  DEAL_PRICE);
      const double sl      = HistoryDealGetDouble(ticket,  DEAL_SL);
      const double tp      = HistoryDealGetDouble(ticket,  DEAL_TP);
      const string comment = HistoryDealGetString(ticket,  DEAL_COMMENT);
      const datetime time  = (datetime)HistoryDealGetInteger(ticket, DEAL_TIME);

      // Skip balance/deposit/withdrawal entries
      if(InpSkipDeposits && (type == DEAL_TYPE_BALANCE ||
                              type == DEAL_TYPE_CREDIT  ||
                              type == DEAL_TYPE_CHARGE  ||
                              type == DEAL_TYPE_CORRECTION))
      {
         runningBalance += profit;
         skipped++;
         continue;
      }

      // Magic filter
      if(InpMagic != 0 && magic != InpMagic) { skipped++; continue; }

      // Symbol filter
      if(InpSymbol != "" && sym != InpSymbol) { skipped++; continue; }

      // Direction string
      string direction = "";
      if(type == DEAL_TYPE_BUY)  direction = "BUY";
      else if(type == DEAL_TYPE_SELL) direction = "SELL";
      else direction = "OTHER";

      // Entry/Exit string
      string entryStr = "";
      if(entry == DEAL_ENTRY_IN)     entryStr = "IN";
      else if(entry == DEAL_ENTRY_OUT)    entryStr = "OUT";
      else if(entry == DEAL_ENTRY_INOUT)  entryStr = "INOUT";
      else if(entry == DEAL_ENTRY_OUT_BY) entryStr = "OUT_BY";

      // Net profit (profit + swap + commission)
      const double netProfit = profit + swap + comm;
      runningBalance += netProfit;

      FileWrite(fh,
         (long)ticket,
         TimeToString(time, TIME_DATE | TIME_SECONDS),
         sym,
         direction,
         entryStr,
         DoubleToString(vol, 2),
         DoubleToString(price, (int)SymbolInfoInteger(sym, SYMBOL_DIGITS)),
         DoubleToString(sl, (int)SymbolInfoInteger(sym, SYMBOL_DIGITS)),
         DoubleToString(tp, (int)SymbolInfoInteger(sym, SYMBOL_DIGITS)),
         DoubleToString(profit,    2),
         DoubleToString(swap,      2),
         DoubleToString(comm,      2),
         DoubleToString(netProfit, 2),
         DoubleToString(runningBalance, 2),
         comment,
         (long)magic);

      exported++;
   }

   FileClose(fh);

   Print(StringFormat("ExportDeals: exported %d deals, skipped %d → %s",
                       exported, skipped, fname));
   Print(StringFormat("ExportDeals: file saved to MQL5\\Files\\%s", fname));
}
