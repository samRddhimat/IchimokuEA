//+------------------------------------------------------------------+
//| Logger.mqh                                                        |
//| IchimokuEA — lightweight CSV trade event logger                  |
//+------------------------------------------------------------------+
#ifndef ICHIMOKUEA_LOGGER_MQH
#define ICHIMOKUEA_LOGGER_MQH

#include <IchimokuEA/Config/Inputs.mqh>

class CLogger
{
private:
   int    m_handle;
   bool   m_enabled;

   string BuildFileName(const string symbol)
   {
      MqlDateTime dt;
      TimeToStruct(TimeCurrent(), dt);
      return StringFormat("%s_%s_%04d%02d%02d_%02d%02d%02d.csv",
                          InpCSVPrefix, symbol,
                          dt.year, dt.mon, dt.day,
                          dt.hour, dt.min, dt.sec);
   }

public:
   CLogger() : m_handle(INVALID_HANDLE), m_enabled(false) {}

   void Init(const string symbol, const bool enabled)
   {
      m_enabled = enabled;
      if(!m_enabled) return;
      const string fname = BuildFileName(symbol);
      m_handle = FileOpen(fname, FILE_WRITE | FILE_CSV | FILE_ANSI);
      if(m_handle == INVALID_HANDLE)
      { Print("Logger: failed to open ", fname); return; }
      FileWrite(m_handle,
         "DateTime,Event,Symbol,Ticket,Direction,Volume,Price,SL,TP,PnL,Score,Reason");
      FileFlush(m_handle);
      Print("IchimokuEA: log -> ", fname);
   }

   void Deinit()
   {
      if(m_handle != INVALID_HANDLE) { FileClose(m_handle); m_handle = INVALID_HANDLE; }
   }

   void Log(const string event, const string symbol, const ulong ticket,
            const string direction, const double volume, const double price,
            const double sl, const double tp, const double pnl,
            const int score, const string reason)
   {
      if(!m_enabled || m_handle == INVALID_HANDLE) return;
      FileWrite(m_handle, StringFormat(
         "%s,%s,%s,%d,%s,%.2f,%.5f,%.5f,%.5f,%.2f,%d,\"%s\"",
         TimeToString(TimeCurrent(), TIME_DATE|TIME_SECONDS),
         event, symbol, (long)ticket, direction,
         volume, price, sl, tp, pnl, score, reason));
      FileFlush(m_handle);
   }

   void Note(const string event, const string symbol, const string reason)
   {
      Log(event, symbol, 0, "", 0.0, 0.0, 0.0, 0.0, 0.0, 0, reason);
   }
};

#endif // ICHIMOKUEA_LOGGER_MQH
