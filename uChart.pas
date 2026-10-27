unit uChart;

{ Warna tema (gaya Binance gelap) dan penggambar grafik:
  - DrawCandles : grafik candlestick + MA + volume + support/resisten
  - DrawSpark   : grafik mini untuk daftar koin }

interface

uses
  Windows, SysUtils, Classes, Graphics, Math, uAnalysis;

const
  clrBg      = $00110E0B;  // #0B0E11
  clrPanel   = $00201A18;  // #181A20
  clrPanel2  = $0029231E;  // #1E2329
  clrBorder  = $0039312B;  // #2B3139
  clrGold    = $000BB9F0;  // #F0B90B
  clrUp      = $0081CB0E;  // #0ECB81 hijau
  clrDown    = $005C3BFF;  // #FF3B5C merah merona
  clrText    = $00EFECEA;  // #EAECEF
  clrDim     = $009C8E84;  // #848E9C
  clrUpBg    = $00221F10;  // baris naik (hijau gelap)
  clrDownBg  = $0022121E;  // baris turun (merah gelap)
  clrUpFill  = $00364D13;
  clrDownFill= $002E1A5E;
  clrUpVol   = $004A6A0E;
  clrDownVol = $00352080;
  clrMA25    = $009343E8;  // pink
  clrMA99    = $00E8CF00;  // cyan
  clrMA200   = $00FF6CA6;  // ungu
  clrMA500   = $003C8CFF;  // oranye
  clrMA700   = $00FF9B5B;  // biru

  { garis MA di grafik }
  ChartMACount = 6;
  ChartMAPeriods: array[0..ChartMACount - 1] of Integer = (9, 25, 99, 200, 500, 700);
  ChartMAColors: array[0..ChartMACount - 1] of TColor = (clrGold, clrMA25, clrMA99, clrMA200, clrMA500, clrMA700);

type
  { Posisi tampilan grafik: digeser/di-zoom dengan mouse }
  TChartView = record
    Offset: Integer;    // jumlah candle digeser ke masa lalu (0 = candle terbaru di kanan)
    Count: Integer;     // jumlah candle terlihat (0 = otomatis)
    Shift: Double;      // geser harga atas/bawah (pecahan tinggi grafik)
    PriceZoom: Double;  // perbesaran skala harga (0 / 1 = normal, >1 diperbesar)
    CurX, PlotRight: Integer;   // diisi DrawCandles: posisi kursor & tepi kanan area candle
    ScaleDrag: Boolean;         // sedang drag di skala harga
    DragZoom: Double;
    VisUsed, PlotW, PlotH: Integer;  // diisi DrawCandles
    AtStart: Boolean;   // diisi DrawCandles: sudah di candle paling lama yang dimuat
    Dragging: Boolean;
    DragX, DragY, DragOffset: Integer;
    DragShift: Double;
  end;

type
  { dipasang unit pola candle: pola terbaik pada candle E (False = tidak ada) }
  TPatternHook = function(const K: TKlines; E: Integer; var Name: string; var Dir, Str: Integer): Boolean;

var
  ChartPatternHook: TPatternHook = nil;

type
  { kesimpulan arah koin (BULLISH / BEARISH / SIDEWAYS) }
  TVerdict = record
    Score: Integer;
    Head, Detail: string;
    Col: TColor;
  end;

  { saran saat ini: mending beli, jual, atau tunggu }
  TAdvice = record
    Action: Integer;          // 1 beli, -1 jual, 0 tunggu
    Head, Plan, Why: string;
    Col: TColor;
    Verdict: TVerdict;
  end;

  { Smart Money Concepts }
  TSmcBreak = record
    FromIdx, ToIdx, Dir: Integer;   // swing yang ditembus -> candle penembus; Dir +1 naik, -1 turun
    Price: Double;
    Choch: Boolean;                 // True = CHoCH (arah struktur berbalik), False = BOS (lanjut)
  end;
  TSmcGap = record
    StartIdx, EndIdx, Dir: Integer; // EndIdx = candle yang menutup gap (bila Filled)
    Top, Bot: Double;
    Filled: Boolean;
  end;
  TSmcBreaks = array of TSmcBreak;
  TSmcGaps = array of TSmcGap;

const
  { keterangan BOS / CHoCH untuk grafik & analisa }
  SmcNotes: array[0..2] of string = (
    'Arah tren   : BOS = tren masih lanjut, CHoCH = tren berpotensi berubah',
    'Tujuan      : BOS untuk konfirmasi kelanjutan, CHoCH untuk deteksi awal pembalikan',
    'Posisi chart: BOS biasanya muncul setelah konsolidasi kecil, CHoCH sering di area puncak / dasar tren');

procedure FindSmc(const K: TKlines; var Br: TSmcBreaks; var Gp: TSmcGaps);
function MarketVerdict(const K: TKlines; const A: TAnalysis): TVerdict;
function TradeAdvice(const K: TKlines; const A: TAnalysis): TAdvice;
procedure DrawCandles(C: TCanvas; R: TRect; const K: TKlines; const A: TAnalysis;
  HoverX: Integer; const Title: string; var View: TChartView);
procedure DrawSpark(C: TCanvas; R: TRect; const V: array of Double; Bg: TColor);
function KlineTime(OpenTimeMs: Double): TDateTime;

procedure ResetView(var View: TChartView);
procedure ViewMouseDown(var View: TChartView; X, Y: Integer);
function ViewMouseMove(var View: TChartView; X, Y: Integer): Boolean;
procedure ViewMouseUp(var View: TChartView);
procedure ViewZoom(var View: TChartView; WheelDelta: Integer);

implementation

procedure ResetView(var View: TChartView);
begin
  FillChar(View, SizeOf(View), 0);
end;

procedure ViewMouseDown(var View: TChartView; X, Y: Integer);
begin
  View.Dragging := True;
  View.DragX := X;
  View.DragY := Y;
  View.DragOffset := View.Offset;
  View.DragShift := View.Shift;
  // klik di skala harga (kanan): drag ke atas/bawah = perbesar/kecilkan skala
  View.ScaleDrag := (View.PlotRight > 0) and (X > View.PlotRight);
  View.DragZoom := View.PriceZoom;
  if View.DragZoom <= 0 then
    View.DragZoom := 1;
end;

