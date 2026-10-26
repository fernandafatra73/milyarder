unit uAnalysis;

{ Analisa teknikal: MA 9/25/44/99/200/650, persilangan MA, volume beli/jual,
  support/resisten, breakout dan sinyal beli/jual }

interface

uses
  SysUtils, Math;

const
  MACount = 6;
  MAPeriods: array[0..MACount - 1] of Integer = (9, 25, 44, 99, 200, 650);
  CrossLookback = 10;   // cross dihitung "baru" bila terjadi dalam 10 candle terakhir
  KlineLimit = 700;     // cukup untuk MA650

type
  TKline = record
    OpenTime: Double;
    O, H, L, C, V: Double;
    QV: Double;    // quote volume (USDT)
    TBQV: Double;  // taker buy quote volume (USDT yang dibeli agresif)
  end;
  TKlines = array of TKline;
  TDoubleArray = array of Double;

  TCrossInfo = record
    Fast, Slow: Integer;  // index ke MAPeriods
    Valid: Boolean;
    Above: Boolean;       // MA cepat di atas MA lambat
    Ago: Integer;         // berapa candle lalu terjadi cross (-1 = tidak ada)
    Golden: Boolean;
  end;

  TAnalysis = record
    Symbol, Interval, Err: string;
    Ok: Boolean;
    CandleCount: Integer;
    Price: Double;
    MA: array[0..MACount - 1] of Double;
    MAValid: array[0..MACount - 1] of Boolean;
    Crosses: array of TCrossInfo;
    LastCrossText: string;
    LastCrossAgo: Integer;
    LastCrossGolden: Boolean;
    Trend: string;
    TrendScore: Integer;
    BuyUSD, SellUSD, BuyPct, SellPct: Double;
    VolWindow: Integer;
    Pivot, R1, R2, S1, S2: Double;
    SwingRes, SwingSup: Double;
    StrongSup, StrongRes: Double;          // level yang paling sering memantulkan harga
    StrongSupHits, StrongResHits: Integer; // berapa kali level itu menahan harga
    RangeHigh, RangeLow: Double;
    VolRatio: Double;
    Rise4: Double;      // % naik dari low 4 candle terakhir
    ChgLast: Double;    // % perubahan candle terakhir
    Breakout: string;
    Score: Integer;
    Signal: string;     // BELI / JUAL / TUNGGU
    Reasons: string;
  end;

procedure ClearAnalysis(var A: TAnalysis);
function BreakoutStatus(Price, RangeHigh, RangeLow, MA9, MA25, VolRatio: Double): string;
procedure MergeKlines(var K: TKlines; const U: TKlines);
function PrependKlines(var K: TKlines; const Old: TKlines): Integer;
function Analyze(const Sym, Interval: string; const K: TKlines): TAnalysis;
function FmtPrice(D: Double): string;
function FmtUSD(D: Double): string;
function FmtPct(D: Double): string;
function SignalText(const Sig: string): string;

implementation

procedure ClearAnalysis(var A: TAnalysis);
begin
  Finalize(A);
  FillChar(A, SizeOf(A), 0);
  A.LastCrossAgo := -1;
end;

{ Status breakout dari harga terhadap range 50 candle. Dipakai Analyze dan
  pengecekan ulang tiap menit dengan harga terbaru. }
function BreakoutStatus(Price, RangeHigh, RangeLow, MA9, MA25, VolRatio: Double): string;
begin
  Result := '';
  if (RangeHigh <= 0) or (RangeLow <= 0) then
    Exit;
  if Price > RangeHigh then
    Result := 'BREAKOUT NAIK'
  else if Price < RangeLow then
    Result := 'BREAKDOWN'
  else if (Price >= RangeHigh * 0.985) and ((MA9 > MA25) or (VolRatio >= 1.5)) then
    Result := 'MAU BREAKOUT'
  else if (Price <= RangeLow * 1.015) and (MA9 < MA25) then
    Result := 'MAU BREAKDOWN';
end;

{ Gabungkan candle terbaru (U) ke grafik (K): candle dengan waktu buka sama
  diganti, candle yang lebih baru ditambahkan di belakang. }
