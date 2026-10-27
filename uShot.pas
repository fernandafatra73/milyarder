unit uShot;

{ Baca screenshot grafik candlestick (hijau = naik, merah = turun) menjadi data
  candle: gambar dimuat lewat GDI+ (PNG/JPG/BMP/GIF), piksel hijau/merah
  dikelompokkan per kolom menjadi candle, lalu tinggi piksel dipetakan ke harga
  memakai harga tertinggi & terendah yang diberikan pengguna. Batang volume di
  bawah candle (bila ada) dipakai sebagai bobot volume. }

interface

uses
  Windows, SysUtils, Classes, Graphics, Math, uAnalysis;

function ShotToKlines(const FileName: string; HighP, LowP: Double;
  var K: TKlines; var Info: string): Boolean;
function LoadAnyPicture(const FileName: string; Bmp: TBitmap): Boolean;
function SaveBitmapPng(Bmp: TBitmap; const FileName: string): Boolean;

implementation

type
  TGdipStartupInput = record
    Version: Cardinal;
    Callback: Pointer;
    SuppressThread: BOOL;
    SuppressCodecs: BOOL;
  end;
  TGdiplusStartup = function(var Token: Cardinal; var Input: TGdipStartupInput; Output: Pointer): Integer; stdcall;
  TGdipCreateBitmapFromFile = function(FileName: PWideChar; var Bmp: Pointer): Integer; stdcall;
  TGdipCreateHBITMAPFromBitmap = function(Bmp: Pointer; var HBmp: HBITMAP; Background: Cardinal): Integer; stdcall;
  TGdipDisposeImage = function(Img: Pointer): Integer; stdcall;
  TGdiplusShutdown = procedure(Token: Cardinal); stdcall;

{ Muat gambar apa pun yang dikenal Windows ke Bmp (24 bit) }
function LoadAnyPicture(const FileName: string; Bmp: TBitmap): Boolean;
var
  Lib: HMODULE;
  Startup: TGdiplusStartup;
  FromFile: TGdipCreateBitmapFromFile;
  ToHBmp: TGdipCreateHBITMAPFromBitmap;
  Dispose: TGdipDisposeImage;
  Shutdown: TGdiplusShutdown;
  Inp: TGdipStartupInput;
  Tok: Cardinal;
  Img: Pointer;
  HB: HBITMAP;
  Tmp: TBitmap;
  WName: WideString;
begin
  Result := False;
  Lib := LoadLibrary('gdiplus.dll');
  if Lib = 0 then
    Exit;
  try
    Startup := GetProcAddress(Lib, 'GdiplusStartup');
    FromFile := GetProcAddress(Lib, 'GdipCreateBitmapFromFile');
    ToHBmp := GetProcAddress(Lib, 'GdipCreateHBITMAPFromBitmap');
    Dispose := GetProcAddress(Lib, 'GdipDisposeImage');
    Shutdown := GetProcAddress(Lib, 'GdiplusShutdown');
    if not (Assigned(Startup) and Assigned(FromFile) and Assigned(ToHBmp) and
      Assigned(Dispose) and Assigned(Shutdown)) then
      Exit;
    Inp.Version := 1;
    Inp.Callback := nil;
    Inp.SuppressThread := False;
    Inp.SuppressCodecs := False;
    if Startup(Tok, Inp, nil) <> 0 then
      Exit;
    try
      WName := WideString(FileName);
      Img := nil;
      if FromFile(PWideChar(WName), Img) <> 0 then
        Exit;
      try
        HB := 0;
        if ToHBmp(Img, HB, $FF000000) <> 0 then
          Exit;
        Tmp := TBitmap.Create;
        try
          Tmp.Handle := HB;
          Bmp.PixelFormat := pf24bit;
          Bmp.Width := Tmp.Width;
          Bmp.Height := Tmp.Height;
          Bmp.Canvas.Draw(0, 0, Tmp);
          Result := True;
        finally
          Tmp.Free;
        end;
      finally
        Dispose(Img);
      end;
    finally
      Shutdown(Tok);
    end;
  finally
    FreeLibrary(Lib);
  end;
