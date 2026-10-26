unit uBtc;

{ Jendela khusus BTC: grafik, naik/turun, support, resisten, kapan boleh beli/jual }

interface

uses
  Windows, Messages, SysUtils, Classes, Graphics, Controls, Forms, StdCtrls,
  ExtCtrls, uAnalysis, uBinance, uWorkers, uChart;

type
  TBtcForm = class(TForm)
  private
    pnlHead, pnlSignal, pnlChart, pnlTF, btnRefresh, btnOpen: TPanel;
    FTFBtns: array[0..ChartTFCount - 1] of TPanel;
    FChartTF: string;
    lblPrice, lblChg, lblInfo: TLabel;
    pbChart: TPaintBox;
    memo: TMemo;
    tmr: TTimer;
    FBusy: Boolean;
    FK: TKlines;
    FA: TAnalysis;
    FHoverX: Integer;
    FCV: TChartView;
    FOlderBusy, FNoMoreHistory: Boolean;
    tmrLive: TTimer;
    FLiveBusy: Boolean;
    FLiveStart: Cardinal;
    procedure LoadOlderIfNeeded;
    procedure WMOlder(var M: TMessage); message WM_FT_OLDER;
    procedure LiveTimer(Sender: TObject);
    procedure WMLive(var M: TMessage); message WM_FT_LIVE;
    procedure DoRefresh(Sender: TObject);
    procedure DoOpen(Sender: TObject);
    procedure BtcFormClose(Sender: TObject; var Action: TCloseAction);
    procedure TFClick(Sender: TObject);
    procedure UpdateTFButtons;
    procedure ChartPaint(Sender: TObject);
    procedure ChartMouseMove(Sender: TObject; Shift: TShiftState; X, Y: Integer);
    procedure ChartMouseDown(Sender: TObject; Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
    procedure ChartMouseUp(Sender: TObject; Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
    procedure ChartDblClick(Sender: TObject);
    procedure WMBtc(var M: TMessage); message WM_FT_BTC;
    procedure ShowData(D: TBtcData);
  public
    constructor Create(AOwner: TComponent); override;
  end;

procedure ShowBtcForm;
function BtcChartWheel(P: TPoint; Delta: Integer): Boolean;

implementation

const
  TFWeight: array[0..3] of Integer = (1, 2, 2, 1);

var
  BtcForm: TBtcForm = nil;

procedure ShowBtcForm;
begin
  if BtcForm = nil then
    BtcForm := TBtcForm.Create(Application);
  BtcForm.Show;
  BtcForm.BringToFront;
  BtcForm.tmr.Enabled := True;
  BtcForm.DoRefresh(nil);
end;

function MakeBtn(Owner: TComponent; AParent: TWinControl; const Txt: string;
  Bg, Fg: TColor; Click: TNotifyEvent): TPanel;
begin
  Result := TPanel.Create(Owner);
  Result.Parent := AParent;
  Result.BevelOuter := bvNone;
  Result.Color := Bg;
  Result.Font.Color := Fg;
  Result.Font.Style := [fsBold];
  Result.Font.Size := 10;
  Result.Caption := Txt;
  Result.Cursor := crHandPoint;
  Result.OnClick := Click;
end;

constructor TBtcForm.Create(AOwner: TComponent);
var
  I: Integer;
begin
  inherited CreateNew(AOwner);
  Caption := 'Fernanda Taker - Analisa Khusus BTC';
  Width := 1000;
  Height := 860;
  Position := poScreenCenter;
  Color := clrBg;
  Font.Name := 'Segoe UI';
  Font.Size := 9;
  Font.Color := clrText;
  OnClose := BtcFormClose;
  FHoverX := -1;

  pnlHead := TPanel.Create(Self);
  pnlHead.Parent := Self;
  pnlHead.Align := alTop;
  pnlHead.Height := 104;
  pnlHead.BevelOuter := bvNone;
  pnlHead.Color := clrPanel;

  lblPrice := TLabel.Create(Self);
  lblPrice.Parent := pnlHead;
  lblPrice.SetBounds(18, 6, 320, 40);
  lblPrice.Font.Size := 26;
  lblPrice.Font.Style := [fsBold];
  lblPrice.Font.Color := clrGold;
  lblPrice.Caption := 'BTC ...';

  lblChg := TLabel.Create(Self);
  lblChg.Parent := pnlHead;
  lblChg.SetBounds(20, 52, 320, 24);
  lblChg.Font.Size := 14;
  lblChg.Font.Style := [fsBold];

  lblInfo := TLabel.Create(Self);
  lblInfo.Parent := pnlHead;
  lblInfo.SetBounds(20, 80, 420, 18);
  lblInfo.Font.Color := clrDim;

  pnlSignal := TPanel.Create(Self);
  pnlSignal.Parent := pnlHead;
  pnlSignal.SetBounds(440, 12, 320, 80);
  pnlSignal.BevelOuter := bvNone;
  pnlSignal.Font.Size := 18;
  pnlSignal.Font.Style := [fsBold];
  pnlSignal.Color := clrPanel2;
  pnlSignal.Font.Color := clrText;
  pnlSignal.Caption := 'MEMUAT...';

  btnRefresh := MakeBtn(Self, pnlHead, 'Refresh', clrPanel2, clrText, DoRefresh);
  btnRefresh.SetBounds(776, 12, 190, 36);
  btnOpen := MakeBtn(Self, pnlHead, 'Buka BTC di Binance.bh', clrGold, clrBg, DoOpen);
  btnOpen.SetBounds(776, 56, 190, 36);

  pnlTF := TPanel.Create(Self);
  pnlTF.Parent := Self;
  pnlTF.Align := alTop;
  pnlTF.Top := pnlHead.Height;
  pnlTF.Height := 34;
  pnlTF.BevelOuter := bvNone;
  pnlTF.Color := clrPanel;
  for I := 0 to ChartTFCount - 1 do
  begin
    FTFBtns[I] := MakeBtn(Self, pnlTF, ChartTFLabels[I], clrPanel2, clrDim, TFClick);
    FTFBtns[I].SetBounds(8 + I * 66, 5, 60, 24);
    FTFBtns[I].Font.Size := 9;
    FTFBtns[I].Tag := I;
  end;
  FChartTF := ChartTFApi[DefaultChartTF];
  UpdateTFButtons;

  pnlChart := TPanel.Create(Self);
  pnlChart.Parent := Self;
  pnlChart.Align := alTop;
  pnlChart.Top := pnlTF.Top + pnlTF.Height;
  pnlChart.Height := 380;
  pnlChart.BevelOuter := bvNone;
  pnlChart.Color := clrPanel;
  pnlChart.DoubleBuffered := True;

  pbChart := TPaintBox.Create(Self);
  pbChart.Parent := pnlChart;
  pbChart.Align := alClient;
  pbChart.OnPaint := ChartPaint;
  pbChart.OnMouseMove := ChartMouseMove;
  pbChart.OnMouseDown := ChartMouseDown;
  pbChart.OnMouseUp := ChartMouseUp;
  pbChart.OnDblClick := ChartDblClick;
  pbChart.Cursor := crCross;

  memo := TMemo.Create(Self);
  memo.Parent := Self;
  memo.Align := alClient;
  memo.BorderStyle := bsNone;
  memo.ReadOnly := True;
  memo.ScrollBars := ssVertical;
  memo.WordWrap := False;
  memo.Color := clrBg;
  memo.Font.Name := 'Consolas';
  memo.Font.Size := 10;
  memo.Font.Color := clrText;

  tmr := TTimer.Create(Self);
  tmr.Interval := 20000;
  tmr.OnTimer := DoRefresh;

  tmrLive := TTimer.Create(Self);
  tmrLive.Interval := 1000;
  tmrLive.OnTimer := LiveTimer;
end;

procedure TBtcForm.BtcFormClose(Sender: TObject; var Action: TCloseAction);
begin
  tmr.Enabled := False;
  Action := caHide;
end;

procedure TBtcForm.DoRefresh(Sender: TObject);
begin
  if FBusy then
    Exit;
  FBusy := True;
  TBtcThread.Create(Handle, FChartTF);
end;

procedure TBtcForm.UpdateTFButtons;
var
  I: Integer;
begin
  for I := 0 to ChartTFCount - 1 do
    if ChartTFApi[I] = FChartTF then
    begin
      FTFBtns[I].Color := clrGold;
      FTFBtns[I].Font.Color := clrBg;
    end
    else
    begin
      FTFBtns[I].Color := clrPanel2;
      FTFBtns[I].Font.Color := clrDim;
    end;
end;

procedure TBtcForm.TFClick(Sender: TObject);
begin
  FChartTF := ChartTFApi[TPanel(Sender).Tag];
  UpdateTFButtons;
  ResetView(FCV);
  FNoMoreHistory := False;
  SetLength(FK, 0);
  pbChart.Invalidate;
  FBusy := False;   // permintaan baru boleh langsung jalan
  DoRefresh(nil);
end;

procedure TBtcForm.DoOpen(Sender: TObject);
begin
  OpenBinance(BtcSymbol);
end;

procedure TBtcForm.ChartPaint(Sender: TObject);
begin
  DrawCandles(pbChart.Canvas, pbChart.ClientRect, FK, FA, FHoverX, 'BTCUSDT  ' + ChartTFLabel(FChartTF), FCV);
end;

procedure TBtcForm.ChartMouseMove(Sender: TObject; Shift: TShiftState; X, Y: Integer);
begin
  FHoverX := X;
  if ViewMouseMove(FCV, X, Y) then
    LoadOlderIfNeeded;
  pbChart.Invalidate;
end;

procedure TBtcForm.LoadOlderIfNeeded;
begin
  if FCV.AtStart and not FOlderBusy and not FNoMoreHistory and (Length(FK) > 0) then
  begin
    FOlderBusy := True;
    TOlderThread.Create(Handle, BtcSymbol, FChartTF, FK[0].OpenTime - 1);
  end;
end;

procedure TBtcForm.WMOlder(var M: TMessage);
var
  D: TLiveData;
begin
  D := TLiveData(M.LParam);
  try
    FOlderBusy := False;
    if (D.Err <> '') or (D.Interval <> FChartTF) then
      Exit;
    if PrependKlines(FK, D.K) = 0 then
      FNoMoreHistory := True;
    pbChart.Invalidate;
  finally
    D.Free;
  end;
end;

procedure TBtcForm.ChartMouseDown(Sender: TObject; Button: TMouseButton;
  Shift: TShiftState; X, Y: Integer);
begin
  if Button <> mbLeft then
    Exit;
  ViewMouseDown(FCV, X, Y);
  pbChart.Cursor := crSizeAll;
end;

procedure TBtcForm.ChartMouseUp(Sender: TObject; Button: TMouseButton;
  Shift: TShiftState; X, Y: Integer);
begin
  ViewMouseUp(FCV);
  pbChart.Cursor := crCross;
end;

procedure TBtcForm.ChartDblClick(Sender: TObject);
begin
  ResetView(FCV);
  pbChart.Invalidate;
end;

function BtcChartWheel(P: TPoint; Delta: Integer): Boolean;
begin
  Result := (BtcForm <> nil) and BtcForm.Visible and
    (WindowFromPoint(P) = BtcForm.pnlChart.Handle);
  if Result then
  begin
    ViewZoom(BtcForm.FCV, Delta);
    BtcForm.pbChart.Invalidate;
    BtcForm.LoadOlderIfNeeded;
  end;
end;

procedure TBtcForm.LiveTimer(Sender: TObject);
begin
  if not Visible or (Length(FK) = 0) then
    Exit;
  if FLiveBusy and (GetTickCount - FLiveStart < 10000) then
    Exit;
  FLiveBusy := True;
  FLiveStart := GetTickCount;
  TLiveThread.Create(Handle, BtcSymbol, FChartTF);
end;

procedure TBtcForm.WMLive(var M: TMessage);
var
  D: TLiveData;
begin
  D := TLiveData(M.LParam);
  try
    FLiveBusy := False;
    if (D.Err <> '') or (D.Interval <> FChartTF) or (Length(D.K) = 0) or (Length(FK) = 0) then
      Exit;
    MergeKlines(FK, D.K);
    lblPrice.Caption := 'BTC  ' + FmtPrice(FK[High(FK)].C);
    pbChart.Invalidate;
  finally
    D.Free;
  end;
end;

procedure TBtcForm.WMBtc(var M: TMessage);
var
  D: TBtcData;
begin
  D := TBtcData(M.LParam);
  try
    FBusy := False;
    ShowData(D);
  finally
    D.Free;
  end;
end;

function Lv(D: Double; Price: Double): string;
begin
  Result := FmtPrice(D);
  if (Price > 0) and (D > 0) then
    Result := Result + ' (' + FmtPct((D - Price) / Price * 100) + ')';
end;

procedure TBtcForm.ShowData(D: TBtcData);
var
  L: TStringList;
  I, Total: Integer;
  A: TAnalysis;
  S, Verdict: string;
  Tot: Double;
begin
  if D.Err <> '' then
  begin
    pnlSignal.Caption := 'ERROR';
    pnlSignal.Color := clrPanel2;
    memo.Lines.Text := ' Gagal memuat data BTC:' + #13#10 + ' ' + D.Err;
    Exit;
  end;

  if D.AChart.Interval = FChartTF then   // abaikan hasil time frame lama
  begin
    // sambungkan agar riwayat lama yang sudah dimuat tidak hilang
    if (Length(FK) > 0) and (FA.Interval = FChartTF) then
      MergeKlines(FK, D.KChart)
    else
      FK := D.KChart;
    FA := D.AChart;
    pbChart.Invalidate;
  end;

  lblPrice.Caption := 'BTC  ' + FmtPrice(D.Price);
  if D.Chg >= 0 then
  begin
    lblChg.Caption := 'NAIK ' + FmtPct(D.Chg) + '  (24 jam)';
    lblChg.Font.Color := clrUp;
  end
  else
  begin
    lblChg.Caption := 'TURUN ' + FmtPct(D.Chg) + '  (24 jam)';
    lblChg.Font.Color := clrDown;
  end;
  lblInfo.Caption := Format('High %s   |   Low %s   |   Vol %s   |   %s',
    [FmtPrice(D.High), FmtPrice(D.Low), FmtUSD(D.QV), FormatDateTime('hh:nn:ss', Now)]);

  Total := 0;
  for I := 0 to 3 do
    if D.TF[I].Ok then
      Inc(Total, D.TF[I].Score * TFWeight[I]);
  if Total >= 10 then
  begin
    Verdict := 'BELI';
    pnlSignal.Caption := 'BOLEH BELI (LONG)';
    pnlSignal.Color := clrUp;
    pnlSignal.Font.Color := clrBg;
  end
  else if Total <= -10 then
  begin
    Verdict := 'JUAL';
    pnlSignal.Caption := 'BOLEH JUAL (SHORT)';
    pnlSignal.Color := clrDown;
    pnlSignal.Font.Color := clrText;
  end
  else
  begin
    Verdict := 'TUNGGU';
    pnlSignal.Caption := 'TUNGGU / WAIT';
    pnlSignal.Color := clrPanel2;
    pnlSignal.Font.Color := clrGold;
  end;

  L := TStringList.Create;
  try
    L.Add(Format(' KESIMPULAN BTC: %s   (skor gabungan %d)', [pnlSignal.Caption, Total]));
    L.Add('');
    if D.TF[1].Ok and D.TF[2].Ok then
    begin
      L.Add(' --- KAPAN BOLEH BELI ---');
      L.Add('  * Harga turun ke support 1j ' + Lv(D.TF[1].SwingSup, D.Price) + ' lalu memantul,');
      L.Add('    atau ke SUPPORT TERKUAT 4j ' + Lv(D.TF[2].StrongSup, D.Price) +
        Format(' (sudah memantul %dx)', [D.TF[2].StrongSupHits]));
      L.Add('  * ATAU candle tutup di atas resisten 1j ' + Lv(D.TF[1].SwingRes, D.Price) + ' dengan volume besar');
      L.Add(' --- KAPAN BOLEH JUAL ---');
      L.Add('  * Harga gagal tembus resisten 1j ' + Lv(D.TF[1].SwingRes, D.Price));
      L.Add('    atau RESISTEN TERKUAT 4j ' + Lv(D.TF[2].StrongRes, D.Price) +
        Format(' (%dx ditolak)', [D.TF[2].StrongResHits]));
      L.Add('  * ATAU candle tutup di bawah support 1j ' + Lv(D.TF[1].SwingSup, D.Price));
      L.Add('');
      if Verdict = 'BELI' then
      begin
        L.Add(' Rencana LONG : entry ' + FmtPrice(D.TF[1].SwingSup) + ' - ' + FmtPrice(D.Price));
        L.Add('                stop loss di bawah ' + FmtPrice(D.TF[2].SwingSup * 0.995));
        L.Add('                target 1 ' + FmtPrice(D.TF[1].SwingRes) + ', target 2 ' + FmtPrice(D.TF[2].SwingRes));
      end
      else if Verdict = 'JUAL' then
      begin
        L.Add(' Rencana SHORT: entry ' + FmtPrice(D.Price) + ' - ' + FmtPrice(D.TF[1].SwingRes));
        L.Add('                stop loss di atas ' + FmtPrice(D.TF[2].SwingRes * 1.005));
        L.Add('                target 1 ' + FmtPrice(D.TF[1].SwingSup) + ', target 2 ' + FmtPrice(D.TF[2].SwingSup));
      end
      else
        L.Add(' Belum ada konfirmasi kuat. Tunggu harga ke support (beli) / resisten (jual) atau breakout.');
      L.Add('');
    end;

    if D.DepthOk then
    begin
      Tot := D.BidUSD + D.AskUSD;
      if Tot > 0 then
        L.Add(Format(' Order book : beli %s (%.1f%%)  vs  jual %s (%.1f%%)',
          [FmtUSD(D.BidUSD), D.BidUSD / Tot * 100, FmtUSD(D.AskUSD), D.AskUSD / Tot * 100]));
      L.Add('');
    end;

    for I := 0 to 3 do
    begin
      A := D.TF[I];
      L.Add(Format(' ==== TIMEFRAME %s ====', [BtcIntervalNames[I]]));
      if not A.Ok then
      begin
        L.Add('  ' + A.Err);
        L.Add('');
        Continue;
      end;
      if A.ChgLast >= 0 then S := 'NAIK' else S := 'TURUN';
      L.Add(Format('  Candle sekarang : %s %s   |  Trend: %s', [S, FmtPct(A.ChgLast), A.Trend]));
      L.Add(Format('  Sinyal          : %s (skor %d)', [SignalText(A.Signal), A.Score]));
      L.Add(Format('  MA9 %s | MA25 %s | MA44 %s', [FmtPrice(A.MA[0]), FmtPrice(A.MA[1]), FmtPrice(A.MA[2])]));
      L.Add(Format('  MA99 %s | MA200 %s | MA650 %s', [FmtPrice(A.MA[3]), FmtPrice(A.MA[4]), FmtPrice(A.MA[5])]));
      if A.LastCrossAgo >= 0 then
        L.Add(Format('  Cross terakhir  : %s (%d candle lalu)', [A.LastCrossText, A.LastCrossAgo]));
      L.Add(Format('  Beli %s (%.1f%%)  |  Jual %s (%.1f%%)',
        [FmtUSD(A.BuyUSD), A.BuyPct, FmtUSD(A.SellUSD), A.SellPct]));
      L.Add('  Resisten        : ' + Lv(A.SwingRes, A.Price) + '   R1 ' + FmtPrice(A.R1) + '   R2 ' + FmtPrice(A.R2));
      L.Add('  Support         : ' + Lv(A.SwingSup, A.Price) + '   S1 ' + FmtPrice(A.S1) + '   S2 ' + FmtPrice(A.S2));
      L.Add(Format('  Support terkuat : %s  (memantul %dx)', [Lv(A.StrongSup, A.Price), A.StrongSupHits]));
      L.Add(Format('  Resisten terkuat: %s  (ditolak %dx)', [Lv(A.StrongRes, A.Price), A.StrongResHits]));
      if A.Breakout <> '' then
        L.Add('  WARNING         : ' + A.Breakout);
      L.Add('');
    end;
    L.Add(' Catatan: ini alat bantu analisa teknikal, bukan saran keuangan. Gunakan stop loss.');
    memo.Lines.Assign(L);
  finally
    L.Free;
  end;
end;

end.