procedure MergeKlines(var K: TKlines; const U: TKlines);
var
  I, J, N: Integer;
begin
  for I := 0 to High(U) do
  begin
    N := Length(K);
    if N = 0 then
      Exit;
    if U[I].OpenTime > K[N - 1].OpenTime then
    begin
      SetLength(K, N + 1);
      K[N] := U[I];
      Continue;
    end;
    for J := N - 1 downto Max(0, N - 3) do
      if K[J].OpenTime = U[I].OpenTime then
      begin
        K[J] := U[I];
        Break;
      end;
  end;
end;

{ Sambungkan candle lama (Old) di depan K; hanya yang lebih tua dari K[0].
  Hasil: jumlah candle yang ditambahkan. }
function PrependKlines(var K: TKlines; const Old: TKlines): Integer;
var
  I, N: Integer;
  R: TKlines;
begin
  Result := 0;
  if Length(K) = 0 then
    Exit;
  for I := 0 to High(Old) do
    if Old[I].OpenTime < K[0].OpenTime then
      Inc(Result);
  if Result = 0 then
    Exit;
  SetLength(R, Result + Length(K));
  N := 0;
  for I := 0 to High(Old) do
    if Old[I].OpenTime < K[0].OpenTime then
    begin
      R[N] := Old[I];
      Inc(N);
    end;
  for I := 0 to High(K) do
    R[N + I] := K[I];
  K := R;
end;

function FmtPrice(D: Double): string;
var
  X: Double;
begin
  X := Abs(D);
  if X = 0 then
    Result := '-'
  else if X >= 1000 then
    Result := FormatFloat('#,##0.00', D)
  else if X >= 10 then
    Result := FormatFloat('0.000', D)
  else if X >= 1 then
    Result := FormatFloat('0.0000', D)
  else if X >= 0.01 then
    Result := FormatFloat('0.00000', D)
  else
    Result := FormatFloat('0.00000000', D);
end;

function FmtUSD(D: Double): string;
var
  X: Double;
begin
  X := Abs(D);
  if X >= 1E9 then
    Result := Format('$%.2fB', [D / 1E9])
  else if X >= 1E6 then
    Result := Format('$%.2fM', [D / 1E6])
  else if X >= 1E3 then
    Result := Format('$%.1fK', [D / 1E3])
  else
    Result := Format('$%.0f', [D]);
end;

function FmtPct(D: Double): string;
begin
  if D >= 0 then
    Result := Format('+%.2f%%', [D])
  else
    Result := Format('%.2f%%', [D]);
end;

function SignalText(const Sig: string): string;
begin
  if Sig = 'BELI' then
    Result := 'BOLEH BELI (LONG)'
  else if Sig = 'JUAL' then
    Result := 'BOLEH JUAL (SHORT)'
  else if Sig = '' then
    Result := '-'
  else
    Result := 'TUNGGU';
end;

{ Cari harga yang paling sering "diinjak" lalu memantul naik (support terkuat)
  dan paling sering menolak harga naik (resisten terkuat). Swing low/high
  (2 candle kiri-kanan) dalam 500 candle terakhir dikelompokkan dengan
  toleransi setengah rata-rata panjang candle; kelompok terbanyak = level terkuat. }
procedure FindStrongLevels(const K: TKlines; Price: Double; var A: TAnalysis);
var
  n, lo, i, j, x, cntL, cntH, Hits, Best: Integer;
  Lows, Highs: array of Double;
  Tol, Sum, Avg, BestLvl: Double;
  isL, isH: Boolean;
