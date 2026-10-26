unit uMain;

{ Form utama Fernanda Taker. Semua komponen dibuat lewat kode (tanpa .dfm). }

interface

uses
  Windows, Messages, SysUtils, Classes, Graphics, Controls, Forms, StdCtrls,
  ExtCtrls, ComCtrls, CommCtrl, ImgList, Math, uAnalysis, uBinance, uWorkers,
  uChart, uBtc;

const
  WM_FT_HIDESUGGEST = WM_USER + 301;

type
  TCoinRow = record
    Symbol: string;
    Price, Chg24, QuoteVol, High24, Low24: Double;
    Scanned: Boolean;
    BuyPct, SellPct, BuyUSD, SellUSD: Double;
    Trend, LastCross, Breakout, Signal: string;
    TrendScore, Score, CrossAgo: Integer;
    CrossGolden: Boolean;
    Support, Resist, Rise4: Double;
    StrongSup: Double;
    StrongHits: Integer;
    Alert24, AlertRise: Boolean;
    AlertBO: string;
  end;

  TMainForm = class(TForm)
  private
    pnlTop, pnlMarket, pnlRight, pnlBottom, pnlStatus, pnlCoinHead, pnlChart: TPanel;
    btnBtc, btnOpen: TPanel;
    lblSource, lblCoin, lblCoinPrice, lblCoinChg: TLabel;
    lblUp, lblDown, lblGainers, lblLosers: TLabel;
    edSearch, edThreshold: TEdit;
    cbFilter: TComboBox;
    pnlTF: TPanel;
    FTFBtns: array[0..ChartTFCount - 1] of TPanel;
    FInterval: string;
    chkSound: TCheckBox;
    lv: TListView;
    ilRows: TImageList;
    pbChart: TPaintBox;
    memoDetail: TMemo;
    lbAlerts, lbSuggest: TListBox;
    tmrDetail, tmrSelect, tmrRefresh, tmrLive: TTimer;
    lblLive: TLabel;
    FLiveBusy: Boolean;
    FLiveStart: Cardinal;

    FCoins: array of TCoinRow;
    FIndex: TStringList;
    FView: array of Integer;
    FSortCol: Integer;
    FSortDesc: Boolean;
    FScanner: TScannerThread;
    FSelected: string;
    FReqId: Integer;
    FScanned: Integer;
    FUpdating: Boolean;
    FLastTicker: TDateTime;
    FChartK: TKlines;
    FChartA: TAnalysis;
    FChartTitle: string;
    FHoverX: Integer;
    FCV: TChartView;   // posisi geser/zoom grafik
    FOlderBusy, FNoMoreHistory: Boolean;
    FDirty: Boolean;
    FStatusExtra: string;

    procedure BuildUI;
    function MakeLabel(AParent: TWinControl; X, Y: Integer; const Txt: string): TLabel;
    function MakeBtn(AParent: TWinControl; X, Y, W, H: Integer; const Txt: string;
      Bg, Fg: TColor; Click: TNotifyEvent): TPanel;
    function MakeHeader(AParent: TWinControl; const Txt: string): TPanel;
    function FindCoin(const Sym: string): Integer;
    function Threshold: Double;
    function PassFilter(const R: TCoinRow): Boolean;
    function CompareRows(A, B: Integer): Integer;
    procedure SortView;
    procedure RebuildView;
    procedure tmrRefreshTimer(Sender: TObject);
    procedure tmrLiveTimer(Sender: TObject);
    procedure WMLive(var M: TMessage); message WM_FT_LIVE;
    procedure UpdateMarketStrip;
    procedure UpdateCoinHeader;
    procedure UpdateSuggest;
    procedure ChooseSuggest(I: Integer);
    procedure AddAlert(const Sym, Txt: string);
    procedure SetSelected(const Sym: string);
    procedure SelectSymbol(const Sym: string);
    procedure RequestDetail;
    procedure ShowDetail(D: TDetailData);
    procedure ApplyAnalysis(Idx: Integer; const A: TAnalysis);
    procedure UpdateStatus(const Extra: string);

    procedure lvData(Sender: TObject; Item: TListItem);
    procedure lvCustomDrawItem(Sender: TCustomListView; Item: TListItem;
      State: TCustomDrawState; var DefaultDraw: Boolean);
    procedure lvCustomDrawSubItem(Sender: TCustomListView; Item: TListItem;
      SubItem: Integer; State: TCustomDrawState; var DefaultDraw: Boolean);
    procedure lvSelectItem(Sender: TObject; Item: TListItem; Selected: Boolean);
    procedure lvColumnClick(Sender: TObject; Column: TListColumn);
    procedure lvDblClick(Sender: TObject);
    procedure edSearchChange(Sender: TObject);
    procedure edSearchEnter(Sender: TObject);
    procedure edSearchExit(Sender: TObject);
    procedure edSearchKeyDown(Sender: TObject; var Key: Word; Shift: TShiftState);
    procedure edSearchKeyPress(Sender: TObject; var Key: Char);
    procedure lbSuggestDrawItem(Control: TWinControl; Index: Integer; Rect: TRect; State: TOwnerDrawState);
    procedure lbSuggestMouseUp(Sender: TObject; Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
    procedure lbSuggestKeyDown(Sender: TObject; var Key: Word; Shift: TShiftState);
    procedure FilterChange(Sender: TObject);
    procedure TFClick(Sender: TObject);
    procedure UpdateTFButtons;
    procedure btnBtcClick(Sender: TObject);
    procedure btnOpenClick(Sender: TObject);
    procedure lbAlertsDblClick(Sender: TObject);
    procedure lbAlertsDrawItem(Control: TWinControl; Index: Integer; Rect: TRect; State: TOwnerDrawState);
    procedure pbChartPaint(Sender: TObject);
    procedure pbChartMouseMove(Sender: TObject; Shift: TShiftState; X, Y: Integer);
    procedure pbChartMouseDown(Sender: TObject; Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
    procedure pbChartMouseUp(Sender: TObject; Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
    procedure pbChartDblClick(Sender: TObject);
    procedure AppMessage(var Msg: TMsg; var Handled: Boolean);
    procedure LoadOlderIfNeeded;
    procedure WMOlder(var M: TMessage); message WM_FT_OLDER;
    procedure tmrDetailTimer(Sender: TObject);
    procedure tmrSelectTimer(Sender: TObject);

    procedure WMTickers(var M: TMessage); message WM_FT_TICKERS;
    procedure WMScan(var M: TMessage); message WM_FT_SCAN;
    procedure WMDetail(var M: TMessage); message WM_FT_DETAIL;
    procedure WMMsg(var M: TMessage); message WM_FT_MSG;
    procedure WMHideSuggest(var M: TMessage); message WM_FT_HIDESUGGEST;
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
  end;

var
  MainForm: TMainForm;

implementation

const
  ColNames: array[0..15] of string = ('No', 'Koin', 'Harga', '24j %',
    'Volume 24j', 'Beli %', 'Jual %', 'Beli $ (24j)', 'Jual $ (24j)', 'Trend MA',
    'Cross MA terakhir', 'Support', 'Resisten', 'Support terkuat (x mantul)', 'Status', 'Sinyal');
  ColWidths: array[0..15] of Integer = (42, 105, 95, 72, 88, 58, 58, 88, 88, 100,
    150, 88, 88, 165, 120, 135);

  FilterNames: array[0..9] of string = ('Semua koin', 'Naik >= warning %', 'Turun',
    'Mau breakout / breakout', 'Golden cross baru', 'Death cross baru',
    'Trend bullish', 'Trend bearish', 'Sinyal BELI', 'Sinyal JUAL');

function Bar(Pct: Double; W: Integer): string;
var
  N: Integer;
begin
  N := Round(Pct / 100 * W);
  if N < 0 then N := 0;
  if N > W then N := W;
  Result := '[' + StringOfChar('#', N) + StringOfChar('.', W - N) + ']';
end;

function DistPct(Level, Price: Double): string;
begin
  if (Price = 0) or (Level = 0) then
    Result := ''
  else
    Result := '(' + FmtPct((Level - Price) / Price * 100) + ')';
end;

function CmpF(A, B: Double): Integer;
begin
  if A < B then Result := -1
  else if A > B then Result := 1
  else Result := 0;
end;

{ TMainForm }

constructor TMainForm.Create(AOwner: TComponent);
begin
  inherited CreateNew(AOwner);
  FIndex := TStringList.Create;
  FIndex.Sorted := True;
  FSortCol := 4;
  FSortDesc := True;
  FHoverX := -1;
  FInterval := ChartTFApi[DefaultChartTF];
  BuildUI;
  UpdateTFButtons;
  FScanner := TScannerThread.Create(Handle);
end;

destructor TMainForm.Destroy;
begin
  if FScanner <> nil then
  begin
    FScanner.Terminate;
    if WaitForSingleObject(FScanner.Handle, 3000) = WAIT_OBJECT_0 then
      FScanner.Free;
  end;
  FIndex.Free;
  inherited;
end;

function TMainForm.MakeLabel(AParent: TWinControl; X, Y: Integer; const Txt: string): TLabel;
begin
  Result := TLabel.Create(Self);
  Result.Parent := AParent;
  Result.Left := X;
  Result.Top := Y;
  Result.Caption := Txt;
  Result.Font.Color := clrDim;
end;

function TMainForm.MakeBtn(AParent: TWinControl; X, Y, W, H: Integer; const Txt: string;
  Bg, Fg: TColor; Click: TNotifyEvent): TPanel;
begin
  Result := TPanel.Create(Self);
  Result.Parent := AParent;
  Result.SetBounds(X, Y, W, H);
  Result.BevelOuter := bvNone;
  Result.Color := Bg;
  Result.Font.Color := Fg;
  Result.Font.Style := [fsBold];
  Result.Font.Size := 10;
  Result.Caption := Txt;
  Result.Cursor := crHandPoint;
  Result.OnClick := Click;
end;

function TMainForm.MakeHeader(AParent: TWinControl; const Txt: string): TPanel;
var
  Lbl: TLabel;
begin
  Result := TPanel.Create(Self);
  Result.Parent := AParent;
  Result.Align := alTop;
  Result.Height := 26;
  Result.BevelOuter := bvNone;
  Result.Color := clrPanel;
  Lbl := MakeLabel(Result, 10, 5, Txt);
  Lbl.Font.Style := [fsBold];
  Lbl.Font.Color := clrGold;
end;

procedure StyleInput(C: TWinControl);
begin
  if C is TEdit then
  begin
    TEdit(C).Color := clrPanel2;
    TEdit(C).Font.Color := clrText;
    TEdit(C).Ctl3D := False;
  end
  else if C is TComboBox then
  begin
    TComboBox(C).Color := clrPanel2;
    TComboBox(C).Font.Color := clrText;
    TComboBox(C).Ctl3D := False;
  end;
end;

procedure TMainForm.BuildUI;
var
  I: Integer;
  Col: TListColumn;
  Lbl: TLabel;
begin
  Caption := 'Fernanda Taker - Binance Futures';
  Width := 1400;
  Height := 850;
  Position := poScreenCenter;
  WindowState := wsMaximized;
  Color := clrBg;
  Font.Name := 'Segoe UI';
  Font.Size := 9;
  Font.Color := clrText;

  { --- Panel atas --- }
  pnlTop := TPanel.Create(Self);
  pnlTop.Parent := Self;
  pnlTop.Align := alTop;
  pnlTop.Height := 66;
  pnlTop.BevelOuter := bvNone;
  pnlTop.Color := clrPanel;

  Lbl := MakeLabel(pnlTop, 16, 6, 'FERNANDA TAKER');
  Lbl.Font.Size := 20;
  Lbl.Font.Style := [fsBold];
  Lbl.Font.Color := clrGold;
  lblSource := MakeLabel(pnlTop, 18, 42, 'Binance Futures Scanner');

  Lbl := MakeLabel(pnlTop, 270, 6, 'CARI KOIN  (ketik, lalu pilih)');
  Lbl.Font.Style := [fsBold];
  edSearch := TEdit.Create(Self);
  edSearch.Parent := pnlTop;
  edSearch.SetBounds(270, 26, 220, 26);
  edSearch.Font.Size := 11;
  edSearch.CharCase := ecUpperCase;
  StyleInput(edSearch);
  edSearch.OnChange := edSearchChange;
  edSearch.OnEnter := edSearchEnter;
  edSearch.OnExit := edSearchExit;
  edSearch.OnKeyDown := edSearchKeyDown;
  edSearch.OnKeyPress := edSearchKeyPress;

  MakeLabel(pnlTop, 504, 6, 'Filter');
  cbFilter := TComboBox.Create(Self);
  cbFilter.Parent := pnlTop;
  cbFilter.Style := csDropDownList;
  cbFilter.SetBounds(504, 28, 170, 23);
  StyleInput(cbFilter);
  for I := 0 to High(FilterNames) do
    cbFilter.Items.Add(FilterNames[I]);
  cbFilter.ItemIndex := 0;
  cbFilter.OnChange := FilterChange;

  MakeLabel(pnlTop, 686, 6, 'Warning naik %');
  edThreshold := TEdit.Create(Self);
  edThreshold.Parent := pnlTop;
  edThreshold.SetBounds(686, 28, 50, 23);
  StyleInput(edThreshold);
  edThreshold.Text := '5';
  edThreshold.OnChange := FilterChange;

  chkSound := TCheckBox.Create(Self);
  chkSound.Parent := pnlTop;
  chkSound.SetBounds(746, 30, 60, 19);
  chkSound.Caption := 'Suara';
  chkSound.Checked := True;
  chkSound.Color := clrPanel;
  chkSound.Font.Color := clrText;

  btnBtc := MakeBtn(pnlTop, 820, 10, 96, 46, 'BTC', clrGold, clrBg, btnBtcClick);
  btnBtc.Font.Size := 16;
  btnBtc.Hint := 'Analisa khusus Bitcoin: naik/turun, support, resisten, kapan beli/jual';
  btnBtc.ShowHint := True;

  btnOpen := MakeBtn(pnlTop, 926, 10, 250, 46, 'Buka di Binance.bh Futures',
    clrPanel2, clrGold, btnOpenClick);

  { --- Strip pasar: jumlah naik/turun & top gainer/loser --- }
  pnlMarket := TPanel.Create(Self);
  pnlMarket.Parent := Self;
  pnlMarket.Align := alTop;
  pnlMarket.Top := pnlTop.Height;
  pnlMarket.Height := 28;
  pnlMarket.BevelOuter := bvNone;
  pnlMarket.Color := clrBg;
  lblUp := MakeLabel(pnlMarket, 16, 6, 'NAIK -');
  lblUp.Font.Color := clrUp;
  lblUp.Font.Style := [fsBold];
  lblDown := MakeLabel(pnlMarket, 100, 6, 'TURUN -');
  lblDown.Font.Color := clrDown;
  lblDown.Font.Style := [fsBold];
  lblGainers := MakeLabel(pnlMarket, 200, 6, '');
  lblGainers.Font.Color := clrUp;
  lblLosers := MakeLabel(pnlMarket, 600, 6, '');
  lblLosers.Font.Color := clrDown;

  { --- Status bawah --- }
  pnlStatus := TPanel.Create(Self);
  pnlStatus.Parent := Self;
  pnlStatus.Align := alBottom;
  pnlStatus.Height := 24;
  pnlStatus.BevelOuter := bvNone;
  pnlStatus.Color := clrPanel;
  pnlStatus.Font.Color := clrDim;
  pnlStatus.Alignment := taLeftJustify;
  pnlStatus.Caption := '   Menghubungkan ke Binance...';

  { --- Panel alert --- }
  pnlBottom := TPanel.Create(Self);
  pnlBottom.Parent := Self;
  pnlBottom.Align := alBottom;
  pnlBottom.Height := 150;
  pnlBottom.Top := pnlStatus.Top - 1;
  pnlBottom.BevelOuter := bvNone;
  pnlBottom.Color := clrPanel;
  MakeHeader(pnlBottom, 'WARNING / ALERT   (klik 2x untuk membuka koin)');

  lbAlerts := TListBox.Create(Self);
  lbAlerts.Parent := pnlBottom;
  lbAlerts.Align := alClient;
  lbAlerts.BorderStyle := bsNone;
  lbAlerts.Color := clrBg;
  lbAlerts.Font.Name := 'Consolas';
  lbAlerts.Font.Size := 10;
  lbAlerts.Style := lbOwnerDrawFixed;
  lbAlerts.ItemHeight := 20;
  lbAlerts.OnDrawItem := lbAlertsDrawItem;
  lbAlerts.OnDblClick := lbAlertsDblClick;

  with TSplitter.Create(Self) do
  begin
    Parent := Self;
    Align := alBottom;
    Top := pnlBottom.Top - 1;
    Height := 4;
  end;

  { --- Panel kanan: header koin, grafik, detail --- }
  pnlRight := TPanel.Create(Self);
  pnlRight.Parent := Self;
  pnlRight.Align := alRight;
  pnlRight.Width := 660;
  pnlRight.BevelOuter := bvNone;
  pnlRight.Color := clrPanel;

  pnlCoinHead := TPanel.Create(Self);
  pnlCoinHead.Parent := pnlRight;
  pnlCoinHead.Align := alTop;
  pnlCoinHead.Height := 48;
  pnlCoinHead.BevelOuter := bvNone;
  pnlCoinHead.Color := clrPanel2;
  lblCoin := MakeLabel(pnlCoinHead, 12, 8, 'Pilih koin');
  lblCoin.Font.Size := 16;
  lblCoin.Font.Style := [fsBold];
  lblCoin.Font.Color := clrGold;
  lblCoinPrice := MakeLabel(pnlCoinHead, 200, 8, '');
  lblCoinPrice.Font.Size := 16;
  lblCoinPrice.Font.Style := [fsBold];
  lblCoinPrice.Font.Color := clrText;
  lblCoinChg := MakeLabel(pnlCoinHead, 380, 13, '');
  lblCoinChg.Font.Size := 12;
  lblCoinChg.Font.Style := [fsBold];

  { tombol time frame grafik }
  pnlTF := TPanel.Create(Self);
  pnlTF.Parent := pnlRight;
  pnlTF.Align := alTop;
  pnlTF.Top := pnlCoinHead.Height;
  pnlTF.Height := 34;
  pnlTF.BevelOuter := bvNone;
  pnlTF.Color := clrPanel;
  for I := 0 to ChartTFCount - 1 do
  begin
    FTFBtns[I] := MakeBtn(pnlTF, 8 + I * 66, 5, 60, 24, ChartTFLabels[I],
      clrPanel2, clrDim, TFClick);
    FTFBtns[I].Font.Size := 9;
    FTFBtns[I].Tag := I;
  end;
  lblLive := MakeLabel(pnlTF, 8 + ChartTFCount * 66 + 6, 9, '');
  lblLive.Font.Style := [fsBold];
  lblLive.Font.Color := clrUp;

  pnlChart := TPanel.Create(Self);
  pnlChart.Parent := pnlRight;
  pnlChart.Align := alTop;
  pnlChart.Top := pnlTF.Top + pnlTF.Height;
  pnlChart.Height := 400;
  pnlChart.BevelOuter := bvNone;
  pnlChart.Color := clrPanel;
  pnlChart.DoubleBuffered := True;

  pbChart := TPaintBox.Create(Self);
  pbChart.Parent := pnlChart;
  pbChart.Align := alClient;
  pbChart.OnPaint := pbChartPaint;
  pbChart.OnMouseMove := pbChartMouseMove;
  pbChart.OnMouseDown := pbChartMouseDown;
  pbChart.OnMouseUp := pbChartMouseUp;
  pbChart.OnDblClick := pbChartDblClick;
  pbChart.Cursor := crCross;
  Application.OnMessage := AppMessage;   // scroll mouse untuk zoom grafik

  memoDetail := TMemo.Create(Self);
  memoDetail.Parent := pnlRight;
  memoDetail.Align := alClient;
  memoDetail.BorderStyle := bsNone;
  memoDetail.ReadOnly := True;
  memoDetail.ScrollBars := ssVertical;
  memoDetail.WordWrap := False;
  memoDetail.Color := clrBg;
  memoDetail.Font.Name := 'Consolas';
  memoDetail.Font.Size := 10;
  memoDetail.Font.Color := clrText;

  with TSplitter.Create(Self) do
  begin
    Parent := Self;
    Align := alRight;
    Left := pnlRight.Left - 1;
    Width := 4;
  end;

  { --- Daftar semua koin --- }
  ilRows := TImageList.Create(Self);
  ilRows.Width := 1;
  ilRows.Height := 24;   // tinggi baris supaya grafik mini terlihat

  lv := TListView.Create(Self);
  lv.Parent := Self;
  lv.Align := alClient;
  lv.ViewStyle := vsReport;
  lv.OwnerData := True;
  lv.ReadOnly := True;
  lv.RowSelect := True;
  lv.HideSelection := False;
  lv.BorderStyle := bsNone;
  lv.Color := clrBg;
  lv.Font.Color := clrText;
  lv.SmallImages := ilRows;
  for I := 0 to High(ColNames) do
  begin
    Col := lv.Columns.Add;
    Col.Caption := ColNames[I];
    Col.Width := ColWidths[I];
    if I in [2..8, 11..13] then
      Col.Alignment := taRightJustify;
  end;
  lv.OnData := lvData;
  lv.OnCustomDrawItem := lvCustomDrawItem;
  lv.OnCustomDrawSubItem := lvCustomDrawSubItem;
  lv.OnSelectItem := lvSelectItem;
  lv.OnColumnClick := lvColumnClick;
  lv.OnDblClick := lvDblClick;

  { --- Daftar pilihan hasil pencarian (muncul di bawah kotak cari) --- }
  lbSuggest := TListBox.Create(Self);
  lbSuggest.Parent := Self;
  lbSuggest.Visible := False;
  lbSuggest.Style := lbOwnerDrawFixed;
  lbSuggest.ItemHeight := 26;
  lbSuggest.Color := clrPanel2;
  lbSuggest.Ctl3D := False;
  lbSuggest.Font.Size := 10;
  lbSuggest.OnDrawItem := lbSuggestDrawItem;
  lbSuggest.OnMouseUp := lbSuggestMouseUp;
  lbSuggest.OnKeyDown := lbSuggestKeyDown;
  lbSuggest.OnExit := edSearchExit;

  tmrDetail := TTimer.Create(Self);
  tmrDetail.Interval := 15000;
  tmrDetail.OnTimer := tmrDetailTimer;
  tmrSelect := TTimer.Create(Self);
  tmrSelect.Enabled := False;
  tmrSelect.Interval := 300;
  tmrSelect.OnTimer := tmrSelectTimer;
  tmrRefresh := TTimer.Create(Self);
  tmrRefresh.Interval := 1500;
  tmrRefresh.OnTimer := tmrRefreshTimer;
  tmrLive := TTimer.Create(Self);
  tmrLive.Interval := 1000;   // harga grafik diperbarui tiap 1 detik
  tmrLive.OnTimer := tmrLiveTimer;

  memoDetail.Lines.Text :=
    ' Selamat datang di FERNANDA TAKER' + #13#10 + #13#10 +
    ' - Semua koin terisi otomatis dari Binance, harga update tiap beberapa detik.' + #13#10 +
    ' - Ketik nama koin di CARI KOIN, lalu pilih dari daftar pilihan.' + #13#10 +
    '   Klik tulisan "binance.bh >" untuk langsung membuka halaman futures-nya.' + #13#10 +
    ' - Klik koin untuk grafik & analisa, klik 2x untuk membuka di Binance.bh.' + #13#10 +
    ' - Grafik: candle HIJAU = naik, MERAH = turun.' + #13#10 +
    ' - Tombol kuning BTC = analisa khusus Bitcoin.';
end;

function TMainForm.FindCoin(const Sym: string): Integer;
var
  I: Integer;
begin
  I := FIndex.IndexOf(Sym);
  if I >= 0 then
    Result := Integer(FIndex.Objects[I])
  else
    Result := -1;
end;

function TMainForm.Threshold: Double;
var
  Code: Integer;
  S: string;
begin
  S := StringReplace(Trim(edThreshold.Text), ',', '.', []);
  Val(S, Result, Code);
  if (Code <> 0) or (Result <= 0) then
    Result := 5;
end;

function TMainForm.PassFilter(const R: TCoinRow): Boolean;
var
  S: string;
begin
  S := Trim(edSearch.Text);
  if (S <> '') and (Pos(S, R.Symbol) = 0) then
  begin
    Result := False;
    Exit;
  end;
  case cbFilter.ItemIndex of
    1: Result := R.Chg24 >= Threshold;
    2: Result := R.Chg24 < 0;
    3: Result := (R.Breakout = 'MAU BREAKOUT') or (R.Breakout = 'BREAKOUT NAIK');
    4: Result := R.Scanned and (R.CrossAgo >= 0) and R.CrossGolden;
    5: Result := R.Scanned and (R.CrossAgo >= 0) and not R.CrossGolden;
    6: Result := R.Scanned and (R.TrendScore >= 2);
    7: Result := R.Scanned and (R.TrendScore <= -2);
    8: Result := R.Signal = 'BELI';
    9: Result := R.Signal = 'JUAL';
  else
    Result := True;
  end;
end;

function TMainForm.CompareRows(A, B: Integer): Integer;
var
  CA, CB: Integer;
begin
  case FSortCol of
    1: Result := CompareStr(FCoins[A].Symbol, FCoins[B].Symbol);
    2: Result := CmpF(FCoins[A].Price, FCoins[B].Price);
    3: Result := CmpF(FCoins[A].Chg24, FCoins[B].Chg24);
    5: Result := CmpF(FCoins[A].BuyPct, FCoins[B].BuyPct);
    6: Result := CmpF(FCoins[A].SellPct, FCoins[B].SellPct);
    7: Result := CmpF(FCoins[A].BuyUSD, FCoins[B].BuyUSD);
    8: Result := CmpF(FCoins[A].SellUSD, FCoins[B].SellUSD);
    9: Result := FCoins[A].TrendScore - FCoins[B].TrendScore;
    10:
      begin
        CA := FCoins[A].CrossAgo; if CA < 0 then CA := 999;
        CB := FCoins[B].CrossAgo; if CB < 0 then CB := 999;
        Result := CB - CA;
      end;
    11: Result := CmpF(FCoins[A].Support, FCoins[B].Support);
    12: Result := CmpF(FCoins[A].Resist, FCoins[B].Resist);
    13: Result := FCoins[A].StrongHits - FCoins[B].StrongHits;
    14: Result := CompareStr(FCoins[A].Breakout, FCoins[B].Breakout);
    15: Result := FCoins[A].Score - FCoins[B].Score;
  else
    Result := CmpF(FCoins[A].QuoteVol, FCoins[B].QuoteVol);
  end;
  if Result = 0 then
    Result := CompareStr(FCoins[B].Symbol, FCoins[A].Symbol);
  if FSortDesc then
    Result := -Result;
end;

procedure TMainForm.SortView;
var
  Gap, I, J, T, N: Integer;
begin
  N := Length(FView);
  Gap := N div 2;
  while Gap > 0 do
  begin
    for I := Gap to N - 1 do
    begin
      T := FView[I];
      J := I;
      while (J >= Gap) and (CompareRows(FView[J - Gap], T) > 0) do
      begin
        FView[J] := FView[J - Gap];
        Dec(J, Gap);
      end;
      FView[J] := T;
    end;
    Gap := Gap div 2;
  end;
end;

procedure TMainForm.RebuildView;
var
  I, N, Sel: Integer;
begin
  SetLength(FView, Length(FCoins));
  N := 0;
  for I := 0 to High(FCoins) do
    if PassFilter(FCoins[I]) then
    begin
      FView[N] := I;
      Inc(N);
    end;
  SetLength(FView, N);
  SortView;

  FUpdating := True;
  try
    if lv.Items.Count <> N then
      lv.Items.Count := N;
    Sel := -1;
    if FSelected <> '' then
      for I := 0 to N - 1 do
        if FCoins[FView[I]].Symbol = FSelected then
        begin
          Sel := I;
          Break;
        end;
    if (lv.Selected = nil) or (lv.Selected.Index <> Sel) then
    begin
      lv.Selected := nil;
      if Sel >= 0 then
      begin
        lv.Items[Sel].Selected := True;
        lv.Items[Sel].Focused := True;
      end;
    end;
    // gambar ulang tanpa menghapus latar dulu supaya tabel tidak berkedip
    InvalidateRect(lv.Handle, nil, False);
  finally
    FUpdating := False;
  end;
end;

procedure TMainForm.tmrRefreshTimer(Sender: TObject);
begin
  if not FDirty then
    Exit;
  FDirty := False;
  RebuildView;
  UpdateStatus(FStatusExtra);
  if lbSuggest.Visible then
    lbSuggest.Invalidate;
end;

procedure TMainForm.tmrLiveTimer(Sender: TObject);
begin
  if (FSelected = '') or (Length(FChartK) = 0) then
    Exit;
  if FLiveBusy and (GetTickCount - FLiveStart < 10000) then
    Exit;
  FLiveBusy := True;
  FLiveStart := GetTickCount;
  TLiveThread.Create(Handle, FSelected, FInterval);
end;

procedure TMainForm.WMLive(var M: TMessage);
var
  D: TLiveData;
  Idx: Integer;
begin
  D := TLiveData(M.LParam);
  try
    FLiveBusy := False;
    if (D.Err <> '') or (D.Sym <> FSelected) or (D.Interval <> FInterval) or
       (Length(D.K) = 0) or (Length(FChartK) = 0) then
      Exit;
    MergeKlines(FChartK, D.K);
    Idx := FindCoin(FSelected);
    if Idx >= 0 then
    begin
      FCoins[Idx].Price := FChartK[High(FChartK)].C;
      FDirty := True;
    end;
    UpdateCoinHeader;
    lblLive.Caption := 'LIVE  ' + FormatDateTime('hh:nn:ss', Now);
    pbChart.Invalidate;
  finally
    D.Free;
  end;
end;

procedure TMainForm.UpdateMarketStrip;
var
  I, J, Up, Down: Integer;
  Top: array[0..2] of Integer;
  Bot: array[0..2] of Integer;
  S: string;
begin
  Up := 0;
  Down := 0;
  for J := 0 to 2 do
  begin
    Top[J] := -1;
    Bot[J] := -1;
  end;
  for I := 0 to High(FCoins) do
  begin
    if FCoins[I].Chg24 >= 0 then Inc(Up) else Inc(Down);
    for J := 0 to 2 do
      if (Top[J] < 0) or (FCoins[I].Chg24 > FCoins[Top[J]].Chg24) then
      begin
        if J < 2 then Move(Top[J], Top[J + 1], (2 - J) * SizeOf(Integer));
        Top[J] := I;
        Break;
      end;
    for J := 0 to 2 do
      if (Bot[J] < 0) or (FCoins[I].Chg24 < FCoins[Bot[J]].Chg24) then
      begin
        if J < 2 then Move(Bot[J], Bot[J + 1], (2 - J) * SizeOf(Integer));
        Bot[J] := I;
        Break;
      end;
  end;
  lblUp.Caption := Format('NAIK %d', [Up]);
  lblDown.Caption := Format('TURUN %d', [Down]);
  lblDown.Left := lblUp.Left + lblUp.Width + 24;

  S := 'TOP NAIK: ';
  for J := 0 to 2 do
    if Top[J] >= 0 then
      S := S + Format('%s %s   ', [FCoins[Top[J]].Symbol, FmtPct(FCoins[Top[J]].Chg24)]);
  lblGainers.Caption := S;
  lblGainers.Left := lblDown.Left + lblDown.Width + 40;
  S := 'TOP TURUN: ';
  for J := 0 to 2 do
    if Bot[J] >= 0 then
      S := S + Format('%s %s   ', [FCoins[Bot[J]].Symbol, FmtPct(FCoins[Bot[J]].Chg24)]);
  lblLosers.Caption := S;
  lblLosers.Left := lblGainers.Left + lblGainers.Width + 30;
end;

procedure TMainForm.UpdateCoinHeader;
var
  Idx: Integer;
begin
  Idx := FindCoin(FSelected);
  if Idx < 0 then
    Exit;
  lblCoin.Caption := FSelected;
  lblCoinPrice.Left := lblCoin.Left + lblCoin.Width + 20;
  lblCoinPrice.Caption := FmtPrice(FCoins[Idx].Price);
  lblCoinChg.Left := lblCoinPrice.Left + lblCoinPrice.Width + 16;
  if FCoins[Idx].Chg24 >= 0 then
  begin
    lblCoinChg.Caption := 'NAIK ' + FmtPct(FCoins[Idx].Chg24) + ' (24j)';
    lblCoinChg.Font.Color := clrUp;
  end
  else
  begin
    lblCoinChg.Caption := 'TURUN ' + FmtPct(FCoins[Idx].Chg24) + ' (24j)';
    lblCoinChg.Font.Color := clrDown;
  end;
end;

procedure TMainForm.UpdateStatus(const Extra: string);
var
  S: string;
begin
  S := Format('   Sumber: %s   |   Koin: %d   |   Ditampilkan: %d   |   Sudah dianalisa: %d/%d',
    [SourceName, Length(FCoins), Length(FView), FScanned, Length(FCoins)]);
  if FLastTicker > 0 then
    S := S + '   |   Update: ' + FormatDateTime('hh:nn:ss', FLastTicker);
  if Extra <> '' then
    S := S + '   |   ' + Extra;
  pnlStatus.Caption := S;
  if UseSpot then
    lblSource.Caption := 'Data otomatis: server cadangan Binance'
  else
    lblSource.Caption := 'Data otomatis: ' + SourceName;
end;

{ ---------- Pencarian dengan daftar pilihan ---------- }

procedure TMainForm.UpdateSuggest;
var
  S: string;
  I, J, Best, P: Integer;
  Starts, Contains: TStringList;
  Used: array of Boolean;
  Pt: TPoint;
begin
  if not (edSearch.Focused or lbSuggest.Focused) or (Length(FCoins) = 0) then
  begin
    lbSuggest.Visible := False;
    Exit;
  end;
  S := Trim(edSearch.Text);
  lbSuggest.Items.BeginUpdate;
  try
    lbSuggest.Items.Clear;
    if S = '' then
    begin
      // tanpa teks: tampilkan 15 koin volume terbesar sebagai pilihan
      SetLength(Used, Length(FCoins));
      for J := 1 to 15 do
      begin
        Best := -1;
        for I := 0 to High(FCoins) do
          if not Used[I] and ((Best < 0) or (FCoins[I].QuoteVol > FCoins[Best].QuoteVol)) then
            Best := I;
        if Best < 0 then Break;
        Used[Best] := True;
        lbSuggest.Items.Add(FCoins[Best].Symbol);
      end;
    end
    else
    begin
      Starts := TStringList.Create;
      Contains := TStringList.Create;
      try
        for I := 0 to High(FCoins) do
        begin
          P := Pos(S, FCoins[I].Symbol);
          if P = 1 then Starts.Add(FCoins[I].Symbol)
          else if P > 1 then Contains.Add(FCoins[I].Symbol);
        end;
        Starts.Sort;
        Contains.Sort;
        for I := 0 to Starts.Count - 1 do
          if lbSuggest.Items.Count < 15 then lbSuggest.Items.Add(Starts[I]);
        for I := 0 to Contains.Count - 1 do
          if lbSuggest.Items.Count < 15 then lbSuggest.Items.Add(Contains[I]);
      finally
        Starts.Free;
        Contains.Free;
      end;
    end;
  finally
    lbSuggest.Items.EndUpdate;
  end;
  if lbSuggest.Items.Count = 0 then
  begin
    lbSuggest.Visible := False;
    Exit;
  end;
  Pt := ScreenToClient(edSearch.ClientToScreen(Point(0, edSearch.Height + 2)));
  lbSuggest.SetBounds(Pt.X, Pt.Y, 420, lbSuggest.Items.Count * lbSuggest.ItemHeight + 4);
  lbSuggest.Visible := True;
  lbSuggest.BringToFront;
end;

procedure TMainForm.ChooseSuggest(I: Integer);
begin
  if (I < 0) or (I >= lbSuggest.Items.Count) then
    Exit;
  lbSuggest.Visible := False;
  SelectSymbol(lbSuggest.Items[I]);
  lv.SetFocus;
end;

procedure TMainForm.lbSuggestDrawItem(Control: TWinControl; Index: Integer;
  Rect: TRect; State: TOwnerDrawState);
var
  Cv: TCanvas;
  Idx: Integer;
  Sym: string;
begin
  Cv := lbSuggest.Canvas;
  if odSelected in State then
    Cv.Brush.Color := clrBorder
  else
    Cv.Brush.Color := clrPanel2;
  Cv.FillRect(Rect);
  Sym := lbSuggest.Items[Index];
  Idx := FindCoin(Sym);
  Cv.Brush.Style := bsClear;
  Cv.Font.Size := 10;
  Cv.Font.Style := [fsBold];
  Cv.Font.Color := clrGold;
  Cv.TextOut(Rect.Left + 10, Rect.Top + 4, Sym);
  if Idx >= 0 then
  begin
    Cv.Font.Style := [];
    Cv.Font.Color := clrText;
    Cv.TextOut(Rect.Left + 135, Rect.Top + 4, FmtPrice(FCoins[Idx].Price));
    Cv.Font.Style := [fsBold];
    if FCoins[Idx].Chg24 >= 0 then Cv.Font.Color := clrUp else Cv.Font.Color := clrDown;
    Cv.TextOut(Rect.Left + 235, Rect.Top + 4, FmtPct(FCoins[Idx].Chg24));
  end;
  Cv.Font.Style := [fsUnderline];
  Cv.Font.Size := 9;
  Cv.Font.Color := clrDim;
  Cv.TextOut(Rect.Right - 100, Rect.Top + 5, 'binance.bh >');
  Cv.Brush.Style := bsSolid;
end;

procedure TMainForm.lbSuggestMouseUp(Sender: TObject; Button: TMouseButton;
  Shift: TShiftState; X, Y: Integer);
var
  I: Integer;
begin
  I := lbSuggest.ItemAtPos(Point(X, Y), True);
  if I < 0 then
    Exit;
  if X >= lbSuggest.Width - 110 then
    OpenBinance(lbSuggest.Items[I]);  // klik "binance.bh >" langsung buka halaman futures
  ChooseSuggest(I);
end;

procedure TMainForm.lbSuggestKeyDown(Sender: TObject; var Key: Word; Shift: TShiftState);
begin
  case Key of
    VK_RETURN:
      begin
        ChooseSuggest(lbSuggest.ItemIndex);
        Key := 0;
      end;
    VK_ESCAPE:
      begin
        lbSuggest.Visible := False;
        edSearch.SetFocus;
        Key := 0;
      end;
    VK_UP:
      if lbSuggest.ItemIndex <= 0 then
      begin
        edSearch.SetFocus;
        Key := 0;
      end;
  end;
end;

procedure TMainForm.edSearchChange(Sender: TObject);
begin
  RebuildView;
  UpdateStatus('');
  UpdateSuggest;
end;

procedure TMainForm.edSearchEnter(Sender: TObject);
begin
  UpdateSuggest;
end;

procedure TMainForm.edSearchExit(Sender: TObject);
begin
  PostMessage(Handle, WM_FT_HIDESUGGEST, 0, 0);
end;

procedure TMainForm.WMHideSuggest(var M: TMessage);
begin
  if not (edSearch.Focused or lbSuggest.Focused) then
    lbSuggest.Visible := False;
end;

procedure TMainForm.edSearchKeyDown(Sender: TObject; var Key: Word; Shift: TShiftState);
begin
  case Key of
    VK_DOWN:
      if lbSuggest.Visible then
      begin
        lbSuggest.SetFocus;
        lbSuggest.ItemIndex := 0;
        Key := 0;
      end;
    VK_RETURN:
      begin
        if lbSuggest.Visible then
          ChooseSuggest(0);
        Key := 0;
      end;
    VK_ESCAPE:
      lbSuggest.Visible := False;
  end;
end;

procedure TMainForm.edSearchKeyPress(Sender: TObject; var Key: Char);
begin
  if Key in [#13, #27] then
    Key := #0;  // cegah bunyi beep
end;

{ ---------- Alert ---------- }

procedure TMainForm.AddAlert(const Sym, Txt: string);
var
  Idx: Integer;
begin
  Idx := FindCoin(Sym);
  lbAlerts.Items.InsertObject(0, FormatDateTime('hh:nn:ss', Now) + '  ' + Txt, TObject(Idx));
  while lbAlerts.Items.Count > 500 do
    lbAlerts.Items.Delete(lbAlerts.Items.Count - 1);
  if chkSound.Checked then
    MessageBeep(MB_ICONEXCLAMATION);
end;

procedure TMainForm.ApplyAnalysis(Idx: Integer; const A: TAnalysis);
begin
  if not A.Ok then
    Exit;
  with FCoins[Idx] do
  begin
    if not Scanned then
      Inc(FScanned);
    Scanned := True;
    if A.Price > 0 then
      Price := A.Price;
    BuyPct := A.BuyPct;
    SellPct := A.SellPct;
    BuyUSD := A.BuyUSD;
    SellUSD := A.SellUSD;
    Trend := A.Trend;
    TrendScore := A.TrendScore;
    CrossAgo := A.LastCrossAgo;
    CrossGolden := A.LastCrossGolden;
    if A.LastCrossAgo >= 0 then
      LastCross := Format('%s (%d)', [A.LastCrossText, A.LastCrossAgo])
    else
      LastCross := '-';
    Support := A.SwingSup;
    Resist := A.SwingRes;
    StrongSup := A.StrongSup;
    StrongHits := A.StrongSupHits;
    Rise4 := A.Rise4;
    Breakout := A.Breakout;
    Signal := A.Signal;
    Score := A.Score;

    if (Rise4 >= Threshold) and not AlertRise then
    begin
      AlertRise := True;
      AddAlert(Symbol, Format('[MULAI NAIK] %s naik %.2f%% dari low 4 jam terakhir (harga %s)',
        [Symbol, Rise4, FmtPrice(Price)]));
    end
    else if Rise4 < Threshold / 2 then
      AlertRise := False;

    if (Breakout <> '') and (Breakout <> AlertBO) then
      AddAlert(Symbol, Format('[%s] %s harga %s, resisten %s, support %s',
        [Breakout, Symbol, FmtPrice(Price), FmtPrice(A.RangeHigh), FmtPrice(A.RangeLow)]));
    AlertBO := Breakout;
  end;
end;

{ ---------- Pesan dari thread ---------- }

procedure TMainForm.WMTickers(var M: TMessage);
var
  TD: TTickerData;
  I, Idx: Integer;
  Th: Double;
begin
  TD := TTickerData(M.LParam);
  try
    Th := Threshold;
    for I := 0 to TD.Count - 1 do
    begin
      Idx := FindCoin(TD.Sym[I]);
      if Idx < 0 then
      begin
        Idx := Length(FCoins);
        SetLength(FCoins, Idx + 1);
        FCoins[Idx].Symbol := TD.Sym[I];
        FCoins[Idx].CrossAgo := -1;
        FIndex.AddObject(TD.Sym[I], TObject(Idx));
      end;
      with FCoins[Idx] do
      begin
        Price := TD.Price[I];
        Chg24 := TD.Chg[I];
        QuoteVol := TD.QV[I];
        High24 := TD.High[I];
        Low24 := TD.Low[I];
        if (Chg24 >= Th) and not Alert24 then
        begin
          Alert24 := True;
          AddAlert(Symbol, Format('[NAIK %.0f%%] %s naik %s dalam 24 jam (harga %s)',
            [Th, Symbol, FmtPct(Chg24), FmtPrice(Price)]));
        end
        else if Chg24 < Th - 1 then
          Alert24 := False;
      end;
    end;
    FLastTicker := Now;
    FDirty := True;
    FStatusExtra := 'Online';
    UpdateMarketStrip;
    UpdateCoinHeader;
    if lbSuggest.Visible then
      lbSuggest.Invalidate;
  finally
    TD.Free;
  end;
end;

procedure TMainForm.WMScan(var M: TMessage);
var
  SD: TScanData;
  Idx: Integer;
begin
  SD := TScanData(M.LParam);
  try
    Idx := FindCoin(SD.A.Symbol);
    if Idx >= 0 then
    begin
      ApplyAnalysis(Idx, SD.A);
      FDirty := True;   // tabel digambar ulang oleh tmrRefresh, bukan tiap koin
      FStatusExtra := 'Menganalisa: ' + SD.A.Symbol;
    end;
  finally
    SD.Free;
  end;
end;

procedure TMainForm.WMDetail(var M: TMessage);
var
  D: TDetailData;
begin
  D := TDetailData(M.LParam);
  try
    if D.ReqId = FReqId then
      ShowDetail(D);
  finally
    D.Free;
  end;
end;

procedure TMainForm.WMMsg(var M: TMessage);
var
  D: TMsgData;
begin
  D := TMsgData(M.LParam);
  try
    if D.IsError then
      UpdateStatus('ERROR: ' + D.Text)
    else
      UpdateStatus(D.Text);
  finally
    D.Free;
  end;
end;

{ ---------- Daftar koin ---------- }

procedure TMainForm.lvData(Sender: TObject; Item: TListItem);
var
  I: Integer;
begin
  if (Item.Index < 0) or (Item.Index > High(FView)) then
    Exit;
  I := FView[Item.Index];
  Item.Caption := IntToStr(Item.Index + 1);
  with FCoins[I] do
  begin
    Item.SubItems.Add(Symbol);
    Item.SubItems.Add(FmtPrice(Price));
    Item.SubItems.Add(FmtPct(Chg24));
    Item.SubItems.Add(FmtUSD(QuoteVol));
    if Scanned then
    begin
      Item.SubItems.Add(Format('%.1f%%', [BuyPct]));
      Item.SubItems.Add(Format('%.1f%%', [SellPct]));
      Item.SubItems.Add(FmtUSD(BuyUSD));
      Item.SubItems.Add(FmtUSD(SellUSD));
      Item.SubItems.Add(Trend);
      Item.SubItems.Add(LastCross);
      Item.SubItems.Add(FmtPrice(Support));
      Item.SubItems.Add(FmtPrice(Resist));
      if StrongHits > 0 then
        Item.SubItems.Add(Format('%s (%dx)', [FmtPrice(StrongSup), StrongHits]))
      else
        Item.SubItems.Add('-');
      Item.SubItems.Add(Breakout);
      Item.SubItems.Add(SignalText(Signal));
    end
    else
    begin
      Item.SubItems.Add('...');
      Item.SubItems.Add('...');
      Item.SubItems.Add('...');
      Item.SubItems.Add('...');
      Item.SubItems.Add('menganalisa...');
    end;
  end;
end;

function RowBg(Chg: Double): TColor;
begin
  if Chg >= 0 then Result := clrUpBg else Result := clrDownBg;
end;

procedure TMainForm.lvCustomDrawItem(Sender: TCustomListView; Item: TListItem;
  State: TCustomDrawState; var DefaultDraw: Boolean);
begin
  DefaultDraw := True;
  if (Item.Index < 0) or (Item.Index > High(FView)) then
    Exit;
  Sender.Canvas.Brush.Color := RowBg(FCoins[FView[Item.Index]].Chg24);
  Sender.Canvas.Font.Color := clrDim;
end;

procedure TMainForm.lvCustomDrawSubItem(Sender: TCustomListView; Item: TListItem;
  SubItem: Integer; State: TCustomDrawState; var DefaultDraw: Boolean);
var
  I: Integer;
  C: TColor;
begin
  DefaultDraw := True;
  if (Item.Index < 0) or (Item.Index > High(FView)) then
    Exit;
  I := FView[Item.Index];
  Sender.Canvas.Brush.Color := RowBg(FCoins[I].Chg24);

  C := clrText;
  with FCoins[I] do
    case SubItem of
      1: C := clrGold;
      3: if Chg24 >= 0 then C := clrUp else C := clrDown;
      4: C := clrDim;
      5: if BuyPct >= 50 then C := clrUp else C := clrDim;
      6: if SellPct > 50 then C := clrDown else C := clrDim;
      7: C := clrUp;
      8: C := clrDown;
      9: if TrendScore >= 2 then C := clrUp
         else if TrendScore <= -2 then C := clrDown
         else C := clrDim;
      10: if CrossAgo < 0 then C := clrDim
          else if CrossGolden then C := clrUp else C := clrDown;
      11: C := clrUp;
      12: C := clrDown;
      13: C := clrGold;
      14: if Pos('BREAKOUT', Breakout) > 0 then C := clrGold
          else if Breakout <> '' then C := clrDown;
      15: if Signal = 'BELI' then C := clrUp
          else if Signal = 'JUAL' then C := clrDown
          else C := clrDim;
    end;
  Sender.Canvas.Font.Color := C;
  if SubItem in [1, 3, 13..15] then
    Sender.Canvas.Font.Style := [fsBold]
  else
    Sender.Canvas.Font.Style := [];
end;

procedure TMainForm.SetSelected(const Sym: string);
begin
  if Sym = FSelected then
    Exit;
  FSelected := Sym;
  ResetView(FCV);
  FNoMoreHistory := False;
  SetLength(FChartK, 0);
  ClearAnalysis(FChartA);
  FChartTitle := Sym;
  pbChart.Invalidate;
  btnOpen.Caption := 'Buka ' + Sym + ' di Binance.bh';
  UpdateCoinHeader;
  memoDetail.Lines.Text := ' Memuat grafik & analisa ' + Sym + ' ...';
end;

procedure TMainForm.lvSelectItem(Sender: TObject; Item: TListItem; Selected: Boolean);
begin
  if FUpdating or not Selected or (Item = nil) then
    Exit;
  if (Item.Index < 0) or (Item.Index > High(FView)) then
    Exit;
  if FCoins[FView[Item.Index]].Symbol <> FSelected then
  begin
    SetSelected(FCoins[FView[Item.Index]].Symbol);
    tmrSelect.Enabled := False;
    tmrSelect.Enabled := True;   // tunda sedikit agar scroll pakai panah tidak membanjiri request
  end;
end;

procedure TMainForm.tmrSelectTimer(Sender: TObject);
begin
  tmrSelect.Enabled := False;
  RequestDetail;
end;

procedure TMainForm.lvColumnClick(Sender: TObject; Column: TListColumn);
begin
  if Column.Index = FSortCol then
    FSortDesc := not FSortDesc
  else
  begin
    FSortCol := Column.Index;
    FSortDesc := Column.Index <> 1;
  end;
  RebuildView;
end;

procedure TMainForm.lvDblClick(Sender: TObject);
begin
  if FSelected <> '' then
    OpenBinance(FSelected);
end;

procedure TMainForm.FilterChange(Sender: TObject);
begin
  RebuildView;
  UpdateStatus('');
end;

procedure TMainForm.UpdateTFButtons;
var
  I: Integer;
begin
  for I := 0 to ChartTFCount - 1 do
    if ChartTFApi[I] = FInterval then
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

procedure TMainForm.TFClick(Sender: TObject);
begin
  FInterval := ChartTFApi[TPanel(Sender).Tag];
  UpdateTFButtons;
  ResetView(FCV);
  FNoMoreHistory := False;
  SetLength(FChartK, 0);
  pbChart.Invalidate;
  RequestDetail;
end;

procedure TMainForm.btnBtcClick(Sender: TObject);
begin
  ShowBtcForm;
end;

procedure TMainForm.btnOpenClick(Sender: TObject);
begin
  if FSelected <> '' then
    OpenBinance(FSelected)
  else
    OpenBinance('BTCUSDT');
end;

procedure TMainForm.tmrDetailTimer(Sender: TObject);
begin
  RequestDetail;
end;

procedure TMainForm.SelectSymbol(const Sym: string);
var
  I: Integer;
begin
  SetSelected(Sym);
  if edSearch.Text <> '' then
    edSearch.Text := '';
  cbFilter.ItemIndex := 0;
  RebuildView;
  for I := 0 to High(FView) do
    if FCoins[FView[I]].Symbol = Sym then
    begin
      lv.Items[I].MakeVisible(False);
      Break;
    end;
  RequestDetail;
end;

procedure TMainForm.lbAlertsDblClick(Sender: TObject);
var
  Idx: Integer;
begin
  if lbAlerts.ItemIndex < 0 then
    Exit;
  Idx := Integer(lbAlerts.Items.Objects[lbAlerts.ItemIndex]);
  if (Idx >= 0) and (Idx <= High(FCoins)) then
    SelectSymbol(FCoins[Idx].Symbol);
end;

procedure TMainForm.lbAlertsDrawItem(Control: TWinControl; Index: Integer;
  Rect: TRect; State: TOwnerDrawState);
var
  S: string;
  Cv: TCanvas;
begin
  Cv := lbAlerts.Canvas;
  S := lbAlerts.Items[Index];
  if odSelected in State then
    Cv.Brush.Color := clrBorder
  else
    Cv.Brush.Color := clrBg;
  Cv.FillRect(Rect);
  if Pos('BREAKDOWN', S) > 0 then
    Cv.Font.Color := clrDown
  else if Pos('BREAKOUT', S) > 0 then
    Cv.Font.Color := clrGold
  else
    Cv.Font.Color := clrUp;
  Cv.TextOut(Rect.Left + 8, Rect.Top + 2, S);
end;

{ ---------- Grafik & detail ---------- }

procedure TMainForm.pbChartPaint(Sender: TObject);
begin
  DrawCandles(pbChart.Canvas, pbChart.ClientRect, FChartK, FChartA, FHoverX, FChartTitle, FCV);
end;

procedure TMainForm.pbChartMouseMove(Sender: TObject; Shift: TShiftState; X, Y: Integer);
begin
  FHoverX := X;
  if ViewMouseMove(FCV, X, Y) then
    LoadOlderIfNeeded;
  pbChart.Invalidate;
end;

procedure TMainForm.LoadOlderIfNeeded;
begin
  if FCV.AtStart and not FOlderBusy and not FNoMoreHistory and (Length(FChartK) > 0) then
  begin
    FOlderBusy := True;
    TOlderThread.Create(Handle, FSelected, FInterval, FChartK[0].OpenTime - 1);
  end;
end;

procedure TMainForm.WMOlder(var M: TMessage);
var
  D: TLiveData;
begin
  D := TLiveData(M.LParam);
  try
    FOlderBusy := False;
    if (D.Err <> '') or (D.Sym <> FSelected) or (D.Interval <> FInterval) then
      Exit;
    if PrependKlines(FChartK, D.K) = 0 then
      FNoMoreHistory := True;   // sudah sampai candle pertama koin ini
    pbChart.Invalidate;
  finally
    D.Free;
  end;
end;

procedure TMainForm.pbChartMouseDown(Sender: TObject; Button: TMouseButton;
  Shift: TShiftState; X, Y: Integer);
begin
  if Button <> mbLeft then
    Exit;
  ViewMouseDown(FCV, X, Y);
  pbChart.Cursor := crSizeAll;
end;

procedure TMainForm.pbChartMouseUp(Sender: TObject; Button: TMouseButton;
  Shift: TShiftState; X, Y: Integer);
begin
  ViewMouseUp(FCV);
  pbChart.Cursor := crCross;
end;

procedure TMainForm.pbChartDblClick(Sender: TObject);
begin
  ResetView(FCV);
  pbChart.Invalidate;
end;

procedure TMainForm.AppMessage(var Msg: TMsg; var Handled: Boolean);
var
  P: TPoint;
  Delta: Integer;
begin
  if Msg.message <> WM_MOUSEWHEEL then
    Exit;
  P := Point(SmallInt(LoWord(Msg.lParam)), SmallInt(HiWord(Msg.lParam)));
  Delta := SmallInt(HiWord(Msg.wParam));
  if WindowFromPoint(P) = pnlChart.Handle then
  begin
    ViewZoom(FCV, Delta);
    pbChart.Invalidate;
    LoadOlderIfNeeded;
    Handled := True;
  end
  else
    Handled := BtcChartWheel(P, Delta);
end;

procedure TMainForm.RequestDetail;
begin
  if FSelected = '' then
    Exit;
  Inc(FReqId);
  TDetailThread.Create(Handle, FSelected, FInterval, FReqId);
  tmrDetail.Enabled := False;
  tmrDetail.Enabled := True;
end;

procedure TMainForm.ShowDetail(D: TDetailData);
var
  L: TStringList;
  A: TAnalysis;
  I, Idx: Integer;
  Row: TCoinRow;
  S, St: string;
  Tot: Double;
begin
  A := D.A;
  if D.Err = '' then
  begin
    // grafik tetap tampil walau candle terlalu sedikit untuk analisa (mis. 1 bln).
    // Bila koin & time frame sama, sambungkan saja agar riwayat lama yang sudah dimuat tidak hilang.
    if (Length(FChartK) > 0) and (FChartA.Symbol = A.Symbol) and (FChartA.Interval = A.Interval) then
      MergeKlines(FChartK, D.K)
    else
      FChartK := D.K;
    FChartA := A;
    FChartTitle := A.Symbol + '  ' + ChartTFLabel(A.Interval);
    pbChart.Invalidate;
  end;
  if (D.Err <> '') or not A.Ok then
  begin
    if D.Err <> '' then S := D.Err else S := A.Err;
    memoDetail.Lines.Text := ' Analisa ' + A.Symbol + ' (' + ChartTFLabel(A.Interval) +
      ') belum bisa dibuat:' + #13#10 + ' ' + S;
    Exit;
  end;

  Idx := FindCoin(A.Symbol);
  if Idx >= 0 then
  begin
    if A.Interval = ScanInterval then
      ApplyAnalysis(Idx, A);
    Row := FCoins[Idx];
  end
  else
    Row.Chg24 := 0;
  UpdateCoinHeader;

  L := TStringList.Create;
  try
    L.Add(Format(' %s   |   timeframe %s   |   %s', [A.Symbol, A.Interval, FormatDateTime('hh:nn:ss', Now)]));
    L.Add('');
    L.Add(Format(' SINYAL   : %s   (skor %d)', [SignalText(A.Signal), A.Score]));
    L.Add(' Trend MA : ' + A.Trend);
    if A.Reasons <> '' then
      L.Add(TrimRight(A.Reasons));
    L.Add('');

    L.Add(' --- LEVEL PALING SERING MENOLAK (500 candle) ---');
    L.Add(Format(' SUPPORT TERKUAT  : %s %s  memantul naik %d kali',
      [FmtPrice(A.StrongSup), DistPct(A.StrongSup, A.Price), A.StrongSupHits]));
    L.Add(Format(' RESISTEN TERKUAT : %s %s  ditolak turun %d kali',
      [FmtPrice(A.StrongRes), DistPct(A.StrongRes, A.Price), A.StrongResHits]));
    L.Add('');

    L.Add(' --- SUPPORT & RESISTEN ---');
    L.Add(Format(' Resisten terdekat : %14s %s', [FmtPrice(A.SwingRes), DistPct(A.SwingRes, A.Price)]));
    L.Add(Format(' Support terdekat  : %14s %s', [FmtPrice(A.SwingSup), DistPct(A.SwingSup, A.Price)]));
    L.Add(Format(' Pivot  R2 %s | R1 %s | P %s | S1 %s | S2 %s',
      [FmtPrice(A.R2), FmtPrice(A.R1), FmtPrice(A.Pivot), FmtPrice(A.S1), FmtPrice(A.S2)]));
    L.Add(Format(' Range 50 candle   : %s - %s', [FmtPrice(A.RangeLow), FmtPrice(A.RangeHigh)]));
    L.Add('');

    L.Add(Format(' --- VOLUME BELI vs JUAL (%d candle terakhir) ---', [A.VolWindow]));
    L.Add(Format(' Beli : %12s  (%5.1f%%)', [FmtUSD(A.BuyUSD), A.BuyPct]));
    L.Add(Format(' Jual : %12s  (%5.1f%%)', [FmtUSD(A.SellUSD), A.SellPct]));
    L.Add(' Beli ' + Bar(A.BuyPct, 30) + ' Jual');
    if D.DepthOk then
    begin
      Tot := D.BidUSD + D.AskUSD;
      if Tot > 0 then
      begin
        L.Add(Format(' Order book: antrian beli %s (%.1f%%) | antrian jual %s (%.1f%%)',
          [FmtUSD(D.BidUSD), D.BidUSD / Tot * 100, FmtUSD(D.AskUSD), D.AskUSD / Tot * 100]));
      end;
    end;
    L.Add('');

    L.Add(' --- MOVING AVERAGE ---');
    for I := 0 to MACount - 1 do
      if A.MAValid[I] then
      begin
        if A.Price > A.MA[I] then St := 'harga DI ATAS' else St := 'harga DI BAWAH';
        L.Add(Format(' MA%-4d: %14s  %-10s %s', [MAPeriods[I], FmtPrice(A.MA[I]),
          DistPct(A.MA[I], A.Price), St]));
      end
      else
        L.Add(Format(' MA%-4d: data belum cukup', [MAPeriods[I]]));
    L.Add('');

    L.Add(' --- PERSILANGAN MA (cross dalam ' + IntToStr(CrossLookback) + ' candle terakhir) ---');
    for I := 0 to High(A.Crosses) do
      with A.Crosses[I] do
      begin
        S := Format(' MA%-3d x MA%-3d : ', [MAPeriods[Fast], MAPeriods[Slow]]);
        if not Valid then
          S := S + 'data belum cukup'
        else
        begin
          if Above then S := S + 'DI ATAS  ' else S := S + 'DI BAWAH ';
          if Ago >= 0 then
          begin
            if Golden then S := S + '| GOLDEN CROSS ' else S := S + '| DEATH CROSS ';
            if Ago = 0 then S := S + '(candle ini)'
            else S := S + Format('(%d candle lalu)', [Ago]);
          end;
        end;
        L.Add(S);
      end;
    L.Add('');

    L.Add(' --- WARNING ---');
    if Row.Chg24 >= Threshold then
      L.Add(Format(' ! NAIK %s dalam 24 jam (>= %.1f%%)', [FmtPct(Row.Chg24), Threshold]));
    if A.Rise4 >= Threshold then
      L.Add(Format(' ! MULAI NAIK %.2f%% dari low 4 candle terakhir', [A.Rise4]));
    if A.Breakout <> '' then
      L.Add(' ! ' + A.Breakout + Format('  (volume %.1fx rata-rata)', [A.VolRatio]));
    if (Row.Chg24 < Threshold) and (A.Rise4 < Threshold) and (A.Breakout = '') then
      L.Add(' Tidak ada warning.');
    L.Add('');
    L.Add(' Catatan: sinyal hanya alat bantu analisa teknikal, bukan saran keuangan.');
    memoDetail.Lines.Assign(L);
  finally
    L.Free;
  end;
end;

end.
