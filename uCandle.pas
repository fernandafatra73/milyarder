unit uCandle;

{ Pola candle, pola chart dan strategi indikator -> sinyal BELI / JUAL untuk
  time frame 1m, 5m, 15m, 30m. Semua pola terdaftar di tabel teori (Theory):
  jenis, arah (+1 beli / -1 jual) dan arti singkatnya. }

interface

uses
  Windows, Messages, SysUtils, Classes, Graphics, Controls, Forms, StdCtrls,
  ExtCtrls, ComCtrls, Math, StrUtils, uAnalysis, uBinance, uWorkers, uChart;

const
  WM_FT_CANDLE = WM_USER + 210;
  CandleTFCount = 4;
  CandleTFApi: array[0..CandleTFCount - 1] of string = ('1m', '5m', '15m', '30m');
  KindNames: array[0..2] of string = ('Candle', 'Pola Chart', 'Strategi');

type
  TSymArr = array of string;
  TSymProvider = procedure(var Syms: TSymArr) of object;

  TPatHit = record
    Kind, Dir, Str: Integer;   // Kind 0 candle/1 chart/2 strategi, Dir +1 beli/-1 jual, Str 1..3
    Name: string;
  end;
  TPatHits = array of TPatHit;

function DetectPatterns(const K: TKlines): TPatHits;
function PatternReport(const K: TKlines): string;
procedure ShowCandleForm(Provider: TSymProvider);

implementation

type
  TIntArr = array of Integer;

var
  Theory: TStringList;   // Nama=Jenis|Arah|Arti

{ ---------- Tabel teori ---------- }

procedure T(Kind, Dir: Integer; const Name, Desc: string);
begin
  Theory.Add(Format('%s=%d|%d|%s', [Name, Kind, Dir, Desc]));
end;

procedure BuildTheory;
begin
  Theory := TStringList.Create;
  { --- candle tunggal --- }
  T(0, 1, 'Hammer', 'Ekor bawah panjang setelah turun: penjual ditolak, pembeli masuk');
  T(0, 1, 'Inverted Hammer', 'Ekor atas panjang setelah turun: pembeli mulai mencoba naik (butuh konfirmasi)');
  T(0, -1, 'Hanging Man', 'Bentuk hammer setelah naik: tanda pembeli melemah');
  T(0, -1, 'Shooting Star', 'Ekor atas panjang setelah naik: harga ditolak di atas, penjual masuk');
  T(0, 1, 'Dragonfly Doji', 'Doji berekor bawah panjang di akhir turun: pantulan naik');
  T(0, -1, 'Gravestone Doji', 'Doji berekor atas panjang di akhir naik: penolakan harga atas');
  T(0, 1, 'Bullish Marubozu', 'Candle hijau penuh tanpa ekor: pembeli menguasai penuh');
  T(0, -1, 'Bearish Marubozu', 'Candle merah penuh tanpa ekor: penjual menguasai penuh');
  T(0, 1, 'Bullish Pin Bar', 'Ekor bawah sangat panjang di dasar 10 candle: false breakdown, rawan naik');
  T(0, -1, 'Bearish Pin Bar', 'Ekor atas sangat panjang di puncak 10 candle: false breakout, rawan turun');
  T(0, 1, 'Volume Spike Bullish', 'Candle hijau besar dengan volume 2,5x lipat: dorongan beli kuat');
  T(0, -1, 'Volume Spike Bearish', 'Candle merah besar dengan volume 2,5x lipat: tekanan jual kuat');
  T(0, 1, 'Bullish Belt Hold', 'Buka di dasar lalu naik penuh setelah turun: pembalikan naik');
  T(0, -1, 'Bearish Belt Hold', 'Buka di puncak lalu turun penuh setelah naik: pembalikan turun');
  T(0, 1, 'Hammer Terkonfirmasi', 'Hammer lalu candle berikutnya hijau menutup di atas high hammer');
  T(0, -1, 'Shooting Star Terkonfirmasi', 'Shooting star lalu candle merah menutup di bawah low-nya');
  { --- dua candle --- }
  T(0, 1, 'Bullish Engulfing', 'Candle hijau menelan candle merah sebelumnya setelah turun');
  T(0, -1, 'Bearish Engulfing', 'Candle merah menelan candle hijau sebelumnya setelah naik');
  T(0, 1, 'Piercing Line', 'Hijau menembus lebih dari separuh candle merah sebelumnya');
  T(0, -1, 'Dark Cloud Cover', 'Merah menembus lebih dari separuh candle hijau sebelumnya');
  T(0, 1, 'Bullish Harami', 'Candle kecil di dalam badan candle merah besar: tekanan turun habis');
  T(0, -1, 'Bearish Harami', 'Candle kecil di dalam badan candle hijau besar: tenaga naik habis');
  T(0, 1, 'Bullish Harami Cross', 'Harami dengan doji di dalam merah besar: pembalikan naik lebih kuat');
  T(0, -1, 'Bearish Harami Cross', 'Harami dengan doji di dalam hijau besar: pembalikan turun lebih kuat');
  T(0, 1, 'Tweezer Bottom', 'Dua candle dengan low sama: dasar kuat, pembeli menahan');
  T(0, -1, 'Tweezer Top', 'Dua candle dengan high sama: puncak kuat, penjual menahan');
  T(0, 1, 'Bullish Counterattack', 'Hijau besar menutup di harga tutup merah besar sebelumnya: serangan balik pembeli');
  T(0, -1, 'Bearish Counterattack', 'Merah besar menutup di harga tutup hijau besar sebelumnya: serangan balik penjual');
  { --- tiga sampai lima candle --- }
  T(0, 1, 'Morning Star', 'Merah besar, candle kecil, hijau besar: pembalikan naik');
  T(0, -1, 'Evening Star', 'Hijau besar, candle kecil, merah besar: pembalikan turun');
  T(0, 1, 'Morning Doji Star', 'Seperti morning star dengan doji di tengah: pembalikan naik kuat');
  T(0, -1, 'Evening Doji Star', 'Seperti evening star dengan doji di tengah: pembalikan turun kuat');
  T(0, 1, 'Three White Soldiers', 'Tiga hijau besar berurutan naik: tren naik baru');
  T(0, -1, 'Three Black Crows', 'Tiga merah besar berurutan turun: tren turun baru');
  T(0, 1, 'Three Inside Up', 'Harami naik lalu hijau ketiga menutup di atas awal merah: konfirmasi naik');
  T(0, -1, 'Three Inside Down', 'Harami turun lalu merah ketiga menutup di bawah awal hijau: konfirmasi turun');
  T(0, 1, 'Three Outside Up', 'Engulfing naik lalu hijau lanjutan: konfirmasi naik');
  T(0, -1, 'Three Outside Down', 'Engulfing turun lalu merah lanjutan: konfirmasi turun');
  T(0, 1, 'Rising Three Methods', 'Hijau besar, tiga koreksi kecil di dalamnya, hijau penutup: tren naik lanjut');
  T(0, -1, 'Falling Three Methods', 'Merah besar, tiga pantulan kecil di dalamnya, merah penutup: tren turun lanjut');
  { --- pola chart --- }
  T(1, 1, 'Double Bottom', 'Dua dasar hampir sama (huruf W), harga menembus neckline: naik');
  T(1, -1, 'Double Top', 'Dua puncak hampir sama (huruf M), harga menembus neckline ke bawah: turun');
  T(1, 1, 'Inverse Head & Shoulders', 'Tiga dasar, tengah paling dalam; tembus neckline ke atas: naik');
  T(1, -1, 'Head & Shoulders', 'Tiga puncak, tengah paling tinggi; tembus neckline ke bawah: turun');
  T(1, 1, 'Ascending Triangle', 'Puncak datar, dasar makin tinggi; harga menekan/menembus atas: naik');
  T(1, -1, 'Descending Triangle', 'Dasar datar, puncak makin rendah; harga menekan/menembus bawah: turun');
  T(1, 1, 'Symmetrical Triangle Naik', 'Segitiga simetris menyempit lalu tembus ke atas');
  T(1, -1, 'Symmetrical Triangle Turun', 'Segitiga simetris menyempit lalu tembus ke bawah');
  T(1, 1, 'Falling Wedge', 'Baji menurun menyempit, tembus ke atas: pembalikan naik');
  T(1, -1, 'Rising Wedge', 'Baji menaik menyempit, tembus ke bawah: pembalikan turun');
  T(1, 1, 'Bull Flag', 'Kenaikan tajam (tiang), konsolidasi sempit, lalu tembus atas: lanjut naik');
  T(1, -1, 'Bear Flag', 'Penurunan tajam (tiang), konsolidasi sempit, lalu tembus bawah: lanjut turun');
  { --- strategi indikator --- }
  T(2, 1, 'EMA 9/21 Golden Cross', 'EMA9 memotong EMA21 ke atas: momentum naik');
  T(2, -1, 'EMA 9/21 Death Cross', 'EMA9 memotong EMA21 ke bawah: momentum turun');
  T(2, 1, 'EMA 5/13 Scalping Naik', 'EMA5 memotong EMA13 ke atas (scalping cepat)');
  T(2, -1, 'EMA 5/13 Scalping Turun', 'EMA5 memotong EMA13 ke bawah (scalping cepat)');
  T(2, 1, 'Harga Tembus MA25 Naik', 'Harga menembus MA25 ke atas');
  T(2, -1, 'Harga Tembus MA25 Turun', 'Harga menembus MA25 ke bawah');
  T(2, 1, 'Harga Tembus MA99 Naik', 'Harga menembus MA99 ke atas: tren menengah berbalik naik');
  T(2, -1, 'Harga Tembus MA99 Turun', 'Harga menembus MA99 ke bawah: tren menengah berbalik turun');
  T(2, 1, 'Harga Tembus MA200 Naik', 'Harga menembus MA200 ke atas: tren besar berbalik naik');
  T(2, -1, 'Harga Tembus MA200 Turun', 'Harga menembus MA200 ke bawah: tren besar berbalik turun');
  T(2, 1, 'RSI Keluar Oversold', 'RSI14 naik kembali melewati 30: jenuh jual selesai');
  T(2, -1, 'RSI Keluar Overbought', 'RSI14 turun kembali melewati 70: jenuh beli selesai');
  T(2, 1, 'Divergence RSI Bullish', 'Harga low lebih rendah tetapi RSI low lebih tinggi: tekanan turun melemah');
  T(2, -1, 'Divergence RSI Bearish', 'Harga high lebih tinggi tetapi RSI high lebih rendah: tenaga naik melemah');
  T(2, 1, 'MACD Cross Naik', 'Garis MACD memotong sinyal ke atas (kuat bila di bawah nol)');
  T(2, -1, 'MACD Cross Turun', 'Garis MACD memotong sinyal ke bawah (kuat bila di atas nol)');
  T(2, 1, 'Pantul Bollinger Bawah', 'Harga kembali masuk dari bawah band Bollinger bawah');
  T(2, -1, 'Tolak Bollinger Atas', 'Harga kembali masuk dari atas band Bollinger atas');
  T(2, 1, 'Bollinger Squeeze Breakout Naik', 'Band menyempit lalu harga menutup di atas band atas');
  T(2, -1, 'Bollinger Squeeze Breakout Turun', 'Band menyempit lalu harga menutup di bawah band bawah');
  T(2, 1, 'Stochastic Cross Oversold', 'Stochastic K memotong D ke atas di area jenuh jual (<20)');
  T(2, -1, 'Stochastic Cross Overbought', 'Stochastic K memotong D ke bawah di area jenuh beli (>80)');
  T(2, 1, 'Breakout Range 20 + Volume', 'Tutup di atas high 20 candle dengan volume 1,5x');
  T(2, -1, 'Breakdown Range 20 + Volume', 'Tutup di bawah low 20 candle dengan volume 1,5x');
  T(2, 1, 'Pullback EMA21 Tren Naik', 'Di tren naik harga menyentuh EMA21 lalu memantul hijau');
  T(2, -1, 'Pullback EMA21 Tren Turun', 'Di tren turun harga menyentuh EMA21 lalu ditolak merah');
  T(2, 1, 'Supertrend Balik Naik', 'Supertrend (ATR10 x3) berbalik ke arah naik');
  T(2, -1, 'Supertrend Balik Turun', 'Supertrend (ATR10 x3) berbalik ke arah turun');
  T(2, 1, 'Ichimoku Tenkan/Kijun Cross Naik', 'Tenkan memotong Kijun ke atas');
  T(2, -1, 'Ichimoku Tenkan/Kijun Cross Turun', 'Tenkan memotong Kijun ke bawah');
  T(2, 1, 'Heikin Ashi Balik Naik', 'Heikin Ashi berganti merah ke hijau setelah 3 candle merah');
  T(2, -1, 'Heikin Ashi Balik Turun', 'Heikin Ashi berganti hijau ke merah setelah 3 candle hijau');