function ViewMouseMove(var View: TChartView; X, Y: Integer): Boolean;
begin
  Result := View.Dragging;
  if not Result then
    Exit;
  if View.ScaleDrag then
  begin
    View.PriceZoom := Min(30, Max(0.2, View.DragZoom * Exp((View.DragY - Y) / 120)));
    Exit;
  end;
  // geser kanan = lihat candle lama; geser bawah = grafik turun
  if (View.VisUsed > 0) and (View.PlotW > 0) then
    View.Offset := View.DragOffset + Round((X - View.DragX) * View.VisUsed / View.PlotW);
  if View.PlotH > 0 then
    View.Shift := View.DragShift + (Y - View.DragY) / View.PlotH;
end;

procedure ViewMouseUp(var View: TChartView);
begin
  View.Dragging := False;
  View.ScaleDrag := False;
end;

procedure ViewZoom(var View: TChartView; WheelDelta: Integer);
var
  Base: Integer;
  Z: Double;
begin
  // kursor di skala harga (kanan): roda mouse memperbesar/memperkecil skala harga
  if (View.PlotRight > 0) and (View.CurX > View.PlotRight) then
  begin
    Z := View.PriceZoom;
    if Z <= 0 then
      Z := 1;
    if WheelDelta > 0 then Z := Z * 1.2 else Z := Z / 1.2;
    View.PriceZoom := Min(30, Max(0.2, Z));
    Exit;
  end;
  Base := View.VisUsed;
  if Base <= 0 then
    Base := 120;
  if WheelDelta > 0 then
    View.Count := Max(10, Round(Base / 1.2))   // scroll ke atas = zoom in
  else
    View.Count := Round(Base * 1.2) + 1;       // scroll ke bawah = zoom out
end;

function KlineTime(OpenTimeMs: Double): TDateTime;
var
  TZ: TTimeZoneInformation;
  Bias: Integer;
begin
  Bias := 0;
  case GetTimeZoneInformation(TZ) of
    TIME_ZONE_ID_STANDARD, TIME_ZONE_ID_UNKNOWN: Bias := TZ.Bias;
    TIME_ZONE_ID_DAYLIGHT: Bias := TZ.Bias + TZ.DaylightBias;
  end;
  Result := 25569 + OpenTimeMs / 86400000 - Bias / 1440;
end;

procedure DrawSpark(C: TCanvas; R: TRect; const V: array of Double; Bg: TColor);
var
  I, N: Integer;
  Hi, Lo: Double;
  Pts: array of TPoint;
  Up: Boolean;
begin
  C.Brush.Style := bsSolid;
  C.Brush.Color := Bg;
  C.FillRect(R);
  N := Length(V);
  if N < 2 then
    Exit;
  InflateRect(R, -3, -3);
  Hi := V[0];
  Lo := V[0];
  for I := 1 to N - 1 do
  begin
    Hi := Max(Hi, V[I]);
    Lo := Min(Lo, V[I]);
  end;
  if Hi = Lo then
    Hi := Lo + 1;
  Up := V[N - 1] >= V[0];
  SetLength(Pts, N + 2);
  for I := 0 to N - 1 do
  begin
    Pts[I].X := R.Left + Round(I * (R.Right - R.Left) / (N - 1));
    Pts[I].Y := R.Bottom - Round((V[I] - Lo) / (Hi - Lo) * (R.Bottom - R.Top));
  end;
  Pts[N].X := R.Right;
  Pts[N].Y := R.Bottom;
  Pts[N + 1].X := R.Left;
  Pts[N + 1].Y := R.Bottom;
  C.Pen.Style := psClear;
  if Up then C.Brush.Color := clrUpFill else C.Brush.Color := clrDownFill;
  C.Polygon(Pts);
  C.Pen.Style := psSolid;
  C.Pen.Width := 2;
  if Up then C.Pen.Color := clrUp else C.Pen.Color := clrDown;
  SetLength(Pts, N);
  C.Polyline(Pts);
  C.Pen.Width := 1;
end;

{ catatan target jual untuk label grafik: maksimal dua alasan pertama }
function ShortNote(const S: string): string;
var
  P1, P2: Integer;
begin
  Result := S;
  P1 := Pos(' + ', S);
  if P1 > 0 then
  begin
    P2 := Pos(' + ', Copy(S, P1 + 3, MaxInt));
    if P2 > 0 then
      Result := Copy(S, 1, P1 + 2 + P2 - 1) + ' ...';
  end;
end;

type
  TMark = record
    Idx, Dir, Str: Integer;
    Name: string;
  end;

var
  MarkCache: array of TMark;
  MarkN: Integer = -1;
  MarkFirstTime, MarkLastTime: Double;

{ hitung ulang penanda pola hanya bila data candle berubah (bukan tiap gambar ulang) }
procedure EnsureMarks(const K: TKlines);
var
  n, E, D, S: Integer;
  Nm: string;
begin
  n := Length(K);
  if (n = MarkN) and (K[0].OpenTime = MarkFirstTime) and (K[n - 1].OpenTime = MarkLastTime) then
    Exit;
  MarkN := n;
  MarkFirstTime := K[0].OpenTime;
  MarkLastTime := K[n - 1].OpenTime;
  SetLength(MarkCache, 0);
  for E := Max(22, n - 400) to n - 2 do
    if ChartPatternHook(K, E, Nm, D, S) and (S >= 2) then
    begin
      SetLength(MarkCache, Length(MarkCache) + 1);
      with MarkCache[High(MarkCache)] do
      begin
        Idx := E;
        Dir := D;
        Str := S;
        Name := Nm;
      end;
    end;
end;

{ ---------- Smart Money Concepts: FVG, BOS, CHoCH ---------- }

const
  SmcSwing = 3;      // swing high/low: lebih tinggi/rendah dari 3 candle kiri & kanan
  SmcBack = 500;     // candle terakhir yang dianalisa
  SmcMinGap = 0.25;  // FVG minimal 0,25x rata-rata panjang candle

{ BOS: harga menutup melewati swing searah struktur sebelumnya.
  CHoCH: penembusan pertama yang berlawanan dengan struktur sebelumnya.
  FVG: celah 3 candle - low candle ke-3 di atas high candle ke-1 (bullish),
  atau high candle ke-3 di bawah low candle ke-1 (bearish). }
