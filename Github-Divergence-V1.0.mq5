#property copyright "Copyright 2024"
#property link      "https://github.com/masomnajafpour-oss"
#property version   "1.00"
#property strict
#property indicator_chart_window
#property indicator_buffers 2
#property indicator_plots   2

// Plot 1: RSI Red (Low-based)
#property indicator_label1  "RSI Red (Low)"
#property indicator_type1   DRAW_LINE
#property indicator_color1  clrRed
#property indicator_width1  2

// Plot 2: RSI Blue (High-based)
#property indicator_label2  "RSI Blue (High)"
#property indicator_type2   DRAW_LINE
#property indicator_color2  clrBlue
#property indicator_width2  2

// Buffers
double rsiRedBuffer[];
double rsiBluBuffer[];

// ===== INPUTS =====
input group "=== Divergence Types ===";
input bool Enable_DoubleBullish = true;              // Double Bullish Divergence (Buy)
input bool Enable_DoubleBearish = true;             // Double Bearish Divergence (Sell)
input bool Enable_BullishThenHiddenBearish = true;  // Bullish + Hidden Bearish (Sell)
input bool Enable_BearishThenHiddenBullish = true;  // Bearish + Hidden Bullish (Buy)

input group "=== Candle Patterns ===";
input bool Enable_PinBar = true;                    // Enable Pin Bar pattern
input bool Enable_Engulfing = true;                 // Enable Engulfing pattern

input group "=== RSI Settings ===";
input int RSI_Period = 14;                          // RSI Period
input int Overbought = 70;                          // Overbought Level
input int Oversold = 30;                            // Oversold Level

input group "=== Divergence Settings ===";
input int PivotStrength = 3;                        // Candles to check for Pivot 3/4
input int CycleCandles = 111;                       // Max distance between Pivot 1 and 3

input group "=== Signal Settings ===";
input int SignalLookForward = 5;                    // Candles after pattern to draw signal
input double PinBarRatio = 2.5;                     // Pin Bar wick to body ratio

input group "=== Signal Distance (Points) ===";
input int Signal_Distance_E0_E1 = 50;              // Distance between E0 and E1
input int Signal_Distance_Ei_Ei1 = 30;             // Distance between Ei and E(i+1) for i>=1

// Global variables for signal tracking
struct Signal {
    int barIndex;
    double price;
    int type; // 1=Buy, -1=Sell
    datetime time;
};

Signal lastSignal;
bool signalInitialized = false;
int lastSignalBar = -1;

// ===== MAIN FUNCTIONS =====
int OnInit() {
    SetIndexBuffer(0, rsiRedBuffer, INDICATOR_DATA);
    SetIndexBuffer(1, rsiBluBuffer, INDICATOR_DATA);
    
    PlotIndexSetDouble(0, PLOT_EMPTY_VALUE, EMPTY_VALUE);
    PlotIndexSetDouble(1, PLOT_EMPTY_VALUE, EMPTY_VALUE);
    
    IndicatorSetString(INDICATOR_SHORTNAME, "Divergence Indicator V1.0");
    
    return INIT_SUCCEEDED;
}

int OnCalculate(const int rates_total,
                const int prev_calculated,
                const datetime &time[],
                const double &open[],
                const double &high[],
                const double &low[],
                const double &close[],
                const long &tick_volume[],
                const long &volume[],
                const int &spread[]) {
    
    ArraySetAsSeries(rsiRedBuffer, true);
    ArraySetAsSeries(rsiBluBuffer, true);
    ArraySetAsSeries(time, true);
    ArraySetAsSeries(open, true);
    ArraySetAsSeries(high, true);
    ArraySetAsSeries(low, true);
    ArraySetAsSeries(close, true);
    
    // Calculate RSI values
    for (int i = prev_calculated; i < rates_total; i++) {
        rsiRedBuffer[i] = CalculateRSI(low, i, RSI_Period, rates_total);
        rsiBluBuffer[i] = CalculateRSI(high, i, RSI_Period, rates_total);
    }
    
    // Check for signals on the latest bar
    int lastBar = 0;
    
    // Check for bullish candle patterns (Pin Bar or Engulfing)
    if (Enable_PinBar || Enable_Engulfing) {
        if (IsBullishPattern(open, high, low, close, lastBar, PinBarRatio)) {
            CheckDoubleBullish(low, high, close, lastBar, rates_total, time);
            CheckBearishThenHiddenBullish(low, high, close, lastBar, rates_total, time);
        }
    }
    
    // Check for bearish candle patterns (Pin Bar or Engulfing)
    if (Enable_PinBar || Enable_Engulfing) {
        if (IsBearishPattern(open, high, low, close, lastBar, PinBarRatio)) {
            CheckDoubleBearish(low, high, close, lastBar, rates_total, time);
            CheckBullishThenHiddenBearish(low, high, close, lastBar, rates_total, time);
        }
    }
    
    return rates_total;
}