end;

function TheoryDesc(const Name: string): string;
var
  V: string;
  P: Integer;
begin
  V := Theory.Values[Name];
  P := Pos('|', V);
  Delete(V, 1, P);
  P := Pos('|', V);
  Delete(V, 1, P);
  Result := V;
end;

procedure AddHit(var Hits: TPatHits; const Name: string; Str: Integer);
var
  V: string;
  P, N: Integer;
begin
  V := Theory.Values[Name];
  if V = '' then
    Exit;
  N := Length(Hits);
  SetLength(Hits, N + 1);
  Hits[N].Name := Name;
  Hits[N].Str := Str;
  P := Pos('|', V);
  Hits[N].Kind := StrToIntDef(Copy(V, 1, P - 1), 0);
  Delete(V, 1, P);
  P := Pos('|', V);
  Hits[N].Dir := StrToIntDef(Copy(V, 1, P - 1), 0);
end;

{ ---------- Pola candle ---------- }

procedure CandlePat(const K: TKlines; EndIdx: Integer; var Hits: TPatHits);
var
  n, e, p, q, x, c: Integer;
  avgB, avgR, avgV, mn, mx: Double;

  function Body(i: Integer): Double;
  begin Result := Abs(K[i].C - K[i].O); end;
  function Rng(i: Integer): Double;
  begin Result := K[i].H - K[i].L; end;
  function UpW(i: Integer): Double;
  begin Result := K[i].H - Max(K[i].O, K[i].C); end;
  function LoW(i: Integer): Double;
  begin Result := Min(K[i].O, K[i].C) - K[i].L; end;
  function Bull(i: Integer): Boolean;
  begin Result := K[i].C > K[i].O; end;
  function Bear(i: Integer): Boolean;
  begin Result := K[i].C < K[i].O; end;
  function Mid(i: Integer): Double;
  begin Result := (K[i].O + K[i].C) / 2; end;
  function Doji(i: Integer): Boolean;
  begin Result := (Rng(i) > 0) and (Body(i) <= Rng(i) * 0.1); end;
  function Big(i: Integer): Boolean;
  begin Result := (Body(i) >= avgB) and (Body(i) >= Rng(i) * 0.6); end;
  function Small(i: Integer): Boolean;
  begin Result := Body(i) <= avgB * 0.5; end;
  function UpT(s: Integer): Boolean;
  begin Result := (K[s].C > K[s - 4].C) and (K[s].C > K[s - 8].C); end;
  function DnT(s: Integer): Boolean;
  begin Result := (K[s].C < K[s - 4].C) and (K[s].C < K[s - 8].C); end;
  function LowTail(i: Integer): Boolean;
  begin
    Result := (Rng(i) > 0) and (Body(i) >= Rng(i) * 0.1) and (LoW(i) >= 2 * Body(i)) and
      (UpW(i) <= Max(Body(i) * 0.5, Rng(i) * 0.1));
  end;
  function UpTail(i: Integer): Boolean;
  begin
    Result := (Rng(i) > 0) and (Body(i) >= Rng(i) * 0.1) and (UpW(i) >= 2 * Body(i)) and
      (LoW(i) <= Max(Body(i) * 0.5, Rng(i) * 0.1));
  end;

begin
  n := Length(K);
  e := EndIdx;   // candle yang dinilai (harus sudah selesai)
  if (e < 22) or (e > n - 1) then
    Exit;
  p := e - 1;
  q := e - 2;
  avgB := 0;
  avgR := 0;
  for x := e - 14 to e - 1 do
  begin
    avgB := avgB + Body(x);
    avgR := avgR + Rng(x);
  end;
  avgB := avgB / 14;
  avgR := avgR / 14;
  avgV := 0;
  for x := e - 20 to e - 1 do
    avgV := avgV + K[x].QV;
  avgV := avgV / 20;
  if (avgB <= 0) or (avgR <= 0) then
    Exit;

  { tunggal }
  if LowTail(e) then
  begin
    if DnT(p) then AddHit(Hits, 'Hammer', IfThen(Bull(e), 3, 2))
    else if UpT(p) then AddHit(Hits, 'Hanging Man', 2);
  end;
  if UpTail(e) then
  begin
    if DnT(p) then AddHit(Hits, 'Inverted Hammer', 1)
    else if UpT(p) then AddHit(Hits, 'Shooting Star', IfThen(Bear(e), 3, 2));
  end;
  if Doji(e) then
  begin
    if (LoW(e) >= Rng(e) * 0.6) and (UpW(e) <= Rng(e) * 0.1) and DnT(p) then
      AddHit(Hits, 'Dragonfly Doji', 2);
    if (UpW(e) >= Rng(e) * 0.6) and (LoW(e) <= Rng(e) * 0.1) and UpT(p) then
      AddHit(Hits, 'Gravestone Doji', 2);
  end;
  if (Body(e) >= Rng(e) * 0.9) and (Body(e) >= avgB * 1.5) then
  begin
    if Bull(e) then AddHit(Hits, 'Bullish Marubozu', 2)
    else if Bear(e) then AddHit(Hits, 'Bearish Marubozu', 2);
  end;
  mn := MaxDouble;
  mx := 0;
  for x := e - 10 to e - 1 do
  begin
    mn := Min(mn, K[x].L);
    mx := Max(mx, K[x].H);
  end;
  if (Rng(e) > 0) and (Body(e) <= Rng(e) * 0.33) then
  begin
    if (LoW(e) >= Rng(e) * 0.66) and (K[e].L <= mn) then AddHit(Hits, 'Bullish Pin Bar', 3);
    if (UpW(e) >= Rng(e) * 0.66) and (K[e].H >= mx) then AddHit(Hits, 'Bearish Pin Bar', 3);
  end;
  if (avgV > 0) and (K[e].QV >= avgV * 2.5) and Big(e) then
  begin
    if Bull(e) then AddHit(Hits, 'Volume Spike Bullish', 2)
    else if Bear(e) then AddHit(Hits, 'Volume Spike Bearish', 2);
  end;
  if Bull(e) and Big(e) and (Body(e) >= avgB * 1.2) and (LoW(e) <= Rng(e) * 0.03) and DnT(p) then
    AddHit(Hits, 'Bullish Belt Hold', 1);
  if Bear(e) and Big(e) and (Body(e) >= avgB * 1.2) and (UpW(e) <= Rng(e) * 0.03) and UpT(p) then
    AddHit(Hits, 'Bearish Belt Hold', 1);
  if LowTail(p) and DnT(p - 1) and Bull(e) and (K[e].C > K[p].H) then
    AddHit(Hits, 'Hammer Terkonfirmasi', 3);
  if UpTail(p) and UpT(p - 1) and Bear(e) and (K[e].C < K[p].L) then
    AddHit(Hits, 'Shooting Star Terkonfirmasi', 3);

  { dua candle }
  if Bear(p) and Bull(e) and DnT(p) and (K[e].O <= K[p].C) and (K[e].C >= K[p].O) and (Body(e) > Body(p)) then
    AddHit(Hits, 'Bullish Engulfing', 3);
  if Bull(p) and Bear(e) and UpT(p) and (K[e].O >= K[p].C) and (K[e].C <= K[p].O) and (Body(e) > Body(p)) then
    AddHit(Hits, 'Bearish Engulfing', 3);
  if Bear(p) and Big(p) and Bull(e) and DnT(p) and (K[e].O <= K[p].C) and (K[e].C > Mid(p)) and (K[e].C < K[p].O) then
    AddHit(Hits, 'Piercing Line', 2);
  if Bull(p) and Big(p) and Bear(e) and UpT(p) and (K[e].O >= K[p].C) and (K[e].C < Mid(p)) and (K[e].C > K[p].O) then
    AddHit(Hits, 'Dark Cloud Cover', 2);
  if Bear(p) and Big(p) and DnT(p) and (Max(K[e].O, K[e].C) < K[p].O) and (Min(K[e].O, K[e].C) > K[p].C) and
    (Body(e) < Body(p) * 0.6) then
  begin
    if Doji(e) then AddHit(Hits, 'Bullish Harami Cross', 2)
    else if Bull(e) then AddHit(Hits, 'Bullish Harami', 1);
  end;
  if Bull(p) and Big(p) and UpT(p) and (Max(K[e].O, K[e].C) < K[p].C) and (Min(K[e].O, K[e].C) > K[p].O) and
    (Body(e) < Body(p) * 0.6) then
  begin
    if Doji(e) then AddHit(Hits, 'Bearish Harami Cross', 2)
    else if Bear(e) then AddHit(Hits, 'Bearish Harami', 1);
  end;
  if DnT(p) and Bear(p) and Bull(e) and (Abs(K[e].L - K[p].L) <= avgR * 0.1) then
    AddHit(Hits, 'Tweezer Bottom', 2);
  if UpT(p) and Bull(p) and Bear(e) and (Abs(K[e].H - K[p].H) <= avgR * 0.1) then
    AddHit(Hits, 'Tweezer Top', 2);
  if Bear(p) and Big(p) and Bull(e) and Big(e) and DnT(p) and (Abs(K[e].C - K[p].C) <= avgR * 0.1) then
    AddHit(Hits, 'Bullish Counterattack', 1);
  if Bull(p) and Big(p) and Bear(e) and Big(e) and UpT(p) and (Abs(K[e].C - K[p].C) <= avgR * 0.1) then
    AddHit(Hits, 'Bearish Counterattack', 1);

  { tiga candle }
  if Bear(q) and Big(q) and DnT(q) and Small(p) and Bull(e) and (K[e].C > Mid(q)) then
    AddHit(Hits, IfThen(Doji(p), 'Morning Doji Star', 'Morning Star'), 3);
  if Bull(q) and Big(q) and UpT(q) and Small(p) and Bear(e) and (K[e].C < Mid(q)) then
    AddHit(Hits, IfThen(Doji(p), 'Evening Doji Star', 'Evening Star'), 3);
  if Bull(q) and Bull(p) and Bull(e) and (K[p].C > K[q].C) and (K[e].C > K[p].C) and
    (K[p].O >= K[q].O) and (K[p].O <= K[q].C) and (K[e].O >= K[p].O) and (K[e].O <= K[p].C) and
    (Body(q) >= avgB * 0.6) and (Body(p) >= avgB * 0.6) and (Body(e) >= avgB * 0.6) and
    (UpW(q) <= Body(q) * 0.3) and (UpW(p) <= Body(p) * 0.3) and (UpW(e) <= Body(e) * 0.3) then
    AddHit(Hits, 'Three White Soldiers', 3);
  if Bear(q) and Bear(p) and Bear(e) and (K[p].C < K[q].C) and (K[e].C < K[p].C) and
    (K[p].O <= K[q].O) and (K[p].O >= K[q].C) and (K[e].O <= K[p].O) and (K[e].O >= K[p].C) and
    (Body(q) >= avgB * 0.6) and (Body(p) >= avgB * 0.6) and (Body(e) >= avgB * 0.6) and
    (LoW(q) <= Body(q) * 0.3) and (LoW(p) <= Body(p) * 0.3) and (LoW(e) <= Body(e) * 0.3) then
    AddHit(Hits, 'Three Black Crows', 3);
  if Bear(q) and Big(q) and DnT(q) and Bull(p) and (K[p].O > K[q].C) and (K[p].C < K[q].O) and
    (K[p].C >= Mid(q)) and Bull(e) and (K[e].C > K[q].O) then
    AddHit(Hits, 'Three Inside Up', 2);
  if Bull(q) and Big(q) and UpT(q) and Bear(p) and (K[p].O < K[q].C) and (K[p].C > K[q].O) and
    (K[p].C <= Mid(q)) and Bear(e) and (K[e].C < K[q].O) then
    AddHit(Hits, 'Three Inside Down', 2);
  if Bear(q) and DnT(q) and Bull(p) and (K[p].O <= K[q].C) and (K[p].C >= K[q].O) and (Body(p) > Body(q)) and
    Bull(e) and (K[e].C > K[p].C) then
    AddHit(Hits, 'Three Outside Up', 3);
  if Bull(q) and UpT(q) and Bear(p) and (K[p].O >= K[q].C) and (K[p].C <= K[q].O) and (Body(p) > Body(q)) and
    Bear(e) and (K[e].C < K[p].C) then
    AddHit(Hits, 'Three Outside Down', 3);

  { lima candle }
  x := e - 4;
  if Bull(x) and Big(x) and Bull(e) and (K[e].C > K[x].C) then
  begin
    c := 0;
    if (K[e - 3].H <= K[x].H) and (K[e - 3].L >= K[x].L) and (K[e - 2].H <= K[x].H) and (K[e - 2].L >= K[x].L) and
      (K[e - 1].H <= K[x].H) and (K[e - 1].L >= K[x].L) then
      c := 1;
    if (c = 1) and (Ord(Bear(e - 3)) + Ord(Bear(e - 2)) + Ord(Bear(e - 1)) >= 2) then
      AddHit(Hits, 'Rising Three Methods', 2);
  end;
  if Bear(x) and Big(x) and Bear(e) and (K[e].C < K[x].C) then
  begin
    if (K[e - 3].H <= K[x].H) and (K[e - 3].L >= K[x].L) and (K[e - 2].H <= K[x].H) and (K[e - 2].L >= K[x].L) and
      (K[e - 1].H <= K[x].H) and (K[e - 1].L >= K[x].L) and
      (Ord(Bull(e - 3)) + Ord(Bull(e - 2)) + Ord(Bull(e - 1)) >= 2) then
      AddHit(Hits, 'Falling Three Methods', 2);
  end;
