//+------------------------------------------------------------------+
//| Logger.mqh                                                        |
//| IchimokuEA — CSV trade event logger                              |
//|                                                                   |
//| File naming: IchimokuEA_SYMBOL_YYYYMMDD.csv (one file per day)   |
//| Write strategy: open → write → close on every entry              |
//| This eliminates file lock — file is only held open milliseconds  |
//| per write, allowing Excel/Notepad to read at any time.           |
//+------------------------------------------------------------------+
#ifndef ICHIMOKUEA_LOGGER_MQH
#define ICHIMOKUEA_LOGGER_MQH

#include <IchimokuEA/Config/Inputs.mqh>

class CLogger
{
private:
   bool   m_enabled;
   string m_symbol;
   bool   m_headerWritten;

   //-------------------------------------------------------------------
   // Build date-based filename — one file per calendar day
   //-------------------------------------------------------------------
   string BuildFileName() const
   {
      MqlDateTime dt;
      TimeToStruct(TimeCurrent(), dt);
      return StringFormat("%s_%s_%04d%02d%02d.csv",
                          InpCSVPrefix, m_symbol,
                          dt.year, dt.mon, dt.day);
   }

   //-------------------------------------------------------------------
   // Check if file already exists (has content) — if not, write header
   //-------------------------------------------------------------------
   bool FileExists(const string fname) const
   {
      int h = FileOpen(fname, FILE_READ | FILE_CSV | FILE_ANSI | FILE_SHARE_READ | FILE_SHARE_WRITE);
      if(h == INVALID_HANDLE) return false;
      const bool hasContent = (FileSize(h) > 0);
      FileClose(h);
      return hasContent;
   }

   //-------------------------------------------------------------------
   // Write a single row — open, write, close immediately
   //-------------------------------------------------------------------
   void WriteRow(const string row) const
   {
      if(!m_enabled) return;
      const string fname = BuildFileName();

      // Write header if file is new for today
      if(!FileExists(fname))
      {
         int h = FileOpen(fname, FILE_WRITE | FILE_CSV | FILE_ANSI | FILE_SHARE_READ | FILE_SHARE_WRITE);
         if(h == INVALID_HANDLE) { Print("Logger: cannot create ", fname); return; }
         FileWrite(h, "DateTime,Event,Symbol,Ticket,Direction,Volume,Price,SL,TP,PnL,Score,Reason");
         FileClose(h);
      }

      // Append the row — open, seek to end, write, close
      int h = FileOpen(fname, FILE_WRITE | FILE_READ | FILE_CSV | FILE_ANSI | FILE_SHARE_READ | FILE_SHARE_WRITE);
      if(h == INVALID_HANDLE) { Print("Logger: cannot open for append ", fname); return; }
      FileSeek(h, 0, SEEK_END);
      FileWrite(h, row);
      FileClose(h);
   }

public:
   CLogger() : m_enabled(false), m_headerWritten(false) {}

   void Init(const string symbol, const bool enabled)
   {
      m_enabled = enabled;
      m_symbol  = symbol;
      if(!m_enabled) return;
      Print("IchimokuEA: logging to ", BuildFileName(), " (open-write-close per entry)");
   }

   void Deinit() { /* nothing to close — file not kept open */ }

   void Log(const string event, const string symbol, const ulong ticket,
            const string direction, const double volume, const double price,
            const double sl, const double tp, const double pnl,
            const int score, const string reason)
   {
      if(!m_enabled) return;
      const string row = StringFormat(
         "%s,%s,%s,%d,%s,%.2f,%.5f,%.5f,%.5f,%.2f,%d,\"%s\"",
         TimeToString(TimeCurrent(), TIME_DATE|TIME_SECONDS),
         event, symbol, (long)ticket, direction,
         volume, price, sl, tp, pnl, score, reason);
      WriteRow(row);
   }

   void Note(const string event, const string symbol, const string reason)
   {
      Log(event, symbol, 0, "", 0.0, 0.0, 0.0, 0.0, 0.0, 0, reason);
   }
};

#endif // ICHIMOKUEA_LOGGER_MQH