procedure FindSmc(const K: TKlines; var Br: TSmcBreaks; var Gp: TSmcGaps);
var
  n, st, i, j, m, Trend, ShIdx, SlIdx: Integer;
  ShP, SlP, Rng: Double;
  ShLive, SlLive, PivH, PivL: Boolean;

  procedure AddBreak(FromI, D: Integer; P: Double);
  var
    B: TSmcBreak;
  begin
    B.FromIdx := FromI;
    B.ToIdx := i;
    B.Dir := D;
    B.Price := P;
    B.Choch := (Trend <> 0) and (Trend <> D);
    SetLength(Br, Length(Br) + 1);
    Br[High(Br)] := B;
    Trend := D;
  end;

  procedure AddGap(Dir: Integer; Top, Bot: Double);
  var
    G: TSmcGap;
    j: Integer;
  begin
    G.StartIdx := i - 1;
    G.Dir := Dir;
    G.Top := Top;
    G.Bot := Bot;
    G.Filled := False;
    G.EndIdx := n - 1;
    for j := i + 1 to n - 1 do
      if ((Dir > 0) and (K[j].L <= Bot)) or ((Dir < 0) and (K[j].H >= Top)) then
      begin
        G.Filled := True;
        G.EndIdx := j;
        Break;
      end;
    SetLength(Gp, Length(Gp) + 1);
    Gp[High(Gp)] := G;
  end;

begin
  SetLength(Br, 0);
  SetLength(Gp, 0);
  n := Length(K);
  if n < 20 then
    Exit;
  st := Max(0, n - SmcBack);

  { struktur pasar }
  Trend := 0;
  ShLive := False;
  SlLive := False;
  ShIdx := -1;
  SlIdx := -1;
  ShP := 0;
  SlP := 0;
  for i := st + 2 * SmcSwing to n - 1 do
  begin
    j := i - SmcSwing;   // swing di j baru pasti setelah 3 candle kanannya selesai
    PivH := True;
    PivL := True;
    for m := j - SmcSwing to j + SmcSwing do
    begin
      if m = j then Continue;
      if ((m < j) and (K[m].H >= K[j].H)) or ((m > j) and (K[m].H > K[j].H)) then PivH := False;
      if ((m < j) and (K[m].L <= K[j].L)) or ((m > j) and (K[m].L < K[j].L)) then PivL := False;
    end;
    if PivH then
    begin
      ShIdx := j; ShP := K[j].H; ShLive := True;
    end;
    if PivL then
    begin
      SlIdx := j; SlP := K[j].L; SlLive := True;
    end;
    if ShLive and (K[i].C > ShP) then
    begin
      AddBreak(ShIdx, 1, ShP);
      ShLive := False;
    end;
    if SlLive and (K[i].C < SlP) then
    begin
      AddBreak(SlIdx, -1, SlP);
      SlLive := False;
    end;
  end;

  { fair value gap }
  Rng := 0;
  for i := st to n - 1 do
    Rng := Rng + (K[i].H - K[i].L);
  Rng := Rng / (n - st);
  for i := st + 2 to n - 1 do
    if (K[i].L > K[i - 2].H) and (K[i].L - K[i - 2].H >= Rng * SmcMinGap) then
      AddGap(1, K[i].L, K[i - 2].H)
    else if (K[i].H < K[i - 2].L) and (K[i - 2].L - K[i].H >= Rng * SmcMinGap) then
      AddGap(-1, K[i - 2].L, K[i].H);
end;

{ Skor arah = trend MA (-5..+5) + struktur terakhir BOS/CHoCH (+-2)
  + dominasi volume beli/jual (+-1) + prakiraan gerak segera (+-1) }
function MarketVerdict(const K: TKlines; const A: TAnalysis): TVerdict;
var
  Br: TSmcBreaks;
  Gp: TSmcGaps;
  Er: TEarly;
  S: string;
begin
  Result.Score := 0;
  Result.Head := 'SIDEWAYS';
  Result.Detail := '';
  Result.Col := clrGold;
  if not A.Ok or (Length(K) < 40) then
    Exit;
  Result.Score := A.TrendScore;
  Result.Detail := 'MA ' + IntToStr(A.TrendScore);
  FindSmc(K, Br, Gp);
  if Length(Br) > 0 then
  begin
    Inc(Result.Score, 2 * Br[High(Br)].Dir);
    if Br[High(Br)].Choch then S := 'CHoCH' else S := 'BOS';
    if Br[High(Br)].Dir > 0 then S := S + ' naik' else S := S + ' turun';
    Result.Detail := Result.Detail + '   struktur ' + S;
  end;
  if A.BuyPct >= 55 then Inc(Result.Score) else if A.BuyPct <= 45 then Dec(Result.Score);
  if A.BuyPct > 0 then
    Result.Detail := Result.Detail + Format('   beli %.0f%%', [A.BuyPct]);
  Er := EarlyMove(A, K);
  Inc(Result.Score, Sign(Er.Dir));
  if Result.Score >= 5 then begin Result.Head := 'BULLISH KUAT'; Result.Col := clrUp; end
  else if Result.Score >= 2 then begin Result.Head := 'BULLISH'; Result.Col := clrUp; end
  else if Result.Score <= -5 then begin Result.Head := 'BEARISH KUAT'; Result.Col := clrDown; end
  else if Result.Score <= -2 then begin Result.Head := 'BEARISH'; Result.Col := clrDown; end;
  if Result.Score > 0 then S := '+' else S := '';
  Result.Detail := 'skor ' + S + IntToStr(Result.Score) + '   ' + Result.Detail;
end;

function PctTo(Level, P: Double): string;
begin
  Result := FmtPrice(Level) + ' (' + FmtPct((Level - P) / P * 100) + ')';
end;

{ Saran saat ini dari arah koin + jarak ke support/resisten + FVG terdekat:
  bullish dan masih ada ruang ke resisten -> BELI; bearish dan masih ada ruang
  ke support -> JUAL; mepet level atau sideways -> TUNGGU di level yang jelas. }
function TradeAdvice(const K: TKlines; const A: TAnalysis): TAdvice;
const
  NearPct = 0.5;   // "mepet" level bila jaraknya < 0,5%
var
  Br: TSmcBreaks;
  Gp: TSmcGaps;
  n, i: Integer;
  P, Sup, Res, DSup, DRes, FbTop, FbBot, FsTop, FsBot, SL, TP: Double;

  procedure SetPlan(Entry, Stop, Target: Double);
  begin
    Result.Plan := 'Masuk ' + FmtPrice(Entry);
    if Stop > 0 then Result.Plan := Result.Plan + '   |   Cut loss ' + PctTo(Stop, Entry);
    if Target > 0 then Result.Plan := Result.Plan + '   |   Target ' + PctTo(Target, Entry);
    if (Stop > 0) and (Target > 0) and (Abs(Entry - Stop) > 0) then
      Result.Plan := Result.Plan + Format('   |   untung:rugi %.1f : 1', [Abs(Target - Entry) / Abs(Entry - Stop)]);
  end;