end;

{ ---------- Pola chart ---------- }

{ Swing high/low: puncak/lembah dengan 2 candle di kiri dan kanan }
procedure FindSwings(const K: TKlines; HighSide: Boolean; var R: TIntArr);
var
  i, j, n: Integer;
  ok, strict: Boolean;
begin
  SetLength(R, 0);
  n := Length(K);
  for i := Max(2, n - 100) to n - 4 do
  begin
    ok := True;
    strict := False;
    for j := i - 2 to i + 2 do
      if j <> i then
        if HighSide then
        begin
          if K[j].H > K[i].H then ok := False;
          if K[j].H < K[i].H then strict := True;
        end
        else
        begin
          if K[j].L < K[i].L then ok := False;
          if K[j].L > K[i].L then strict := True;
        end;
    if ok and strict then
    begin
      SetLength(R, Length(R) + 1);
      R[High(R)] := i;
    end;
  end;
end;

procedure ChartPat(const K: TKlines; var Hits: TPatHits);
var
  n, e, i, a, b, c, nh, nl: Integer;
  atr, P, neck, la, lb, ha, hb, h1, h2, h3, t1, t2, M, ch, cl: Double;
  HS, LS: TIntArr;
begin
  n := Length(K);
  if n < 40 then
    Exit;
  e := n - 2;
  P := K[e].C;
  atr := 0;
  for i := e - 13 to e do
    atr := atr + (K[i].H - K[i].L);
  atr := atr / 14;
  if atr <= 0 then
    Exit;
  FindSwings(K, True, HS);
  FindSwings(K, False, LS);
  nh := Length(HS);
  nl := Length(LS);

  { double bottom / double top }
  if nl >= 2 then
  begin
    a := LS[nl - 2];
    b := LS[nl - 1];
    la := K[a].L;
    lb := K[b].L;
    if (b - a >= 5) and (n - 1 - b <= 35) and (Abs(la - lb) <= 1.2 * atr) then
    begin
      neck := 0;
      for i := a to b do
        neck := Max(neck, K[i].H);
      if neck - Max(la, lb) >= 2.5 * atr then
      begin
        if P > neck then AddHit(Hits, 'Double Bottom', 3)
        else if P > neck - atr then AddHit(Hits, 'Double Bottom', 1);
      end;
    end;
  end;
  if nh >= 2 then
  begin
    a := HS[nh - 2];
    b := HS[nh - 1];
    ha := K[a].H;
    hb := K[b].H;
    if (b - a >= 5) and (n - 1 - b <= 35) and (Abs(ha - hb) <= 1.2 * atr) then
    begin
      neck := MaxDouble;
      for i := a to b do
        neck := Min(neck, K[i].L);
      if Min(ha, hb) - neck >= 2.5 * atr then
      begin
        if P < neck then AddHit(Hits, 'Double Top', 3)
        else if P < neck + atr then AddHit(Hits, 'Double Top', 1);
      end;
    end;
  end;

  { head & shoulders }
  if nh >= 3 then
  begin
    a := HS[nh - 3];
    b := HS[nh - 2];
    c := HS[nh - 1];
    h1 := K[a].H;
    h2 := K[b].H;
    h3 := K[c].H;
    if (b - a >= 3) and (c - b >= 3) and (n - 1 - c <= 35) and (h2 > h1 + atr) and (h2 > h3 + atr) and
      (Abs(h1 - h3) <= 2 * atr) then
    begin
      t1 := MaxDouble;
      t2 := MaxDouble;
      for i := a to b do t1 := Min(t1, K[i].L);
      for i := b to c do t2 := Min(t2, K[i].L);
      neck := (t1 + t2) / 2;
      if P < neck then AddHit(Hits, 'Head & Shoulders', 3)
      else if P < neck + 0.5 * atr then AddHit(Hits, 'Head & Shoulders', 1);
    end;
  end;
  if nl >= 3 then
  begin
    a := LS[nl - 3];
    b := LS[nl - 2];
    c := LS[nl - 1];
    h1 := K[a].L;
    h2 := K[b].L;
    h3 := K[c].L;
    if (b - a >= 3) and (c - b >= 3) and (n - 1 - c <= 35) and (h2 < h1 - atr) and (h2 < h3 - atr) and
      (Abs(h1 - h3) <= 2 * atr) then
    begin
      t1 := 0;
      t2 := 0;
      for i := a to b do t1 := Max(t1, K[i].H);
      for i := b to c do t2 := Max(t2, K[i].H);
      neck := (t1 + t2) / 2;
      if P > neck then AddHit(Hits, 'Inverse Head & Shoulders', 3)
      else if P > neck - 0.5 * atr then AddHit(Hits, 'Inverse Head & Shoulders', 1);
    end;
  end;

  { segitiga & wedge dari dua puncak + dua lembah terakhir }
  if (nh >= 2) and (nl >= 2) then
  begin
    ha := K[HS[nh - 2]].H;
    hb := K[HS[nh - 1]].H;
    la := K[LS[nl - 2]].L;
    lb := K[LS[nl - 1]].L;
    if (HS[nh - 1] - HS[nh - 2] >= 3) and (LS[nl - 1] - LS[nl - 2] >= 3) and
      (n - 1 - HS[nh - 1] <= 35) and (n - 1 - LS[nl - 1] <= 35) then
    begin
      if (Abs(hb - ha) <= 0.8 * atr) and (lb > la + 0.8 * atr) and (P >= hb - 0.3 * atr) then
        AddHit(Hits, 'Ascending Triangle', IfThen(P > hb, 3, 2));
      if (Abs(lb - la) <= 0.8 * atr) and (hb < ha - 0.8 * atr) and (P <= lb + 0.3 * atr) then
        AddHit(Hits, 'Descending Triangle', IfThen(P < lb, 3, 2));
      if (hb < ha - 0.8 * atr) and (lb > la + 0.8 * atr) then
      begin
        if P > hb then AddHit(Hits, 'Symmetrical Triangle Naik', 2)
        else if P < lb then AddHit(Hits, 'Symmetrical Triangle Turun', 2);
      end;
      if (hb < ha - 0.5 * atr) and (lb < la - 0.5 * atr) and (hb - lb < (ha - la) * 0.8) and (P > hb) then
        AddHit(Hits, 'Falling Wedge', 3);
      if (hb > ha + 0.5 * atr) and (lb > la + 0.5 * atr) and (hb - lb < (ha - la) * 0.8) and (P < lb) then
        AddHit(Hits, 'Rising Wedge', 3);
    end;
  end;

  { bull / bear flag }
  M := K[e - 6].C - K[e - 16].C;
  ch := 0;
  cl := MaxDouble;
  for i := e - 5 to e - 1 do
  begin
    ch := Max(ch, K[i].H);
    cl := Min(cl, K[i].L);
  end;
  if (M >= 6 * atr) and (ch - cl <= M * 0.5) and (P > ch) then
    AddHit(Hits, 'Bull Flag', 3);
  if (M <= -6 * atr) and (ch - cl <= -M * 0.5) and (P < cl) then
    AddHit(Hits, 'Bear Flag', 3);
