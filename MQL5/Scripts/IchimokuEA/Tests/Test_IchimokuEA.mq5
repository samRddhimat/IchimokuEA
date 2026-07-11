//+------------------------------------------------------------------+
//| Test_IchimokuEA.mq5                                               |
//| IchimokuEA — unit tests for signal engine and trade manager      |
//+------------------------------------------------------------------+
#property script_show_inputs
#include <IchimokuEA/Signal/IchimokuSignal.mqh>
#include <IchimokuEA/TradeManagement/TradeManager.mqh>

int g_pass = 0;
int g_fail = 0;

void Check(const string name, const bool condition)
{
   if(condition) { g_pass++; Print("PASS: ", name); }
   else          { g_fail++; Print("FAIL: ", name); }
}

IchimokuValues MakeValues(
   double tenkanCur, double tenkanPrev,
   double kijunCur,  double kijunPrev,
   double chikou,
   double cloudTopChikou, double cloudBotChikou,
   double price, double cloudTop, double cloudBot,
   double threshold = 0.01)
{
   IchimokuValues v;
   v.tenkanCur        = tenkanCur;
   v.tenkanPrev       = tenkanPrev;
   v.kijunCur         = kijunCur;
   v.kijunPrev        = kijunPrev;
   v.chikouCur        = chikou;
   v.cloudTopAtChikou = cloudTopChikou;
   v.cloudBotAtChikou = cloudBotChikou;
   v.currentPrice     = price;
   v.cloudTop         = cloudTop;
   v.cloudBot         = cloudBot;
   v.nearThresholdPct = threshold;
   return v;
}

IchiTradeContext MakeContext(int type, double entry, double currentPrice,
                              double currentSL, double initialRisk,
                              double volume, bool beDone, bool partialDone,
                              int barsOpen)
{
   IchiTradeContext c;
   c.ticket        = 1;
   c.type          = type;
   c.entry         = entry;
   c.currentPrice  = currentPrice;
   c.currentSL     = currentSL;
   c.currentTP     = 0.0;
   c.volume        = volume;
   c.initialRisk   = initialRisk;
   c.initialVolume = volume;
   c.beDone        = beDone;
   c.partialDone   = partialDone;
   c.barsOpen      = barsOpen;
   c.symbol        = _Symbol;
   return c;
}