void OnDeinit(const int reason) {
}

// ===== RSI CALCULATION =====
double CalculateRSI(const double &price[], int index, int period, int rates_total) {
    if (index < period) return 50.0;
    
    double gain = 0.0, loss = 0.0;
    
    for (int i = 1; i <= period; i++) {
        int currentIdx = index - i + 1;
        int prevIdx = index - i;
        
        if (currentIdx < rates_total && prevIdx < rates_total && currentIdx >= 0 && prevIdx >= 0) {
            double diff = price[currentIdx] - price[prevIdx];
            if (diff > 0) gain += diff;
            else loss -= diff;
        }
    }
    
    double avgGain = gain / period;
    double avgLoss = loss / period;
    
    if (avgLoss == 0.0) return 100.0;
    
    double rs = avgGain / avgLoss;
    return 100.0 - (100.0 / (1.0 + rs));
}

// ===== CANDLE PATTERN DETECTION =====
bool IsBullishPattern(const double &open[], const double &high[], const double &low[],
                      const double &close[], int index, double pinBarRatio) {
    if (index + 1 >= ArraySize(open)) return false;
    
    double body = MathAbs(close[index] - open[index]);
    double range = high[index] - low[index];
    
    if (body < 0.00001) return false;
    
    double wickLow = close[index] < open[index] ? close[index] - low[index] : open[index] - low[index];
    double wickHigh = close[index] > open[index] ? high[index] - close[index] : high[index] - open[index];
    
    // Pin Bar
    if (Enable_PinBar) {
        if (wickLow > body * pinBarRatio && wickHigh < body * 0.5) {
            // Close in upper third
            if (close[index] > open[index] + body * 0.667) {
                return true;
            }
        }
    }
    
    // Engulfing
    if (Enable_Engulfing) {
        if (index + 1 < ArraySize(open)) {
            if (close[index] > high[index + 1] && open[index] < low[index + 1]) {
                return true;
            }
        }
    }
    
    return false;
}

bool IsBearishPattern(const double &open[], const double &high[], const double &low[],
                      const double &close[], int index, double pinBarRatio) {
    if (index + 1 >= ArraySize(open)) return false;
    
    double body = MathAbs(close[index] - open[index]);
    
    if (body < 0.00001) return false;
    
    double wickHigh = close[index] > open[index] ? high[index] - close[index] : high[index] - open[index];
    double wickLow = close[index] < open[index] ? close[index] - low[index] : open[index] - low[index];
    
    // Pin Bar
    if (Enable_PinBar) {
        if (wickHigh > body * pinBarRatio && wickLow < body * 0.5) {
            // Close in lower third
            if (close[index] < open[index] - body * 0.667) {
                return true;
            }
        }
    }
    
    // Engulfing
    if (Enable_Engulfing) {
        if (index + 1 < ArraySize(open)) {
            if (close[index] < low[index + 1] && open[index] > high[index + 1]) {
                return true;
            }
        }
    }
    
    return false;
}

// ===== DIVERGENCE DETECTION =====