end;

{ ---------- Strategi indikator ---------- }

function EMAOf(const X: TDoubleArray; Period: Integer): TDoubleArray;
var
  i: Integer;
  a: Double;
begin
  SetLength(Result, Length(X));
  a := 2 / (Period + 1);
  for i := 0 to High(X) do
    if i = 0 then Result[i] := X[i]
    else Result[i] := Result[i - 1] + a * (X[i] - Result[i - 1]);
end;

function CrossAt(const A, B: TDoubleArray; i: Integer): Integer;
begin
  Result := 0;
  if i < 1 then
    Exit;
  if (A[i - 1] <= B[i - 1]) and (A[i] > B[i]) then Result := 1
  else if (A[i - 1] >= B[i - 1]) and (A[i] < B[i]) then Result := -1;
end;

{ persilangan pada candle selesai terakhir atau sebelumnya }
function CrossRecent(const A, B: TDoubleArray; e: Integer): Integer;
begin
  Result := CrossAt(A, B, e);
  if Result = 0 then
    Result := CrossAt(A, B, e - 1);
end;

procedure StratPat(const K: TKlines; var Hits: TPatHits);
var
  n, e, p, i, j, c, nl, nh: Integer;
  Cl, E5, E9, E13, E21, E50, E12, E26, Macd, Sig, Rsi, Ten, Kij, Kraw, Ks, Ds, Ub, Lb, Fub, Flb, Atr, Haa: TDoubleArray;
  Tr: array of Integer;
  a, g, l, d, sum, sd, mid, up, lo, bw, minbw, hh, ll, avgV, ho, hc, tp: Double;
  LS, HS: TIntArr;

  function SMAAt(Period, idx: Integer): Double;
  var
    x: Integer;
  begin
    Result := 0;
    if idx - Period + 1 < 0 then
      Exit;
    for x := idx - Period + 1 to idx do
      Result := Result + K[x].C;
    Result := Result / Period;
  end;

  procedure BB(idx: Integer; var Mn, U, Lw, W: Double);
  var
    x: Integer;
    s2: Double;
  begin
    Mn := SMAAt(20, idx);
    s2 := 0;
    for x := idx - 19 to idx do
      s2 := s2 + Sqr(K[x].C - Mn);
    s2 := Sqrt(s2 / 20);
    U := Mn + 2 * s2;
    Lw := Mn - 2 * s2;
    if Mn > 0 then W := 4 * s2 / Mn else W := 0;
  end;

  procedure PriceMA(Period: Integer; const NmUp, NmDn: string);
  var
    x: Integer;
    s0, s1: Double;
    done: Boolean;
  begin
    if n < Period + 4 then
      Exit;
    done := False;
    for x := e downto e - 1 do
    begin
      if done then Break;
      s0 := SMAAt(Period, x - 1);
      s1 := SMAAt(Period, x);
      if (K[x - 1].C <= s0) and (K[x].C > s1) then
      begin AddHit(Hits, NmUp, 2); done := True; end
      else if (K[x - 1].C >= s0) and (K[x].C < s1) then
      begin AddHit(Hits, NmDn, 2); done := True; end;
    end;
  end;

begin
  n := Length(K);
  if n < 60 then
    Exit;
  e := n - 2;
  p := e - 1;
  SetLength(Cl, n);
  for i := 0 to n - 1 do
    Cl[i] := K[i].C;
  E5 := EMAOf(Cl, 5);
  E9 := EMAOf(Cl, 9);
  E13 := EMAOf(Cl, 13);
  E21 := EMAOf(Cl, 21);
  E50 := EMAOf(Cl, 50);
  E12 := EMAOf(Cl, 12);
  E26 := EMAOf(Cl, 26);

  { EMA cross }
  c := CrossRecent(E9, E21, e);
  if c > 0 then AddHit(Hits, 'EMA 9/21 Golden Cross', 2)
  else if c < 0 then AddHit(Hits, 'EMA 9/21 Death Cross', 2);
  c := CrossRecent(E5, E13, e);
  if c > 0 then AddHit(Hits, 'EMA 5/13 Scalping Naik', 1)
  else if c < 0 then AddHit(Hits, 'EMA 5/13 Scalping Turun', 1);

  { harga vs MA }
  PriceMA(25, 'Harga Tembus MA25 Naik', 'Harga Tembus MA25 Turun');
  PriceMA(99, 'Harga Tembus MA99 Naik', 'Harga Tembus MA99 Turun');
  PriceMA(200, 'Harga Tembus MA200 Naik', 'Harga Tembus MA200 Turun');

  { RSI 14 (Wilder) }
  SetLength(Rsi, n);
  g := 0;
  l := 0;
  for i := 0 to n - 1 do
  begin
    Rsi[i] := 50;
    if i = 0 then Continue;
    d := Cl[i] - Cl[i - 1];
    if i <= 14 then
    begin
      g := g + Max(d, 0);
      l := l + Max(-d, 0);
      if i = 14 then
      begin
        g := g / 14;
        l := l / 14;
      end;
    end
    else
    begin
      g := (g * 13 + Max(d, 0)) / 14;
      l := (l * 13 + Max(-d, 0)) / 14;
    end;
    if i >= 14 then
      if l = 0 then Rsi[i] := 100 else Rsi[i] := 100 - 100 / (1 + g / l);
  end;
  if ((Rsi[p] < 30) and (Rsi[e] >= 30)) or ((Rsi[p - 1] < 30) and (Rsi[p] >= 30)) then
    AddHit(Hits, 'RSI Keluar Oversold', 2)
  else if ((Rsi[p] > 70) and (Rsi[e] <= 70)) or ((Rsi[p - 1] > 70) and (Rsi[p] <= 70)) then
    AddHit(Hits, 'RSI Keluar Overbought', 2);
  FindSwings(K, False, LS);
  FindSwings(K, True, HS);
  nl := Length(LS);
  nh := Length(HS);
  if nl >= 2 then
    if (LS[nl - 1] - LS[nl - 2] >= 4) and (n - 1 - LS[nl - 1] <= 25) and (K[LS[nl - 1]].L < K[LS[nl - 2]].L) and
      (Rsi[LS[nl - 1]] > Rsi[LS[nl - 2]] + 2) and (Rsi[LS[nl - 2]] < 40) then
      AddHit(Hits, 'Divergence RSI Bullish', 3);
  if nh >= 2 then
    if (HS[nh - 1] - HS[nh - 2] >= 4) and (n - 1 - HS[nh - 1] <= 25) and (K[HS[nh - 1]].H > K[HS[nh - 2]].H) and
      (Rsi[HS[nh - 1]] < Rsi[HS[nh - 2]] - 2) and (Rsi[HS[nh - 2]] > 60) then
      AddHit(Hits, 'Divergence RSI Bearish', 3);

  { MACD 12/26/9 }
  SetLength(Macd, n);
  for i := 0 to n - 1 do
    Macd[i] := E12[i] - E26[i];
  Sig := EMAOf(Macd, 9);
  c := CrossRecent(Macd, Sig, e);
  if c > 0 then AddHit(Hits, 'MACD Cross Naik', IfThen(Macd[e] < 0, 3, 2))
  else if c < 0 then AddHit(Hits, 'MACD Cross Turun', IfThen(Macd[e] > 0, 3, 2));

  { Bollinger 20,2 }
  BB(e, mid, up, lo, bw);
  BB(p, a, hh, ll, d);   // a/hh/ll/d = tengah, atas, bawah, lebar candle sebelumnya
  if (K[p].C < ll) and (K[e].C > lo) then AddHit(Hits, 'Pantul Bollinger Bawah', 2)
  else if (K[p].C > hh) and (K[e].C < up) then AddHit(Hits, 'Tolak Bollinger Atas', 2);
  minbw := MaxDouble;
  for i := e - 20 to e - 1 do
  begin
    BB(i, sum, sd, tp, ho);
    minbw := Min(minbw, ho);
  end;
  if (d > 0) and (d <= minbw * 1.1) then
  begin
    if K[e].C > up then AddHit(Hits, 'Bollinger Squeeze Breakout Naik', 3)
    else if K[e].C < lo then AddHit(Hits, 'Bollinger Squeeze Breakout Turun', 3);
  end;

  { Stochastic 14,3,3 }
  SetLength(Kraw, n);
  SetLength(Ks, n);
  SetLength(Ds, n);
  for i := 0 to n - 1 do
  begin
    Kraw[i] := 50;
    Ks[i] := 50;
    Ds[i] := 50;
  end;
  for i := 13 to n - 1 do
  begin
    hh := 0;
    ll := MaxDouble;
    for j := i - 13 to i do
    begin
      hh := Max(hh, K[j].H);
      ll := Min(ll, K[j].L);
    end;
    if hh > ll then Kraw[i] := (Cl[i] - ll) / (hh - ll) * 100;
  end;
  for i := 15 to n - 1 do
    Ks[i] := (Kraw[i] + Kraw[i - 1] + Kraw[i - 2]) / 3;
  for i := 17 to n - 1 do
    Ds[i] := (Ks[i] + Ks[i - 1] + Ks[i - 2]) / 3;
  c := CrossRecent(Ks, Ds, e);
  if (c > 0) and (Ks[e] < 25) then AddHit(Hits, 'Stochastic Cross Oversold', 2)
  else if (c < 0) and (Ks[e] > 75) then AddHit(Hits, 'Stochastic Cross Overbought', 2);

  { breakout / breakdown range 20 + volume }
  hh := 0;
  ll := MaxDouble;
  avgV := 0;
  for i := e - 20 to e - 1 do
  begin
    hh := Max(hh, K[i].H);
    ll := Min(ll, K[i].L);
    avgV := avgV + K[i].QV;
  end;
  avgV := avgV / 20;
  if (avgV > 0) and (K[e].QV >= avgV * 1.5) then
  begin
    if K[e].C > hh then AddHit(Hits, 'Breakout Range 20 + Volume', 3)
    else if K[e].C < ll then AddHit(Hits, 'Breakdown Range 20 + Volume', 3);
  end;

  { pullback ke EMA21 mengikuti tren }
  if (E21[e] > E50[e]) and (E50[e] > E50[e - 5]) and (K[e].L <= E21[e] * 1.001) and (K[e].C > E21[e]) and
    (K[e].C > K[e].O) then
    AddHit(Hits, 'Pullback EMA21 Tren Naik', 2);
  if (E21[e] < E50[e]) and (E50[e] < E50[e - 5]) and (K[e].H >= E21[e] * 0.999) and (K[e].C < E21[e]) and
    (K[e].C < K[e].O) then
    AddHit(Hits, 'Pullback EMA21 Tren Turun', 2);

  { Supertrend ATR10 x3 }
  SetLength(Atr, n);
  SetLength(Ub, n);
  SetLength(Lb, n);
  SetLength(Fub, n);
  SetLength(Flb, n);
  SetLength(Tr, n);
  for i := 0 to n - 1 do
  begin
    if i = 0 then
      d := K[i].H - K[i].L
    else
      d := Max(K[i].H - K[i].L, Max(Abs(K[i].H - K[i - 1].C), Abs(K[i].L - K[i - 1].C)));
    if i = 0 then Atr[i] := d
    else Atr[i] := (Atr[i - 1] * 9 + d) / 10;
    Ub[i] := (K[i].H + K[i].L) / 2 + 3 * Atr[i];
    Lb[i] := (K[i].H + K[i].L) / 2 - 3 * Atr[i];
    if i = 0 then
    begin
      Fub[i] := Ub[i];
      Flb[i] := Lb[i];
      Tr[i] := 1;
    end
    else
    begin
      if (Ub[i] < Fub[i - 1]) or (Cl[i - 1] > Fub[i - 1]) then Fub[i] := Ub[i] else Fub[i] := Fub[i - 1];
      if (Lb[i] > Flb[i - 1]) or (Cl[i - 1] < Flb[i - 1]) then Flb[i] := Lb[i] else Flb[i] := Flb[i - 1];
      Tr[i] := Tr[i - 1];
      if (Tr[i - 1] = -1) and (Cl[i] > Fub[i - 1]) then Tr[i] := 1
      else if (Tr[i - 1] = 1) and (Cl[i] < Flb[i - 1]) then Tr[i] := -1;
    end;
  end;
  begin
    if ((Tr[e] = 1) and (Tr[e - 1] = -1)) or ((Tr[p] = 1) and (Tr[p - 1] = -1)) then
      AddHit(Hits, 'Supertrend Balik Naik', 2)
    else if ((Tr[e] = -1) and (Tr[e - 1] = 1)) or ((Tr[p] = -1) and (Tr[p - 1] = 1)) then
      AddHit(Hits, 'Supertrend Balik Turun', 2);
  end;

  { Ichimoku Tenkan 9 / Kijun 26 }
  SetLength(Ten, n);
  SetLength(Kij, n);
  for i := 0 to n - 1 do
  begin
    Ten[i] := Cl[i];
    Kij[i] := Cl[i];
    if i >= 25 then
    begin
      hh := 0; ll := MaxDouble;
      for j := i - 8 to i do begin hh := Max(hh, K[j].H); ll := Min(ll, K[j].L); end;
      Ten[i] := (hh + ll) / 2;
      hh := 0; ll := MaxDouble;
      for j := i - 25 to i do begin hh := Max(hh, K[j].H); ll := Min(ll, K[j].L); end;
      Kij[i] := (hh + ll) / 2;
    end;
  end;
  c := CrossRecent(Ten, Kij, e);
  if c > 0 then AddHit(Hits, 'Ichimoku Tenkan/Kijun Cross Naik', 2)
  else if c < 0 then AddHit(Hits, 'Ichimoku Tenkan/Kijun Cross Turun', 2);

  { Heikin Ashi: 3 candle satu warna lalu berbalik }
  SetLength(Haa, n);   // Haa = open HA; close HA dihitung langsung
  ho := (K[0].O + K[0].C) / 2;
  for i := 0 to n - 1 do
  begin
    hc := (K[i].O + K[i].H + K[i].L + K[i].C) / 4;
    if i > 0 then
      ho := (Haa[i - 1] + tp) / 2;
    Haa[i] := ho;
    tp := hc;   // tp = close HA candle ini (dipakai candle berikutnya)
    if i = e then
    begin
      a := hc - ho;   // a > 0 hijau
      g := ho;
    end;
    if i = p then d := hc - ho;
    if i = p - 1 then l := hc - ho;
    if i = p - 2 then sum := hc - ho;
  end;
  if (a > 0) and (d < 0) and (l < 0) and (sum < 0) then AddHit(Hits, 'Heikin Ashi Balik Naik', 2)
  else if (a < 0) and (d > 0) and (l > 0) and (sum > 0) then AddHit(Hits, 'Heikin Ashi Balik Turun', 2);
