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

  // time frame untuk deteksi sideways + prediksi arah, dan batas lebar range
  // (% dari 30 candle terakhir) agar masih dianggap sideways
  SideTFCount = 6;
  SideTFApi: array[0..SideTFCount - 1] of string = ('1m', '5m', '10m', '15m', '30m', '1h');
  SideTFLabel: array[0..SideTFCount - 1] of string = ('1m', '5m', '10m', '15m', '30m', '1j');
  SideMaxRange: array[0..SideTFCount - 1] of Double = (0.5, 0.9, 1.2, 1.5, 2.0, 3.0);

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

type
  TTarget = record
    Price: Double;
    Note: string;
  end;
  TTargets = array of TTarget;

procedure ClearAnalysis(var A: TAnalysis);
function SellTargets(const A: TAnalysis; const K: TKlines; out StopPrice: Double;
  out StopNote: string): TTargets;
function BreakoutStatus(Price, RangeHigh, RangeLow, MA9, MA25, VolRatio: Double): string;
function BreakoutChance(const K: TKlines; RangeHigh: Double; out Note: string; out EtaMin: Integer): Integer;
function SidewaysForecast(const K: TKlines; MaxRangePct: Double; out Dir: Integer): Boolean;
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

{ Peluang breakout (0-100) dari candle 1 menit terakhir, dilihat dari bawah:
  persilangan MA9 memotong MA25 ke atas, higher low, volume & tekanan beli
  naik, serta dekat/di atas resisten (RangeHigh dari analisa 1 jam). }
function BreakoutChance(const K: TKlines; RangeHigh: Double; out Note: string; out EtaMin: Integer): Integer;
var
  slope: Double;
  n, last, j, Back: Integer;
  P, gNow, gPrev, minA, minB, vNow, vOld, qv, tb, d, rise: Double;
  Crossed: Boolean;

  function SMA5(Period, Idx: Integer): Double;
  var
    X: Integer;
  begin
    Result := 0;
    for X := Idx - Period + 1 to Idx do
      Result := Result + K[X].C;
    Result := Result / Period;
  end;

  function Gap(Idx: Integer): Double;
  begin
    Result := SMA5(9, Idx) - SMA5(25, Idx);
  end;

  procedure Pt(Points: Integer; const Txt: string);
  begin
    Inc(Result, Points);
    if Note <> '' then
      Note := Note + '; ';
    Note := Note + Txt;
  end;

begin
  Result := 0;
  Note := '';
  EtaMin := -1;
  n := Length(K);
  if n < 70 then
    Exit;
  last := n - 1;
  P := K[last].C;
  if P <= 0 then
    Exit;

  { persilangan dari bawah ke atas dalam 15 candle (15 menit) terakhir }
  Crossed := False;
  Back := 0;
  for j := last downto last - 14 do
    if (Gap(j - 1) <= 0) and (Gap(j) > 0) then
    begin
      Crossed := True;
      Back := last - j;
      Break;
    end;
  gNow := Gap(last);
  gPrev := Gap(last - 1);
  if Crossed then
    Pt(30, Format('MA9 baru memotong MA25 dari bawah (%d menit lalu)', [Back]))
  else if (gNow < 0) and (gNow > gPrev) and (Abs(gNow) / P < 0.003) then
    Pt(22, 'MA9 hampir memotong MA25 dari bawah')
  else if (gNow > 0) and (gNow > gPrev) then
    Pt(8, 'MA9 di atas MA25 dan melebar');
  if (P > SMA5(9, last)) and (P > SMA5(25, last)) then
    Pt(8, 'harga di atas MA9 & MA25');

  { higher low: dasar 5 menit terakhir lebih tinggi dari 5 menit sebelumnya }
  minA := K[last].L;
  minB := K[last - 5].L;
  for j := last - 4 to last do
    if K[j].L < minA then minA := K[j].L;
  for j := last - 9 to last - 5 do
    if K[j].L < minB then minB := K[j].L;
  if minA > minB then
    Pt(12, 'higher low');

  { volume 15 menit terakhir vs rata-rata 45 menit sebelumnya }
  vNow := 0;
  for j := last - 14 to last do
    vNow := vNow + K[j].QV;
  vNow := vNow / 15;
  vOld := 0;
  for j := last - 59 to last - 15 do
    vOld := vOld + K[j].QV;
  vOld := vOld / 45;
  if vOld > 0 then
  begin
    if vNow >= vOld * 2 then Pt(20, Format('volume %.1fx rata-rata', [vNow / vOld]))
    else if vNow >= vOld * 1.3 then Pt(12, Format('volume %.1fx rata-rata', [vNow / vOld]))
    else if vNow >= vOld then Pt(5, 'volume naik');
  end;

  { dominasi pembeli agresif 15 menit terakhir }
  qv := 0;
  tb := 0;
  for j := last - 14 to last do
  begin
    qv := qv + K[j].QV;
    tb := tb + K[j].TBQV;
  end;
  if (qv > 0) and (tb / qv >= 0.55) then
    Pt(10, Format('pembeli agresif %.0f%%', [tb / qv * 100]));

  { jarak ke resisten }
  if RangeHigh > 0 then
  begin
    d := (RangeHigh - P) / RangeHigh * 100;
    if d < 0 then Pt(20, 'sudah di atas resisten')
    else if d <= 0.5 then Pt(20, Format('%.2f%% dari resisten', [d]))
    else if d <= 1.5 then Pt(12, Format('%.2f%% dari resisten', [d]))
    else if d <= 3 then Pt(5, Format('%.2f%% dari resisten', [d]));
  end;

  rise := (P - K[last - 30].C) / K[last - 30].C * 100;
  if rise > 0 then
    Pt(5, Format('naik %.2f%% dalam 30 menit', [rise]));

  { perkiraan waktu mencapai resisten: laju naik 30 menit terakhir diteruskan lurus }
  if RangeHigh > 0 then
  begin
    if P > RangeHigh then
      EtaMin := 0
    else
    begin
      slope := (P - K[last - 30].C) / 30;   // naik per menit
      if slope > 0 then
      begin
        d := (RangeHigh - P) / slope;   // menit
        if d <= 240 then
          EtaMin := Ceil(d);
      end;
    end;
  end;

  if Result > 100 then
    Result := 100;
