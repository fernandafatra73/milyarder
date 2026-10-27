unit uLeverage;

{ Hitung Leverage: berapa besar posisi bila memakai 1-100% modal dengan
  leverage tertentu, harga likuidasi (Isolated & Cross, rumus Binance Futures
  tier pertama), margin rasio, uji ketahanan modal bila harga bergerak
  melawan posisi, dan saran leverage / pemakaian modal yang aman terhadap
  support/resisten dari analisa grafik. }

interface

uses
  Windows, Messages, SysUtils, Classes, Graphics, Controls, Forms, StdCtrls,
  ExtCtrls, ComCtrls, Math, uAnalysis, uChart;

procedure ShowLeverage(const Sym: string; const A: TAnalysis);

implementation

const
  UsePcts: array[0..15] of Integer = (1, 2, 3, 5, 10, 15, 20, 25, 30, 40, 50, 60, 70, 80, 90, 100);
  StressMoves: array[0..10] of Double = (0.5, 1, 2, 3, 5, 7.5, 10, 15, 20, 30, 50);
  MaxLev = 125;

type
  { hasil hitung satu kombinasi pakai modal % + leverage }
  TLevCalc = record
    Pct, Lev: Double;
    Margin, Notional, Qty, EffLev, FeeOpen, MM: Double;
    LiqIso, LiqCross: Double;     // 0 = tidak bisa terlikuidasi
    DistIso, DistCross: Double;   // % harga melawan posisi sampai likuidasi
    MRIso, MRCross: Double;       // margin rasio awal (%)
  end;

  TLevForm = class(TForm)
  private
    pnlTop: TPanel;
    lblCoin, lblLevel, lblPct, lblLev: TLabel;
    edModal, edEntry, edMMR, edFee, edSL, edPct, edLev: TEdit;
    cbSide, cbMode: TComboBox;
    tbPct, tbLev: TTrackBar;
    lv: TListView;
    memo: TMemo;
    FSync: Boolean;
    FSym: string;
    FPrice, FSup, FRes: Double;
    FRowStat: array of Integer;   // 0 aman, 1 waspada, 2 bahaya
    FRowPct: array of Integer;
    function MakeLabel(X, Y: Integer; const Txt: string): TLabel;
    function MakeEdit(X, Y, W: Integer; const Txt: string): TEdit;
    function MakeCombo(X, Y, W: Integer; const Items: array of string): TComboBox;
    function MakeTrack(X, Y, W, AMin, AMax: Integer): TTrackBar;
    function Side: Integer;
    function IsCross: Boolean;
    function Calc(Pct, Lev: Double): TLevCalc;
    function SLDist: Double;
    function Status(const C: TLevCalc; Dsl: Double): Integer;
    procedure DefaultSL;
    procedure Recalc;
    procedure InputChange(Sender: TObject);
    procedure SideChange(Sender: TObject);
    procedure PctTrack(Sender: TObject);
    procedure LevTrack(Sender: TObject);
    procedure PctEdit(Sender: TObject);
    procedure LevEdit(Sender: TObject);
    procedure lvDrawItem(Sender: TCustomListView; Item: TListItem; State: TCustomDrawState;
      var DefaultDraw: Boolean);
    procedure lvClick(Sender: TObject);
    procedure FormClose(Sender: TObject; var Action: TCloseAction);
  public
    constructor Create(AOwner: TComponent); override;
    procedure SetCoin(const Sym: string; const A: TAnalysis);
  end;

var
  LevForm: TLevForm = nil;

{ angka dari kotak isian: titik = desimal; koma dianggap desimal bila tidak ada titik }
function Num(const S: string; Def: Double): Double;
var
  T: string;
begin
  T := StringReplace(Trim(S), ' ', '', [rfReplaceAll]);
  if Pos('.', T) > 0 then
    T := StringReplace(T, ',', '', [rfReplaceAll])
  else
    T := StringReplace(T, ',', '.', [rfReplaceAll]);
  Result := StrToFloatDef(T, Def);
end;

function Usd(V: Double): string;
begin
  Result := FormatFloat('#,##0.00', V);