begin
  Result.Action := 0;
  Result.Head := 'TUNGGU';
  Result.Plan := '';
  Result.Why := '';
  Result.Col := clrGold;
  Result.Verdict := MarketVerdict(K, A);
  n := Length(K);
  if not A.Ok or (n < 40) then
  begin
    Result.Why := 'data grafik belum cukup';
    Exit;
  end;
  P := K[n - 1].C;

  { support di bawah & resisten di atas harga terkini }
  Sup := 0;
  if (A.SwingSup > 0) and (A.SwingSup < P) then Sup := A.SwingSup
  else if (A.StrongSup > 0) and (A.StrongSup < P) then Sup := A.StrongSup
  else if (A.S1 > 0) and (A.S1 < P) then Sup := A.S1;
  Res := 0;
  if A.SwingRes > P then Res := A.SwingRes
  else if A.StrongRes > P then Res := A.StrongRes
  else if A.R1 > P then Res := A.R1;
  if Sup > 0 then DSup := (P - Sup) / P * 100 else DSup := 100;
  if Res > 0 then DRes := (Res - P) / P * 100 else DRes := 100;

  { FVG belum terisi terdekat: bullish di bawah harga, bearish di atas harga }
  FindSmc(K, Br, Gp);
  FbTop := 0; FbBot := 0; FsTop := 0; FsBot := 0;
  for i := 0 to High(Gp) do
    if not Gp[i].Filled then
      if (Gp[i].Dir > 0) and (Gp[i].Top < P) and (Gp[i].Top > FbTop) then
      begin
        FbTop := Gp[i].Top; FbBot := Gp[i].Bot;
      end
      else if (Gp[i].Dir < 0) and (Gp[i].Bot > P) and ((FsBot = 0) or (Gp[i].Bot < FsBot)) then
      begin
        FsTop := Gp[i].Top; FsBot := Gp[i].Bot;
      end;

  Result.Why := Result.Verdict.Head + ' (' + Result.Verdict.Detail + ')';
  if A.Signal <> '' then
    Result.Why := Result.Why + '   sinyal analisa ' + A.Signal;

  if Result.Verdict.Score >= 2 then
  begin
    if (DRes < NearPct) and (Result.Verdict.Score < 5) then
    begin
      Result.Head := 'TUNGGU - bullish tapi mepet resisten';
      if FbTop > 0 then
        Result.Plan := 'Beli saat turun ke FVG ' + PctTo(FbTop, P) + ' atau support ' + PctTo(Sup, P)
      else if Sup > 0 then
        Result.Plan := 'Beli saat turun ke support ' + PctTo(Sup, P)
      else
        Result.Plan := '';
      Result.Plan := Result.Plan + '   |   atau beli bila candle menutup di atas resisten ' + PctTo(Res, P);
    end
    else
    begin
      Result.Action := 1;
      Result.Head := 'BELI';
      Result.Col := clrUp;
      if Sup > 0 then SL := Sup * 0.997
      else if FbBot > 0 then SL := FbBot * 0.997
      else SL := P * 0.98;
      if Res > 0 then TP := Res else TP := P + 2 * (P - SL);
      SetPlan(P, SL, TP);
    end;
  end
  else if Result.Verdict.Score <= -2 then
  begin
    if (DSup < NearPct) and (Result.Verdict.Score > -5) then
    begin
      Result.Head := 'TUNGGU - bearish tapi mepet support';
      if FsBot > 0 then
        Result.Plan := 'Jual saat naik ke FVG ' + PctTo(FsBot, P) + ' atau resisten ' + PctTo(Res, P)
      else if Res > 0 then
        Result.Plan := 'Jual saat naik ke resisten ' + PctTo(Res, P)
      else
        Result.Plan := '';
      Result.Plan := Result.Plan + '   |   atau jual bila candle menutup di bawah support ' + PctTo(Sup, P);
    end
    else
    begin
      Result.Action := -1;
      Result.Head := 'JUAL';
      Result.Col := clrDown;
      if Res > 0 then SL := Res * 1.003
      else if FsTop > 0 then SL := FsTop * 1.003
      else SL := P * 1.02;
      if Sup > 0 then TP := Sup else TP := P - 2 * (SL - P);
      SetPlan(P, SL, TP);
      Result.Plan := Result.Plan + '   (punya koin: jual/kurangi; futures: short)';
    end;
  end
  else
  begin
    Result.Head := 'TUNGGU - belum ada arah jelas';
    Result.Plan := '';
    if Sup > 0 then Result.Plan := 'Beli dekat support ' + PctTo(Sup, P);
    if Res > 0 then
    begin
      if Result.Plan <> '' then Result.Plan := Result.Plan + '   |   ';
      Result.Plan := Result.Plan + 'jual dekat resisten ' + PctTo(Res, P);
    end;
  end;
end;

procedure DrawCandles(C: TCanvas; R: TRect; const K: TKlines; const A: TAnalysis;
  HoverX: Integer; const Title: string; var View: TChartView);
