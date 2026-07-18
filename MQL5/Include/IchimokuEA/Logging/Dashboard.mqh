//+------------------------------------------------------------------+
//| Dashboard.mqh                                                     |
//| IchimokuEA — floating chart dashboard with drag support          |
//|                                                                   |
//| Uses OBJ_LABEL for all text and OBJ_RECTANGLE_LABEL for bg.     |
//| Drag: hold left mouse button on header and move. All objects     |
//| reposition together via OnChartEvent MOUSE_MOVE tracking.        |
//+------------------------------------------------------------------+
#ifndef ICHIMOKUEA_DASHBOARD_MQH
#define ICHIMOKUEA_DASHBOARD_MQH

#include <IchimokuEA/Config/Inputs.mqh>

#define DB_PREFIX   "ICHI_DB_"
#define DB_W        270
#define DB_RH       17
#define DB_PX       8
#define DB_PY       4

//+------------------------------------------------------------------+
//| Shape detection result                                            |
//+------------------------------------------------------------------+
struct IchiShapeResult
{
   string primary;
   string cloud;
   string tkGap;
   string chikou;
   color  primaryColor;
};

//+------------------------------------------------------------------+
class CDashboard
{
private:
   bool   m_enabled;
   string m_symbol;
   int    m_x;
   int    m_y;
   bool   m_dragging;
   int    m_dragOffX;
   int    m_dragOffY;
   int    m_totalRows;

   string N(const string id) { return DB_PREFIX + id; }

   //-------------------------------------------------------------------
   // Create or update a rectangle label
   //-------------------------------------------------------------------
   void Rect(const string id, int x, int y, int w, int h,
             color bg, color border, bool selectable=false, int zorder=0)
   {
      const string name = N(id);
      if(ObjectFind(0, name) < 0)
         ObjectCreate(0, name, OBJ_RECTANGLE_LABEL, 0, 0, 0);
      ObjectSetInteger(0, name, OBJPROP_XDISTANCE,   x);
      ObjectSetInteger(0, name, OBJPROP_YDISTANCE,   y);
      ObjectSetInteger(0, name, OBJPROP_XSIZE,       w);
      ObjectSetInteger(0, name, OBJPROP_YSIZE,       h);
      ObjectSetInteger(0, name, OBJPROP_BGCOLOR,     bg);
      ObjectSetInteger(0, name, OBJPROP_COLOR,       border);
      ObjectSetInteger(0, name, OBJPROP_BORDER_TYPE, BORDER_FLAT);
      ObjectSetInteger(0, name, OBJPROP_BACK,        false);
      ObjectSetInteger(0, name, OBJPROP_SELECTABLE,  selectable);
      ObjectSetInteger(0, name, OBJPROP_SELECTED,    false);
      ObjectSetInteger(0, name, OBJPROP_HIDDEN,      false);
      ObjectSetInteger(0, name, OBJPROP_ZORDER,      zorder);
   }

   //-------------------------------------------------------------------
   // Create or update a text label
   //-------------------------------------------------------------------
   void Lbl(const string id, int x, int y, const string text,
            color clr, bool bold=false, int sz=8, int zorder=2)
   {
      const string name = N(id);
      if(ObjectFind(0, name) < 0)
         ObjectCreate(0, name, OBJ_LABEL, 0, 0, 0);
      ObjectSetInteger(0, name, OBJPROP_XDISTANCE, x);
      ObjectSetInteger(0, name, OBJPROP_YDISTANCE, y);
      ObjectSetString(0,  name, OBJPROP_TEXT,      text);
      ObjectSetInteger(0, name, OBJPROP_COLOR,     clr);
      ObjectSetInteger(0, name, OBJPROP_FONTSIZE,  sz);
      ObjectSetString(0,  name, OBJPROP_FONT,      bold ? "Arial Bold" : "Arial");
      ObjectSetInteger(0, name, OBJPROP_CORNER,    CORNER_LEFT_UPPER);
      ObjectSetInteger(0, name, OBJPROP_ANCHOR,    ANCHOR_LEFT_UPPER);
      ObjectSetInteger(0, name, OBJPROP_BACK,      false);
      ObjectSetInteger(0, name, OBJPROP_SELECTABLE,false);
      ObjectSetInteger(0, name, OBJPROP_HIDDEN,    false);
      ObjectSetInteger(0, name, OBJPROP_ZORDER,    zorder);
   }