end;

function Pad(const S: string; W: Integer): string;
begin
  Result := S;
  if Length(Result) < W then
    Result := StringOfChar(' ', W - Length(Result)) + Result;
end;

function PadR(const S: string; W: Integer): string;
begin
  Result := S;
  if Length(Result) < W then
    Result := Result + StringOfChar(' ', W - Length(Result));
end;

{ Harga likuidasi satu posisi (Binance, tier pertama, jumlah maintenance = 0):
    LP = (WB - s*Qty*Entry) / (Qty*MMR - s*Qty)
  WB = saldo yang menanggung posisi (Isolated: margin posisi, Cross: seluruh modal),
  s = +1 long, -1 short. Hasil <= 0 berarti tidak bisa terlikuidasi. }
function LiqPrice(WB, Qty, Entry, MMR: Double; S: Integer): Double;
var
  Den: Double;
begin
  Result := 0;
  Den := Qty * MMR - S * Qty;
  if (Qty <= 0) or (Den = 0) then
    Exit;
  Result := (WB - S * Qty * Entry) / Den;
  if Result < 0 then
    Result := 0;
end;

{ % harga harus bergerak melawan posisi sampai likuidasi }
function LiqDist(Liq, Entry: Double; S: Integer): Double;
begin
  if Entry <= 0 then
    Result := 0
  else if Liq <= 0 then
    Result := 100   // long tanpa likuidasi: harga harus jatuh ke 0
  else
    Result := S * (Entry - Liq) / Entry * 100;
end;

{ ---------- form ---------- }

function TLevForm.MakeLabel(X, Y: Integer; const Txt: string): TLabel;
begin
  Result := TLabel.Create(Self);
  Result.Parent := pnlTop;
  Result.Left := X;
  Result.Top := Y;
  Result.Caption := Txt;
  Result.Font.Color := clrDim;
end;

function TLevForm.MakeEdit(X, Y, W: Integer; const Txt: string): TEdit;
begin
  Result := TEdit.Create(Self);
  Result.Parent := pnlTop;
  Result.SetBounds(X, Y, W, 24);
  Result.Color := clrPanel2;
  Result.Font.Color := clrText;
  Result.Font.Style := [fsBold];
  Result.Ctl3D := False;
  Result.Text := Txt;
  Result.OnChange := InputChange;
end;

function TLevForm.MakeCombo(X, Y, W: Integer; const Items: array of string): TComboBox;
var
  I: Integer;
begin
  Result := TComboBox.Create(Self);
  Result.Parent := pnlTop;
  Result.Style := csDropDownList;
  Result.SetBounds(X, Y, W, 24);
  Result.Color := clrPanel2;
  Result.Font.Color := clrText;
  Result.Font.Style := [fsBold];
  Result.Ctl3D := False;
  for I := 0 to High(Items) do
    Result.Items.Add(Items[I]);
  Result.ItemIndex := 0;
  Result.OnChange := InputChange;
end;

function TLevForm.MakeTrack(X, Y, W, AMin, AMax: Integer): TTrackBar;
begin
  Result := TTrackBar.Create(Self);
  Result.Parent := pnlTop;
  Result.SetBounds(X, Y, W, 30);
  Result.Min := AMin;
  Result.Max := AMax;
  Result.TickStyle := tsNone;
  Result.ThumbLength := 18;
end;

constructor TLevForm.Create(AOwner: TComponent);
const
  Cols: array[0..10] of string = ('Pakai modal', 'Margin (USDT)', 'Nilai posisi', 'Lev efektif',
    'Likuidasi Isolated', 'Jarak', 'Likuidasi Cross', 'Jarak', 'Margin rasio awal',
    'Rugi di SL (% modal)', 'Status');
  Wid: array[0..10] of Integer = (85, 110, 120, 85, 125, 75, 125, 75, 120, 135, 230);
var
  I: Integer;
  Col: TListColumn;