end;

type
  TGdipCreateBitmapFromHBITMAP = function(HBmp: HBITMAP; Pal: HPALETTE; var Bmp: Pointer): Integer; stdcall;
  TGdipSaveImageToFile = function(Img: Pointer; FileName: PWideChar; Clsid: PGUID; Params: Pointer): Integer; stdcall;

const
  PngEncoderClsid: TGUID = '{557CF406-1A04-11D3-9A73-0000F81EF32E}';

{ Simpan bitmap sebagai PNG lewat GDI+ (False bila gagal) }
function SaveBitmapPng(Bmp: TBitmap; const FileName: string): Boolean;
var
  Lib: HMODULE;
  Startup: TGdiplusStartup;
  FromHBmp: TGdipCreateBitmapFromHBITMAP;
  SaveFile: TGdipSaveImageToFile;
  Dispose: TGdipDisposeImage;
  Shutdown: TGdiplusShutdown;
  Inp: TGdipStartupInput;
  Tok: Cardinal;
  Img: Pointer;
  WName: WideString;
begin
  Result := False;
  Lib := LoadLibrary('gdiplus.dll');
  if Lib = 0 then
    Exit;
  try
    Startup := GetProcAddress(Lib, 'GdiplusStartup');
    FromHBmp := GetProcAddress(Lib, 'GdipCreateBitmapFromHBITMAP');
    SaveFile := GetProcAddress(Lib, 'GdipSaveImageToFile');
    Dispose := GetProcAddress(Lib, 'GdipDisposeImage');
    Shutdown := GetProcAddress(Lib, 'GdiplusShutdown');
    if not (Assigned(Startup) and Assigned(FromHBmp) and Assigned(SaveFile) and
      Assigned(Dispose) and Assigned(Shutdown)) then
      Exit;
    Inp.Version := 1;
    Inp.Callback := nil;
    Inp.SuppressThread := False;
    Inp.SuppressCodecs := False;
    if Startup(Tok, Inp, nil) <> 0 then
      Exit;
    try
      Img := nil;
      if FromHBmp(Bmp.Handle, 0, Img) <> 0 then
        Exit;
      try
        WName := WideString(FileName);
        Result := SaveFile(Img, PWideChar(WName), @PngEncoderClsid, nil) = 0;
      finally
        Dispose(Img);
      end;
    finally
      Shutdown(Tok);
    end;
  finally
    FreeLibrary(Lib);
  end;
end;

type
  TByteRow = array[0..MaxInt div 2] of Byte;
  PByteRow = ^TByteRow;

procedure SortInts(var A: array of Integer; Count: Integer);
var
  I, J, T: Integer;
begin
  for I := 1 to Count - 1 do
  begin
    T := A[I];
    J := I - 1;
    while (J >= 0) and (A[J] > T) do
    begin
      A[J + 1] := A[J];
      Dec(J);
    end;
    A[J + 1] := T;
  end;
end;

function ShotToKlines(const FileName: string; HighP, LowP: Double;
  var K: TKlines; var Info: string): Boolean;
const
  MaxRuns = 12;
type
  TRun = record
    S, E, G, R: Integer;   // baris awal/akhir, jumlah piksel hijau/merah
  end;
  TPiece = record
    X0, X1, N: Integer;
    Runs: array[0..MaxRuns - 1] of TRun;
  end;
  TCand = record
    Top, Bot, BodyTop, BodyBot: Integer;
    Green: Boolean;
    Vol: Integer;
  end;