   //-------------------------------------------------------------------
   // Row helpers
   //-------------------------------------------------------------------
   int RowY(int row) { return m_y + DB_PY + row * DB_RH; }

   void SectionRow(const string id, int row, const string text)
   {
      Rect(id+"_bg", m_x, RowY(row), DB_W, DB_RH,
           0x2E6098, 0x2E6098, false, 1);
      Lbl(id, m_x + DB_PX, RowY(row) + 3, text, 0xFFFFFF, true, 8, 2);
   }

   void KVRow(const string id, int row,
              const string key, const string val,
              color valClr=0x000000)
   {
      Rect(id+"_bg", m_x, RowY(row), DB_W, DB_RH,
           row%2==0 ? 0xF2F7FB : 0xE8F0F8, 0xE8F0F8, false, 1);
      Lbl(id+"_k", m_x + DB_PX,  RowY(row)+3, key+":", 0x595959, false, 8, 2);
      Lbl(id+"_v", m_x + 115,    RowY(row)+3, val,      valClr,   true,  8, 2);
   }

   //-------------------------------------------------------------------
   // Is mouse inside header zone?
   //-------------------------------------------------------------------
   bool IsInHeader(int mouseX, int mouseY)
   {
      return mouseX >= m_x && mouseX <= m_x + DB_W &&
             mouseY >= m_y && mouseY <= m_y + DB_RH + 2;
   }

   //-------------------------------------------------------------------
   // Move all dashboard objects to new position
   //-------------------------------------------------------------------
   void MoveTo(int newX, int newY)
   {
      m_x = newX;
      m_y = newY;
   }

   //-------------------------------------------------------------------
   // Delete all dashboard objects
   //-------------------------------------------------------------------
   void DeleteAll()
   {
      for(int i = ObjectsTotal(0) - 1; i >= 0; i--)
      {
         const string name = ObjectName(0, i);
         if(StringFind(name, DB_PREFIX) == 0)
            ObjectDelete(0, name);
      }
   }

