//+------------------------------------------------------------------+
//|                                                    IchimokuEA.mq5 |
//| Ichimoku Kinko Hyo Expert Advisor                                 |
//|                                                                   |
//| Two modes via InpEAMode:                                          |
//|   0 = Trend/Swing: wider stops, Kijun trail, cloud exit          |
//|   1 = Scalp: tighter time exit, faster TP, same Ichimoku signal  |
//|                                                                   |
//| Signal: M15 TK cross + Chikou free + price vs cloud              |
//| Stop:   max(cloud boundary, Kijun, ATR) ± buffer                 |
//| Management sequence:                                              |
//|   Cloud emergency exit → Time exit → Breakeven → Partial TP      |
//|   → Kijun trail                                                   |
//| Sizing: risk% per trade (default 1%) or fixed lot                |
//+------------------------------------------------------------------+
#property copyright "IchimokuEA"
#property version   "1.00"
#property strict

#include <IchimokuEA/Config/Inputs.mqh>
#include <IchimokuEA/Signal/IchimokuSignal.mqh>
#include <IchimokuEA/Risk/StopCalculator.mqh>
#include <IchimokuEA/Risk/PositionSizing.mqh>
#include <IchimokuEA/Risk/DynamicSizing.mqh>
#include <IchimokuEA/TradeManagement/TradeTypes.mqh>
#include <IchimokuEA/TradeManagement/TradeManager.mqh>
#include <IchimokuEA/TradeManagement/PositionRegistry.mqh>
#include <IchimokuEA/Execution/OrderExecutor.mqh>
#include <IchimokuEA/Logging/Logger.mqh>

//--- subsystems
CIchimokuSignal  g_signal;
CStopCalculator  g_stopCalc;
CDynamicSizing   g_dynSizing;  // replaces g_sizing — wraps CPositionSizing with anti-martingale
CTradeManager    g_mgr;
CPositionRegistry g_registry;
COrderExecutor   g_exec;
CLogger          g_log;

string g_symbol      = "";
string g_lastSignal  = "none";

//+------------------------------------------------------------------+
string BuildLogFileName()
{
   MqlDateTime dt;
   TimeToStruct(TimeCurrent(), dt);
   string per = StringSubstr(EnumToString(InpTimeframe), 7);
   return StringFormat("%s_%s_%s_%04d%02d%02d_%02d%02d%02d.csv",
                       InpCSVPrefix, _Symbol, per,
                       dt.year, dt.mon, dt.day, dt.hour, dt.min, dt.sec);
}

//+------------------------------------------------------------------+
int CountOurPositions()
{
   int n = 0;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      const ulong t = PositionGetTicket(i);
      if(t == 0) continue;
      if(PositionGetInteger(POSITION_MAGIC) != InpMagicNumber) continue;
      if(PositionGetString(POSITION_SYMBOL) != g_symbol) continue;
      n++;
   }
   return n;
}

//+------------------------------------------------------------------+
int BarsSinceEntry(const ulong ticket)
{
   if(!PositionSelectByTicket(ticket)) return 0;
   const datetime entryTime = (datetime)PositionGetInteger(POSITION_TIME);
   const datetime curBarTime = iTime(g_symbol, InpTimeframe, 0);
   // Approximate bar count from time difference
   const int periodSecs = PeriodSeconds(InpTimeframe);
   if(periodSecs <= 0) return 0;
   return (int)((curBarTime - entryTime) / periodSecs);
}