var
  Bmp: TBitmap;
  W, Hh, x, y, i, j, c, n, nc, p, kk, x0, x1, pw: Integer;
  Row: PByteRow;
  R, G, B: Integer;
  Cls: array of Byte;
  Col, Hist, Diffs, CS, CE: array of Integer;
  HRun: array of Byte;
  BestStart, BestCnt, CurStart, CurCnt, Gap, Pitch, Chain: Integer;
  Pieces: array of TPiece;
  Cands: array of TCand;
  Pc: TPiece;
  Cd: TCand;
  inRun: Boolean;
  lastY, tg, tr, need, cnt, VolBase, VolCnt, ri, bestRi, bestMass, mass, volRi, np: Integer;
  minTop, maxBot: Integer;
  rngY: Double;

  function PV(Yp: Integer): Double;
  begin
    Result := LowP + (maxBot - Yp) / rngY * (HighP - LowP);
  end;

begin
  Result := False;
  K := nil;
  Info := '';
  Bmp := TBitmap.Create;
  try
    if not LoadAnyPicture(FileName, Bmp) then
    begin
      try
        Bmp.LoadFromFile(FileName);
        Bmp.PixelFormat := pf24bit;
      except
        Info := 'Gambar tidak bisa dibuka. Pakai PNG, JPG, atau BMP.';
        Exit;
      end;
    end;
    W := Bmp.Width;
    Hh := Bmp.Height;
    if (W < 200) or (Hh < 120) then
    begin
      Info := 'Gambar terlalu kecil untuk dibaca.';
      Exit;
    end;

    { 1. klasifikasi piksel (1 hijau, 2 merah) + garis vertikal terpanjang per kolom }
    SetLength(Cls, W * Hh);
    SetLength(Col, W);
    for y := 0 to Hh - 1 do
    begin
      Row := Bmp.ScanLine[y];
      for x := 0 to W - 1 do
      begin
        B := Row[x * 3];
        G := Row[x * 3 + 1];
        R := Row[x * 3 + 2];
        c := 0;
        if (G - R >= 35) and (G >= B + 10) and (G >= 85) then
          c := 1
        else if (R - G >= 70) and (R - B >= 30) and (B <= G + 34) and (R >= 105) then
          c := 2;
        Cls[y * W + x] := c;
      end;
    end;

    { piksel "badan" = bagian blok berwarna selebar >= 3 dan setinggi >= 2:
      huruf, garis tipis, dan garis putus-putus tidak memenuhi ini }
    SetLength(HRun, W * Hh);
    for y := 0 to Hh - 1 do
    begin
      x := 0;
      while x < W do
      begin
        if Cls[y * W + x] = 0 then
          Inc(x)
        else
        begin
          x0 := x;
          while (x < W) and (Cls[y * W + x] <> 0) do
            Inc(x);
          for j := x0 to x - 1 do
            HRun[y * W + j] := Min(x - x0, 255);
        end;
      end;
    end;
    for x := 0 to W - 1 do
    begin
      y := 0;
      while y < Hh do
      begin
        if Cls[y * W + x] = 0 then
          Inc(y)
        else
        begin
          x0 := y;
          while (y < Hh) and (Cls[y * W + x] <> 0) do
            Inc(y);
          if y - x0 >= 2 then
            for j := x0 to y - 1 do
              if HRun[j * W + x] >= 3 then
                Inc(Col[x]);
        end;
      end;
    end;

    { 2. kelompok kolom yang punya batang vertikal >= 3 piksel = satu candle
         (garis horizontal & teks tipis tidak ikut terhitung) }
    SetLength(CS, W);
    SetLength(CE, W);
    nc := 0;
    x := 0;
    while x < W do
    begin
      if Col[x] >= 1 then
      begin
        CS[nc] := x;
        while (x < W) and (Col[x] >= 1) do
          Inc(x);
        CE[nc] := x - 1;
        Inc(nc);
      end
      else
        Inc(x);
    end;
    if nc < 20 then
    begin
      Info := Format('Hanya %d bentuk candle terdeteksi. Pastikan screenshot berisi grafik candlestick hijau/merah yang jelas.', [nc]);
      Exit;
    end;

    { 3. jarak antar candle = median selisih awal kelompok }
    SetLength(Diffs, nc);
    n := 0;
    for i := 1 to nc - 1 do
      if CS[i] - CS[i - 1] <= 60 then
      begin
        Diffs[n] := CS[i] - CS[i - 1];
        Inc(n);
      end;
    if n < 10 then
    begin
      Info := 'Jarak antar candle tidak teratur; ini sepertinya bukan grafik candlestick.';
      Exit;
    end;
    SortInts(Diffs, n);
    Pitch := Max(2, Diffs[n div 2]);

    { 4. rangkaian candle terpanjang yang jaraknya teratur }
    Gap := Max(3 * Pitch, 12);
    BestStart := 0;
    BestCnt := 0;
    CurStart := 0;
    CurCnt := 1;
    for i := 1 to nc do
    begin
      if (i < nc) and (CS[i] - CS[i - 1] <= Gap) then
        Inc(CurCnt)
      else
      begin
        if CurCnt > BestCnt then
        begin
          BestCnt := CurCnt;
          BestStart := CurStart;
        end;
        CurStart := i;
        CurCnt := 1;
      end;
    end;
    Chain := BestCnt;

    { 5. run vertikal berwarna pada tiap candle }
    np := 0;
    for i := BestStart to BestStart + Chain - 1 do
    begin
      pw := CE[i] - CS[i] + 1;
      if pw > 3 * Pitch + 2 then
        Continue;   // kotak label harga, bukan candle
      if (pw < 3) and (Pitch > 4) then
        Continue;   // goresan huruf/garis tipis, bukan badan candle
      kk := Round(pw / Pitch);
      if kk < 1 then kk := 1;
      for p := 0 to kk - 1 do
      begin
        x0 := CS[i] + (p * pw) div kk;
        x1 := CS[i] + ((p + 1) * pw) div kk - 1;
        Pc.X0 := x0;
        Pc.X1 := x1;
        Pc.N := 0;
        inRun := False;
        lastY := -10;
        for y := 0 to Hh - 1 do
        begin
          tg := 0;
          tr := 0;
          for j := x0 to x1 do
            case Cls[y * W + j] of
              1: Inc(tg);
              2: Inc(tr);
            end;
          if tg + tr > 0 then
          begin
            if (not inRun) or (y - lastY > 2) then
            begin
              if Pc.N >= MaxRuns then Break;
              Pc.Runs[Pc.N].S := y;
              Pc.Runs[Pc.N].G := 0;
              Pc.Runs[Pc.N].R := 0;
              Inc(Pc.N);
              inRun := True;
            end;
            Pc.Runs[Pc.N - 1].E := y;
            Inc(Pc.Runs[Pc.N - 1].G, tg);
            Inc(Pc.Runs[Pc.N - 1].R, tr);
            lastY := y;
          end;
        end;
        if Pc.N = 0 then
          Continue;
        SetLength(Pieces, np + 1);
        Pieces[np] := Pc;
        Inc(np);
      end;
    end;
    if np < 30 then
    begin
      Info := Format('Hanya %d candle terbaca (butuh minimal 30). Pakai screenshot yang lebih lebar / lebih jelas.', [np]);
      Exit;
    end;

    { 6. garis dasar batang volume = dasar run terakhir yang sama di sebagian besar candle }
    SetLength(Hist, Hh);
    for i := 0 to np - 1 do
      if Pieces[i].N >= 2 then
        Inc(Hist[Pieces[i].Runs[Pieces[i].N - 1].E]);
    VolBase := -1;
    VolCnt := 0;
    for y := 0 to Hh - 1 do
    begin
      c := Hist[y];
      if y > 0 then Inc(c, Hist[y - 1]);
      if y < Hh - 1 then Inc(c, Hist[y + 1]);
      if c > VolCnt then
      begin
        VolCnt := c;
        VolBase := y;
      end;
    end;
    if VolCnt < np div 2 then
      VolBase := -1;

    { 7. bentuk tiap candle: run bermassa terbesar (di luar batang volume), lalu badannya }
    SetLength(Cands, 0);
    for i := 0 to np - 1 do
    begin
      Pc := Pieces[i];
      volRi := -1;
      if (VolBase >= 0) and (Pc.N >= 2) and (Abs(Pc.Runs[Pc.N - 1].E - VolBase) <= 2) then
        volRi := Pc.N - 1;
      bestRi := -1;
      bestMass := 0;
      for ri := 0 to Pc.N - 1 do
        if ri <> volRi then
        begin
          mass := Pc.Runs[ri].G + Pc.Runs[ri].R;
          if (mass > bestMass) and ((Pc.Runs[ri].E - Pc.Runs[ri].S >= 2) or (Pc.N = 1)) then
          begin
            bestMass := mass;
            bestRi := ri;
          end;
        end;
      if bestRi < 0 then
        Continue;
      Cd.Top := Pc.Runs[bestRi].S;
      Cd.Bot := Pc.Runs[bestRi].E;
      Cd.Green := Pc.Runs[bestRi].G >= Pc.Runs[bestRi].R;
      Cd.Vol := 1;
      if volRi >= 0 then
        Cd.Vol := Max(1, Pc.Runs[volRi].E - Pc.Runs[volRi].S + 1);
      // badan = baris yang hampir seluruh lebar candle berwarna (sumbu hanya 1 piksel)
      Cd.BodyTop := -1;
      Cd.BodyBot := -1;
      if Pc.X1 - Pc.X0 + 1 <= 2 then
      begin
        Cd.BodyTop := Cd.Top;
        Cd.BodyBot := Cd.Bot;
      end
      else
      begin
        need := Max(2, Round((Pc.X1 - Pc.X0 + 1) * 0.6));
        for y := Cd.Top to Cd.Bot do
        begin
          cnt := 0;
          for j := Pc.X0 to Pc.X1 do
            if Cls[y * W + j] <> 0 then
              Inc(cnt);
          if cnt >= need then
          begin
            if Cd.BodyTop < 0 then Cd.BodyTop := y;
            Cd.BodyBot := y;
          end;
        end;
      end;
      if Cd.BodyTop < 0 then
      begin
        Cd.BodyTop := (Cd.Top + Cd.Bot) div 2;
        Cd.BodyBot := Cd.BodyTop;
      end;
      SetLength(Cands, Length(Cands) + 1);
      Cands[High(Cands)] := Cd;
    end;

    n := Length(Cands);
    if n < 30 then
    begin
      Info := Format('Hanya %d candle terbaca (butuh minimal 30). Pakai screenshot yang lebih lebar / lebih jelas.', [n]);
      Exit;
    end;

    { 8. petakan piksel ke harga }
    minTop := Cands[0].Top;
    maxBot := Cands[0].Bot;
    for i := 1 to n - 1 do
    begin
      minTop := Min(minTop, Cands[i].Top);
      maxBot := Max(maxBot, Cands[i].Bot);
    end;
    if maxBot - minTop < 10 then
    begin
      Info := 'Tinggi grafik terlalu kecil untuk dibaca.';
      Exit;
    end;
    rngY := maxBot - minTop;
    if HighP <= LowP then
    begin
      LowP := 0;
      HighP := 100;
    end;

    SetLength(K, n);
    for i := 0 to n - 1 do
    begin
      Cd := Cands[i];
      FillChar(K[i], SizeOf(TKline), 0);
      K[i].OpenTime := 1.7E12 + i * 60000.0;
      K[i].H := PV(Cd.Top);
      K[i].L := PV(Cd.Bot);
      if Cd.Green then
      begin
        K[i].C := PV(Cd.BodyTop);
        K[i].O := PV(Cd.BodyBot);
      end
      else
      begin
        K[i].O := PV(Cd.BodyTop);
        K[i].C := PV(Cd.BodyBot);
      end;
      K[i].V := Cd.Vol;
      K[i].QV := Cd.Vol;
      if Cd.Green then
        K[i].TBQV := Cd.Vol;   // perkiraan: volume candle hijau dianggap pembelian
    end;
    Info := Format('Terbaca %d candle dari gambar %dx%d (jarak %d px per candle).', [n, W, Hh, Pitch]);
    Result := True;
  finally
    Bmp.Free;
  end;
end;

end.