   //-------------------------------------------------------------------
   // Detect Ichimoku shape
   //-------------------------------------------------------------------
   IchiShapeResult DetectShape(const int handle, const string symbol,
                                const ENUM_TIMEFRAMES tf,
                                const int displacement)
   {
      IchiShapeResult res;
      res.primary      = "—";
      res.cloud        = "—";
      res.tkGap        = "—";
      res.chikou       = "—";
      res.primaryColor = (color)0x595959;

      if(handle == INVALID_HANDLE) return res;

      double tenkan[], kijun[], senkouA[], senkouB[], chikou[];
      double chikouSA[], chikouSB[];
      ArraySetAsSeries(tenkan,   true);
      ArraySetAsSeries(kijun,    true);
      ArraySetAsSeries(senkouA,  true);
      ArraySetAsSeries(senkouB,  true);
      ArraySetAsSeries(chikou,   true);
      ArraySetAsSeries(chikouSA, true);
      ArraySetAsSeries(chikouSB, true);

      if(CopyBuffer(handle, 0, 0, 5, tenkan)  < 5) return res;
      if(CopyBuffer(handle, 1, 0, 5, kijun)   < 5) return res;
      if(CopyBuffer(handle, 2, 0, 5, senkouA) < 5) return res;
      if(CopyBuffer(handle, 3, 0, 5, senkouB) < 5) return res;
      if(CopyBuffer(handle, 4, 0, 5, chikou)  < 5) return res;
      if(CopyBuffer(handle, 2, displacement, 2, chikouSA) < 2) return res;
      if(CopyBuffer(handle, 3, displacement, 2, chikouSB) < 2) return res;

      const double bid = SymbolInfoDouble(symbol, SYMBOL_BID);
      const double ask = SymbolInfoDouble(symbol, SYMBOL_ASK);
      const double price    = (bid + ask) / 2.0;
      const double cloudTop = MathMax(senkouA[0], senkouB[0]);
      const double cloudBot = MathMin(senkouA[0], senkouB[0]);
      const double cloudW   = cloudTop - cloudBot;

      // Future cloud
      double futA[], futB[];
      ArraySetAsSeries(futA, true);
      ArraySetAsSeries(futB, true);
      bool futureTwist = false;
      if(CopyBuffer(handle, 2, -(displacement-1), 3, futA) >= 3 &&
         CopyBuffer(handle, 3, -(displacement-1), 3, futB) >= 3)
      {
         futureTwist = (futA[0] > futB[0] && futA[1] <= futB[1]) ||
                       (futA[0] < futB[0] && futA[1] >= futB[1]);
      }

      // Cloud
      if(price > cloudTop)
         res.cloud = StringFormat("ABOVE %.1f pts", cloudW);
      else if(price < cloudBot)
         res.cloud = StringFormat("BELOW %.1f pts", cloudW);
      else
         res.cloud = StringFormat("INSIDE %.1f pts", cloudW);

      // TK Gap
      double g0 = MathAbs(tenkan[0]-kijun[0]);
      double g1 = MathAbs(tenkan[1]-kijun[1]);
      double g2 = MathAbs(tenkan[2]-kijun[2]);
      if(g0 > g1 && g1 > g2)      res.tkGap = "WIDENING";
      else if(g0 < g1 && g1 < g2) res.tkGap = "NARROWING";
      else                          res.tkGap = "FLAT";

      // Chikou
      double chTop = MathMax(chikouSA[0], chikouSB[0]);
      double chBot = MathMin(chikouSA[0], chikouSB[0]);
      double priceAtChi = iClose(symbol, tf, displacement);
      if(chikou[0] > chTop && chikou[0] > priceAtChi)
         res.chikou = "FREE ABOVE";
      else if(chikou[0] < chBot && chikou[0] < priceAtChi)
         res.chikou = "FREE BELOW";
      else if(chikou[0] > chTop || chikou[0] < chBot)
         res.chikou = "FREE (near price)";
      else
         res.chikou = "TANGLED";

      // Primary shape
      if(price >= cloudBot && price <= cloudTop)
      { res.primary = "CONSOLIDATION"; res.primaryColor = (color)0x595959; return res; }

      if(futureTwist)
      { res.primary = price > cloudTop ? "CLOUD TWIST ▲" : "CLOUD TWIST ▼";
        res.primaryColor = price > cloudTop ? (color)0x375623 : (color)0x9C0006; return res; }

      // Recent TK cross (last 3 bars)
      for(int i = 1; i <= 3 && i+1 < 5; i++)
      {
         if(tenkan[i] > kijun[i] && tenkan[i+1] <= kijun[i+1] && price > cloudTop)
         { res.primary = "TK CROSS BULL"; res.primaryColor = (color)0x375623; return res; }
         if(tenkan[i] < kijun[i] && tenkan[i+1] >= kijun[i+1] && price < cloudBot)
         { res.primary = "TK CROSS BEAR"; res.primaryColor = (color)0x9C0006; return res; }
      }

      // Recent Kumo breakout (last 3 bars)
      for(int i = 1; i <= 3 && i+1 < 5; i++)
      {
         double pTop = MathMax(senkouA[i+1], senkouB[i+1]);
         double pBot = MathMin(senkouA[i+1], senkouB[i+1]);
         double cl   = iClose(symbol, tf, i);
         double clp  = iClose(symbol, tf, i+1);
         if(cl > pTop && clp <= pTop)
         { res.primary = "KUMO BREAK ▲"; res.primaryColor = (color)0x375623; return res; }
         if(cl < pBot && clp >= pBot)
         { res.primary = "KUMO BREAK ▼"; res.primaryColor = (color)0x9C0006; return res; }
      }

      // Flat Kijun compression
      double pt = SymbolInfoDouble(symbol, SYMBOL_POINT);
      if(MathAbs(kijun[0]-kijun[1]) < pt*3 &&
         MathAbs(kijun[1]-kijun[2]) < pt*3 &&
         MathAbs(kijun[2]-kijun[3]) < pt*3)
      { res.primary = "FLAT KIJUN"; res.primaryColor = (color)0x595959; return res; }

      // Kijun pullback
      if(price > cloudTop && tenkan[0] > kijun[0])
      {
         if(MathAbs(price - kijun[0]) / price < 0.005)
         { res.primary = "KIJUN PULLBK ▲"; res.primaryColor = (color)0x375623; return res; }
         res.primary = "UPTREND"; res.primaryColor = (color)0x375623; return res;
      }
      if(price < cloudBot && tenkan[0] < kijun[0])
      {
         if(MathAbs(price - kijun[0]) / price < 0.005)
         { res.primary = "KIJUN PULLBK ▼"; res.primaryColor = (color)0x9C0006; return res; }
         res.primary = "DOWNTREND"; res.primaryColor = (color)0x9C0006; return res;
      }

      res.primary = "MIXED"; res.primaryColor = (color)0x595959;
      return res;
   }

public:
   CDashboard() : m_enabled(false), m_x(10), m_y(28),
                  m_dragging(false), m_dragOffX(0), m_dragOffY(0),
                  m_totalRows(0) {}