// 1. Double Bullish Divergence (Buy)
void CheckDoubleBullish(const double &low[], const double &high[], const double &close[],
                        int signalBar, int rates_total, const datetime &time[]) {
    if (!Enable_DoubleBullish) return;
    
    struct Pivot { int bar; double rsiRed; double priceLow; };
    
    Pivot pivot3, pivot2, pivot1;
    pivot3.bar = -1;
    pivot2.bar = -1;
    pivot1.bar = -1;
    
    int searchEnd = signalBar + CycleCandles;
    if (searchEnd >= rates_total) searchEnd = rates_total - 1;
    
    // Find Pivot 3 (minimum RSI in last PivotStrength candles)
    pivot3.rsiRed = 100.0;
    for (int i = signalBar; i <= signalBar + PivotStrength && i < rates_total; i++) {
        if (rsiRedBuffer[i] < pivot3.rsiRed) {
            pivot3.rsiRed = rsiRedBuffer[i];
            pivot3.bar = i;
            pivot3.priceLow = low[i];
        }
    }
    
    if (pivot3.bar == -1 || pivot3.rsiRed >= Oversold) return;
    
    // Find Pivot 2 and Pivot 1
    int searchStart = pivot3.bar + 1;
    
    bool foundDivergence = false;
    
    for (int i = searchStart; i <= searchEnd && i < rates_total; i++) {
        if (rsiRedBuffer[i] > pivot3.rsiRed && low[i] < pivot3.priceLow) {
            // Potential Pivot 2 found
            pivot2.bar = i;
            pivot2.rsiRed = rsiRedBuffer[i];
            pivot2.priceLow = low[i];
            
            // Now find Pivot 1
            for (int j = i + 1; j <= searchEnd && j < rates_total; j++) {
                if (rsiRedBuffer[j] > pivot2.rsiRed && low[j] < pivot2.priceLow) {
                    pivot1.bar = j;
                    pivot1.rsiRed = rsiRedBuffer[j];
                    pivot1.priceLow = low[j];
                    
                    // Validate filters
                    if (pivot1.rsiRed < Oversold) {
                        // Check no lower RSI between pivots
                        bool valid = true;
                        
                        // Check between Pivot 1 and 2
                        for (int k = pivot1.bar - 1; k > pivot2.bar; k--) {
                            if (rsiRedBuffer[k] < pivot2.rsiRed) {
                                valid = false;
                                break;
                            }
                        }
                        
                        // Check between Pivot 2 and 3
                        if (valid) {
                            for (int k = pivot2.bar - 1; k > pivot3.bar; k--) {
                                if (rsiRedBuffer[k] < pivot3.rsiRed) {
                                    valid = false;
                                    break;
                                }
                            }
                        }
                        
                        if (valid && CanDrawSignal(signalBar, 1)) {
                            // Signal confirmed
                            DrawSignal(signalBar, 1, time, low, "Buy Signal - Double Bullish");
                            DrawDivergenceLines(pivot1.bar, pivot2.bar, pivot3.bar, 1);
                            foundDivergence = true;
                            break;
                        }
                    }
                }
            }
            
            if (foundDivergence) break;
        }
    }
}

// 2. Double Bearish Divergence (Sell)
void CheckDoubleBearish(const double &low[], const double &high[], const double &close[],
                        int signalBar, int rates_total, const datetime &time[]) {
    if (!Enable_DoubleBearish) return;
    
    struct Pivot { int bar; double rsiBlue; double priceHigh; };
    
    Pivot pivot3, pivot2, pivot1;
    pivot3.bar = -1;
    pivot2.bar = -1;
    pivot1.bar = -1;
    
    int searchEnd = signalBar + CycleCandles;
    if (searchEnd >= rates_total) searchEnd = rates_total - 1;
    
    // Find Pivot 3 (maximum RSI in last PivotStrength candles)
    pivot3.rsiBlue = 0.0;
    for (int i = signalBar; i <= signalBar + PivotStrength && i < rates_total; i++) {
        if (rsiBluBuffer[i] > pivot3.rsiBlue) {
            pivot3.rsiBlue = rsiBluBuffer[i];
            pivot3.bar = i;
            pivot3.priceHigh = high[i];
        }
    }
    
    if (pivot3.bar == -1 || pivot3.rsiBlue <= Overbought) return;
    
    // Find Pivot 2 and Pivot 1
    int searchStart = pivot3.bar + 1;
    
    bool foundDivergence = false;
    
    for (int i = searchStart; i <= searchEnd && i < rates_total; i++) {
        if (rsiBluBuffer[i] < pivot3.rsiBlue && high[i] > pivot3.priceHigh) {
            // Potential Pivot 2 found
            pivot2.bar = i;
            pivot2.rsiBlue = rsiBluBuffer[i];
            pivot2.priceHigh = high[i];
            
            // Now find Pivot 1
            for (int j = i + 1; j <= searchEnd && j < rates_total; j++) {
                if (rsiBluBuffer[j] < pivot2.rsiBlue && high[j] > pivot2.priceHigh) {
                    pivot1.bar = j;
                    pivot1.rsiBlue = rsiBluBuffer[j];
                    pivot1.priceHigh = high[j];
                    
                    // Validate filters
                    if (pivot1.rsiBlue > Overbought) {
                        // Check no higher RSI between pivots
                        bool valid = true;
                        
                        // Check between Pivot 1 and 2
                        for (int k = pivot1.bar - 1; k > pivot2.bar; k--) {
                            if (rsiBluBuffer[k] > pivot2.rsiBlue) {
                                valid = false;
                                break;
                            }
                        }
                        
                        // Check between Pivot 2 and 3
                        if (valid) {
                            for (int k = pivot2.bar - 1; k > pivot3.bar; k--) {
                                if (rsiBluBuffer[k] > pivot3.rsiBlue) {
                                    valid = false;
                                    break;
                                }
                            }
                        }
                        
                        if (valid && CanDrawSignal(signalBar, -1)) {
                            // Signal confirmed
                            DrawSignal(signalBar, -1, time, high, "Sell Signal - Double Bearish");
                            DrawDivergenceLines(pivot1.bar, pivot2.bar, pivot3.bar, -1);
                            foundDivergence = true;
                            break;
                        }
                    }
                }
            }
            
            if (foundDivergence) break;
        }
    }
}