void OnStart()
{
   g_pass = 0; g_fail = 0;
   CIchimokuSignal sig;
   CTradeManager   mgr;
   mgr.Init(NULL); // no live signal needed for trade management tests

   Print("=== IchimokuSignal Tests ===");

   // Case 1: BUY — bullish cross, Chikou free, price far above cloud
   {
      IchimokuValues v = MakeValues(105,99, 100,100, 3400, 3300,3280, 3380, 3310,3290);
      IchimokuSignalResult r = sig.EvaluateSignal(v);
      Check("S1: BUY signal far above cloud", r.signal == ICHI_BUY);
      Check("S1: score=90", r.score == 90);
      Check("S1: cloudTop/Bot populated", r.cloudTop == 3310 && r.cloudBot == 3290);
      Check("S1: kijun populated", r.kijun == 100);
   }

   // Case 2: BUY near cloud — score=60
   {
      IchimokuValues v = MakeValues(105,99, 100,100, 3400, 3300,3280, 3315, 3310,3290);
      IchimokuSignalResult r = sig.EvaluateSignal(v);
      Check("S2: BUY near cloud score=60", r.signal == ICHI_BUY && r.score == 60);
   }

   // Case 3: SELL — bearish cross, price far below cloud
   {
      IchimokuValues v = MakeValues(95,101, 100,100, 3100, 3200,3180, 3050, 3130,3110);
      IchimokuSignalResult r = sig.EvaluateSignal(v);
      Check("S3: SELL signal far below cloud", r.signal == ICHI_SELL);
      Check("S3: score=90", r.score == 90);
   }

   // Case 4: No TK cross
   {
      IchimokuValues v = MakeValues(102,101, 100,99, 3400, 3300,3280, 3380, 3310,3290);
      IchimokuSignalResult r = sig.EvaluateSignal(v);
      Check("S4: no signal without TK cross", r.signal == ICHI_NONE);
   }

   // Case 5: Chikou inside cloud
   {
      IchimokuValues v = MakeValues(105,99, 100,100, 3290, 3300,3280, 3380, 3310,3290);
      IchimokuSignalResult r = sig.EvaluateSignal(v);
      Check("S5: no signal Chikou inside cloud", r.signal == ICHI_NONE);
   }

   // Case 6: Price inside cloud
   {
      IchimokuValues v = MakeValues(105,99, 100,100, 3400, 3300,3280, 3320, 3330,3310);
      IchimokuSignalResult r = sig.EvaluateSignal(v);
      Check("S6: no signal price inside cloud", r.signal == ICHI_NONE);
   }

   // Case 7: Conflict — bullish cross but price below cloud
   {
      IchimokuValues v = MakeValues(105,99, 100,100, 3400, 3300,3280, 3050, 3130,3110);
      IchimokuSignalResult r = sig.EvaluateSignal(v);
      Check("S7: no signal on conflict (bull cross, price below cloud)", r.signal == ICHI_NONE);
   }

   Print("=== TradeManager Tests ===");

   // Case 8: Breakeven trigger at 1R
   {
      // BUY: entry=3300, initialRisk=100 (stop at 3200), current=3400 (+1R)
      IchiTradeContext c = MakeContext(+1, 3300, 3400, 3200, 100, 0.1, false, false, 3);
      IchiTradeAction a = mgr.Evaluate(c);
      Check("M1: BE triggered at 1R", a.modifySL && !a.closeAll);
   }

   // Case 8b: BE NOT triggered before 1R (0.5R profit)
   {
      IchiTradeContext c2 = MakeContext(+1, 3300, 3350, 3200, 100, 0.1, false, false, 3);
      IchiTradeAction a2 = mgr.Evaluate(c2);
      Check("M1b: BE not triggered at 0.5R", !a2.modifySL && !a2.closeAll);
   }

   // Case 9: Time exit triggers when stalled
   {
      // 20 bars open, only 0.2R profit — should exit
      IchiTradeContext c = MakeContext(+1, 3300, 3320, 3200, 100, 0.1, false, false, 20);
      IchiTradeAction a = mgr.Evaluate(c);
      Check("M2: time exit after 20 bars with <0.5R", a.closeAll);
   }

   // Case 10: Time exit does NOT trigger when profitable
   {
      // 20 bars open but 1.5R profit — should NOT time exit
      IchiTradeContext c = MakeContext(+1, 3300, 3450, 3200, 100, 0.1, true, false, 20);
      IchiTradeAction a = mgr.Evaluate(c);
      Check("M3: no time exit when >0.5R after 20 bars", !a.closeAll || a.modifySL);
   }

   // Case 11: Partial close at TP
   {
      // BUY: entry=3300, risk=100, current=3450 (1.5R) — should partial close
      IchiTradeContext c = MakeContext(+1, 3300, 3450, 3300, 100, 0.2, true, false, 5);
      IchiTradeAction a = mgr.Evaluate(c);
      Check("M4: partial close at 1.5R", a.closePartial);
      Check("M4: close volume = 50% of initial", MathAbs(a.closeVolume - 0.1) < 0.001);
   }

   // Case 12: SELL breakeven
   {
      // SELL: entry=3300, risk=100 (stop at 3400), current=3200 (+1R)
      IchiTradeContext c = MakeContext(-1, 3300, 3200, 3400, 100, 0.1, false, false, 3);
      IchiTradeAction a = mgr.Evaluate(c);
      Check("M5: SELL BE triggered at 1R", a.modifySL && !a.closeAll);
   }

   Print(StringFormat("=== IchimokuEA Tests: %d passed, %d failed ===", g_pass, g_fail));
}