end;

function DetectPatterns(const K: TKlines): TPatHits;
begin
  SetLength(Result, 0);
  try CandlePat(K, Length(K) - 2, Result); except end;
  try ChartPat(K, Result); except end;
  try StratPat(K, Result); except end;
end;

{ ---------- Thread scan ---------- }

type
  TCandleData = class
  public
    Sym, TF: string;
    Price, Time: Double;
    Hits: TPatHits;
    Last: Boolean;
  end;

  TCandleThread = class(TThread)
  private
    FWnd: HWND;
    FSyms: array of string;
  protected
    procedure Execute; override;
  public
    constructor Create(AWnd: HWND; const Syms: TSymArr);
  end;

constructor TCandleThread.Create(AWnd: HWND; const Syms: TSymArr);
var
  I: Integer;
begin
  FWnd := AWnd;
  SetLength(FSyms, Length(Syms));
  for I := 0 to High(Syms) do
    FSyms[I] := Syms[I];
  FreeOnTerminate := True;
  inherited Create(False);
end;

procedure TCandleThread.Execute;
var
  I, T: Integer;
  D: TCandleData;
  K: TKlines;
begin
  EnsureSource;
  for I := 0 to High(FSyms) do
  begin
    if Terminated then
      Break;
    for T := 0 to CandleTFCount - 1 do
    begin
      D := TCandleData.Create;
      D.Sym := FSyms[I];
      D.TF := CandleTFApi[T];
      try
        K := GetKlines(FSyms[I], CandleTFApi[T], 210);
        if Length(K) > 2 then
        begin
          D.Price := K[High(K)].C;
          D.Time := K[Length(K) - 2].OpenTime;
          D.Hits := DetectPatterns(K);
        end;
      except
      end;
      PostObj(FWnd, WM_FT_CANDLE, D);
      Sleep(60);
    end;
  end;
  D := TCandleData.Create;
  D.Last := True;
  PostObj(FWnd, WM_FT_CANDLE, D);
end;

{ ---------- Gambar pola ---------- }

var
  Shapes: TStringList;   // Nama=konteks|pola  (candle: o,h,l,c;...  chart: x,y;...|garis)

procedure Sh(const Name, Ctx, Pat: string);
begin
  Shapes.Add(Name + '=' + Ctx + '|' + Pat);
end;

procedure BuildShapes;
const
  Dn = '80,82,70,72;72,74,62,64';   // konteks tren turun
  Up = '20,30,18,28;28,38,26,36';   // konteks tren naik