   void Init(const string symbol, const bool enabled)
   {
      m_enabled = enabled;
      m_symbol  = symbol;
      if(!m_enabled) return;
      // Restore previous position if objects exist
      const string bgName = N("HDR_BG");
      if(ObjectFind(0, bgName) >= 0)
      {
         m_x = (int)ObjectGetInteger(0, bgName, OBJPROP_XDISTANCE);
         m_y = (int)ObjectGetInteger(0, bgName, OBJPROP_YDISTANCE);
      }
   }

   void Deinit() { DeleteAll(); ChartRedraw(0); }

   //-------------------------------------------------------------------
   // OnEvent — tracks mouse drag manually
   //-------------------------------------------------------------------
   void OnEvent(const int id, const long lparam,
                const double dparam, const string sparam)
   {
      if(!m_enabled) return;

      const int mouseX = (int)lparam;
      const int mouseY = (int)dparam;
      const bool leftBtn = (sparam == "1" || sparam == "3"); // left or left+shift

      if(id == CHARTEVENT_MOUSE_MOVE)
      {
         if(m_dragging && leftBtn)
         {
            // Move all objects
            DeleteAll();
            MoveTo(mouseX - m_dragOffX, mouseY - m_dragOffY);
            // Force re-render on next tick by just redrawing
            ChartRedraw(0);
         }
         else if(m_dragging && !leftBtn)
         {
            // Button released — stop dragging
            m_dragging = false;
         }
         else if(!m_dragging && leftBtn && IsInHeader(mouseX, mouseY))
         {
            // Started dragging from header
            m_dragging  = true;
            m_dragOffX  = mouseX - m_x;
            m_dragOffY  = mouseY - m_y;
         }
      }
   }