var
  Vd: TVerdict;
  SmBr: TSmcBreaks;
  SmGp: TSmcGaps;
  sx1, sx2, sy1, sy2: Integer;
  sCol: TColor;
  mk, mx, my, mw, mh, lastRU, lastRD: Integer;
  mt: string;
  Tg: TTargets;
  StopP: Double;
  StopN: string;
  Er: TEarly;
  bx, by, bwid, bln, bi, bj, bt: Integer;
  bs: string;
  BLines: array[0..3] of string;
  BCols: array[0..3] of TColor;
  tgN, tgI, tgJ, tgY, tgLast: Integer;
  tgP: array[0..3] of Double;
  tgC: array[0..3] of TColor;
  tgV: Double;
  tgK: TColor;
  n, vis, first, last, lastData, maxVis, i, m, x, bw, plotL, plotR, plotT, plotB, volT, volB, y1, y2, hov, tx: Integer;
  hi, lo, vmax, slot, v, step, zmid: Double;
  cum: array of Double;
  started: Boolean;
  S: string;
  Kc: TKline;

  function Y(P: Double): Integer;
  begin
    Result := plotT + Round((hi - P) / (hi - lo) * (plotB - plotT));
  end;

  function XC(Idx: Integer): Integer;
  begin
    Result := plotL + Round((Idx - first + 0.5) * slot);
  end;

  procedure TextAt(X, YY: Integer; const T: string; Col: TColor; Bold: Boolean);
  begin
    C.Brush.Style := bsClear;
    C.Font.Color := Col;
    if Bold then C.Font.Style := [fsBold] else C.Font.Style := [];
    C.TextOut(X, YY, T);
  end;

  procedure Tag(P: Double; Col, TextCol: TColor; const T: string);
  var
    YY: Integer;
  begin
    YY := Y(P);
    C.Brush.Style := bsSolid;
    C.Brush.Color := Col;
    C.Pen.Style := psClear;
    C.Rectangle(plotR + 2, YY - 8, R.Right - 2, YY + 9);
    C.Pen.Style := psSolid;
    TextAt(plotR + 5, YY - 7, T, TextCol, True);
  end;

  procedure Level(P: Double; Col: TColor; const T: string);
  var
    YY: Integer;
    S2: string;
  begin
    if (P <= lo) or (P >= hi) then
      Exit;
    YY := Y(P);
    C.Pen.Color := Col;
    C.Pen.Style := psDot;
    C.Pen.Width := 1;
    C.MoveTo(plotL, YY);
    C.LineTo(plotR, YY);
    C.Pen.Style := psSolid;
    S2 := T + '  (' + FmtPct((P - K[n - 1].C) / K[n - 1].C * 100) + ')';
    C.Font.Style := [fsBold];
    TextAt(plotR - C.TextWidth(S2) - 6, YY - 15, S2, Col, True);
  end;