begin
  Shapes := TStringList.Create;
  Sh('Hammer', Dn, '48,60,20,58');
  Sh('Inverted Hammer', Dn, '50,86,48,60');
  Sh('Hanging Man', Up, '40,50,12,48');
  Sh('Shooting Star', Up, '52,84,44,46');
  Sh('Dragonfly Doji', Dn, '50,51,20,50');
  Sh('Gravestone Doji', Up, '40,72,39,40');
  Sh('Bullish Marubozu', Dn, '30,80,30,80');
  Sh('Bearish Marubozu', Up, '80,80,30,30');
  Sh('Bullish Pin Bar', Dn, '48,56,10,54');
  Sh('Bearish Pin Bar', Up, '44,84,38,40');
  Sh('Volume Spike Bullish', '50,52,48,51;51,53,49,50', '50,90,48,88');
  Sh('Volume Spike Bearish', '50,52,48,51;51,53,49,50', '50,52,10,12');
  Sh('Bullish Belt Hold', Dn, '40,80,40,78');
  Sh('Bearish Belt Hold', Up, '70,70,30,32');
  Sh('Hammer Terkonfirmasi', Dn, '48,58,20,56;56,82,54,80');
  Sh('Shooting Star Terkonfirmasi', Up, '52,84,44,46;44,46,14,16');
  Sh('Bullish Engulfing', Dn, '62,63,52,54;50,70,48,68');
  Sh('Bearish Engulfing', Up, '38,48,36,46;50,52,30,32');
  Sh('Piercing Line', Dn, '70,71,50,52;46,66,45,64');
  Sh('Dark Cloud Cover', Up, '30,50,29,48;54,55,34,36');
  Sh('Bullish Harami', Dn, '70,71,40,42;50,58,48,56');
  Sh('Bearish Harami', Up, '30,60,29,58;52,55,45,47');
  Sh('Bullish Harami Cross', Dn, '70,71,40,42;55,60,50,55');
  Sh('Bearish Harami Cross', Up, '30,60,29,58;45,50,40,45');
  Sh('Tweezer Bottom', Dn, '60,62,30,34;34,60,30,56');
  Sh('Tweezer Top', Up, '40,70,38,66;66,70,40,44');
  Sh('Bullish Counterattack', Dn, '70,71,40,42;20,43,18,42');
  Sh('Bearish Counterattack', Up, '30,60,29,58;80,82,56,58');
  Sh('Morning Star', Dn, '75,76,45,47;38,42,34,36;40,72,38,70');
  Sh('Evening Star', Up, '30,60,29,58;66,70,62,64;60,62,30,32');
  Sh('Morning Doji Star', Dn, '75,76,45,47;38,42,34,38;40,72,38,70');
  Sh('Evening Doji Star', Up, '30,60,29,58;66,70,62,66;60,62,30,32');
  Sh('Three White Soldiers', Dn, '30,50,28,48;44,64,42,62;58,78,56,76');
  Sh('Three Black Crows', Up, '70,72,50,52;56,58,36,38;42,44,22,24');
  Sh('Three Inside Up', Dn, '75,76,45,47;52,66,50,64;64,80,62,78');
  Sh('Three Inside Down', Up, '30,60,29,58;54,56,40,42;40,42,20,22');
  Sh('Three Outside Up', Dn, '60,62,50,52;48,68,46,66;66,82,64,80');
  Sh('Three Outside Down', Up, '40,50,38,48;52,54,30,32;32,34,14,16');
  Sh('Rising Three Methods', '', '30,70,28,68;66,68,58,60;60,62,52,54;56,58,48,50;52,86,50,84');
  Sh('Falling Three Methods', '', '70,72,30,32;34,42,32,40;40,48,38,46;44,52,42,50;48,50,10,12');
  { pola chart: garis harga | garis bantu (neckline / trendline) }
  Sh('Double Bottom', '', '0,80;15,20;30,60;45,20;60,60;80,92|15,60,95,60');
  Sh('Double Top', '', '0,20;15,80;30,40;45,80;60,40;80,8|15,40,95,40');
  Sh('Inverse Head & Shoulders', '', '0,70;12,40;24,65;40,15;56,65;68,40;80,70;95,92|24,65,95,65');
  Sh('Head & Shoulders', '', '0,30;12,60;24,35;40,85;56,35;68,60;80,30;95,8|24,35,95,35');
  Sh('Ascending Triangle', '', '0,20;15,70;30,35;45,70;60,48;75,70;92,92|15,70,80,70/30,35,75,62');
  Sh('Descending Triangle', '', '0,80;15,30;30,65;45,30;60,52;75,30;92,8|15,30,80,30/30,65,75,40');
  Sh('Symmetrical Triangle Naik', '', '0,50;10,90;25,15;40,75;52,30;62,60;70,45;95,92|10,90,70,52/25,15,70,48');
  Sh('Symmetrical Triangle Turun', '', '0,50;10,10;25,85;40,25;52,70;62,40;70,55;95,8|10,10,70,48/25,85,70,55');
  Sh('Falling Wedge', '', '0,90;12,70;22,82;40,50;50,62;65,40;72,45;95,88|0,92,70,48/12,68,70,36');
  Sh('Rising Wedge', '', '0,10;12,30;22,18;40,50;50,38;65,60;72,55;95,8|0,8,70,52/12,32,70,64');
  Sh('Bull Flag', '', '0,10;25,85;32,75;40,80;48,68;56,74;64,62;90,95|25,88,62,66/32,72,62,52');
  Sh('Bear Flag', '', '0,90;25,15;32,25;40,20;48,32;56,26;64,38;90,5|25,12,62,34/32,28,62,48');
end;

{ pecah S pada pemisah Sep ke dalam L }
procedure SplitTo(const S: string; Sep: Char; L: TStringList);
var
  I, St: Integer;
begin
  L.Clear;
  St := 1;
  for I := 1 to Length(S) + 1 do
    if (I > Length(S)) or (S[I] = Sep) then
    begin
      if I > St then
        L.Add(Copy(S, St, I - St));
      St := I + 1;
    end;
end;

{ ambil bilangan bulat dipisah koma ke A }
procedure ParseInts(const S: string; var A: array of Integer);
var
  L: TStringList;
  I: Integer;
begin
  L := TStringList.Create;
  try
    SplitTo(S, ',', L);
    for I := 0 to High(A) do
      if I < L.Count then A[I] := StrToIntDef(L[I], 0) else A[I] := 0;
  finally
    L.Free;
  end;
end;

function TheoryField(const Name: string; Field: Integer): Integer;
var
  V: string;
  P: Integer;
begin
  V := Theory.Values[Name];
  P := Pos('|', V);
  if Field = 0 then
    Result := StrToIntDef(Copy(V, 1, P - 1), 0)
  else
  begin
    Delete(V, 1, P);
    P := Pos('|', V);
    Result := StrToIntDef(Copy(V, 1, P - 1), 0);
  end;
end;

function CountItems(const S: string): Integer;
var
  L: TStringList;
begin
  L := TStringList.Create;
  try
    SplitTo(S, ';', L);
    Result := L.Count;
  finally
    L.Free;
  end;
end;

procedure DrawCandleList(C: TCanvas; R: TRect; const S: string; Dim: Boolean; Start, Total: Integer);
var
  L: TStringList;
  I: Integer;
  A: array[0..3] of Integer;
  Slot: Double;
  Bw, Xc, Yo, Yc, Yh, Yl, Hgt: Integer;

  function PY(V: Integer): Integer;
  begin
    Result := R.Bottom - 8 - Round(V / 100 * Hgt);
  end;

begin
  if S = '' then
    Exit;
  Hgt := R.Bottom - R.Top - 16;
  Slot := (R.Right - R.Left - 16) / Total;
  Bw := Max(5, Min(26, Round(Slot * 0.55)));
  L := TStringList.Create;
  try
    SplitTo(S, ';', L);
    for I := 0 to L.Count - 1 do
    begin
      ParseInts(L[I], A);   // o,h,l,c
      Xc := R.Left + 8 + Round(Slot * (Start + I + 0.5));
      Yh := PY(A[1]);
      Yl := PY(A[2]);
      Yo := PY(A[0]);
      Yc := PY(A[3]);
      if A[3] >= A[0] then
      begin
        if Dim then begin C.Pen.Color := clrDim; C.Brush.Color := clrUpFill; end
        else begin C.Pen.Color := clrUp; C.Brush.Color := clrUp; end;
      end
      else
      begin
        if Dim then begin C.Pen.Color := clrDim; C.Brush.Color := clrDownFill; end
        else begin C.Pen.Color := clrDown; C.Brush.Color := clrDown; end;
      end;
      C.Pen.Width := 1;
      C.Pen.Style := psSolid;
      C.MoveTo(Xc, Yh);
      C.LineTo(Xc, Yl);
      if Abs(Yo - Yc) < 3 then
      begin
        C.Pen.Width := 2;
        C.MoveTo(Xc - Bw div 2, (Yo + Yc) div 2);
        C.LineTo(Xc + Bw div 2 + 1, (Yo + Yc) div 2);
        C.Pen.Width := 1;
      end
      else
        C.Rectangle(Xc - Bw div 2, Min(Yo, Yc), Xc + Bw div 2 + 1, Max(Yo, Yc));
    end;
  finally
    L.Free;
  end;
end;

{ gambar ilustrasi pola di kotak R: candle mini (jenis 0), garis harga + garis
  bantu (jenis 1), atau dua garis yang bersilang (strategi) }
procedure DrawPatternArt(C: TCanvas; R: TRect; const Name: string; Kind, Dir: Integer);
var
  V, Ctx, Pat, Aux: string;
  P: Integer;
  L: TStringList;
  I, N1, N2: Integer;
  A: array[0..3] of Integer;
  Col: TColor;
  W, H: Integer;

  function PX(X: Integer): Integer;
  begin
    Result := R.Left + 8 + Round(X / 100 * (W - 16));
  end;

  function PY(Y: Integer): Integer;
  begin
    Result := R.Bottom - 8 - Round(Y / 100 * (H - 16));
  end;

begin
  C.Brush.Style := bsSolid;
  C.Brush.Color := clrBg;
  C.Pen.Color := clrBorder;
  C.Pen.Width := 1;
  C.Pen.Style := psSolid;
  C.Rectangle(R.Left, R.Top, R.Right, R.Bottom);
  W := R.Right - R.Left;
  H := R.Bottom - R.Top;
  if Dir > 0 then Col := clrUp else Col := clrDown;
  V := Shapes.Values[Name];
  P := Pos('|', V);
  if Kind = 0 then
  begin
    if P = 0 then Exit;
    Ctx := Copy(V, 1, P - 1);
    Pat := Copy(V, P + 1, MaxInt);
    N1 := CountItems(Ctx);
    N2 := CountItems(Pat);
    DrawCandleList(C, R, Ctx, True, 0, N1 + N2);
    DrawCandleList(C, R, Pat, False, N1, N1 + N2);
  end
  else if Kind = 1 then
  begin
    if P = 0 then Exit;
    Delete(V, 1, P);   // buang konteks (kosong untuk pola chart)
    P := Pos('|', V);
    if P = 0 then Exit;
    Pat := Copy(V, 1, P - 1);
    Aux := Copy(V, P + 1, MaxInt);
    L := TStringList.Create;
    try
      SplitTo(Aux, '/', L);
      C.Pen.Style := psDash;
      C.Pen.Color := clrGold;
      C.Pen.Width := 1;
      for I := 0 to L.Count - 1 do
      begin
        ParseInts(L[I], A);   // x1,y1,x2,y2
        C.MoveTo(PX(A[0]), PY(A[1]));
        C.LineTo(PX(A[2]), PY(A[3]));
      end;
      C.Pen.Style := psSolid;
      C.Pen.Color := Col;
      C.Pen.Width := 2;
      SplitTo(Pat, ';', L);
      for I := 0 to L.Count - 1 do
      begin
        ParseInts(L[I], A);
        if I = 0 then C.MoveTo(PX(A[0]), PY(A[1])) else C.LineTo(PX(A[0]), PY(A[1]));
      end;
      C.Brush.Color := Col;
      C.Pen.Width := 1;
      C.Ellipse(PX(A[0]) - 4, PY(A[1]) - 4, PX(A[0]) + 5, PY(A[1]) + 5);
    finally
      L.Free;
    end;
  end
  else
  begin
    // strategi: garis lambat (abu) dan garis cepat yang memotongnya
    C.Pen.Style := psSolid;
    C.Pen.Width := 2;
    C.Pen.Color := clrDim;
    C.MoveTo(PX(5), PY(50));
    C.LineTo(PX(95), PY(52));
    C.Pen.Color := Col;
    if Dir > 0 then
    begin
      C.MoveTo(PX(5), PY(18));
      C.LineTo(PX(50), PY(50));
      C.LineTo(PX(95), PY(88));
    end
    else
    begin
      C.MoveTo(PX(5), PY(82));
      C.LineTo(PX(50), PY(50));
      C.LineTo(PX(95), PY(12));
    end;
    C.Brush.Color := clrGold;
    C.Pen.Width := 1;
    C.Pen.Color := clrGold;
    C.Ellipse(PX(50) - 4, PY(50) - 4, PX(50) + 5, PY(50) + 5);
  end;
end;