//+------------------------------------------------------------------+
void ManageOpenPositions()
{
   g_registry.PruneClosed();

   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      const ulong t = PositionGetTicket(i);
      if(t == 0) continue;
      if(PositionGetInteger(POSITION_MAGIC) != InpMagicNumber) continue;
      if(PositionGetString(POSITION_SYMBOL) != g_symbol) continue;

      // Build or backfill registry record
      IchiPositionRecord rec;
      if(!g_registry.Get(t, rec))
      {
         const double entry = PositionGetDouble(POSITION_PRICE_OPEN);
         const double sl    = PositionGetDouble(POSITION_SL);
         const double risk  = MathAbs(entry - sl);
         if(risk <= 0.0) continue;
         g_registry.Register(t, risk, PositionGetDouble(POSITION_VOLUME), entry);
         g_registry.Get(t, rec);
      }

      // Build context
      IchiTradeContext c;
      c.ticket        = t;
      c.symbol        = g_symbol;
      const int ptype = (int)PositionGetInteger(POSITION_TYPE);
      c.type          = (ptype == POSITION_TYPE_BUY) ? +1 : -1;
      c.entry         = PositionGetDouble(POSITION_PRICE_OPEN);
      c.initialRisk   = rec.initialRisk;
      c.currentPrice  = (c.type > 0) ? SymbolInfoDouble(g_symbol, SYMBOL_BID)
                                     : SymbolInfoDouble(g_symbol, SYMBOL_ASK);
      c.currentSL     = PositionGetDouble(POSITION_SL);
      c.currentTP     = PositionGetDouble(POSITION_TP);
      c.initialVolume = rec.initialVolume;
      c.volume        = PositionGetDouble(POSITION_VOLUME);
      c.beDone        = rec.beDone;
      c.partialDone   = rec.partialDone;
      c.barsOpen      = BarsSinceEntry(t);

      // Evaluate
      const IchiTradeAction a = g_mgr.Evaluate(c);

      if(a.closeAll)
      {
         if(g_exec.ClosePartial(t, c.volume))
            g_log.Note("CLOSE", g_symbol,
                       StringFormat("ticket=%d %s", (long)t, a.reason));
      }
      else if(a.closePartial)
      {
         if(g_exec.ClosePartial(t, a.closeVolume))
         {
            g_registry.SetPartialDone(t);
            g_log.Note("PARTIAL", g_symbol,
                       StringFormat("ticket=%d vol=%.2f %s", (long)t, a.closeVolume, a.reason));
         }
      }
      else if(a.modifySL)
      {
         if(g_exec.ModifyStop(t, a.newSL))
         {
            if(!rec.beDone) g_registry.SetBeDone(t);
            g_log.Note("SL_MODIFY", g_symbol,
                       StringFormat("ticket=%d newSL=%.5f %s", (long)t, a.newSL, a.reason));
         }
      }
   }
}

//+------------------------------------------------------------------+
void TryNewEntry()
{
   // Allow up to InpMaxPositions simultaneous positions
   if(CountOurPositions() >= InpMaxPositions) return;

   // Evaluate signal (new-bar gated inside CIchimokuSignal)
   IchimokuSignalResult sig = g_signal.Evaluate();
   if(sig.signal == ICHI_NONE) return;

   const bool isBuy = (sig.signal == ICHI_BUY);

   // Compute stop price
   const double entryPx = isBuy ? SymbolInfoDouble(g_symbol, SYMBOL_ASK)
                                 : SymbolInfoDouble(g_symbol, SYMBOL_BID);

   const double stopPx = g_stopCalc.ComputeStopPrice(
                            entryPx, isBuy, sig.cloudTop, sig.cloudBot, sig.kijun);

   if(stopPx <= 0.0)
   {
      g_log.Note("ENTRY_SKIP", g_symbol, "stop computation failed");
      return;
   }

   // Check stop acceptability
   if(!g_stopCalc.IsStopAcceptable(entryPx, stopPx))
   {
      g_log.Note("ENTRY_SKIP", g_symbol,
                 StringFormat("stop too wide: entry=%.5f stop=%.5f (>%.1fx ATR)",
                               entryPx, stopPx, InpMaxStopRMult));
      return;
   }

   // Size the position
   const double equity = AccountInfoDouble(ACCOUNT_EQUITY);
   string sizeReason   = "";
   const double lot    = g_dynSizing.CalculateLot(equity, entryPx, stopPx, sizeReason);
   if(lot <= 0.0)
   {
      g_log.Note("ENTRY_SKIP", g_symbol, "sizing: " + sizeReason);
      return;
   }

   // Build comment
   const string modeTag = (InpEAMode == 0) ? "TREND" : "SCALP";
   const string comment = InpTradeComment + "|" + modeTag +
                          "|sc=" + IntegerToString(sig.score);

   // Execute
   const double initialRisk = MathAbs(entryPx - stopPx);
   const ulong  ticket      = g_exec.Open(g_symbol, isBuy, lot, stopPx, 0.0, comment);

   if(ticket > 0)
   {
      g_registry.Register(ticket, initialRisk, lot, entryPx);
      g_lastSignal = StringFormat("%s score=%d lot=%.2f stop=%.5f",
                                   isBuy ? "BUY" : "SELL", sig.score, lot, stopPx);
      g_log.Log("ENTRY", g_symbol, ticket,
                isBuy ? "BUY" : "SELL", lot, entryPx, stopPx, 0.0, 0.0,
                sig.score, sig.reason + " | " + sizeReason);
   }
}