// 3. Bullish then Hidden Bearish Divergence (Sell)
void CheckBullishThenHiddenBearish(const double &low[], const double &high[], const double &close[],
                                   int signalBar, int rates_total, const datetime &time[]) {
    if (!Enable_BullishThenHiddenBearish) return;
    
    struct Pivot { int bar; double rsiRed; double rsiBlue; double priceLow; double priceHigh; };
    
    Pivot pivot1, pivot2, pivot3, pivot4;
    pivot1.bar = -1;
    pivot2.bar = -1;
    pivot3.bar = -1;
    pivot4.bar = -1;
    
    int searchEnd = signalBar + CycleCandles;
    if (searchEnd >= rates_total) searchEnd = rates_total - 1;
    
    // Find Pivot 4 (maximum RSI Blue in last PivotStrength candles) - end of hidden bearish
    pivot4.rsiBlue = 0.0;
    for (int i = signalBar; i <= signalBar + PivotStrength && i < rates_total; i++) {
        if (rsiBluBuffer[i] > pivot4.rsiBlue) {
            pivot4.rsiBlue = rsiBluBuffer[i];
            pivot4.bar = i;
            pivot4.priceHigh = high[i];
        }
    }
    
    if (pivot4.bar == -1) return;
    
    // Search backwards for Pivot 1 (first RSI Red < 30)
    int searchStart = pivot4.bar + 1;
    
    for (int i = searchStart; i <= searchEnd && i < rates_total; i++) {
        if (rsiRedBuffer[i] < Oversold) {
            pivot1.bar = i;
            pivot1.rsiRed = rsiRedBuffer[i];
            pivot1.priceLow = low[i];
            break;
        }
    }
    
    if (pivot1.bar == -1) return;
    
    // Find Pivot 2 (first where RSI Red > pivot1.rsiRed)
    for (int i = pivot1.bar - 1; i >= 0 && (pivot1.bar - i) <= CycleCandles; i--) {
        if (rsiRedBuffer[i] > pivot1.rsiRed) {
            pivot2.bar = i;
            pivot2.rsiRed = rsiRedBuffer[i];
            pivot2.priceLow = low[i];
            break;
        }
    }
    
    if (pivot2.bar == -1) return;
    
    // Check: between Pivot 1 and 2, no RSI Red < pivot2.rsiRed
    bool valid = true;
    for (int k = pivot1.bar - 1; k > pivot2.bar; k--) {
        if (rsiRedBuffer[k] < pivot2.rsiRed) {
            valid = false;
            break;
        }
    }
    
    if (!valid) return;
    
    // Find Pivot 3 (maximum RSI Blue between Pivot 1 and 2)
    pivot3.rsiBlue = 0.0;
    for (int i = pivot2.bar; i < pivot1.bar; i++) {
        if (rsiBluBuffer[i] > pivot3.rsiBlue) {
            pivot3.rsiBlue = rsiBluBuffer[i];
            pivot3.bar = i;
            pivot3.priceHigh = high[i];
        }
    }
    
    if (pivot3.bar == -1) return;
    
    // Validate: RSI Blue in Pivot 4 > RSI Blue in Pivot 3 AND High in Pivot 4 < High in Pivot 3
    if (pivot4.rsiBlue > pivot3.rsiBlue && pivot4.priceHigh < pivot3.priceHigh) {
        if (CanDrawSignal(signalBar, -1)) {
            DrawSignal(signalBar, -1, time, high, "Sell Signal - Bullish+Hidden Bearish");
            DrawDivergenceLines(pivot1.bar, pivot2.bar, pivot3.bar, 1); // Bullish part in red
            DrawDivergenceLines(pivot3.bar, pivot4.bar, pivot4.bar, -1); // Hidden bearish part
        }
    }
}