   //-------------------------------------------------------------------
   // Render dashboard
   //-------------------------------------------------------------------
   void Render(const string symbol,
               const int    ichiHandle,
               const int    displacement,
               const ENUM_TIMEFRAMES tf,
               const int    positions,
               const string lastSignal,
               const int    barsSinceCross,
               const double atr,
               const double adx,
               const double dynMult,
               const int    dynWins,
               const int    dynLosses,
               const double riskPct)
   {
      if(!m_enabled) return;
      if(MQLInfoInteger(MQL_TESTER)) return;  // skip during backtesting — zero overhead

      IchiShapeResult shape = DetectShape(ichiHandle, symbol, tf, displacement);
      const long   spread   = SymbolInfoInteger(symbol, SYMBOL_SPREAD);
      const string modeStr  = (InpEAMode == 0) ? "TREND" : "SCALP";

      int row = 0;

      // ── Outer background ──────────────────────────────────────────
      const int totalH = DB_PY + (23 * DB_RH) + DB_PY;
      Rect("OUTER", m_x-1, m_y-1, DB_W+2, totalH+2,
           0x1F4E79, 0x1F4E79, false, 0);

      // ── Header (drag zone) ────────────────────────────────────────
      Rect("HDR_BG", m_x, m_y, DB_W, DB_RH+2, 0x1F4E79, 0x1F4E79, false, 1);
      Lbl("HDR", m_x+DB_PX, m_y+3,
          "≡  IchimokuEA v1.1.0   [drag here]",
          0xC9A84C, true, 8, 2);
      row++;

      // ── Section 1: EA Info ────────────────────────────────────────
      SectionRow("S1",     row, "── EA INFO"); row++;
      KVRow("S1_SYM",  row, "Symbol",    symbol); row++;
      KVRow("S1_TF",   row, "Timeframe", EnumToString(tf)); row++;
      KVRow("S1_MODE", row, "Mode",      modeStr,
            InpEAMode==0 ? (color)0x375623 : (color)0x595959); row++;
      KVRow("S1_MGC",  row, "Magic",
            IntegerToString(InpMagicNumber)); row++;

      // ── Section 2: Signal ─────────────────────────────────────────
      SectionRow("S2",     row, "── SIGNAL STATUS"); row++;
      KVRow("S2_POS",  row, "Positions",
            StringFormat("%d / %d", positions, InpMaxPositions),
            positions > 0 ? (color)0x375623 : (color)0x595959); row++;

      string sigShort = lastSignal;
      if(StringLen(sigShort) > 26) sigShort = StringSubstr(sigShort,0,26)+"..";
      color sigClr = StringFind(lastSignal,"BUY")>=0  ? 0x375623 :
                     StringFind(lastSignal,"SELL")>=0 ? (color)0x9C0006 : (color)0x595959;
      KVRow("S2_SIG",  row, "Signal", sigShort, sigClr); row++;

      string freshStr = barsSinceCross >= 0
                        ? StringFormat("%d bar(s) ago", barsSinceCross)
                        : "no cross yet";
      color freshClr = (barsSinceCross >= 0 && barsSinceCross <= InpFreshnessBarLimit)
                       ? (color)0x375623 : (color)0x595959;
      KVRow("S2_FRE",  row, "Cross age", freshStr, freshClr); row++;

      // ── Section 3: Market ─────────────────────────────────────────
      SectionRow("S3",     row, "── MARKET METRICS"); row++;
      KVRow("S3_ATR",  row, "ATR(14)",
            atr > 0 ? StringFormat("%.2f", atr) : "—",
            atr > 5 ? (color)0x375623 : (color)0x9C0006); row++;
      KVRow("S3_ADX",  row, "ADX(14)",
            adx > 0 ? StringFormat("%.1f", adx) : "—",
            adx >= 25 ? 0x375623 : adx >= 20 ? 0x595959 : 0x9C0006); row++;
      KVRow("S3_SPR",  row, "Spread",
            StringFormat("%d pts", (int)spread),
            spread < 100 ? 0x375623 : spread < 250 ? 0x595959 : 0x9C0006); row++;

      // ── Section 4: Sizing ─────────────────────────────────────────
      SectionRow("S4",     row, "── DYNAMIC SIZING"); row++;
      KVRow("S4_MUL",  row, "Multiplier",
            StringFormat("%.2fx", dynMult),
            dynMult > 1.0 ? (color)0x375623 : (color)0x595959); row++;
      KVRow("S4_STK",  row, "Streak",
            StringFormat("W:%d  L:%d", dynWins, dynLosses),
            dynWins > 0 ? 0x375623 : dynLosses > 0 ? (color)0x9C0006 : (color)0x595959); row++;
      KVRow("S4_EFF",  row, "Eff. Risk%",
            StringFormat("%.2f%%", riskPct * dynMult),
            0x595959); row++;

      // ── Section 5: Shape ──────────────────────────────────────────
      SectionRow("S5",     row, "── ICHIMOKU SHAPE"); row++;
      KVRow("S5_SHP",  row, "Formation", shape.primary,
            shape.primaryColor); row++;
      KVRow("S5_CLD",  row, "Cloud",     shape.cloud,
            StringFind(shape.cloud,"ABOVE")>=0 ? 0x375623 :
            StringFind(shape.cloud,"BELOW")>=0 ? (color)0x9C0006 : (color)0x595959); row++;
      KVRow("S5_TKG",  row, "TK Gap",   shape.tkGap,
            shape.tkGap=="WIDENING" ? 0x375623 :
            shape.tkGap=="NARROWING"? (color)0x9C0006 : (color)0x595959); row++;
      KVRow("S5_CHI",  row, "Chikou",   shape.chikou,
            StringFind(shape.chikou,"FREE")>=0 ? 0x375623 :
            shape.chikou=="TANGLED"  ? (color)0x9C0006 : (color)0x595959); row++;

      m_totalRows = row;
      ChartRedraw(0);
   }
};

#endif // ICHIMOKUEA_DASHBOARD_MQH