begin
  inherited CreateNew(AOwner);
  Caption := 'Hitung Leverage - margin rasio, likuidasi & ketahanan modal';
  SetBounds(90, 60, 1420, 860);
  Color := clrBg;
  Font.Name := 'Segoe UI';
  Font.Size := 9;
  Font.Color := clrText;
  OnClose := FormClose;
  FSync := True;

  pnlTop := TPanel.Create(Self);
  pnlTop.Parent := Self;
  pnlTop.Align := alTop;
  pnlTop.Height := 156;
  pnlTop.BevelOuter := bvNone;
  pnlTop.Color := clrPanel;

  lblCoin := MakeLabel(12, 8, 'Hitung Leverage');
  lblCoin.Font.Size := 15;
  lblCoin.Font.Style := [fsBold];
  lblCoin.Font.Color := clrGold;
  lblLevel := MakeLabel(330, 14, '');
  lblLevel.Font.Size := 10;
  lblLevel.Font.Style := [fsBold];
  lblLevel.Font.Color := clrText;

  MakeLabel(12, 46, 'Modal (USDT)');
  edModal := MakeEdit(12, 64, 110, '100');
  MakeLabel(134, 46, 'Arah');
  cbSide := MakeCombo(134, 64, 110, ['Long (beli)', 'Short (jual)']);
  cbSide.OnChange := SideChange;
  MakeLabel(256, 46, 'Mode margin');
  cbMode := MakeCombo(256, 64, 110, ['Isolated', 'Cross']);
  MakeLabel(378, 46, 'Harga masuk');
  edEntry := MakeEdit(378, 64, 120, '');
  MakeLabel(510, 46, 'Stop loss (harga)');
  edSL := MakeEdit(510, 64, 120, '');
  MakeLabel(642, 46, 'Maint. margin %');
  edMMR := MakeEdit(642, 64, 90, '0.5');
  MakeLabel(744, 46, 'Fee taker %');
  edFee := MakeEdit(744, 64, 80, '0.05');
  with MakeLabel(840, 50, 'Maint. margin Binance tier 1: BTC/ETH 0.4%, altcoin 0.5-1%.' + #13#10 +
    'Stop loss otomatis diisi sedikit di luar support (long) / resisten (short).' + #13#10 +
    'Angka desimal pakai titik, contoh 0.5') do
    Font.Color := clrDim;

  lblPct := MakeLabel(12, 102, 'Pakai modal: 10%');
  lblPct.Font.Style := [fsBold];
  lblPct.Font.Color := clrText;
  tbPct := MakeTrack(150, 98, 380, 1, 100);
  tbPct.OnChange := PctTrack;
  edPct := MakeEdit(536, 100, 50, '10');
  edPct.OnChange := PctEdit;
  MakeLabel(590, 104, '%');

  lblLev := MakeLabel(640, 102, 'Leverage: 10x');
  lblLev.Font.Style := [fsBold];
  lblLev.Font.Color := clrText;
  tbLev := MakeTrack(760, 98, 380, 1, MaxLev);
  tbLev.OnChange := LevTrack;
  edLev := MakeEdit(1146, 100, 50, '10');
  edLev.OnChange := LevEdit;
  MakeLabel(1200, 104, 'x');
  tbPct.Position := 10;
  tbLev.Position := 10;

  memo := TMemo.Create(Self);
  memo.Parent := Self;
  memo.Align := alBottom;
  memo.Height := 400;
  memo.ReadOnly := True;
  memo.ScrollBars := ssBoth;
  memo.WordWrap := False;
  memo.BorderStyle := bsNone;
  memo.Color := clrBg;
  memo.Font.Name := 'Consolas';
  memo.Font.Size := 10;
  memo.Font.Color := clrText;

  with TSplitter.Create(Self) do
  begin
    Parent := Self;
    Align := alBottom;
    Height := 5;
    Color := clrBorder;
  end;

  lv := TListView.Create(Self);
  lv.Parent := Self;
  lv.Align := alClient;
  lv.ViewStyle := vsReport;
  lv.ReadOnly := True;
  lv.RowSelect := True;
  lv.HideSelection := False;
  lv.Color := clrBg;
  lv.Font.Color := clrText;
  lv.OnCustomDrawItem := lvDrawItem;
  lv.OnClick := lvClick;
  for I := 0 to High(Cols) do
  begin
    Col := lv.Columns.Add;
    Col.Caption := Cols[I];
    Col.Width := Wid[I];
  end;
  FSync := False;
