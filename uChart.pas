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

type
  { Posisi tampilan grafik: digeser/di-zoom dengan mouse }
  TChartView = record
    Offset: Integer;    // jumlah candle digeser ke masa lalu (0 = candle terbaru di kanan)
    Count: Integer;     // jumlah candle terlihat (0 = otomatis)
    Shift: Double;      // geser harga atas/bawah (pecahan tinggi grafik)
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
end;

function ViewMouseMove(var View: TChartView; X, Y: Integer): Boolean;
begin
  Result := View.Dragging;
  if not Result then
    Exit;
  // geser kanan = lihat candle lama; geser bawah = grafik turun
  if (View.VisUsed > 0) and (View.PlotW > 0) then
    View.Offset := View.DragOffset + Round((X - View.DragX) * View.VisUsed / View.PlotW);
  if View.PlotH > 0 then
    View.Shift := View.DragShift + (Y - View.DragY) / View.PlotH;
end;

procedure ViewMouseUp(var View: TChartView);
begin
  View.Dragging := False;
end;

procedure ViewZoom(var View: TChartView; WheelDelta: Integer);
var
  Base: Integer;
begin
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

procedure DrawCandles(C: TCanvas; R: TRect; const K: TKlines; const A: TAnalysis;
  HoverX: Integer; const Title: string; var View: TChartView);
var
  mk, mx, my, mw, mh, lastRU, lastRD: Integer;
  mt: string;
  n, vis, first, last, lastData, maxVis, i, m, x, bw, plotL, plotR, plotT, plotB, volT, volB, y1, y2, hov, tx: Integer;
  hi, lo, vmax, slot, v, step: Double;
  cum: array of Double;
  started: Boolean;
  S: string;
  Kc: TKline;
  maIdx: array[0..3] of Integer;
  maCol: array[0..3] of TColor;

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
    TextAt(plotL + 4, YY - 15, T, Col, True);
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
  v := (hi - lo) * View.Shift;   // geser harga atas/bawah
  hi := hi + v;
  lo := lo + v;

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
  maIdx[0] := 0; maIdx[1] := 1; maIdx[2] := 3; maIdx[3] := 4;
  maCol[0] := clrGold; maCol[1] := clrMA25; maCol[2] := clrMA99; maCol[3] := clrMA200;
  for m := 0 to 3 do
  begin
    C.Pen.Color := maCol[m];
    C.Pen.Width := 1;
    started := False;
    for i := first to lastData do
      if i >= MAPeriods[maIdx[m]] - 1 then
      begin
        v := (cum[i + 1] - cum[i + 1 - MAPeriods[maIdx[m]]]) / MAPeriods[maIdx[m]];
        if started then
          C.LineTo(XC(i), Y(v))
        else
        begin
          C.MoveTo(XC(i), Y(v));
          started := True;
        end;
      end;
  end;

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
  SelectClipRgn(C.Handle, 0);

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
  TextAt(tx, R.Top + 8, 'MA9', clrGold, True);
  TextAt(tx + 34, R.Top + 8, 'MA25', clrMA25, True);
  TextAt(tx + 74, R.Top + 8, 'MA99', clrMA99, True);
  TextAt(tx + 114, R.Top + 8, 'MA200', clrMA200, True);
  S := 'drag = geser   scroll = zoom   klik 2x = reset';
  if plotR - C.TextWidth(S) > tx + 170 then
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