begin
  C.Font.Name := 'Segoe UI';
  C.Font.Size := 8;
  C.Brush.Style := bsSolid;
  C.Brush.Color := clrPanel;
  C.FillRect(R);
  n := Length(K);
  if n < 2 then
  begin
    TextAt(R.Left + 16, R.Top + 16, 'Pilih koin untuk melihat grafik...', clrDim, False);
    Exit;
  end;

  plotL := R.Left + 8;
  plotR := R.Right - 80;
  plotT := R.Top + 40;
  volB := R.Bottom - 6;
  volT := volB - (R.Bottom - R.Top) div 6;
  plotB := volT - 6;
  if (plotR - plotL < 50) or (plotB - plotT < 40) then
    Exit;

  View.CurX := HoverX;
  View.PlotRight := plotR;

  { jendela candle yang terlihat (bisa digeser & di-zoom) }
  maxVis := Max(10, (plotR - plotL) div 2);
  if View.Count > 0 then
    vis := View.Count
  else
    vis := Min(120, (plotR - plotL) div 6);
  vis := Min(n, Max(10, Min(vis, maxVis)));
  if View.Offset > n - vis then View.Offset := n - vis;
  if View.Offset < -(vis div 2) then View.Offset := -(vis div 2);  // ruang kosong di kanan
  View.AtStart := View.Offset >= n - vis;
  last := n - 1 - View.Offset;
  lastData := Min(last, n - 1);
  first := last - vis + 1;
  View.VisUsed := vis;
  View.PlotW := plotR - plotL;
  View.PlotH := plotB - plotT;
  slot := (plotR - plotL) / vis;
  bw := Max(1, Round(slot * 0.62));

  hi := 0;
  lo := MaxDouble;
  vmax := 0;
  for i := first to lastData do
  begin
    hi := Max(hi, K[i].H);
    lo := Min(lo, K[i].L);
    vmax := Max(vmax, K[i].V);
  end;
  if hi <= lo then hi := lo * 1.01 + 0.00000001;
  v := (hi - lo) * 0.06;
  hi := hi + v;
  lo := lo - v;
  if View.PriceZoom > 0 then   // perbesar/kecilkan skala harga di sekitar tengah
  begin
    v := (hi - lo) / 2 / View.PriceZoom;
    zmid := (hi + lo) / 2;
    hi := zmid + v;
    lo := zmid - v;
  end;
  v := (hi - lo) * View.Shift;   // geser harga atas/bawah
  hi := hi + v;
  lo := lo + v;

  { kursor di skala harga: tandai area & beri petunjuk }
  if (HoverX > plotR) and (HoverX <= R.Right) then
  begin
    C.Brush.Style := bsSolid;
    C.Brush.Color := clrPanel2;
    C.FillRect(Rect(plotR + 1, plotT - 18, R.Right, plotB));
    C.Font.Size := 7;
    TextAt(plotR + 5, plotT - 15, 'skala: zoom', clrGold, True);
  end;

  { grid + label harga }
  C.Font.Size := 8;
  for i := 0 to 5 do
  begin
    step := hi - (hi - lo) * i / 5;
    y1 := Y(step);
    C.Pen.Color := clrBorder;
    C.Pen.Style := psSolid;
    C.MoveTo(plotL, y1);
    C.LineTo(plotR, y1);
    TextAt(plotR + 6, y1 - 7, FmtPrice(step), clrDim, False);
  end;
  C.Pen.Color := clrBorder;
  C.MoveTo(plotL, volT - 3);
  C.LineTo(plotR, volT - 3);

  { volume }
  for i := first to lastData do
  begin
    if vmax <= 0 then Break;
    x := XC(i);
    y1 := volB - Round(K[i].V / vmax * (volB - volT));
    C.Brush.Style := bsSolid;
    if K[i].C >= K[i].O then C.Brush.Color := clrUpVol else C.Brush.Color := clrDownVol;
    C.FillRect(Rect(x - bw div 2, y1, x - bw div 2 + bw, volB));
  end;

  { candle: hijau naik, merah turun }
  IntersectClipRect(C.Handle, plotL, plotT, plotR, plotB);

  { FVG di belakang candle: kotak penuh = belum terisi (diperpanjang ke kanan),
    garis titik = sudah terisi harga }
  FindSmc(K, SmBr, SmGp);
  C.Font.Size := 7;
  for mk := 0 to High(SmGp) do
    with SmGp[mk] do
    begin
      if (EndIdx < first) or (StartIdx > lastData) then Continue;
      if (Top <= lo) or (Bot >= hi) then Continue;
      sx1 := XC(StartIdx) - bw div 2;
      if Filled then sx2 := XC(EndIdx) else sx2 := plotR;
      sy1 := Y(Top);
      sy2 := Y(Bot);
      if sy2 - sy1 < 2 then sy2 := sy1 + 2;
      if Dir > 0 then sCol := clrUp else sCol := clrDown;
      if Filled then
      begin
        C.Brush.Style := bsClear;
        C.Pen.Color := clrBorder;
        C.Pen.Style := psDot;
        C.Rectangle(sx1, sy1, sx2, sy2 + 1);
        C.Pen.Style := psSolid;
      end
      else
      begin
        C.Brush.Style := bsSolid;
        if Dir > 0 then C.Brush.Color := clrUpFill else C.Brush.Color := clrDownFill;
        C.FillRect(Rect(sx1, sy1, sx2, sy2 + 1));
        if Dir > 0 then mt := 'FVG bullish' else mt := 'FVG bearish';
        TextAt(sx1 + 3, sy1 + (sy2 - sy1 - C.TextHeight(mt)) div 2, mt, sCol, True);
      end;
    end;
  C.Font.Size := 8;
  C.Brush.Style := bsSolid;

  for i := first to lastData do
  begin
    x := XC(i);
    if K[i].C >= K[i].O then
    begin
      C.Pen.Color := clrUp;
      C.Brush.Color := clrUp;
    end
    else
    begin
      C.Pen.Color := clrDown;
      C.Brush.Color := clrDown;
    end;
    C.Pen.Width := 1;
    C.MoveTo(x, Y(K[i].H));
    C.LineTo(x, Y(K[i].L) + 1);
    y1 := Y(Max(K[i].O, K[i].C));
    y2 := Y(Min(K[i].O, K[i].C));
    if y2 - y1 < 1 then y2 := y1 + 1;
    C.Brush.Style := bsSolid;
    C.FillRect(Rect(x - bw div 2, y1, x - bw div 2 + bw, y2 + 1));
  end;

  { garis MA }
  SetLength(cum, n + 1);
  cum[0] := 0;
  for i := 0 to n - 1 do
    cum[i + 1] := cum[i] + K[i].C;
  for m := 0 to ChartMACount - 1 do
  begin
    C.Pen.Color := ChartMAColors[m];
    C.Pen.Width := 1;
    started := False;
    for i := first to lastData do
      if i >= ChartMAPeriods[m] - 1 then
      begin
        v := (cum[i + 1] - cum[i + 1 - ChartMAPeriods[m]]) / ChartMAPeriods[m];
        if started then
          C.LineTo(XC(i), Y(v))
        else
        begin
          C.MoveTo(XC(i), Y(v));
          started := True;
        end;
      end;
  end;

  { BOS / CHoCH: garis putus dari swing yang ditembus ke candle penembus }
  C.Font.Size := 7;
  for mk := 0 to High(SmBr) do
    with SmBr[mk] do
    begin
      if (ToIdx < first) or (FromIdx > lastData) then Continue;
      if (Price <= lo) or (Price >= hi) then Continue;
      sx1 := XC(FromIdx);
      sx2 := XC(ToIdx);
      sy1 := Y(Price);
      if Dir > 0 then sCol := clrUp else sCol := clrDown;
      C.Pen.Color := sCol;
      C.Pen.Style := psDash;
      C.Pen.Width := 1;
      C.MoveTo(sx1, sy1);
      C.LineTo(sx2, sy1);
      C.Pen.Style := psSolid;
      if Choch then mt := 'CHoCH - potensi balik arah' else mt := 'BOS - tren lanjut';
      mw := C.TextWidth(mt);
      if Dir > 0 then
        sy2 := sy1 - C.TextHeight(mt) - 1   // tembus ke atas: label di atas garis
      else
        sy2 := sy1 + 1;
      if Choch then
        TextAt((sx1 + sx2 - mw) div 2, sy2, mt, clrGold, True)
      else
        TextAt((sx1 + sx2 - mw) div 2, sy2, mt, sCol, True);
    end;

  { keterangan BOS / CHoCH di pojok kiri bawah grafik }
  if Length(SmBr) > 0 then
  begin
    C.Font.Size := 7;
    C.Font.Style := [];
    bwid := 0;
    for bi := 0 to High(SmcNotes) do
      bwid := Max(bwid, C.TextWidth(SmcNotes[bi]));
    bx := plotL + 8;
    by := plotB - (Length(SmcNotes) + 1) * 12 - 8;
    C.Brush.Style := bsSolid;
    C.Brush.Color := clrBg;
    C.Pen.Color := clrBorder;
    C.Pen.Style := psSolid;
    C.Pen.Width := 1;
    C.Rectangle(bx - 5, by - 3, bx + bwid + 7, by + (Length(SmcNotes) + 1) * 12 + 3);
    TextAt(bx, by, 'BOS', clrUp, True);
    TextAt(bx + C.TextWidth('BOS '), by, '/', clrDim, True);
    TextAt(bx + C.TextWidth('BOS / '), by, 'CHoCH', clrGold, True);
    TextAt(bx + C.TextWidth('BOS / CHoCH '), by, '(struktur pasar)', clrDim, False);
    for bi := 0 to High(SmcNotes) do
      TextAt(bx, by + (bi + 1) * 12, SmcNotes[bi], clrText, False);
  end;
  C.Font.Size := 8;

  { support / resisten }
  if A.Ok then
  begin
    Level(A.SwingRes, clrDown, 'Resisten ' + FmtPrice(A.SwingRes));
    Level(A.SwingSup, clrUp, 'Support ' + FmtPrice(A.SwingSup));
    if A.StrongSupHits > 0 then
      Level(A.StrongSup, clrGold, Format('SUPPORT TERKUAT %s (%dx memantul)', [FmtPrice(A.StrongSup), A.StrongSupHits]));
    if A.StrongResHits > 0 then
      Level(A.StrongRes, clrMA25, Format('RESISTEN TERKUAT %s (%dx ditolak)', [FmtPrice(A.StrongRes), A.StrongResHits]));
  end;

  { penanda pola candle: panah + nama; hijau di bawah candle = BELI, merah di atas = JUAL }
  if Assigned(ChartPatternHook) and (n > 30) then
  begin
    EnsureMarks(K);
    lastRU := -1000;
    lastRD := -1000;
    C.Font.Size := 7;
    mh := C.TextHeight('A');
    for mk := 0 to High(MarkCache) do
      if (MarkCache[mk].Idx >= first) and (MarkCache[mk].Idx <= lastData) then
      begin
        mx := XC(MarkCache[mk].Idx);
        if MarkCache[mk].Dir > 0 then
        begin
          my := Y(K[MarkCache[mk].Idx].L) + 4;
          C.Pen.Color := clrUp;
          C.Brush.Color := clrUp;
          C.Brush.Style := bsSolid;
          C.Polygon([Point(mx, my), Point(mx - 4, my + 7), Point(mx + 4, my + 7)]);
          mt := 'BELI ' + MarkCache[mk].Name;
          mw := C.TextWidth(mt);
          if mx - mw div 2 > lastRU + 6 then
          begin
            TextAt(mx - mw div 2, my + 9, mt, clrUp, True);
            lastRU := mx + mw div 2;
          end;
        end
        else
        begin
          my := Y(K[MarkCache[mk].Idx].H) - 4;
          C.Pen.Color := clrDown;
          C.Brush.Color := clrDown;
          C.Brush.Style := bsSolid;
          C.Polygon([Point(mx, my), Point(mx - 4, my - 7), Point(mx + 4, my - 7)]);
          mt := 'JUAL ' + MarkCache[mk].Name;
          mw := C.TextWidth(mt);
          if mx - mw div 2 > lastRD + 6 then
          begin
            TextAt(mx - mw div 2, my - 9 - mh, mt, clrDown, True);
            lastRD := mx + mw div 2;
          end;
        end;
      end;
    C.Font.Size := 8;
    C.Brush.Style := bsSolid;
  end;

  { titik tunggu jual (emas) dan batas cut loss (merah), label di sisi kanan }
  if A.Ok and (K[n - 1].C > 0) then
  begin
    Tg := SellTargets(A, K, StopP, StopN);
    C.Font.Size := 8;
    for mk := 0 to High(Tg) do
    begin
      mt := Format('JUAL %d  %s  (%s)  %s', [mk + 1, FmtPrice(Tg[mk].Price),
        FmtPct((Tg[mk].Price - K[n - 1].C) / K[n - 1].C * 100), ShortNote(Tg[mk].Note)]);
      if (Tg[mk].Price > lo) and (Tg[mk].Price < hi) then
      begin
        my := Y(Tg[mk].Price);
        C.Pen.Color := clrGold;
        C.Pen.Style := psDash;
        C.Pen.Width := 1;
        C.MoveTo(plotL, my);
        C.LineTo(plotR, my);
        C.Pen.Style := psSolid;
        TextAt(plotR - C.TextWidth(mt) - 6, my - 15, mt, clrGold, True);
      end
      else if Tg[mk].Price >= hi then   // di atas area grafik: petunjuk di tepi atas
      begin
        mt := '^ ' + mt + '  (di atas grafik)';
        TextAt(plotR - C.TextWidth(mt) - 6, plotT + 3 + mk * 14, mt, clrGold, True);
      end;
    end;
    if (StopP > lo) and (StopP < hi) then
    begin
      my := Y(StopP);
      C.Pen.Color := clrDown;
      C.Pen.Style := psDash;
      C.Pen.Width := 1;
      C.MoveTo(plotL, my);
      C.LineTo(plotR, my);
      C.Pen.Style := psSolid;
      mt := Format('CUT LOSS  %s  (%s)  di bawah %s', [FmtPrice(StopP),
        FmtPct((StopP - K[n - 1].C) / K[n - 1].C * 100), StopN]);
      TextAt(plotR - C.TextWidth(mt) - 6, my + 3, mt, clrDown, True);
    end;
  end;

  { kotak prakiraan: ciri-ciri mau naik / turun secepatnya }
  if A.Ok and (n >= 40) then
  begin
    Er := EarlyMove(A, K);
    BLines[0] := 'PRAKIRAAN: ' + Er.Head + Format('  (skor %d)', [Er.Score]);
    if Er.Dir > 0 then BCols[0] := clrUp else if Er.Dir < 0 then BCols[0] := clrDown else BCols[0] := clrGold;
    bln := 1;
    for bi := 1 to 3 do   // 3 ciri terkuat
    begin
      bt := -1;
      for bj := 0 to High(Er.Items) do
        if (Er.Items[bj].Pts <> 0) and (Er.Items[bj].Text <> '') and
          ((bt < 0) or (Abs(Er.Items[bj].Pts) > Abs(Er.Items[bt].Pts))) then
          bt := bj;
      if bt < 0 then Break;
      if Er.Items[bt].Pts > 0 then BCols[bln] := clrUp else BCols[bln] := clrDown;
      if Er.Items[bt].Pts > 0 then bs := '+' else bs := '-';
      BLines[bln] := ' ' + bs + ' ' + Er.Items[bt].Text;
      Er.Items[bt].Text := '';   // sudah dipakai
      Inc(bln);
    end;
    if Er.Squeeze and (bln < 4) then
    begin
      BLines[bln] := ' ! harga menyempit: gerakan besar segera terjadi';
      BCols[bln] := clrGold;
      Inc(bln);
    end;
    C.Font.Size := 8;
    bwid := 0;
    for bi := 0 to bln - 1 do
      bwid := Max(bwid, C.TextWidth(BLines[bi]));
    bx := plotL + 8;
    by := plotT + 6;
    C.Brush.Style := bsSolid;
    C.Brush.Color := clrBg;
    if Er.Dir > 0 then C.Pen.Color := clrUp else if Er.Dir < 0 then C.Pen.Color := clrDown else C.Pen.Color := clrGold;
    C.Pen.Style := psSolid;
    C.Pen.Width := 1;
    C.Rectangle(bx - 5, by - 3, bx + bwid + 7, by + bln * 14 + 3);
    for bi := 0 to bln - 1 do
      TextAt(bx, by + bi * 14, BLines[bi], BCols[bi], bi = 0);
  end;

  { kesimpulan arah koin: BULLISH / BEARISH dengan tulisan besar di tengah atas }
  if A.Ok and (n >= 40) then
  begin
    Vd := MarketVerdict(K, A);
    mt := Vd.Head;
    bs := Vd.Detail;
    sCol := Vd.Col;
    C.Font.Size := 22;
    C.Font.Style := [fsBold];
    mw := C.TextWidth(mt);
    mh := C.TextHeight(mt);
    C.Font.Size := 8;
    C.Font.Style := [];
    bwid := Max(mw, C.TextWidth(bs)) + 28;
    bx := (plotL + plotR - bwid) div 2;
    by := plotT + 6;
    C.Brush.Style := bsSolid;
    C.Brush.Color := clrBg;
    C.Pen.Color := sCol;
    C.Pen.Style := psSolid;
    C.Pen.Width := 2;
    C.RoundRect(bx, by, bx + bwid, by + mh + 24, 10, 10);
    C.Pen.Width := 1;
    C.Font.Size := 22;
    TextAt(bx + (bwid - mw) div 2, by + 2, mt, sCol, True);
    C.Font.Size := 8;
    TextAt(bx + (bwid - C.TextWidth(bs)) div 2, by + mh + 4, bs, clrDim, False);
    C.Brush.Style := bsSolid;
  end;
  SelectClipRgn(C.Handle, 0);

  { tag harga support / resisten di skala kanan (hindari tumpang tindih) }
  if A.Ok then
  begin
    tgN := 0;
    if (A.SwingRes > lo) and (A.SwingRes < hi) then
    begin tgP[tgN] := A.SwingRes; tgC[tgN] := clrDown; Inc(tgN); end;
    if (A.SwingSup > lo) and (A.SwingSup < hi) then
    begin tgP[tgN] := A.SwingSup; tgC[tgN] := clrUp; Inc(tgN); end;
    if (A.StrongSupHits > 0) and (A.StrongSup > lo) and (A.StrongSup < hi) then
    begin tgP[tgN] := A.StrongSup; tgC[tgN] := clrGold; Inc(tgN); end;
    if (A.StrongResHits > 0) and (A.StrongRes > lo) and (A.StrongRes < hi) then
    begin tgP[tgN] := A.StrongRes; tgC[tgN] := clrMA25; Inc(tgN); end;
    for tgI := 1 to tgN - 1 do   // urut harga tertinggi di atas
    begin
      tgV := tgP[tgI];
      tgK := tgC[tgI];
      tgJ := tgI - 1;
      while (tgJ >= 0) and (tgP[tgJ] < tgV) do
      begin
        tgP[tgJ + 1] := tgP[tgJ];
        tgC[tgJ + 1] := tgC[tgJ];
        Dec(tgJ);
      end;
      tgP[tgJ + 1] := tgV;
      tgC[tgJ + 1] := tgK;
    end;
    tgLast := -100;
    for tgI := 0 to tgN - 1 do
    begin
      tgY := Y(tgP[tgI]);
      if tgY < tgLast + 16 then
        tgY := tgLast + 16;
      tgLast := tgY;
      C.Brush.Style := bsSolid;
      C.Brush.Color := tgC[tgI];
      C.Pen.Style := psClear;
      C.Rectangle(plotR + 2, tgY - 8, R.Right - 2, tgY + 9);
      C.Pen.Style := psSolid;
      if (tgC[tgI] = clrGold) or (tgC[tgI] = clrUp) then
        TextAt(plotR + 5, tgY - 7, FmtPrice(tgP[tgI]), clrBg, True)
      else
        TextAt(plotR + 5, tgY - 7, FmtPrice(tgP[tgI]), clrText, True);
    end;
  end;

  { garis & label harga terakhir }
  Kc := K[n - 1];
  y1 := Y(Kc.C);
  if (y1 >= plotT) and (y1 <= plotB) then
  begin
    if Kc.C >= Kc.O then C.Pen.Color := clrUp else C.Pen.Color := clrDown;
    C.Pen.Style := psDot;
    C.MoveTo(plotL, y1);
    C.LineTo(plotR, y1);
    C.Pen.Style := psSolid;
    if Kc.C >= Kc.O then
      Tag(Kc.C, clrUp, clrBg, FmtPrice(Kc.C))
    else
      Tag(Kc.C, clrDown, clrText, FmtPrice(Kc.C));
  end;

  { crosshair saat mouse di atas grafik }
  hov := -1;
  if (HoverX >= plotL) and (HoverX < plotR) then
  begin
    hov := first + Trunc((HoverX - plotL) / slot);
    if hov > lastData then hov := lastData;
    C.Pen.Color := clrDim;
    C.Pen.Style := psDot;
    C.MoveTo(XC(hov), plotT);
    C.LineTo(XC(hov), volB);
    C.Pen.Style := psSolid;
  end;

  { judul, legenda MA, info OHLC }
  C.Font.Size := 11;
  TextAt(R.Left + 10, R.Top + 4, Title, clrGold, True);
  tx := R.Left + 14 + C.TextWidth(Title);
  C.Font.Size := 8;
  for m := 0 to ChartMACount - 1 do
  begin
    S := 'MA' + IntToStr(ChartMAPeriods[m]);
    TextAt(tx, R.Top + 8, S, ChartMAColors[m], True);
    Inc(tx, C.TextWidth(S) + 8);
  end;
  Inc(tx, 8);
  TextAt(tx, R.Top + 8, 'FVG', clrUp, True);
  Inc(tx, C.TextWidth('FVG') + 8);
  TextAt(tx, R.Top + 8, 'BOS', clrText, True);
  Inc(tx, C.TextWidth('BOS') + 8);
  TextAt(tx, R.Top + 8, 'CHoCH', clrGold, True);
  Inc(tx, C.TextWidth('CHoCH'));
  S := 'drag = geser   scroll = zoom   klik 2x = reset';
  if plotR - C.TextWidth(S) > tx + 20 then
    TextAt(plotR - C.TextWidth(S), R.Top + 8, S, clrBorder + $00202020, False);
  if hov >= 0 then Kc := K[hov];
  if Kc.O > 0 then v := (Kc.C - Kc.O) / Kc.O * 100 else v := 0;
  S := Format('%s   O %s   H %s   L %s   C %s   ', [FormatDateTime('dd/mm hh:nn', KlineTime(Kc.OpenTime)),
    FmtPrice(Kc.O), FmtPrice(Kc.H), FmtPrice(Kc.L), FmtPrice(Kc.C)]);
  TextAt(R.Left + 10, R.Top + 23, S, clrDim, False);
  if v >= 0 then
    TextAt(R.Left + 10 + C.TextWidth(S), R.Top + 23, 'NAIK ' + FmtPct(v), clrUp, True)
  else
    TextAt(R.Left + 10 + C.TextWidth(S), R.Top + 23, 'TURUN ' + FmtPct(v), clrDown, True);
end;

end.