end;

procedure TLevForm.FormClose(Sender: TObject; var Action: TCloseAction);
begin
  Action := caHide;
end;

function TLevForm.Side: Integer;
begin
  if cbSide.ItemIndex = 1 then Result := -1 else Result := 1;
end;

function TLevForm.IsCross: Boolean;
begin
  Result := cbMode.ItemIndex = 1;
end;

function TLevForm.Calc(Pct, Lev: Double): TLevCalc;
var
  W, E, M, F: Double;
begin
  FillChar(Result, SizeOf(Result), 0);
  W := Num(edModal.Text, 0);
  E := Num(edEntry.Text, 0);
  M := Num(edMMR.Text, 0.5) / 100;
  F := Num(edFee.Text, 0) / 100;
  Result.Pct := Pct;
  Result.Lev := Lev;
  if (W <= 0) or (E <= 0) or (Lev <= 0) then
    Exit;
  Result.Margin := W * Pct / 100;                   // margin awal
  Result.Notional := Result.Margin * Lev;           // nilai posisi
  Result.Qty := Result.Notional / E;
  Result.EffLev := Result.Notional / W;             // = pakai% x leverage
  Result.FeeOpen := Result.Notional * F;
  Result.MM := Result.Notional * M;                 // maintenance margin
  Result.LiqIso := LiqPrice(Result.Margin, Result.Qty, E, M, Side);
  Result.LiqCross := LiqPrice(W - Result.FeeOpen, Result.Qty, E, M, Side);
  Result.DistIso := LiqDist(Result.LiqIso, E, Side);
  Result.DistCross := LiqDist(Result.LiqCross, E, Side);
  if Result.Margin > 0 then
    Result.MRIso := Result.MM / Result.Margin * 100;
  if W - Result.FeeOpen > 0 then
    Result.MRCross := Result.MM / (W - Result.FeeOpen) * 100;
end;

{ jarak harga masuk ke stop loss (%), 0 bila belum diisi / di sisi yang salah }
function TLevForm.SLDist: Double;
var
  E, SL: Double;
begin
  Result := 0;
  E := Num(edEntry.Text, 0);
  SL := Num(edSL.Text, 0);
  if (E <= 0) or (SL <= 0) then
    Exit;
  Result := Side * (E - SL) / E * 100;
  if Result < 0 then
    Result := 0;
end;

{ 0 aman, 1 waspada, 2 bahaya: likuidasi harus jauh di luar stop loss }
function TLevForm.Status(const C: TLevCalc; Dsl: Double): Integer;
var
  D, MR: Double;
begin
  if IsCross then
  begin
    D := C.DistCross;
    MR := C.MRCross;
  end
  else
  begin
    D := C.DistIso;
    MR := C.MRIso;
  end;
  if Dsl > 0 then
  begin
    if D <= Dsl then Result := 2
    else if (D < Dsl * 2) or (MR >= 50) then Result := 1
    else Result := 0;
  end
  else
  begin
    if (D < 5) or (MR >= 80) then Result := 2
    else if (D < 15) or (MR >= 50) then Result := 1
    else Result := 0;
  end;
end;

function StatusText(St: Integer; Dsl: Double): string;
begin
  case St of
    2: if Dsl > 0 then Result := 'BAHAYA: likuidasi sebelum SL' else Result := 'BAHAYA: likuidasi dekat';
    1: Result := 'WASPADA: jarak likuidasi tipis';
  else
    Result := 'AMAN';
  end;
end;

procedure TLevForm.SetCoin(const Sym: string; const A: TAnalysis);

  procedure Below(V: Double; var Best: Double);
  begin
    if (V > 0) and (V < FPrice) and (V > Best) then Best := V;
  end;

  procedure Above(V: Double; var Best: Double);
  begin
    if (V > FPrice) and ((Best = 0) or (V < Best)) then Best := V;
  end;

