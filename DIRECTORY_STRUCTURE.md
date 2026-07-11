D:\Repository\IchimokuEA\
└── MQL5\
    ├── Experts\
    │   └── IchimokuEA\
    │       └── IchimokuEA.mq5          ← main orchestrator
    └── Include\
        └── IchimokuEA\
            ├── Config\
            │   └── Inputs.mqh           ← all inputs
            ├── Signal\
            │   └── IchimokuSignal.mqh   ← entry conditions (reuse/adapt from InstitutionalEA)
            ├── Risk\
            │   ├── StopCalculator.mqh   ← cloud/kijun/ATR/combined stop distance
            │   └── PositionSizing.mqh   ← risk%/fixed lot sizing
            ├── TradeManagement\
            │   ├── BreakEven.mqh        ← move SL to BE at +1R
            │   ├── KijunTrail.mqh       ← trail SL to Kijun-sen
            │   ├── ProfitTarget.mqh     ← 1.5R-2R TP, partial close
            │   ├── TimeExit.mqh         ← candle-count time exit
            │   ├── CloudExit.mqh        ← emergency cloud re-entry exit
            │   └── TradeManager.mqh     ← orchestrates all exit logic
            ├── Execution\
            │   └── OrderExecutor.mqh    ← reuse pattern from InstitutionalEA
            └── Logging\
                └── Logger.mqh           ← reuse pattern from InstitutionalEA