end;

{ Sideways = 30 candle terakhir bergerak di range sempit (<= MaxRangePct) dan
  bolak-balik (net gerak < 30% dari total gerak). Bila sideways, Dir = prediksi
  arah keluar range: +1 naik, -1 turun (skor MA9/MA25, harga vs MA25, higher
  low, lower high, dan dominasi taker beli/jual 10 candle terakhir). }
function SidewaysForecast(const K: TKlines; MaxRangePct: Double; out Dir: Integer): Boolean;
const
  Win = 30;
var
  n, i, first, score: Integer;
  hh, ll, path, net, P, ma9, ma25, loA, loB, hiA, hiB, buy, tot: Double;
begin
  Result := False;
  Dir := 0;
  n := Length(K);
  if n < Win + 2 then
    Exit;
  first := n - Win;
  hh := 0;
  ll := MaxDouble;
  path := 0;
  for i := first to n - 1 do
  begin
    hh := Max(hh, K[i].H);
    ll := Min(ll, K[i].L);
    if i > first then
      path := path + Abs(K[i].C - K[i - 1].C);
  end;
  if (ll <= 0) or (path <= 0) then
    Exit;
  net := Abs(K[n - 1].C - K[first].C);
  if ((hh - ll) / ((hh + ll) / 2) * 100 > MaxRangePct) or (net / path >= 0.3) then
    Exit;
  Result := True;

  P := K[n - 1].C;
  ma9 := 0;
  for i := n - 9 to n - 1 do
    ma9 := ma9 + K[i].C;
  ma9 := ma9 / 9;
  ma25 := 0;
  for i := n - 25 to n - 1 do
    ma25 := ma25 + K[i].C;
  ma25 := ma25 / 25;

  score := 0;
  if ma9 > ma25 then Inc(score) else Dec(score);
  if P > ma25 then Inc(score) else Dec(score);

  loA := MaxDouble; loB := MaxDouble; hiA := 0; hiB := 0;
  for i := n - 10 to n - 1 do
  begin
    loA := Min(loA, K[i].L);
    hiA := Max(hiA, K[i].H);
  end;
  for i := n - 20 to n - 11 do
  begin
    loB := Min(loB, K[i].L);
    hiB := Max(hiB, K[i].H);
  end;
  if loA > loB then Inc(score);   // higher low: tekanan naik
  if hiA < hiB then Dec(score);   // lower high: tekanan turun

  buy := 0;
  tot := 0;
  for i := n - 10 to n - 1 do
  begin
    tot := tot + K[i].QV;
    buy := buy + K[i].TBQV;
  end;
  if tot > 0 then
  begin
    if buy / tot >= 0.52 then Inc(score)
    else if buy / tot <= 0.48 then Dec(score);
  end;

  if score > 0 then Dir := 1
  else if score < 0 then Dir := -1
  else if P >= K[n - 6].C then Dir := 1   // seri: ikuti arah 5 candle terakhir
  else Dir := -1;
