//+------------------------------------------------------------------+
//| DynamicSizing.mqh                                                 |
//| IchimokuEA — anti-martingale dynamic position sizing             |
//|                                                                   |
//| Wraps CPositionSizing with a trade-result-based multiplier:      |
//|   - Each consecutive win increases risk by InpSizeStepR           |
//|   - After InpResetAfterNLosses consecutive losses → reset to base |
//|   - Hard cap at 2× InpRiskPercent                                |
//|                                                                   |
//| Example (InpSizeStepR=0.25, InpResetAfterNLosses=2, base=1%):   |
//|   Win1→1.25% Win2→1.50% Win3→1.75% Win4→2.00%(cap)             |
//|   Loss1→2.00%(still) Loss2→reset to 1.00%                        |
//|                                                                   |
//| OnTradeClosed() must be called from TradeTransactionHandler       |
//| each time a position closes, to update the streak counters.       |
//+------------------------------------------------------------------+
#ifndef ICHIMOKUEA_DYNAMICSIZING_MQH
#define ICHIMOKUEA_DYNAMICSIZING_MQH

#include <IchimokuEA/Config/Inputs.mqh>
#include <IchimokuEA/Risk/PositionSizing.mqh>

class CDynamicSizing
{
private:
   CPositionSizing m_sizing;
   string          m_symbol;

   int    m_consecutiveWins;
   int    m_consecutiveLosses;
   double m_currentMultiplier;  // current risk multiplier (1.0 = base)

   //-------------------------------------------------------------------
   // Recompute multiplier from current win streak
   //-------------------------------------------------------------------
   void UpdateMultiplier()
   {
      // Each win adds InpSizeStepR to the multiplier
      // e.g. 2 wins = 1.0 + 2*0.25 = 1.50
      m_currentMultiplier = 1.0 + (m_consecutiveWins * InpSizeStepR);

      // Hard cap at 2x base
      if(m_currentMultiplier > 2.0)
         m_currentMultiplier = 2.0;
   }

public:
   CDynamicSizing()
      : m_consecutiveWins(0),
        m_consecutiveLosses(0),
        m_currentMultiplier(1.0) {}

   void Init(const string symbol)
   {
      m_symbol = symbol;
      m_sizing.Init(symbol);
      m_consecutiveWins   = 0;
      m_consecutiveLosses = 0;
      m_currentMultiplier = 1.0;
   }

   //-------------------------------------------------------------------
   // OnTradeClosed — call from TradeTransactionHandler on each close
   // profit > 0 = win, profit <= 0 = loss
   //-------------------------------------------------------------------
   void OnTradeClosed(const double profit)
   {
      if(!InpDynamicSizing) return; // feature disabled

      if(profit > 0.0)
      {
         // Win — increment win streak, reset loss streak
         m_consecutiveWins++;
         m_consecutiveLosses = 0;
         UpdateMultiplier();
         Print(StringFormat("DynamicSizing: WIN streak=%d multiplier=%.2fx nextRisk=%.2f%%",
                             m_consecutiveWins, m_currentMultiplier,
                             InpRiskPercent * m_currentMultiplier));
      }
      else
      {
         // Loss — increment loss streak, reset win streak
         m_consecutiveWins = 0;
         m_consecutiveLosses++;

         if(m_consecutiveLosses >= InpResetAfterNLosses)
         {
            // Reset to base
            m_consecutiveLosses = 0;
            m_currentMultiplier = 1.0;
            Print(StringFormat("DynamicSizing: RESET after %d losses → back to base %.2f%%",
                                InpResetAfterNLosses, InpRiskPercent));
         }
         else
         {
            Print(StringFormat("DynamicSizing: LOSS %d/%d before reset, multiplier=%.2fx",
                                m_consecutiveLosses, InpResetAfterNLosses,
                                m_currentMultiplier));
         }
      }
   }

   //-------------------------------------------------------------------
   // CalculateLot — applies current multiplier to base risk%
   //-------------------------------------------------------------------
   double CalculateLot(const double equity,
                        const double entryPrice,
                        const double stopPrice,
                        string &reason) const
   {
      if(!InpDynamicSizing)
      {
         // Feature disabled — use base sizing directly
         return m_sizing.CalculateLot(equity, entryPrice, stopPrice, reason);
      }

      // Temporarily scale equity by multiplier to achieve higher risk%
      // effectiveRisk = InpRiskPercent * m_currentMultiplier
      // Since CPositionSizing uses InpRiskPercent internally, we scale
      // the equity input to achieve the desired effective risk
      const double scaledEquity = equity * m_currentMultiplier;
      const double lot = m_sizing.CalculateLot(scaledEquity, entryPrice, stopPrice, reason);

      reason = StringFormat("%s [dynamic: %.2fx streak=%dW/%dL]",
                             reason, m_currentMultiplier,
                             m_consecutiveWins, m_consecutiveLosses);
      return lot;
   }

   // Introspection
   double CurrentMultiplier()   const { return m_currentMultiplier; }
   int    ConsecutiveWins()     const { return m_consecutiveWins; }
   int    ConsecutiveLosses()   const { return m_consecutiveLosses; }
   double EffectiveRiskPct()    const { return InpRiskPercent * m_currentMultiplier; }

   string StatusString() const
   {
      return StringFormat("DynSize: %.2fx risk=%.2f%% wins=%d losses=%d",
                           m_currentMultiplier, EffectiveRiskPct(),
                           m_consecutiveWins, m_consecutiveLosses);
   }
};

#endif // ICHIMOKUEA_DYNAMICSIZING_MQH