// 4. Bearish then Hidden Bullish Divergence (Buy)
void CheckBearishThenHiddenBullish(const double &low[], const double &high[], const double &close[],
                                   int signalBar, int rates_total, const datetime &time[]) {
    if (!Enable_BearishThenHiddenBullish) return;
    
    struct Pivot { int bar; double rsiRed; double rsiBlue; double priceLow; double priceHigh; };
    
    Pivot pivot1, pivot2, pivot3, pivot4;
    pivot1.bar = -1;
    pivot2.bar = -1;
    pivot3.bar = -1;
    pivot4.bar = -1;
    
    int searchEnd = signalBar + CycleCandles;
    if (searchEnd >= rates_total) searchEnd = rates_total - 1;
    
    // Find Pivot 4 (minimum RSI Red in last PivotStrength candles) - end of hidden bullish
    pivot4.rsiRed = 100.0;
    for (int i = signalBar; i <= signalBar + PivotStrength && i < rates_total; i++) {
        if (rsiRedBuffer[i] < pivot4.rsiRed) {
            pivot4.rsiRed = rsiRedBuffer[i];
            pivot4.bar = i;
            pivot4.priceLow = low[i];
        }
    }
    
    if (pivot4.bar == -1) return;
    
    // Search backwards for Pivot 1 (first RSI Blue > 70)
    int searchStart = pivot4.bar + 1;
    
    for (int i = searchStart; i <= searchEnd && i < rates_total; i++) {
        if (rsiBluBuffer[i] > Overbought) {
            pivot1.bar = i;
            pivot1.rsiBlue = rsiBluBuffer[i];
            pivot1.priceHigh = high[i];
            break;
        }
    }
    
    if (pivot1.bar == -1) return;
    
    // Find Pivot 2 (first where RSI Blue < pivot1.rsiBlue)
    for (int i = pivot1.bar - 1; i >= 0 && (pivot1.bar - i) <= CycleCandles; i--) {
        if (rsiBluBuffer[i] < pivot1.rsiBlue) {
            pivot2.bar = i;
            pivot2.rsiBlue = rsiBluBuffer[i];
            pivot2.priceHigh = high[i];
            break;
        }
    }
    
    if (pivot2.bar == -1) return;
    
    // Check: between Pivot 1 and 2, no RSI Blue > pivot2.rsiBlue
    bool valid = true;
    for (int k = pivot1.bar - 1; k > pivot2.bar; k--) {
        if (rsiBluBuffer[k] > pivot2.rsiBlue) {
            valid = false;
            break;
        }
    }
    
    if (!valid) return;
    
    // Find Pivot 3 (minimum RSI Red between Pivot 1 and 2)
    pivot3.rsiRed = 100.0;
    for (int i = pivot2.bar; i < pivot1.bar; i++) {
        if (rsiRedBuffer[i] < pivot3.rsiRed) {
            pivot3.rsiRed = rsiRedBuffer[i];
            pivot3.bar = i;
            pivot3.priceLow = low[i];
        }
    }
    
    if (pivot3.bar == -1) return;
    
    // Validate: RSI Red in Pivot 4 < RSI Red in Pivot 3 AND Low in Pivot 4 > Low in Pivot 3
    if (pivot4.rsiRed < pivot3.rsiRed && pivot4.priceLow > pivot3.priceLow) {
        if (CanDrawSignal(signalBar, 1)) {
            DrawSignal(signalBar, 1, time, low, "Buy Signal - Bearish+Hidden Bullish");
            DrawDivergenceLines(pivot1.bar, pivot2.bar, pivot3.bar, -1); // Bearish part in blue
            DrawDivergenceLines(pivot3.bar, pivot4.bar, pivot4.bar, 1); // Hidden bullish part
        }
    }
}