begin
  FSym := Sym;
  FPrice := 0;
  FSup := 0;
  FRes := 0;
  if A.Ok then
  begin
    FPrice := A.Price;
    { level terdekat dari analisa grafik }
    Below(A.S1, FSup); Below(A.S2, FSup); Below(A.SwingSup, FSup);
    Below(A.StrongSup, FSup); Below(A.RangeLow, FSup);
    Above(A.R1, FRes); Above(A.R2, FRes); Above(A.SwingRes, FRes);
    Above(A.StrongRes, FRes); Above(A.RangeHigh, FRes);
  end;
  if Sym <> '' then
    lblCoin.Caption := 'Hitung Leverage  ' + Sym
  else
    lblCoin.Caption := 'Hitung Leverage';
  if FPrice > 0 then
    lblLevel.Caption := 'Harga ' + FmtPrice(FPrice) + '    Support terdekat ' + FmtPrice(FSup) +
      '    Resisten terdekat ' + FmtPrice(FRes)
  else
    lblLevel.Caption := 'Belum ada grafik: isi harga masuk dan stop loss sendiri';
  FSync := True;
  try
    if FPrice > 0 then
      edEntry.Text := FloatToStr(FPrice);
    DefaultSL;
  finally
    FSync := False;
  end;
  Recalc;
end;

{ stop loss bawaan: 0.3% di luar support (long) / resisten (short) }
procedure TLevForm.DefaultSL;
begin
  if (Side > 0) and (FSup > 0) then
    edSL.Text := FmtPrice(FSup * 0.997)
  else if (Side < 0) and (FRes > 0) then
    edSL.Text := FmtPrice(FRes * 1.003)
  else
    edSL.Text := '';
  edSL.Text := StringReplace(edSL.Text, ',', '', [rfReplaceAll]);
end;

procedure TLevForm.SideChange(Sender: TObject);
begin
  FSync := True;
  try
    DefaultSL;
  finally
    FSync := False;
  end;
  Recalc;
end;

procedure TLevForm.InputChange(Sender: TObject);
begin
  if not FSync then
    Recalc;
end;

procedure TLevForm.PctTrack(Sender: TObject);
begin
  if FSync then Exit;
  FSync := True;
  try
    edPct.Text := IntToStr(tbPct.Position);
  finally
    FSync := False;
  end;
  Recalc;
end;

procedure TLevForm.LevTrack(Sender: TObject);
begin
  if FSync then Exit;
  FSync := True;
  try
    edLev.Text := IntToStr(tbLev.Position);
  finally
    FSync := False;
  end;
  Recalc;
end;

procedure TLevForm.PctEdit(Sender: TObject);
begin
  if FSync then Exit;
  FSync := True;
  try
    tbPct.Position := EnsureRange(Round(Num(edPct.Text, 10)), 1, 100);
  finally
    FSync := False;
  end;
  Recalc;
end;

procedure TLevForm.LevEdit(Sender: TObject);
begin
  if FSync then Exit;
  FSync := True;
  try
    tbLev.Position := EnsureRange(Round(Num(edLev.Text, 10)), 1, MaxLev);
  finally
    FSync := False;
  end;
  Recalc;
end;

{ klik baris tabel: pakai persentase modal baris itu }
procedure TLevForm.lvClick(Sender: TObject);
begin
  if (lv.Selected <> nil) and (lv.Selected.Index <= High(FRowPct)) then
    tbPct.Position := FRowPct[lv.Selected.Index];
end;

procedure TLevForm.lvDrawItem(Sender: TCustomListView; Item: TListItem; State: TCustomDrawState;
  var DefaultDraw: Boolean);
