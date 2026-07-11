//+------------------------------------------------------------------+
//| PositionRegistry.mqh                                              |
//| IchimokuEA — tracks per-position metadata (initialRisk, BE done) |
//+------------------------------------------------------------------+
#ifndef ICHIMOKUEA_POSITIONREGISTRY_MQH
#define ICHIMOKUEA_POSITIONREGISTRY_MQH

#include <IchimokuEA/TradeManagement/TradeTypes.mqh>

#define ICHI_MAX_POSITIONS 50

class CPositionRegistry
{
private:
   IchiPositionRecord m_records[ICHI_MAX_POSITIONS];
   int                m_count;

   int FindIndex(const ulong ticket) const
   {
      for(int i = 0; i < m_count; i++)
         if(m_records[i].ticket == ticket) return i;
      return -1;
   }

public:
   CPositionRegistry() : m_count(0) {}

   void Register(const ulong ticket, const double initialRisk,
                  const double initialVolume, const double entryPrice)
   {
      if(FindIndex(ticket) >= 0) return; // already registered
      if(m_count >= ICHI_MAX_POSITIONS) { Print("PositionRegistry: full"); return; }
      m_records[m_count].ticket        = ticket;
      m_records[m_count].initialRisk   = initialRisk;
      m_records[m_count].initialVolume = initialVolume;
      m_records[m_count].entryPrice    = entryPrice;
      m_records[m_count].beDone        = false;
      m_records[m_count].partialDone   = false;
      m_count++;
   }

   bool Get(const ulong ticket, IchiPositionRecord &rec) const
   {
      const int idx = FindIndex(ticket);
      if(idx < 0) return false;
      rec = m_records[idx];
      return true;
   }

   void SetBeDone(const ulong ticket)
   {
      const int idx = FindIndex(ticket);
      if(idx >= 0) m_records[idx].beDone = true;
   }

   void SetPartialDone(const ulong ticket)
   {
      const int idx = FindIndex(ticket);
      if(idx >= 0) m_records[idx].partialDone = true;
   }

   void PruneClosed()
   {
      for(int i = m_count - 1; i >= 0; i--)
      {
         if(!PositionSelectByTicket(m_records[i].ticket))
         {
            // Shift remaining records down
            for(int j = i; j < m_count - 1; j++)
               m_records[j] = m_records[j + 1];
            m_count--;
         }
      }
   }

   int Count() const { return m_count; }
};

#endif // ICHIMOKUEA_POSITIONREGISTRY_MQH