{ satu kartu galeri / pratinjau: gambar, nama, label bullish/bearish, arti }
procedure DrawCard(C: TCanvas; R: TRect; const Name: string; ArtH: Integer);
var
  Kd, Dir: Integer;
  Txt: string;
  TR: TRect;
begin
  Kd := TheoryField(Name, 0);
  Dir := TheoryField(Name, 1);
  C.Brush.Style := bsSolid;
  C.Brush.Color := clrPanel;
  C.Pen.Color := clrBorder;
  C.Pen.Width := 1;
  C.Pen.Style := psSolid;
  C.Rectangle(R.Left, R.Top, R.Right, R.Bottom);
  DrawPatternArt(C, Rect(R.Left + 6, R.Top + 6, R.Right - 6, R.Top + 6 + ArtH), Name, Kd, Dir);
  C.Brush.Style := bsClear;
  C.Font.Name := 'Segoe UI';
  C.Font.Size := 10;
  C.Font.Style := [fsBold];
  C.Font.Color := clrText;
  C.TextOut(R.Left + 8, R.Top + ArtH + 12, Name);
  C.Font.Size := 9;
  if Dir > 0 then
  begin
    C.Font.Color := clrUp;
    Txt := 'BULLISH  -  sinyal BELI';
  end
  else
  begin
    C.Font.Color := clrDown;
    Txt := 'BEARISH  -  sinyal JUAL';
  end;
  C.TextOut(R.Left + 8, R.Top + ArtH + 32, Txt);
  C.Font.Style := [];
  C.Font.Size := 8;
  C.Font.Color := clrDim;
  TR := Rect(R.Left + 8, R.Top + ArtH + 52, R.Right - 8, R.Bottom - 4);
  Txt := TheoryDesc(Name);
  DrawText(C.Handle, PChar(Txt), Length(Txt), TR, DT_WORDBREAK or DT_NOPREFIX);
  C.Brush.Style := bsSolid;
end;

const
  CardW = 240;
  CardH = 210;
  CardArt = 100;
  CardCols = 4;

type
  TGalleryForm = class(TForm)
  private
    sb: TScrollBox;
    pb: TPaintBox;
    procedure PaintGallery(Sender: TObject);
  public
    constructor Create(AOwner: TComponent); override;
  end;

constructor TGalleryForm.Create(AOwner: TComponent);
var
  Kd, I, Cnt, Y: Integer;
begin
  inherited CreateNew(AOwner);
  Caption := 'Galeri pola: candle, pola chart & strategi (bullish / bearish)';
  SetBounds(80, 60, CardCols * (CardW + 10) + 50, 780);
  Color := clrBg;
  sb := TScrollBox.Create(Self);
  sb.Parent := Self;
  sb.Align := alClient;
  sb.Color := clrBg;
  sb.BorderStyle := bsNone;
  sb.VertScrollBar.Tracking := True;
  pb := TPaintBox.Create(Self);
  pb.Parent := sb;
  pb.OnPaint := PaintGallery;
  Y := 8;
  for Kd := 0 to 2 do
  begin
    Cnt := 0;
    for I := 0 to Theory.Count - 1 do
      if TheoryField(Theory.Names[I], 0) = Kd then
        Inc(Cnt);
    Inc(Y, 34 + ((Cnt + CardCols - 1) div CardCols) * (CardH + 10) + 10);
  end;
  pb.SetBounds(0, 0, CardCols * (CardW + 10) + 24, Y);
end;

procedure TGalleryForm.PaintGallery(Sender: TObject);
var
  C: TCanvas;
  Kd, I, Idx, Y, X, Yy: Integer;
begin
  C := pb.Canvas;
  C.Brush.Style := bsSolid;
  C.Brush.Color := clrBg;
  C.FillRect(Rect(0, 0, pb.Width, pb.Height));
  Y := 8;
  for Kd := 0 to 2 do
  begin
    C.Brush.Style := bsClear;
    C.Font.Name := 'Segoe UI';
    C.Font.Size := 13;
    C.Font.Style := [fsBold];
    C.Font.Color := clrGold;
    C.TextOut(12, Y + 4, UpperCase(KindNames[Kd]));
    C.Brush.Style := bsSolid;
    Inc(Y, 34);
    Idx := 0;
    for I := 0 to Theory.Count - 1 do
      if TheoryField(Theory.Names[I], 0) = Kd then
      begin
        X := 12 + (Idx mod CardCols) * (CardW + 10);
        Yy := Y + (Idx div CardCols) * (CardH + 10);
        DrawCard(C, Rect(X, Yy, X + CardW, Yy + CardH), Theory.Names[I], CardArt);
        Inc(Idx);
      end;
    Inc(Y, ((Idx + CardCols - 1) div CardCols) * (CardH + 10) + 10);
  end;
end;

{ ---------- Jendela ---------- }

type
  TCandleRow = record
    Sym, TF: string;
    Hit: TPatHit;
    Price, Time: Double;
  end;

  TCandleForm = class(TForm)
  private
    pnlTop: TPanel;
    cbSig, cbTF, cbKind: TComboBox;
    btnScan, btnTheory: TPanel;
    lblStatus: TLabel;
    lv: TListView;
    pnlPrev: TPanel;
    pbPrev: TPaintBox;
    tmr: TTimer;
    FProvider: TSymProvider;
    FRows: array of TCandleRow;
    FBusy, FDirty: Boolean;
    FStart: Cardinal;
    FLastScan: TDateTime;
    function MakeBtn(X, W: Integer; const Txt: string; Click: TNotifyEvent): TPanel;
    function MakeCombo(X, W: Integer; const Items: array of string): TComboBox;
    procedure FormClose(Sender: TObject; var Action: TCloseAction);
    procedure ScanClick(Sender: TObject);
    procedure TheoryClick(Sender: TObject);
    procedure FilterChange(Sender: TObject);
    procedure TimerTick(Sender: TObject);
    procedure lvDrawItem(Sender: TCustomListView; Item: TListItem; State: TCustomDrawState;
      var DefaultDraw: Boolean);
    procedure PrevPaint(Sender: TObject);
    procedure lvSelect(Sender: TObject; Item: TListItem; Selected: Boolean);
    procedure lvClick(Sender: TObject);
    procedure WMCandle(var M: TMessage); message WM_FT_CANDLE;
    procedure StartScan;
    procedure Rebuild;
  public
    constructor Create(AOwner: TComponent); override;
  end;

var
  CandleForm: TCandleForm = nil;

function TCandleForm.MakeBtn(X, W: Integer; const Txt: string; Click: TNotifyEvent): TPanel;
begin
  Result := TPanel.Create(Self);
  Result.Parent := pnlTop;
  Result.SetBounds(X, 8, W, 28);
  Result.BevelOuter := bvNone;
  Result.Color := clrPanel2;
  Result.Font.Color := clrGold;
  Result.Font.Style := [fsBold];
  Result.Caption := Txt;
  Result.Cursor := crHandPoint;
  Result.OnClick := Click;
end;

function TCandleForm.MakeCombo(X, W: Integer; const Items: array of string): TComboBox;
var
  I: Integer;
begin
  Result := TComboBox.Create(Self);
  Result.Parent := pnlTop;
  Result.Style := csDropDownList;
  Result.SetBounds(X, 10, W, 23);
  for I := 0 to High(Items) do
    Result.Items.Add(Items[I]);
  Result.ItemIndex := 0;
  Result.OnChange := FilterChange;
end;

constructor TCandleForm.Create(AOwner: TComponent);
const
  Cols: array[0..8] of string = ('Koin', 'TF', 'Jenis', 'Sinyal', 'Pola', 'Kekuatan', 'Harga', 'Candle jam', 'Arti');
  Wid: array[0..8] of Integer = (95, 45, 85, 70, 250, 80, 100, 80, 640);
var
  I: Integer;
  Col: TListColumn;
begin
  inherited CreateNew(AOwner);
  Caption := 'Fernanda Taker - Candle, Pola Chart & Strategi (BELI / JUAL)';
  SetBounds(60, 60, 1500, 760);
  Color := clrBg;
  Font.Name := 'Segoe UI';
  Font.Size := 9;
  Font.Color := clrText;
  OnClose := FormClose;

  pnlTop := TPanel.Create(Self);
  pnlTop.Parent := Self;
  pnlTop.Align := alTop;
  pnlTop.Height := 44;
  pnlTop.BevelOuter := bvNone;
  pnlTop.Color := clrPanel;

  cbSig := MakeCombo(10, 110, ['Semua sinyal', 'BELI', 'JUAL']);
  cbTF := MakeCombo(130, 100, ['Semua TF', '1m', '5m', '15m', '30m']);
  cbKind := MakeCombo(240, 130, ['Semua jenis', 'Candle', 'Pola Chart', 'Strategi']);
  btnScan := MakeBtn(380, 100, 'Scan ulang', ScanClick);
  btnTheory := MakeBtn(490, 150, 'Galeri gambar pola', TheoryClick);
  lblStatus := TLabel.Create(Self);
  lblStatus.Parent := pnlTop;
  lblStatus.SetBounds(660, 14, 800, 18);
  lblStatus.Font.Color := clrDim;

  pnlPrev := TPanel.Create(Self);
  pnlPrev.Parent := Self;
  pnlPrev.Align := alBottom;
  pnlPrev.Height := 190;
  pnlPrev.BevelOuter := bvNone;
  pnlPrev.Color := clrPanel;
  pbPrev := TPaintBox.Create(Self);
  pbPrev.Parent := pnlPrev;
  pbPrev.Align := alClient;
  pbPrev.OnPaint := PrevPaint;

  lv := TListView.Create(Self);
  lv.Parent := Self;
  lv.Align := alClient;
  lv.OnSelectItem := lvSelect;
  lv.OnClick := lvClick;
  lv.ViewStyle := vsReport;
  lv.ReadOnly := True;
  lv.RowSelect := True;
  lv.HideSelection := False;
  lv.Color := clrBg;
  lv.Font.Color := clrText;
  lv.OnCustomDrawItem := lvDrawItem;
  for I := 0 to High(Cols) do
  begin
    Col := lv.Columns.Add;
    Col.Caption := Cols[I];
    Col.Width := Wid[I];
  end;

  tmr := TTimer.Create(Self);
  tmr.Interval := 1000;
  tmr.OnTimer := TimerTick;
end;

procedure TCandleForm.FormClose(Sender: TObject; var Action: TCloseAction);
begin
  Action := caHide;
end;

procedure TCandleForm.StartScan;
var
  Syms: TSymArr;