end;

{ Titik tunggu jual: resisten, pivot, MA di atas harga, dan target kelipatan ATR,
  diurutkan dari yang terdekat dan digabung bila selisihnya < 0,3% (maksimal 3).
  StopPrice = batas cut loss di bawah support terdekat. }
function SellTargets(const A: TAnalysis; const K: TKlines; out StopPrice: Double;
  out StopNote: string): TTargets;
var
  P, Atr, Best: Double;
  Cand, M: TTargets;
  I, J, N: Integer;
  T: TTarget;

  procedure AddUp(Pr: Double; const Nt: string);
  begin
    if Pr > P * 1.002 then
    begin
      SetLength(Cand, Length(Cand) + 1);
      Cand[High(Cand)].Price := Pr;
      Cand[High(Cand)].Note := Nt;
    end;
  end;

  procedure TrySup(Pr: Double; const Nt: string);
  begin
    if (Pr > 0) and (Pr < P * 0.998) and (Pr > Best) then
    begin
      Best := Pr;
      StopNote := Nt;
    end;
  end;

begin
  SetLength(Result, 0);
  SetLength(Cand, 0);
  StopPrice := 0;
  StopNote := '';
  P := A.Price;
  if (not A.Ok) or (P <= 0) then
    Exit;
  N := Length(K);
  Atr := 0;
  if N >= 16 then
  begin
    for I := N - 15 to N - 2 do
      Atr := Atr + (K[I].H - K[I].L);
    Atr := Atr / 14;
  end;

  AddUp(A.SwingRes, 'Resisten terdekat');
  if A.StrongResHits > 0 then
    AddUp(A.StrongRes, Format('Resisten terkuat (ditolak %dx)', [A.StrongResHits]));
  AddUp(A.R1, 'Pivot R1');
  AddUp(A.R2, 'Pivot R2');
  AddUp(A.RangeHigh, 'High range 50 candle');
  for I := 1 to 4 do
    if (I <> 2) and A.MAValid[I] then
      AddUp(A.MA[I], Format('MA%d', [MAPeriods[I]]));
  if Atr > 0 then
  begin
    AddUp(P + Atr, 'Target 1x ATR');
    AddUp(P + 2 * Atr, 'Target 2x ATR');
    AddUp(P + 3 * Atr, 'Target 3x ATR');
    AddUp(P + 5 * Atr, 'Target 5x ATR');
    AddUp(P + 8 * Atr, 'Target 8x ATR');
  end;

  for I := 1 to High(Cand) do   // urut harga naik
  begin
    T := Cand[I];
    J := I - 1;
    while (J >= 0) and (Cand[J].Price > T.Price) do
    begin
      Cand[J + 1] := Cand[J];
      Dec(J);
    end;
    Cand[J + 1] := T;
  end;
  SetLength(M, 0);
  for I := 0 to High(Cand) do
    if (Length(M) > 0) and (Cand[I].Price <= M[High(M)].Price * 1.003) then
      M[High(M)].Note := M[High(M)].Note + ' + ' + Cand[I].Note
    else
    begin
      SetLength(M, Length(M) + 1);
      M[High(M)] := Cand[I];
    end;
  N := Min(3, Length(M));
  SetLength(Result, N);
  for I := 0 to N - 1 do
    Result[I] := M[I];

  { cut loss: support terdekat di bawah harga (dikurangi 0,2%) }
  Best := 0;
  TrySup(A.SwingSup, 'support terdekat');
  if A.StrongSupHits > 0 then
    TrySup(A.StrongSup, 'support terkuat');
  TrySup(A.S1, 'pivot S1');
  if A.MAValid[1] then
    TrySup(A.MA[1], 'MA25');
  if Best > 0 then
    StopPrice := Best * 0.998
  else if Atr > 0 then
  begin
    StopPrice := P - 1.5 * Atr;
    StopNote := '1,5x ATR';
  end;
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