begin
  n := Length(K);
  lo := Max(2, n - 500);
  SetLength(Lows, n);
  SetLength(Highs, n);
  cntL := 0;
  cntH := 0;
  Sum := 0;
  for i := lo to n - 1 do
    if K[i].C > 0 then
      Sum := Sum + (K[i].H - K[i].L) / K[i].C;
  Tol := Max(0.002, Sum / Max(1, n - lo) * 0.5);  // toleransi relatif

  for i := lo to n - 3 do
  begin
    isL := True;
    isH := True;
    for j := i - 2 to i + 2 do
      if j <> i then
      begin
        if K[j].L < K[i].L then isL := False;
        if K[j].H > K[i].H then isH := False;
      end;
    if isL then begin Lows[cntL] := K[i].L; Inc(cntL); end;
    if isH then begin Highs[cntH] := K[i].H; Inc(cntH); end;
  end;

  { support terkuat: hanya level di bawah / sekitar harga sekarang }
  Best := 0;
  BestLvl := 0;
  for i := 0 to cntL - 1 do
  begin
    if Lows[i] > Price * (1 + Tol) then Continue;
    Hits := 0;
    Avg := 0;
    for x := 0 to cntL - 1 do
      if Abs(Lows[x] - Lows[i]) <= Lows[i] * Tol then
      begin
        Inc(Hits);
        Avg := Avg + Lows[x];
      end;
    if (Hits > Best) or ((Hits = Best) and (Lows[i] > BestLvl)) then
    begin
      Best := Hits;
      BestLvl := Avg / Hits;
    end;
  end;
  A.StrongSup := BestLvl;
  A.StrongSupHits := Best;

  { resisten terkuat: hanya level di atas / sekitar harga sekarang }
  Best := 0;
  BestLvl := 0;
  for i := 0 to cntH - 1 do
  begin
    if Highs[i] < Price * (1 - Tol) then Continue;
    Hits := 0;
    Avg := 0;
    for x := 0 to cntH - 1 do
      if Abs(Highs[x] - Highs[i]) <= Highs[i] * Tol then
      begin
        Inc(Hits);
        Avg := Avg + Highs[x];
      end;
    if (Hits > Best) or ((Hits = Best) and ((BestLvl = 0) or (Highs[i] < BestLvl))) then
    begin
      Best := Hits;
      BestLvl := Avg / Hits;
    end;
  end;
  A.StrongRes := BestLvl;
  A.StrongResHits := Best;
end;

function Analyze(const Sym, Interval: string; const K: TKlines): TAnalysis;
var
  n, i, j, m, a, b, w, lo, cnt: Integer;
  cum: array of Double;
  P, buy, tot, h, l, d0, d1, avgV, minL: Double;
  isHigh, isLow: Boolean;
  ci: TCrossInfo;
  nearSup, nearRes: Boolean;

  function SMA(Period, Idx: Integer): Double;
  begin
    Result := (cum[Idx + 1] - cum[Idx + 1 - Period]) / Period;
  end;

  procedure AddReason(Pts: Integer; const Txt: string);
  var
    S: string;
  begin
    Inc(Result.Score, Pts);
    if Pts > 0 then
      S := Format('(+%d) ', [Pts])
    else
      S := Format('(%d) ', [Pts]);
    Result.Reasons := Result.Reasons + '  ' + S + Txt + #13#10;
  end;