begin
  if FBusy and (GetTickCount - FStart < 300000) then
    Exit;
  SetLength(Syms, 0);
  if Assigned(FProvider) then
    FProvider(Syms);
  if Length(Syms) = 0 then
  begin
    lblStatus.Caption := 'Belum ada daftar koin, coba lagi sebentar...';
    Exit;
  end;
  FBusy := True;
  FStart := GetTickCount;
  lblStatus.Caption := Format('Memindai %d koin x 4 time frame...', [Length(Syms)]);
  TCandleThread.Create(Handle, Syms);
end;

procedure TCandleForm.ScanClick(Sender: TObject);
begin
  StartScan;
end;

procedure TCandleForm.TimerTick(Sender: TObject);
begin
  if not Visible then
    Exit;
  if FDirty then
  begin
    FDirty := False;
    Rebuild;
  end;
  if (not FBusy) and (Now - FLastScan > 60 / 86400) then
    StartScan;
end;

procedure TCandleForm.FilterChange(Sender: TObject);
begin
  Rebuild;
end;

procedure TCandleForm.WMCandle(var M: TMessage);
var
  D: TCandleData;
  I, J, N: Integer;
begin
  D := TCandleData(M.LParam);
  try
    if D.Last then
    begin
      FBusy := False;
      FLastScan := Now;
      FDirty := True;
      Exit;
    end;
    // buang hasil lama koin + time frame yang sama, lalu isi yang baru
    N := 0;
    for I := 0 to High(FRows) do
      if not ((FRows[I].Sym = D.Sym) and (FRows[I].TF = D.TF)) then
      begin
        FRows[N] := FRows[I];
        Inc(N);
      end;
    SetLength(FRows, N + Length(D.Hits));
    for J := 0 to High(D.Hits) do
    begin
      FRows[N + J].Sym := D.Sym;
      FRows[N + J].TF := D.TF;
      FRows[N + J].Hit := D.Hits[J];
      FRows[N + J].Price := D.Price;
      FRows[N + J].Time := D.Time;
    end;
    FDirty := True;
  finally
    D.Free;
  end;
end;

procedure TCandleForm.Rebuild;
var
  Idx: array of Integer;
  I, J, N, T, Cnt, Buy, Sell: Integer;
  Item: TListItem;
  Stars: string;
  Ok: Boolean;
begin
  SetLength(Idx, Length(FRows));
  N := 0;
  Buy := 0;
  Sell := 0;
  for I := 0 to High(FRows) do
  begin
    Ok := True;
    if (cbSig.ItemIndex = 1) and (FRows[I].Hit.Dir <= 0) then Ok := False;
    if (cbSig.ItemIndex = 2) and (FRows[I].Hit.Dir >= 0) then Ok := False;
    if (cbTF.ItemIndex > 0) and (FRows[I].TF <> CandleTFApi[cbTF.ItemIndex - 1]) then Ok := False;
    if (cbKind.ItemIndex > 0) and (FRows[I].Hit.Kind <> cbKind.ItemIndex - 1) then Ok := False;
    if not Ok then
      Continue;
    // urut: kekuatan terbesar, lalu candle terbaru (insertion sort)
    J := N;
    while (J > 0) and ((FRows[Idx[J - 1]].Hit.Str < FRows[I].Hit.Str) or
      ((FRows[Idx[J - 1]].Hit.Str = FRows[I].Hit.Str) and (FRows[Idx[J - 1]].Time < FRows[I].Time))) do
    begin
      Idx[J] := Idx[J - 1];
      Dec(J);
    end;
    Idx[J] := I;
    Inc(N);
    if FRows[I].Hit.Dir > 0 then Inc(Buy) else Inc(Sell);
  end;
  lv.Items.BeginUpdate;
  try
    lv.Items.Clear;
    for T := 0 to N - 1 do
    begin
      I := Idx[T];
      Item := lv.Items.Add;
      Item.Data := Pointer(I);
      Item.Caption := FRows[I].Sym;
      Item.SubItems.Add(FRows[I].TF);
      Item.SubItems.Add(KindNames[FRows[I].Hit.Kind]);
      if FRows[I].Hit.Dir > 0 then Item.SubItems.Add('BELI') else Item.SubItems.Add('JUAL');
      Item.SubItems.Add(FRows[I].Hit.Name);
      Stars := '';
      for Cnt := 1 to FRows[I].Hit.Str do
        Stars := Stars + '*';
      Item.SubItems.Add(Stars);
      Item.SubItems.Add(FmtPrice(FRows[I].Price));
      Item.SubItems.Add(FormatDateTime('hh:nn', KlineTime(FRows[I].Time)));
      Item.SubItems.Add(TheoryDesc(FRows[I].Hit.Name));
    end;
  finally
    lv.Items.EndUpdate;
  end;
  if FBusy then
    lblStatus.Caption := Format('Memindai... %d sinyal (%d BELI, %d JUAL)', [N, Buy, Sell])
  else
    lblStatus.Caption := Format('%d sinyal (%d BELI, %d JUAL) - scan terakhir %s - otomatis tiap 1 menit',
      [N, Buy, Sell, FormatDateTime('hh:nn:ss', FLastScan)]);
end;

procedure TCandleForm.lvSelect(Sender: TObject; Item: TListItem; Selected: Boolean);
begin
  pbPrev.Invalidate;
end;

procedure TCandleForm.lvClick(Sender: TObject);
begin
  pbPrev.Invalidate;
end;

{ pratinjau: nama + gambar model pola dari baris yang diklik }
procedure TCandleForm.PrevPaint(Sender: TObject);
var
  C: TCanvas;
  Nm: string;
begin
  C := pbPrev.Canvas;
  C.Brush.Style := bsSolid;
  C.Brush.Color := clrPanel;
  C.FillRect(Rect(0, 0, pbPrev.Width, pbPrev.Height));
  if (lv.Selected = nil) or (lv.Selected.SubItems.Count < 5) then
  begin
    C.Brush.Style := bsClear;
    C.Font.Name := 'Segoe UI';
    C.Font.Size := 10;
    C.Font.Color := clrDim;
    C.TextOut(14, 14, 'Klik satu baris sinyal untuk melihat nama dan gambar model polanya (bullish / bearish).');
    Exit;
  end;
  Nm := lv.Selected.SubItems[3];
  DrawCard(C, Rect(8, 6, 8 + CardW + 60, pbPrev.Height - 6), Nm, 100);
end;

procedure TCandleForm.lvDrawItem(Sender: TCustomListView; Item: TListItem; State: TCustomDrawState;
  var DefaultDraw: Boolean);
var
  I: Integer;
begin
  DefaultDraw := True;
  I := Integer(Item.Data);
  if (I < 0) or (I > High(FRows)) then
    Exit;
  if FRows[I].Hit.Dir > 0 then
  begin
    Sender.Canvas.Font.Color := clrUp;
    Sender.Canvas.Brush.Color := clrUpBg;
  end
  else
  begin
    Sender.Canvas.Font.Color := clrDown;
    Sender.Canvas.Brush.Color := clrDownBg;
  end;
end;

procedure TCandleForm.TheoryClick(Sender: TObject);
begin
  TGalleryForm.Create(Self).Show;
end;

procedure ShowCandleForm(Provider: TSymProvider);
begin
  if CandleForm = nil then
    CandleForm := TCandleForm.Create(Application);
  CandleForm.FProvider := Provider;
  CandleForm.Show;
  CandleForm.BringToFront;
  CandleForm.StartScan;
end;

{ pola candle terbaik pada candle E, dipakai grafik untuk menggambar penanda }
function CandleMarkHook(const K: TKlines; E: Integer; var Name: string; var Dir, Str: Integer): Boolean;
var
  H: TPatHits;
  I, B: Integer;
begin
  Result := False;
  SetLength(H, 0);
  try
    CandlePat(K, E, H);
  except
    Exit;
  end;
  B := -1;
  for I := 0 to High(H) do
    if (B < 0) or (H[I].Str > H[B].Str) then
      B := I;
  if B < 0 then
    Exit;
  Name := H[B].Name;
  Dir := H[B].Dir;
  Str := H[B].Str;
  Result := True;
end;

{ ringkasan teks untuk panel analisa: pola/strategi pada candle selesai terakhir
  dan pola candle 4 candle sebelumnya }
function PatternReport(const K: TKlines): string;
var
  H, P: TPatHits;
  I, J, Buy, Sell, Ago, E: Integer;
  T: TPatHit;
  L: TStringList;
  Sg: string;
begin
  Result := '';
  if Length(K) < 30 then
    Exit;
  H := DetectPatterns(K);
  for I := 1 to High(H) do   // urut kekuatan terbesar dulu
  begin
    T := H[I];
    J := I - 1;
    while (J >= 0) and (H[J].Str < T.Str) do
    begin
      H[J + 1] := H[J];
      Dec(J);
    end;
    H[J + 1] := T;
  end;
  L := TStringList.Create;
  try
    L.Add(' --- POLA CANDLE, POLA CHART & STRATEGI (candle selesai terakhir) ---');
    Buy := 0;
    Sell := 0;
    if Length(H) = 0 then
      L.Add(' Tidak ada pola/strategi terdeteksi di candle ini.');
    for I := 0 to High(H) do
    begin
      if H[I].Dir > 0 then
      begin
        Sg := 'BELI ';
        Inc(Buy);
      end
      else
      begin
        Sg := 'JUAL ';
        Inc(Sell);
      end;
      L.Add(Format(' [%s] %s %s  (%s)', [Sg, H[I].Name, StringOfChar('*', H[I].Str), KindNames[H[I].Kind]]));
      L.Add('        ' + TheoryDesc(H[I].Name));
    end;
    if Length(H) > 0 then
    begin
      if Buy > Sell then Sg := 'condong BELI'
      else if Sell > Buy then Sg := 'condong JUAL'
      else Sg := 'seimbang / tunggu';
      L.Add(Format(' Ringkasan: %d sinyal BELI, %d sinyal JUAL -> %s', [Buy, Sell, Sg]));
    end;
    for Ago := 1 to 4 do
    begin
      E := Length(K) - 2 - Ago;
      SetLength(P, 0);
      try
        CandlePat(K, E, P);
      except
      end;
      for I := 0 to High(P) do
        if P[I].Dir > 0 then
          L.Add(Format(' %d candle lalu: [BELI ] %s', [Ago, P[I].Name]))
        else
          L.Add(Format(' %d candle lalu: [JUAL ] %s', [Ago, P[I].Name]));
    end;
    L.Add(' Panah di grafik: hijau di bawah candle = BELI, merah di atas candle = JUAL.');
    Result := TrimRight(L.Text);
  finally
    L.Free;
  end;
end;

initialization
  ChartPatternHook := CandleMarkHook;
  BuildTheory;
  BuildShapes;

finalization
  Shapes.Free;
  Theory.Free;

end.