// ===== DRAWING FUNCTIONS =====
bool CanDrawSignal(int bar, int type) {
    if (lastSignalBar == bar) return false;
    
    if (!signalInitialized) return true;
    
    int barDiff = bar - lastSignalBar;
    
    if (lastSignal.type == type) {
        // Same direction
        if (barDiff < Signal_Distance_Ei_Ei1) return false;
    } else {
        // Different direction - E0 to E1
        if (barDiff < Signal_Distance_E0_E1) return false;
    }
    
    return true;
}

void DrawSignal(int bar, int type, const datetime &time[], const double &price[], string description) {
    // Draw signal
    string arrowName = "Signal_" + IntegerToString(bar) + "_" + IntegerToString(type) + "_" + IntegerToString(GetTickCount());
    
    if (type == 1) {
        // Buy signal - green arrow up
        ObjectCreate(0, arrowName, OBJ_ARROW_UP, 0, time[bar], price[bar] - 50 * Point());
        ObjectSetInteger(0, arrowName, OBJPROP_COLOR, clrLime);
        ObjectSetInteger(0, arrowName, OBJPROP_WIDTH, 3);
    } else {
        // Sell signal - red arrow down
        ObjectCreate(0, arrowName, OBJ_ARROW_DOWN, 0, time[bar], price[bar] + 50 * Point());
        ObjectSetInteger(0, arrowName, OBJPROP_COLOR, clrRed);
        ObjectSetInteger(0, arrowName, OBJPROP_WIDTH, 3);
    }
    
    // Update last signal
    lastSignal.barIndex = bar;
    lastSignal.type = type;
    lastSignal.time = time[bar];
    lastSignalBar = bar;
    signalInitialized = true;
}

void DrawDivergenceLines(int p1Bar, int p2Bar, int p3Bar, int type) {
    // Draw line from P1 to P2
    string line1Name = "DivLine_P1P2_" + IntegerToString(p1Bar) + "_" + IntegerToString(GetTickCount());
    
    if (type == 1) {
        // Bullish - Red RSI
        ObjectCreate(0, line1Name, OBJ_TREND, 0, iTime(Symbol(), Period(), p1Bar), rsiRedBuffer[p1Bar], 
                     iTime(Symbol(), Period(), p2Bar), rsiRedBuffer[p2Bar]);
    } else {
        // Bearish - Blue RSI
        ObjectCreate(0, line1Name, OBJ_TREND, 0, iTime(Symbol(), Period(), p1Bar), rsiBluBuffer[p1Bar], 
                     iTime(Symbol(), Period(), p2Bar), rsiBluBuffer[p2Bar]);
    }
    
    ObjectSetInteger(0, line1Name, OBJPROP_COLOR, clrGray);
    ObjectSetInteger(0, line1Name, OBJPROP_STYLE, STYLE_DASH);
    ObjectSetInteger(0, line1Name, OBJPROP_WIDTH, 1);
    
    // Draw line from P2 to P3
    string line2Name = "DivLine_P2P3_" + IntegerToString(p2Bar) + "_" + IntegerToString(GetTickCount());
    
    if (type == 1) {
        // Bullish - Red RSI
        ObjectCreate(0, line2Name, OBJ_TREND, 0, iTime(Symbol(), Period(), p2Bar), rsiRedBuffer[p2Bar], 
                     iTime(Symbol(), Period(), p3Bar), rsiRedBuffer[p3Bar]);
    } else {
        // Bearish - Blue RSI
        ObjectCreate(0, line2Name, OBJ_TREND, 0, iTime(Symbol(), Period(), p2Bar), rsiBluBuffer[p2Bar], 
                     iTime(Symbol(), Period(), p3Bar), rsiBluBuffer[p3Bar]);
    }
    
    ObjectSetInteger(0, line2Name, OBJPROP_COLOR, clrGray);
    ObjectSetInteger(0, line2Name, OBJPROP_STYLE, STYLE_DASH);
    ObjectSetInteger(0, line2Name, OBJPROP_WIDTH, 1);
}