begin
  ClearAnalysis(Result);
  Result.Symbol := Sym;
  Result.Interval := Interval;
  n := Length(K);
  Result.CandleCount := n;
  if n < 30 then
  begin
    Result.Err := 'Data candle terlalu sedikit (' + IntToStr(n) + ')';
    Exit;
  end;

  SetLength(cum, n + 1);
  cum[0] := 0;
  for i := 0 to n - 1 do
    cum[i + 1] := cum[i] + K[i].C;

  P := K[n - 1].C;
  Result.Price := P;

  { --- Moving Average --- }
  for m := 0 to MACount - 1 do
    if n >= MAPeriods[m] then
    begin
      Result.MA[m] := SMA(MAPeriods[m], n - 1);
      Result.MAValid[m] := True;
    end;

  { --- Persilangan MA (semua pasangan) --- }
  for a := 0 to MACount - 2 do
    for b := a + 1 to MACount - 1 do
    begin
      ci.Fast := a;
      ci.Slow := b;
      ci.Valid := Result.MAValid[b];
      ci.Above := False;
      ci.Ago := -1;
      ci.Golden := False;
      if ci.Valid then
      begin
        ci.Above := Result.MA[a] > Result.MA[b];
        j := n - 1;
        while (j >= n - CrossLookback) and (j - 1 >= MAPeriods[b] - 1) do
        begin
          d1 := SMA(MAPeriods[a], j) - SMA(MAPeriods[b], j);
          d0 := SMA(MAPeriods[a], j - 1) - SMA(MAPeriods[b], j - 1);
          if (d1 > 0) <> (d0 > 0) then
          begin
            ci.Ago := n - 1 - j;
            ci.Golden := d1 > 0;
            Break;
          end;
          Dec(j);
        end;
        if (ci.Ago >= 0) and ((Result.LastCrossAgo < 0) or (ci.Ago < Result.LastCrossAgo)) then
        begin
          Result.LastCrossAgo := ci.Ago;
          Result.LastCrossGolden := ci.Golden;
          if ci.Golden then
            Result.LastCrossText := Format('GOLDEN MA%d/MA%d', [MAPeriods[a], MAPeriods[b]])
          else
            Result.LastCrossText := Format('DEATH MA%d/MA%d', [MAPeriods[a], MAPeriods[b]]);
        end;
      end;
      cnt := Length(Result.Crosses);
      SetLength(Result.Crosses, cnt + 1);
      Result.Crosses[cnt] := ci;
    end;

  { --- Trend dari posisi MA --- }
  if P > Result.MA[0] then Inc(Result.TrendScore) else Dec(Result.TrendScore);
  if Result.MAValid[1] then
    if Result.MA[0] > Result.MA[1] then Inc(Result.TrendScore) else Dec(Result.TrendScore);
  if Result.MAValid[3] then
    if Result.MA[1] > Result.MA[3] then Inc(Result.TrendScore) else Dec(Result.TrendScore);
  if Result.MAValid[4] then
    if P > Result.MA[4] then Inc(Result.TrendScore) else Dec(Result.TrendScore);
  if Result.MAValid[5] then
    if P > Result.MA[5] then Inc(Result.TrendScore) else Dec(Result.TrendScore);
  if Result.TrendScore >= 4 then Result.Trend := 'BULLISH KUAT'
  else if Result.TrendScore >= 2 then Result.Trend := 'BULLISH'
  else if Result.TrendScore <= -4 then Result.Trend := 'BEARISH KUAT'
  else if Result.TrendScore <= -2 then Result.Trend := 'BEARISH'
  else Result.Trend := 'SIDEWAYS';

  { --- Volume beli vs jual (taker) 24 candle terakhir --- }
  w := Min(24, n);
  Result.VolWindow := w;
  buy := 0;
  tot := 0;
  for i := n - w to n - 1 do
  begin
    tot := tot + K[i].QV;
    buy := buy + K[i].TBQV;
  end;
  Result.BuyUSD := buy;
  Result.SellUSD := tot - buy;
  if tot > 0 then
  begin
    Result.BuyPct := buy / tot * 100;
    Result.SellPct := 100 - Result.BuyPct;
  end;

  { --- Pivot klasik dari 24 candle yang sudah selesai --- }
  w := Min(24, n - 1);
  h := 0;
  l := MaxDouble;
  for i := n - 1 - w to n - 2 do
  begin
    h := Max(h, K[i].H);
    l := Min(l, K[i].L);
  end;
  Result.Pivot := (h + l + K[n - 2].C) / 3;
  Result.R1 := 2 * Result.Pivot - l;
  Result.S1 := 2 * Result.Pivot - h;
  Result.R2 := Result.Pivot + (h - l);
  Result.S2 := Result.Pivot - (h - l);

  { --- Swing support/resisten (fractal 3 candle kiri-kanan) --- }
  lo := Max(3, n - 300);
  for i := lo to n - 4 do
  begin
    isHigh := True;
    isLow := True;
    for j := i - 3 to i + 3 do
      if j <> i then
      begin
        if K[j].H > K[i].H then isHigh := False;
        if K[j].L < K[i].L then isLow := False;
      end;
    if isHigh and (K[i].H > P * 1.001) then
      if (Result.SwingRes = 0) or (K[i].H < Result.SwingRes) then
        Result.SwingRes := K[i].H;
    if isLow and (K[i].L < P * 0.999) then
      if (Result.SwingSup = 0) or (K[i].L > Result.SwingSup) then
        Result.SwingSup := K[i].L;
  end;
  if Result.SwingRes = 0 then
    for i := lo to n - 1 do
      Result.SwingRes := Max(Result.SwingRes, K[i].H);
  if Result.SwingSup = 0 then
  begin
    Result.SwingSup := MaxDouble;
    for i := lo to n - 1 do
      Result.SwingSup := Min(Result.SwingSup, K[i].L);
  end;

  { --- Support/resisten terkuat: level paling sering menolak turun/naik --- }
  FindStrongLevels(K, P, Result);

  { --- Range 50 candle & volume --- }
  w := Min(50, n - 2);
  Result.RangeLow := MaxDouble;
  for i := n - 1 - w to n - 2 do
  begin
    Result.RangeHigh := Max(Result.RangeHigh, K[i].H);
    Result.RangeLow := Min(Result.RangeLow, K[i].L);
  end;
  avgV := 0;
  for i := n - 22 to n - 3 do
    avgV := avgV + K[i].V;
  avgV := avgV / 20;
  if avgV > 0 then
    Result.VolRatio := Max(K[n - 1].V, K[n - 2].V) / avgV;

  minL := MaxDouble;
  for i := n - 4 to n - 1 do
    minL := Min(minL, K[i].L);
  if minL > 0 then
    Result.Rise4 := (P - minL) / minL * 100;
  if K[n - 1].O > 0 then
    Result.ChgLast := (P - K[n - 1].O) / K[n - 1].O * 100;

  { --- Breakout --- }
  Result.Breakout := BreakoutStatus(P, Result.RangeHigh, Result.RangeLow,
    Result.MA[0], Result.MA[1], Result.VolRatio);

  { --- Sinyal --- }
  if Result.TrendScore >= 2 then
    AddReason(2, 'Trend MA ' + Result.Trend)
  else if Result.TrendScore <= -2 then
    AddReason(-2, 'Trend MA ' + Result.Trend);
  if (Result.LastCrossAgo >= 0) and (Result.LastCrossAgo <= 3) then
  begin
    if Result.LastCrossGolden then
      AddReason(1, Result.LastCrossText + ' baru terjadi')
    else
      AddReason(-1, Result.LastCrossText + ' baru terjadi');
  end;
  if Result.BuyPct >= 53 then
    AddReason(1, Format('Pembeli dominan (%.1f%%)', [Result.BuyPct]))
  else if (Result.BuyPct > 0) and (Result.BuyPct <= 47) then
    AddReason(-1, Format('Penjual dominan (%.1f%%)', [Result.SellPct]));
  if Result.Breakout = 'BREAKOUT NAIK' then
    AddReason(2, 'Breakout di atas resisten range 50 candle')
  else if Result.Breakout = 'MAU BREAKOUT' then
    AddReason(1, 'Harga menekan resisten (mau breakout)')
  else if Result.Breakout = 'BREAKDOWN' then
    AddReason(-2, 'Breakdown di bawah support range 50 candle')
  else if Result.Breakout = 'MAU BREAKDOWN' then
    AddReason(-1, 'Harga menekan support (mau breakdown)');
  nearSup := P <= Result.SwingSup * 1.01;
  nearRes := P >= Result.SwingRes * 0.99;
  if nearSup and (Result.TrendScore >= 0) then
    AddReason(1, 'Harga dekat support (area beli)');
  if nearRes and (Pos('BREAKOUT', Result.Breakout) = 0) then
    AddReason(-1, 'Harga dekat resisten (rawan koreksi)');

  if Result.Score >= 4 then
    Result.Signal := 'BELI'
  else if Result.Score <= -4 then
    Result.Signal := 'JUAL'
  else
    Result.Signal := 'TUNGGU';
  Result.Ok := True;
end;

end.