begin
  if Item.Index > High(FRowStat) then Exit;
  case FRowStat[Item.Index] of
    2: Sender.Canvas.Font.Color := clrDown;
    1: Sender.Canvas.Font.Color := clrGold;
  else
    Sender.Canvas.Font.Color := clrUp;
  end;
  if FRowPct[Item.Index] = tbPct.Position then
  begin
    Sender.Canvas.Brush.Color := clrPanel2;
    Sender.Canvas.Font.Style := [fsBold];
  end
  else
  begin
    Sender.Canvas.Brush.Color := clrBg;
    Sender.Canvas.Font.Style := [];
  end;
end;

procedure TLevForm.Recalc;
var
  W, E, MMR, Fee, Lev, Pct, Dsl, D, P, PnL, MB, MR, Sisa, Liq, MaxEff: Double;
  I, J, N, St, SafeLev, Risk1, Risk2: Integer;
  C, T: TLevCalc;
  Pcts: array of Integer;
  It: TListItem;
  L: TStringList;
  ModeName, SideName, S: string;
begin
  if FSync or (lv = nil) then Exit;
  W := Num(edModal.Text, 0);
  E := Num(edEntry.Text, 0);
  MMR := Num(edMMR.Text, 0.5);
  Fee := Num(edFee.Text, 0);
  Pct := tbPct.Position;
  Lev := tbLev.Position;
  lblPct.Caption := 'Pakai modal: ' + IntToStr(tbPct.Position) + '%';
  lblLev.Caption := 'Leverage: ' + IntToStr(tbLev.Position) + 'x';
  Dsl := SLDist;
  if IsCross then ModeName := 'Cross' else ModeName := 'Isolated';
  if Side > 0 then SideName := 'LONG' else SideName := 'SHORT';

  { tabel: daftar persen modal + persen yang dipilih }
  SetLength(Pcts, 0);
  for I := 0 to High(UsePcts) do
  begin
    if (tbPct.Position < UsePcts[I]) and ((I = 0) or (tbPct.Position > UsePcts[I - 1])) then
    begin
      SetLength(Pcts, Length(Pcts) + 1);
      Pcts[High(Pcts)] := tbPct.Position;
    end;
    SetLength(Pcts, Length(Pcts) + 1);
    Pcts[High(Pcts)] := UsePcts[I];
  end;
  SetLength(FRowStat, Length(Pcts));
  SetLength(FRowPct, Length(Pcts));

  lv.Items.BeginUpdate;
  try
    lv.Items.Clear;
    if (W > 0) and (E > 0) then
      for I := 0 to High(Pcts) do
      begin
        T := Calc(Pcts[I], Lev);
        St := Status(T, Dsl);
        FRowStat[I] := St;
        FRowPct[I] := Pcts[I];
        It := lv.Items.Add;
        It.Caption := IntToStr(Pcts[I]) + '%';
        It.SubItems.Add(Usd(T.Margin));
        It.SubItems.Add(Usd(T.Notional));
        It.SubItems.Add(FormatFloat('0.00', T.EffLev) + 'x');
        if T.LiqIso > 0 then It.SubItems.Add(FmtPrice(T.LiqIso)) else It.SubItems.Add('tidak ada');
        It.SubItems.Add(FormatFloat('0.00', T.DistIso) + '%');
        if T.LiqCross > 0 then It.SubItems.Add(FmtPrice(T.LiqCross)) else It.SubItems.Add('tidak ada');
        It.SubItems.Add(FormatFloat('0.00', T.DistCross) + '%');
        if IsCross then MR := T.MRCross else MR := T.MRIso;
        It.SubItems.Add(FormatFloat('0.00', MR) + '%');
        if Dsl > 0 then
          It.SubItems.Add(FormatFloat('0.00', T.EffLev * Dsl + 2 * T.EffLev * Fee) + '%')
        else
          It.SubItems.Add('-');
        It.SubItems.Add(StatusText(St, Dsl));
      end;
  finally
    lv.Items.EndUpdate;
  end;

  L := TStringList.Create;
  try
    if (W <= 0) or (E <= 0) then
    begin
      L.Add(' Isi modal dan harga masuk untuk mulai menghitung.');
      memo.Lines.Assign(L);
      Exit;
    end;
    C := Calc(Pct, Lev);

    L.Add(' RUMUS (Binance Futures, USDT-M, tier pertama)');
    L.Add(' ------------------------------------------------------------------------------');
    L.Add(' Margin awal        = Modal x Pakai modal %');
    L.Add(' Nilai posisi       = Margin awal x Leverage');
    L.Add(' Leverage efektif   = Nilai posisi / Modal  = Pakai modal % x Leverage');
    L.Add(' Jumlah koin (Qty)  = Nilai posisi / Harga masuk');
    L.Add(' Maint. margin (MM) = Nilai posisi x Maint. margin %');
    L.Add(' Harga likuidasi    = (Saldo - s x Qty x Harga masuk) / (Qty x MMR - s x Qty)');
    L.Add('                      s = +1 long, -1 short;  Saldo Isolated = margin awal, Cross = seluruh modal');
    L.Add(' Margin rasio       = MM / (Saldo + PnL belum terealisasi)   ->  100% = LIKUIDASI');
    L.Add('');

    L.Add(Format(' HASIL  %s %s  %s  -  modal %s USDT, pakai %d%%, leverage %dx',
      [SideName, FSym, ModeName, Usd(W), Round(Pct), Round(Lev)]));
    L.Add(' ------------------------------------------------------------------------------');
    L.Add(' Margin awal          : ' + Usd(C.Margin) + ' USDT');
    L.Add(' Nilai posisi         : ' + Usd(C.Notional) + ' USDT   (' + FormatFloat('0.######', C.Qty) + ' koin)');
    L.Add(' Leverage efektif     : ' + FormatFloat('0.00', C.EffLev) + 'x dari total modal');
    L.Add(' Maintenance margin   : ' + Usd(C.MM) + ' USDT');
    L.Add(' Fee buka + tutup     : ' + Usd(2 * C.FeeOpen) + ' USDT (perkiraan)');
    if C.LiqIso > 0 then S := FmtPrice(C.LiqIso) else S := 'tidak ada';
    L.Add(' Likuidasi Isolated   : ' + PadR(S, 16) + 'jarak ' + FormatFloat('0.00', C.DistIso) +
      '%   margin rasio awal ' + FormatFloat('0.00', C.MRIso) + '%');
    if C.LiqCross > 0 then S := FmtPrice(C.LiqCross) else S := 'tidak ada';
    L.Add(' Likuidasi Cross      : ' + PadR(S, 16) + 'jarak ' + FormatFloat('0.00', C.DistCross) +
      '%   margin rasio awal ' + FormatFloat('0.00', C.MRCross) + '%');
    L.Add('');

    { uji ketahanan: harga bergerak melawan posisi }
    L.Add(' UJI KETAHANAN MODAL  (harga bergerak melawan posisi ' + SideName + ', mode ' + ModeName + ')');
    L.Add(' ------------------------------------------------------------------------------');
    L.Add(' Gerak   Harga            PnL (USDT)     Margin rasio   Sisa modal      Kondisi');
    for I := 0 to High(StressMoves) do
    begin
      D := StressMoves[I] / 100;
      P := E * (1 - Side * D);
      PnL := -C.Notional * D;
      if IsCross then MB := W - C.FeeOpen + PnL else MB := C.Margin + PnL;
      if MB > 0 then MR := C.Qty * P * MMR / 100 / MB * 100 else MR := 999;
      if MR >= 100 then
      begin
        if IsCross then Sisa := 0 else Sisa := W - C.Margin - C.FeeOpen;
        S := 'LIKUIDASI';
      end
      else
      begin
        Sisa := W - C.FeeOpen + PnL;
        if MR >= 80 then S := 'BAHAYA (hampir likuidasi)'
        else if MR >= 50 then S := 'WASPADA'
        else S := 'aman';
      end;
      if MR >= 999 then J := 999 else J := Round(MR);
      if Side > 0 then N := -1 else N := 1;
      L.Add(' ' + PadR(FormatFloat('0.0', N * StressMoves[I]) + '%', 7) + ' ' + PadR(FmtPrice(P), 16) +
        Pad(Usd(PnL), 12) + '   ' + Pad(IntToStr(J) + '%', 10) + '   ' + Pad(Usd(Sisa), 12) +
        '    ' + S);
    end;
    L.Add('');

    { analisa terhadap stop loss / support }
    L.Add(' ANALISA & SARAN');
    L.Add(' ------------------------------------------------------------------------------');
    if Side > 0 then
      S := 'support terdekat ' + FmtPrice(FSup)
    else
      S := 'resisten terdekat ' + FmtPrice(FRes);
    if Dsl > 0 then
    begin
      L.Add(' Stop loss ' + FmtPrice(Num(edSL.Text, 0)) + ' = ' + FormatFloat('0.00', Dsl) +
        '% dari harga masuk (' + S + ').');
      L.Add(' Rugi bila kena stop loss: ' + Usd(C.Notional * Dsl / 100 + 2 * C.FeeOpen) + ' USDT = ' +
        FormatFloat('0.00', C.EffLev * Dsl + 2 * C.EffLev * Fee) + '% dari total modal.');

      { leverage tertinggi yang likuidasinya masih >= 2x jarak stop loss }
      SafeLev := 0;
      for J := MaxLev downto 1 do
      begin
        T := Calc(Pct, J);
        if IsCross then D := T.DistCross else D := T.DistIso;
        if D >= Dsl * 2 then
        begin
          SafeLev := J;
          Break;
        end;
      end;
      if SafeLev > 0 then
        L.Add(Format(' Leverage maksimal aman (%s, pakai %d%% modal): %dx  -> likuidasi minimal 2x lebih jauh dari stop loss.',
          [ModeName, Round(Pct), SafeLev]))
      else
        L.Add(' Tidak ada leverage yang aman: stop loss terlalu jauh untuk persentase modal ini.');

      { pemakaian modal agar rugi di stop loss hanya 1% / 2% modal }
      MaxEff := Dsl + 2 * Fee;
      if MaxEff > 0 then
      begin
        Risk1 := Floor(1 / MaxEff / Lev * 100);
        Risk2 := Floor(2 / MaxEff / Lev * 100);
        L.Add(Format(' Agar rugi di stop loss maksimal 1%% modal: pakai <= %d%% modal (%dx). Maksimal 2%%: pakai <= %d%% modal.',
          [Min(Risk1, 100), Round(Lev), Min(Risk2, 100)]));
      end;
    end
    else
      L.Add(' Stop loss belum diisi (' + S + '). Isi stop loss agar status & saran leverage dihitung dari level grafik.');

    St := Status(C, Dsl);
    if IsCross then Liq := C.DistCross else Liq := C.DistIso;
    case St of
      2: L.Add(' KESIMPULAN: BAHAYA. Likuidasi di ' + FormatFloat('0.00', Liq) +
        '% - turunkan leverage atau persentase modal.');
      1: L.Add(' KESIMPULAN: WASPADA. Likuidasi di ' + FormatFloat('0.00', Liq) +
        '% - ruang gerak tipis, pasang stop loss disiplin.');
    else
      L.Add(' KESIMPULAN: AMAN. Likuidasi di ' + FormatFloat('0.00', Liq) +
        '% - modal masih tahan gerak melawan posisi.');
    end;
    if not IsCross and (C.DistCross > C.DistIso) then
      L.Add(' Catatan: Isolated hanya mempertaruhkan margin posisi (' + Usd(C.Margin) +
        ' USDT); Cross lebih tahan (jarak ' + FormatFloat('0.00', C.DistCross) + '%) tetapi bisa menghabiskan seluruh modal.');
    L.Add(' Perhitungan memakai tier maintenance pertama; posisi sangat besar memakai MMR lebih tinggi di Binance.');
    memo.Lines.Assign(L);
  finally
    L.Free;
  end;
end;

procedure ShowLeverage(const Sym: string; const A: TAnalysis);
begin
  if LevForm = nil then
    LevForm := TLevForm.Create(Application);
  LevForm.SetCoin(Sym, A);
  LevForm.Show;
  LevForm.BringToFront;
end;

end.