//+------------------------------------------------------------------+
int OnInit()
{
   g_symbol = _Symbol;

   if(!g_signal.Init(g_symbol, InpTenkan, InpKijun, InpSenkouB,
                     InpDisplacement, InpNearPct))
      return INIT_FAILED;

   if(!g_stopCalc.Init(g_symbol))
      return INIT_FAILED;

   g_dynSizing.Init(g_symbol);
   g_mgr.Init(GetPointer(g_signal));
   g_exec.Init();
   g_log.Init(g_symbol, InpLogToCSV);

   if(!g_exec.IsHedging())
   {
      Print("WARNING: IchimokuEA requires a hedging account");
      Alert("IchimokuEA: non-hedging account detected");
   }

   // Attach Ichimoku indicator to chart for visual reference
   ChartIndicatorAdd(0, 0, g_signal.GetHandle());

   Print(StringFormat("IchimokuEA started: mode=%s symbol=%s TF=%s",
                       InpEAMode == 0 ? "TREND" : "SCALP",
                       g_symbol,
                       EnumToString(InpTimeframe)));
   g_log.Note("INIT", g_symbol,
              StringFormat("mode=%d magic=%d", InpEAMode, InpMagicNumber));
   return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   g_signal.Deinit();
   g_stopCalc.Deinit();
   g_log.Note("DEINIT", g_symbol, "EA stopped reason=" + IntegerToString(reason));
   g_log.Deinit();
}

//+------------------------------------------------------------------+
void OnTick()
{
   // Need enough history
   if(Bars(g_symbol, InpTimeframe) < 100) return;

   // Manage existing positions every tick
   ManageOpenPositions();

   // Try new entry (signal is bar-gated internally)
   TryNewEntry();

   // Diagnostic heartbeat once per bar
   if(InpDiagnosticLog)
   {
      static datetime lastBar = 0;
      const datetime curBar   = iTime(g_symbol, InpTimeframe, 0);
      if(curBar != lastBar)
      {
         lastBar = curBar;
         g_log.Note("DIAG", g_symbol,
                    StringFormat("positions=%d lastSignal=%s %s",
                                  CountOurPositions(), g_lastSignal,
                                  g_dynSizing.StatusString()));
      }
   }
}

//+------------------------------------------------------------------+
//| Feed closed trade results to DynamicSizing anti-martingale       |
//+------------------------------------------------------------------+
void OnTradeTransaction(const MqlTradeTransaction &trans,
                        const MqlTradeRequest &request,
                        const MqlTradeResult &result)
{
   if(trans.type != TRADE_TRANSACTION_DEAL_ADD) return;
   const ulong deal = trans.deal;
   if(deal == 0) return;
   if(!HistoryDealSelect(deal)) return;
   if(HistoryDealGetInteger(deal, DEAL_MAGIC) != InpMagicNumber) return;
   if(HistoryDealGetInteger(deal, DEAL_ENTRY) != DEAL_ENTRY_OUT &&
      HistoryDealGetInteger(deal, DEAL_ENTRY) != DEAL_ENTRY_OUT_BY) return;

   const double profit = HistoryDealGetDouble(deal, DEAL_PROFIT);
   g_dynSizing.OnTradeClosed(profit);
   g_log.Note("TRADE_CLOSED", g_symbol,
              StringFormat("deal=%d profit=%.2f %s",
                            (long)deal, profit, g_dynSizing.StatusString()));
}
//+------------------------------------------------------------------+