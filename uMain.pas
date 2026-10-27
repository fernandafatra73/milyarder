unit uMain;

{ Form utama Fernanda Taker. Semua komponen dibuat lewat kode (tanpa .dfm). }

interface

uses
  Windows, Messages, SysUtils, Classes, Graphics, Controls, Forms, StdCtrls,
  ExtCtrls, ComCtrls, CommCtrl, ImgList, Math, Dialogs, uAnalysis, uBinance, uWorkers,
  uChart, uBtc, uDemo, uExness, uCandle, uShot;

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
    // dari analisa terakhir, untuk cek breakout ulang tiap menit
    RangeHigh, RangeLow, MA9, MA25, VolRatio: Double;
    Alert24, AlertRise: Boolean;
    AlertBO: string;
    BoChance: Integer;   // peluang breakout dari analisa 1 menit (0-100)
    BoNote: string;
    BoAlert: Boolean;
    BoTime: TDateTime;   // jam analisa 1 menit keluar
    BoEta: TDateTime;    // perkiraan jam mencapai resisten (0 = belum terlihat)
    SideCount: Integer;  // jumlah time frame yang sideways
    SideNet: Integer;    // prediksi naik dikurangi turun (>0 naik, <0 turun)
    SideText: string;
  end;

  TMainForm = class(TForm)
  private
    btnDemo, btnExness, btnPersen, btnBO: TPanel;
    pnlTop, pnlMarket, pnlRight, pnlBottom, pnlStatus, pnlCoinHead, pnlChart: TPanel;
    btnBtc, btnOpen, btnSide, btnSS, btnCandle: TPanel;
    pnlFrame, pnlFrameBar, pnlGrip, btnFrameClose, btnFrameMax: TPanel;
    FFrameDrag, FFrameSize, FFrameMax, FFrameInit: Boolean;
    FFramePt: TPoint;
    FrmCoin: TForm;
    pnlBo, pnlPick, btnXau, btnClr: TPanel;
    cbCoin: TComboBox;
    lblCoinBook, lblBookSep, lblBookSell: TLabel;
    lblBo: TLabel;
    FDepthSym: string;       // order book terakhir yang diterima (untuk koin ini)
    FDepthBid, FDepthAsk, FDepthWallPrice, FDepthWallUSD, FDepthBidWallPrice, FDepthBidWallUSD: Double;
    FPreBoBusy: Boolean;
    FPreBoStart: Cardinal;
    FSideBusy: Boolean;
    FSideStart: Cardinal;
    FFrameEdge: Integer;   // bit: 1 kiri, 2 kanan, 4 bawah, 8 atas
    FFrameNormal: TRect;
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
    tmrDetail, tmrSelect, tmrRefresh, tmrLive, tmrBreakout: TTimer;
    FLastBreakoutCheck: TDateTime;
    lblLive: TLabel;
    FLiveBusy: Boolean;
    FLiveStart: Cardinal;

    FCoins: array of TCoinRow;
    FIndex: TStringList;
    FView: array of Integer;
    FSortCol: Integer;
    FSortDesc: Boolean;
    FBoMode: Boolean;     // urutan khusus tombol BO: sinyal beli / breakout dulu
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
    procedure tmrBreakoutTimer(Sender: TObject);
    procedure WMLive(var M: TMessage); message WM_FT_LIVE;
    procedure WMPreBo(var M: TMessage); message WM_FT_PREBO;
    procedure StartPreBo;
    procedure WMSide(var M: TMessage); message WM_FT_SIDE;
    procedure StartSide;
    procedure UpdateBoBanner;
    procedure ChooseCoin(const Sym: string);
    procedure XauClick(Sender: TObject);
    procedure cbCoinDropDown(Sender: TObject);
    procedure ClrClick(Sender: TObject);
    function CoinLabel(const Sym: string): string;
    function LabelSym(const S: string): string;
    procedure cbCoinSelect(Sender: TObject);
    procedure cbCoinKeyDown(Sender: TObject; var Key: Word; Shift: TShiftState);
    procedure UpdateMarketStrip;
    procedure UpdateCoinHeader;
    procedure UpdateSuggest;
    procedure ChooseSuggest(I: Integer);
    procedure AddAlert(const Sym, Txt: string);
    procedure SetSelected(const Sym: string);
    procedure ShowFrame;
    procedure FrmCoinClose(Sender: TObject; var Action: TCloseAction);
    procedure PlaceGrip;
    procedure FrameResize(Sender: TObject);
    procedure RightResize(Sender: TObject);
    procedure FrameCloseClick(Sender: TObject);
    procedure FrameMaxClick(Sender: TObject);
    procedure BarMouseDown(Sender: TObject; Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
    procedure BarMouseMove(Sender: TObject; Shift: TShiftState; X, Y: Integer);
    procedure GripMouseDown(Sender: TObject; Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
    procedure GripMouseMove(Sender: TObject; Shift: TShiftState; X, Y: Integer);
    procedure FrameMouseUp(Sender: TObject; Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
    procedure lvClick(Sender: TObject);
    function EdgeAt(X, Y: Integer): Integer;
    procedure EdgeMouseDown(Sender: TObject; Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
    procedure EdgeMouseMove(Sender: TObject; Shift: TShiftState; X, Y: Integer);
    procedure SelectSymbol(const Sym: string; KeepSearch: Boolean = False);
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
    procedure btnDemoClick(Sender: TObject);
    procedure btnExnessClick(Sender: TObject);
    procedure btnPersenClick(Sender: TObject);
    procedure btnBOClick(Sender: TObject);
    procedure btnSideClick(Sender: TObject);
    procedure btnSSClick(Sender: TObject);
    procedure ShowSSReport(const Title: string; const A: TAnalysis; const K: TKlines;
      P: Double; const Note: string; Relative: Boolean);
    procedure btnCandleClick(Sender: TObject);
    procedure CandleSyms(var Syms: TSymArr);
    function TopVolumeCoins(N: Integer): TSymArr;
    procedure SSClose(Sender: TObject; var Action: TCloseAction);
    function DemoQuote(const Sym: string; var Q: TDemoQuote): Boolean;
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
  SideTopCoins = 30;   // koin volume terbesar yang dicek sideways tiap putaran

  ColNames: array[0..17] of string = ('No', 'Koin', 'Harga', '24j %',
    'Volume 24j', 'Beli %', 'Jual %', 'Beli $ (24j)', 'Jual $ (24j)', 'Trend MA',
    'Cross MA terakhir', 'Support', 'Resisten', 'Support terkuat (x mantul)', 'Status', 'Sinyal', 'Peluang BO 1m (jam, perkiraan breakout)',
    'Sideways + prediksi (1m 5m 10m 15m 30m 1j)');
  ColWidths: array[0..17] of Integer = (42, 105, 95, 72, 88, 58, 58, 88, 88, 100,
    150, 88, 88, 165, 120, 135, 330, 420);

  FilterNames: array[0..13] of string = ('Semua koin', 'Naik >= warning %', 'Turun',
    'Mau breakout / breakout', 'Golden cross baru', 'Death cross baru',
    'Trend bullish', 'Trend bearish', 'Sinyal BELI', 'Sinyal JUAL', 'Peluang breakout tinggi (>=75)',
    'Sideways (semua prediksi)', 'Sideways prediksi NAIK', 'Sideways prediksi TURUN');

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
  FSortCol := 3;
  FSortDesc := True;
  FHoverX := -1;
  FInterval := ChartTFApi[DefaultChartTF];
  BuildUI;
  FrmCoin.HandleNeeded;   // siapkan jendela kerangka sejak awal agar muncul instan
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
  chkSound.Checked := False;   // bunyi peringatan mati; centang "Suara" untuk menyalakan
  chkSound.Color := clrPanel;
  chkSound.Font.Color := clrText;

  btnBtc := MakeBtn(pnlTop, 820, 10, 96, 46, 'BTC', clrGold, clrBg, btnBtcClick);
  btnBtc.Font.Size := 16;
  btnBtc.Hint := 'Analisa khusus Bitcoin: naik/turun, support, resisten, kapan beli/jual';
  btnBtc.ShowHint := True;

  btnCandle := MakeBtn(pnlTop, 926, 10, 96, 46, 'Candle', clrPanel2, clrUp, btnCandleClick);
  btnCandle.Font.Size := 14;
  btnCandle.Hint := 'Pola candle, pola chart & strategi: sinyal BELI/JUAL di 1m, 5m, 15m, 30m';
  btnCandle.ShowHint := True;

  btnSide := MakeBtn(pnlTop, 1032, 10, 96, 46, 'Side Way', clrPanel2, clrGold, btnSideClick);
  btnSide.Font.Size := 12;
  btnSide.Hint := 'Tampilkan hanya koin sideways + prediksi naik/turun (klik lagi untuk semua koin)';
  btnSide.ShowHint := True;

  btnDemo := MakeBtn(pnlTop, 1138, 10, 96, 46, 'Demo', clrUp, clrBg, btnDemoClick);
  btnDemo.Font.Size := 16;
  btnDemo.Hint := 'Demo trading Futures (uang virtual): long/short, leverage, time frame, pilih koin';
  btnDemo.ShowHint := True;

  btnExness := MakeBtn(pnlTop, 1244, 10, 110, 46, 'Exness', $0000E6FF, clrBg, btnExnessClick);
  btnExness.Font.Size := 16;
  btnExness.Hint := 'Terminal trading bergaya Exness (akun demo): lot, Buy/Sell, pending, TP/SL, margin';
  btnExness.ShowHint := True;

  btnPersen := MakeBtn(pnlTop, 1360, 10, 96, 46, 'Persen', clrPanel2, clrUp, btnPersenClick);
  btnPersen.Font.Size := 14;
  btnPersen.Hint := 'Urutkan tabel berdasarkan persen naik 24 jam (tertinggi di atas)';
  btnPersen.ShowHint := True;

  btnBO := MakeBtn(pnlTop, 1462, 10, 76, 46, 'BO', clrPanel2, clrGold, btnBOClick);
  btnBO.Font.Size := 16;
  btnBO.Hint := 'Urutkan tabel berdasarkan koin yang mau breakout (peluang BO tertinggi di atas)';
  btnBO.ShowHint := True;

  btnSS := MakeBtn(pnlTop, 1544, 10, 110, 46, 'Analisa SS', clrPanel2, clrGold, btnSSClick);
  btnSS.Font.Size := 12;
  btnSS.Hint := 'Analisa koin terpilih: breakout/breakdown, MA 25/99/200, resisten, support, dan harga yang paling banyak dibeli';
  btnSS.ShowHint := True;

  btnOpen := MakeBtn(pnlTop, 1664, 10, 220, 46, 'Buka di Binance.bh Futures',
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
  { kerangka melayang di atas tabel: bisa digeser, diperbesar/diperkecil, ditutup }
  { jendela terpisah di luar tabel: bisa dipindah ke mana saja, diubah ukurannya }
  FrmCoin := TForm.CreateNew(Self);
  FrmCoin.BorderStyle := bsSizeable;
  FrmCoin.Caption := 'Grafik & Analisa';
  FrmCoin.Color := clrPanel;
  FrmCoin.Position := poDesigned;
  FrmCoin.SetBounds(Screen.Width - 1120, 90, 1100, 680);
  FrmCoin.Constraints.MinWidth := 420;
  FrmCoin.Constraints.MinHeight := 320;
  FrmCoin.OnClose := FrmCoinClose;

  pnlFrame := TPanel.Create(Self);
  pnlFrame.Parent := FrmCoin;
  pnlFrame.Align := alClient;
  pnlFrame.BevelOuter := bvNone;
  pnlFrame.Color := clrPanel;
  pnlFrame.OnResize := FrameResize;
  pnlFrame.OnMouseDown := EdgeMouseDown;
  pnlFrame.OnMouseMove := EdgeMouseMove;
  pnlFrame.OnMouseUp := FrameMouseUp;

  pnlFrameBar := TPanel.Create(Self);
  pnlFrameBar.Parent := pnlFrame;
  pnlFrameBar.Visible := False;   // judul & tombol sudah disediakan jendela
  pnlFrameBar.Align := alTop;
  pnlFrameBar.Height := 26;
  pnlFrameBar.BevelOuter := bvNone;
  pnlFrameBar.Color := clrPanel2;
  pnlFrameBar.Font.Color := clrGold;
  pnlFrameBar.Font.Style := [fsBold];
  pnlFrameBar.Alignment := taLeftJustify;
  pnlFrameBar.Caption := '  Grafik & Analisa';
  pnlFrameBar.Cursor := crSizeAll;
  pnlFrameBar.OnMouseDown := BarMouseDown;
  pnlFrameBar.OnMouseMove := BarMouseMove;
  pnlFrameBar.OnMouseUp := FrameMouseUp;
  btnFrameClose := MakeBtn(pnlFrameBar, 0, 2, 26, 22, 'X', clrDownBg, clrDown, FrameCloseClick);
  btnFrameClose.Align := alRight;
  btnFrameClose.Width := 30;
  btnFrameMax := MakeBtn(pnlFrameBar, 0, 2, 56, 22, 'Besar', clrPanel, clrText, FrameMaxClick);
  btnFrameMax.Align := alRight;
  btnFrameMax.Font.Size := 8;

  pnlRight := TPanel.Create(Self);
  pnlRight.Parent := pnlFrame;
  pnlRight.Align := alClient;
  pnlRight.BevelOuter := bvNone;
  pnlRight.Color := clrPanel;
  pnlRight.OnResize := RightResize;

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
  lblCoinBook := MakeLabel(pnlCoinHead, 560, 15, '');
  lblCoinBook.Font.Size := 10;
  lblCoinBook.Font.Style := [fsBold];
  lblCoinBook.Font.Color := clrUp;
  lblBookSep := MakeLabel(pnlCoinHead, 560, 15, ' | ');
  lblBookSep.Font.Size := 10;
  lblBookSep.Font.Style := [fsBold];
  lblBookSell := MakeLabel(pnlCoinHead, 560, 15, '');
  lblBookSell.Font.Size := 10;
  lblBookSell.Font.Style := [fsBold];
  lblBookSell.Font.Color := clrDown;

  { peluang breakout (analisa 1 menit) di bagian atas kerangka }
  pnlBo := TPanel.Create(Self);
  pnlBo.Parent := pnlRight;
  pnlBo.Align := alTop;
  pnlBo.Top := pnlCoinHead.Height;
  pnlBo.Height := 46;
  pnlBo.BevelOuter := bvNone;
  pnlBo.Color := clrBg;
  lblBo := TLabel.Create(Self);
  lblBo.Parent := pnlBo;
  lblBo.Align := alClient;
  lblBo.AutoSize := False;
  lblBo.WordWrap := True;
  lblBo.Layout := tlCenter;
  lblBo.Font.Size := 10;
  lblBo.Font.Style := [fsBold];
  lblBo.Font.Color := clrDim;
  lblBo.Caption := '  Peluang breakout (analisa 1 menit): -';

  { tombol time frame grafik }
  pnlTF := TPanel.Create(Self);
  pnlTF.Parent := pnlRight;
  pnlTF.Align := alTop;
  pnlTF.Top := pnlCoinHead.Height + pnlBo.Height;
  pnlTF.Height := 34;
  pnlTF.BevelOuter := bvNone;
  pnlTF.Color := clrPanel;
  for I := 0 to ChartTFCount - 1 do
  begin
    FTFBtns[I] := MakeBtn(pnlTF, 8 + I * 58, 5, 54, 24, ChartTFLabels[I],
      clrPanel2, clrDim, TFClick);
    FTFBtns[I].Font.Size := 9;
    FTFBtns[I].Tag := I;
  end;
  lblLive := MakeLabel(pnlTF, 8 + ChartTFCount * 58 + 6, 9, '');
  lblLive.Font.Style := [fsBold];
  lblLive.Font.Color := clrUp;

  { pilihan koin Binance langsung dari halaman grafik & analisa }
  pnlPick := TPanel.Create(Self);
  pnlPick.Parent := pnlTF;
  pnlPick.Align := alRight;
  pnlPick.Width := 296;
  pnlPick.BevelOuter := bvNone;
  pnlPick.Color := clrPanel;
  cbCoin := TComboBox.Create(Self);
  cbCoin.Parent := pnlPick;
  cbCoin.SetBounds(4, 5, 170, 24);
  btnClr := MakeBtn(pnlPick, 178, 5, 26, 24, 'X', clrPanel2, clrDown, ClrClick);
  btnClr.Font.Size := 10;
  btnClr.Hint := 'Kosongkan pencarian koin';
  btnClr.ShowHint := True;
  btnXau := MakeBtn(pnlPick, 208, 5, 80, 24, 'XAUUSDT', clrGold, clrBg, XauClick);
  btnXau.Font.Size := 9;
  btnXau.Hint := 'Buka grafik & analisa emas (XAUUSDT)';
  btnXau.ShowHint := True;
  cbCoin.Style := csDropDown;
  cbCoin.Color := clrBg;
  cbCoin.Font.Color := clrText;
  cbCoin.Font.Style := [fsBold];
  cbCoin.DropDownCount := 18;
  cbCoin.Text := 'Pilih koin Binance';
  cbCoin.OnDropDown := cbCoinDropDown;
  cbCoin.OnSelect := cbCoinSelect;
  cbCoin.OnKeyDown := cbCoinKeyDown;

  pnlChart := TPanel.Create(Self);
  pnlChart.Parent := pnlRight;
  pnlChart.Align := alClient;
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
  memoDetail.Align := alRight;
  memoDetail.Width := 430;
  memoDetail.BorderStyle := bsNone;
  memoDetail.ReadOnly := True;
  memoDetail.ScrollBars := ssBoth;
  memoDetail.WordWrap := False;
  memoDetail.Color := clrBg;
  memoDetail.Font.Name := 'Consolas';
  memoDetail.Font.Size := 10;
  memoDetail.Font.Color := clrText;

  with TSplitter.Create(Self) do
  begin
    Parent := pnlRight;
    Align := alRight;
    Left := memoDetail.Left - 1;
    Width := 5;
    Color := clrPanel2;
  end;

  pnlGrip := TPanel.Create(Self);
  pnlGrip.Parent := pnlFrame;
  pnlGrip.Visible := False;
  pnlGrip.SetBounds(0, 0, 20, 20);
  pnlGrip.BevelOuter := bvNone;
  pnlGrip.Color := clrGold;
  pnlGrip.Cursor := crSizeNWSE;
  pnlGrip.OnMouseDown := GripMouseDown;
  pnlGrip.OnMouseMove := GripMouseMove;
  pnlGrip.OnMouseUp := FrameMouseUp;

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
  lv.OnClick := lvClick;
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
  tmrSelect.Interval := 150;
  tmrSelect.OnTimer := tmrSelectTimer;
  tmrRefresh := TTimer.Create(Self);
  tmrRefresh.Interval := 1500;
  tmrRefresh.OnTimer := tmrRefreshTimer;
  tmrLive := TTimer.Create(Self);
  tmrLive.Interval := 1000;   // harga grafik diperbarui tiap 1 detik
  tmrLive.OnTimer := tmrLiveTimer;
  tmrBreakout := TTimer.Create(Self);
  tmrBreakout.Interval := 60000;   // analisa breakout semua koin diperbarui tiap 1 menit
  tmrBreakout.OnTimer := tmrBreakoutTimer;

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
    10: Result := R.BoChance >= 75;
    11: Result := R.SideCount > 0;
    12: Result := (R.SideCount > 0) and (R.SideNet > 0);
    13: Result := (R.SideCount > 0) and (R.SideNet < 0);
  else
    Result := True;
  end;
end;

{ 3 = sinyal BELI + breakout, 2 = sinyal BELI, 1 = breakout / mau breakout, 0 = lainnya }
function BoRank(const R: TCoinRow): Integer;
var
  Bo: Boolean;
begin
  Bo := (R.Breakout = 'MAU BREAKOUT') or (R.Breakout = 'BREAKOUT NAIK');
  if (R.Signal = 'BELI') and Bo then Result := 3
  else if R.Signal = 'BELI' then Result := 2
  else if Bo then Result := 1
  else Result := 0;
end;

function TMainForm.CompareRows(A, B: Integer): Integer;
var
  CA, CB: Integer;
begin
  if FBoMode then
  begin
    Result := BoRank(FCoins[A]) - BoRank(FCoins[B]);
    if Result = 0 then
      Result := FCoins[A].BoChance - FCoins[B].BoChance;
    if Result = 0 then
      Result := CmpF(FCoins[A].Chg24, FCoins[B].Chg24);
    if Result = 0 then
      Result := CompareStr(FCoins[B].Symbol, FCoins[A].Symbol);
    Result := -Result;
    Exit;
  end;
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
    16: Result := FCoins[A].BoChance - FCoins[B].BoChance;
    17:
      begin
        Result := FCoins[A].SideCount - FCoins[B].SideCount;
        if Result = 0 then
          Result := FCoins[A].SideNet - FCoins[B].SideNet;
      end;
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

{ Cek ulang status breakout semua koin yang sudah dianalisa memakai harga
  terbaru dari ticker; batas range diambil dari analisa terakhir. }
procedure TMainForm.tmrBreakoutTimer(Sender: TObject);
var
  I: Integer;
  B: string;
begin
  for I := 0 to High(FCoins) do
    with FCoins[I] do
    begin
      if not Scanned then
        Continue;
      B := BreakoutStatus(Price, RangeHigh, RangeLow, MA9, MA25, VolRatio);
      if B <> Breakout then
      begin
        Breakout := B;
        FDirty := True;
      end;
      if (B <> '') and (B <> AlertBO) then
        AddAlert(Symbol, Format('[%s] %s harga %s, resisten %s, support %s',
          [B, Symbol, FmtPrice(Price), FmtPrice(RangeHigh), FmtPrice(RangeLow)]));
      AlertBO := B;
    end;
  StartPreBo;
  StartSide;
  FLastBreakoutCheck := Now;
  FDirty := True;
end;

function EtaText(Eta, Base: TDateTime): string; forward;

{ Koin yang harganya sudah dekat/di atas resisten 1 jam dianalisa lagi dengan
  candle 1 menit untuk menilai peluang breakout (dilihat dari persilangan MA
  di bawah harga). Maksimal 12 koin terdekat per putaran. }
procedure TMainForm.StartPreBo;
var
  I, J, N: Integer;
  Dist: array of Double;
  Cand: array of Integer;
  Syms: array of string;
  Highs: array of Double;
  D: Double;
begin
  if FPreBoBusy and (GetTickCount - FPreBoStart < 60000) then
    Exit;
  N := 0;
  SetLength(Cand, Length(FCoins));
  SetLength(Dist, Length(FCoins));
  for I := 0 to High(FCoins) do
    with FCoins[I] do
    begin
      if Scanned and (RangeHigh > 0) and (Price >= RangeHigh * 0.97) then
      begin
        D := Abs(RangeHigh - Price) / RangeHigh;
        J := N;
        while (J > 0) and (Dist[J - 1] > D) do   // urut: paling dekat resisten dulu
        begin
          Dist[J] := Dist[J - 1];
          Cand[J] := Cand[J - 1];
          Dec(J);
        end;
        Dist[J] := D;
        Cand[J] := I;
        Inc(N);
      end
      else if BoChance <> 0 then
      begin
        BoChance := 0;
        BoNote := '';
        BoAlert := False;
        FDirty := True;
      end;
    end;
  if N > 12 then
    N := 12;
  if N = 0 then
    Exit;
  SetLength(Syms, N);
  SetLength(Highs, N);
  for I := 0 to N - 1 do
  begin
    Syms[I] := FCoins[Cand[I]].Symbol;
    Highs[I] := FCoins[Cand[I]].RangeHigh;
  end;
  FPreBoBusy := True;
  FPreBoStart := GetTickCount;
  TPreBoThread.Create(Handle, Syms, Highs);
end;

procedure TMainForm.WMPreBo(var M: TMessage);
var
  D: TPreBoData;
  Idx: Integer;
begin
  D := TPreBoData(M.LParam);
  try
    if D.Last then
    begin
      FPreBoBusy := False;
      Exit;
    end;
    if D.Err <> '' then
      Exit;
    Idx := FindCoin(D.Sym);
    if Idx < 0 then
      Exit;
    with FCoins[Idx] do
    begin
      BoChance := D.Chance;
      BoNote := D.Note;
      BoTime := Now;
      if D.EtaMin >= 0 then
        BoEta := Now + D.EtaMin / 1440
      else
        BoEta := 0;
      if (BoChance >= 75) and not BoAlert then
      begin
        BoAlert := True;
        AddAlert(Symbol, Format('[PELUANG BREAKOUT %d%%] %s harga %s, resisten %s - %s (analisa 1m jam %s) - %s',
          [BoChance, Symbol, FmtPrice(Price), FmtPrice(RangeHigh), BoNote, FormatDateTime('hh:nn:ss', BoTime), EtaText(BoEta, BoTime)]));
      end
      else if BoChance < 60 then
        BoAlert := False;
    end;
    FDirty := True;
    if D.Sym = FSelected then
      UpdateBoBanner;
  finally
    D.Free;
  end;
end;

{ Cek sideways + prediksi arah di 6 time frame untuk SideTopCoins koin dengan
  volume 24 jam terbesar (satu putaran selesai dulu sebelum mulai lagi). }
procedure TMainForm.StartSide;
var
  I, J, K, N, P: Integer;
  Cand: array of Integer;
  Syms: array of string;
begin
  if FSideBusy and (GetTickCount - FSideStart < 240000) then
    Exit;
  N := Min(SideTopCoins, Length(FCoins));
  if N = 0 then
    Exit;
  SetLength(Cand, N);
  K := 0;
  for I := 0 to High(FCoins) do
  begin
    J := K;   // posisi sisip pada daftar yang terurut volume turun
    while (J > 0) and (FCoins[Cand[J - 1]].QuoteVol < FCoins[I].QuoteVol) do
      Dec(J);
    if J >= N then
      Continue;
    if K < N then
      Inc(K);
    for P := K - 1 downto J + 1 do
      Cand[P] := Cand[P - 1];
    Cand[J] := I;
  end;
  SetLength(Syms, K);
  for I := 0 to K - 1 do
    Syms[I] := FCoins[Cand[I]].Symbol;
  FSideBusy := True;
  FSideStart := GetTickCount;
  TSideThread.Create(Handle, Syms);
end;

procedure TMainForm.WMSide(var M: TMessage);
var
  D: TSideData;
  Idx, T, Up, Dn: Integer;
  S: string;
begin
  D := TSideData(M.LParam);
  try
    if D.Last then
    begin
      FSideBusy := False;
      Exit;
    end;
    if not D.Ok then
      Exit;
    Idx := FindCoin(D.Sym);
    if Idx < 0 then
      Exit;
    Up := 0;
    Dn := 0;
    S := '';
    for T := 0 to SideTFCount - 1 do
      if D.Dir[T] <> 0 then
      begin
        if S <> '' then
          S := S + ', ';
        if D.Dir[T] > 0 then
        begin
          Inc(Up);
          S := S + SideTFLabel[T] + ' NAIK';
        end
        else
        begin
          Inc(Dn);
          S := S + SideTFLabel[T] + ' TURUN';
        end;
      end;
    with FCoins[Idx] do
    begin
      SideCount := Up + Dn;
      SideNet := Up - Dn;
      if SideCount = 0 then
        SideText := ''
      else
      begin
        if Up > Dn then SideText := 'NAIK'
        else if Dn > Up then SideText := 'TURUN'
        else SideText := 'IMBANG';
        SideText := Format('%s (%d/%d)  %s', [SideText, Up, Dn, S]);
      end;
    end;
    FDirty := True;
  finally
    D.Free;
  end;
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

function TMainForm.CoinLabel(const Sym: string): string;
var
  Idx: Integer;
begin
  Idx := FindCoin(Sym);
  if Idx >= 0 then
    Result := Sym + '   ' + FmtPct(FCoins[Idx].Chg24)
  else
    Result := Sym;
end;

{ ambil nama koin dari teks "BTCUSDT   +2.35%" }
function TMainForm.LabelSym(const S: string): string;
var
  P: Integer;
begin
  Result := UpperCase(Trim(S));
  P := Pos(' ', Result);
  if P > 0 then
    Result := Copy(Result, 1, P - 1);
end;

procedure TMainForm.cbCoinDropDown(Sender: TObject);
var
  I: Integer;
  Txt: string;
begin
  Txt := cbCoin.Text;
  cbCoin.Items.BeginUpdate;
  try
    cbCoin.Items.Clear;
    for I := 0 to FIndex.Count - 1 do
      cbCoin.Items.Add(CoinLabel(FIndex[I]));
  finally
    cbCoin.Items.EndUpdate;
  end;
  cbCoin.Text := Txt;
end;

procedure TMainForm.ClrClick(Sender: TObject);
begin
  cbCoin.Text := '';
  cbCoin.SetFocus;
end;

procedure TMainForm.XauClick(Sender: TObject);
begin
  ChooseCoin('XAUUSDT');
end;

procedure TMainForm.cbCoinSelect(Sender: TObject);
begin
  ChooseCoin(LabelSym(cbCoin.Text));
end;

procedure TMainForm.cbCoinKeyDown(Sender: TObject; var Key: Word; Shift: TShiftState);
var
  Sym: string;
begin
  if Key = VK_RETURN then
  begin
    Key := 0;
    Sym := LabelSym(cbCoin.Text);
    if (FindCoin(Sym) < 0) and (FindCoin(Sym + 'USDT') >= 0) then
      Sym := Sym + 'USDT';
    ChooseCoin(Sym);
  end;
end;

{ Ganti koin yang ditampilkan di kerangka tanpa mengubah pencarian di tabel }
procedure TMainForm.ChooseCoin(const Sym: string);
var
  I: Integer;
begin
  if FindCoin(Sym) < 0 then
  begin
    UpdateStatus('Koin ' + Sym + ' tidak ditemukan di Binance');
    Exit;
  end;
  SetSelected(Sym);
  tmrSelect.Enabled := False;
  RequestDetail;
  for I := 0 to High(FView) do
    if FCoins[FView[I]].Symbol = Sym then
    begin
      lv.Items[I].Selected := True;
      lv.Items[I].MakeVisible(False);
      Break;
    end;
end;

procedure TMainForm.UpdateBoBanner;
var
  Idx: Integer;
  Lvl: string;
begin
  Idx := FindCoin(FSelected);
  if Idx < 0 then
    Exit;
  with FCoins[Idx] do
    if BoChance > 0 then
    begin
      if BoChance >= 75 then Lvl := ' SANGAT TINGGI'
      else if BoChance >= 55 then Lvl := ' TINGGI'
      else Lvl := '';
      lblBo.Caption := Format('  Peluang breakout (analisa 1 menit, jam %s): %d%%%s  -  %s' + #13#10 + '  %s',
        [FormatDateTime('hh:nn:ss', BoTime), BoChance,
         Lvl,
         EtaText(BoEta, BoTime), BoNote]);
      if BoChance >= 75 then lblBo.Font.Color := clrUp
      else if BoChance >= 55 then lblBo.Font.Color := clrGold
      else lblBo.Font.Color := clrDim;
    end
    else
    begin
      lblBo.Caption := '  Peluang breakout (analisa 1 menit): belum ada - harga belum dekat resisten 1 jam';
      lblBo.Font.Color := clrDim;
    end;
end;

procedure TMainForm.UpdateCoinHeader;
var
  Idx: Integer;
  Tot: Double;
begin
  Idx := FindCoin(FSelected);
  if Idx < 0 then
    Exit;
  UpdateBoBanner;
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
  { order book di sebelah naik/turun 24 jam }
  lblCoinBook.Left := lblCoinChg.Left + lblCoinChg.Width + 24;
  Tot := FDepthBid + FDepthAsk;
  if (FDepthSym = FSelected) and (Tot > 0) then
  begin
    lblCoinBook.Caption := Format('Order book: antrian beli %s (%.1f%%)',
      [FmtUSD(FDepthBid), FDepthBid / Tot * 100]);
    if FDepthBidWallPrice > 0 then
      lblCoinBook.Caption := lblCoinBook.Caption + Format('  terbanyak di %s (%s)',
        [FmtPrice(FDepthBidWallPrice), FmtUSD(FDepthBidWallUSD)]);
    lblBookSell.Caption := Format('antrian jual %s (%.1f%%)',
      [FmtUSD(FDepthAsk), FDepthAsk / Tot * 100]);   { antrian jual merah }
    if FDepthWallPrice > 0 then
      lblBookSell.Caption := lblBookSell.Caption + Format('  terbanyak di %s (%s)',
        [FmtPrice(FDepthWallPrice), FmtUSD(FDepthWallUSD)]);
    lblBookSep.Visible := True;
  end
  else
  begin
    lblCoinBook.Caption := 'Order book: memuat ...';
    lblBookSell.Caption := '';
    lblBookSep.Visible := False;
  end;
  lblBookSep.Left := lblCoinBook.Left + lblCoinBook.Width;
  lblBookSell.Left := lblBookSep.Left + lblBookSep.Width;
end;

procedure TMainForm.UpdateStatus(const Extra: string);
var
  S: string;
begin
  S := Format('   Sumber: %s   |   Koin: %d   |   Ditampilkan: %d   |   Sudah dianalisa: %d/%d',
    [SourceName, Length(FCoins), Length(FView), FScanned, Length(FCoins)]);
  if FLastTicker > 0 then
    S := S + '   |   Update: ' + FormatDateTime('hh:nn:ss', FLastTicker);
  if FLastBreakoutCheck > 0 then
    S := S + '   |   Breakout dicek: ' + FormatDateTime('hh:nn:ss', FLastBreakoutCheck);
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
  SelectSymbol(lbSuggest.Items[I], True);
  lv.SetFocus;
  lbSuggest.Visible := False;   // teks cari sudah dikosongkan, jangan munculkan pilihan lagi
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
    RangeHigh := A.RangeHigh;
    RangeLow := A.RangeLow;
    MA9 := A.MA[0];
    MA25 := A.MA[1];
    VolRatio := A.VolRatio;
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
    while Item.SubItems.Count < 15 do
      Item.SubItems.Add('');
    if BoChance > 0 then
      Item.SubItems.Add(Format('%d%%  %s  %s', [BoChance, FormatDateTime('hh:nn', BoTime), EtaText(BoEta, BoTime)]))
    else
      Item.SubItems.Add('-');
    if SideText <> '' then
      Item.SubItems.Add(SideText)
    else
      Item.SubItems.Add('-');
  end;
end;

function EtaText(Eta, Base: TDateTime): string;
var
  M: Integer;
begin
  if Eta <= 0 then
    Result := 'waktu belum terlihat'
  else
  begin
    M := Round((Eta - Base) * 1440);
    if M <= 0 then
      Result := 'sudah breakout'
    else
      Result := Format('perkiraan breakout jam %s (+%d mnt)', [FormatDateTime('hh:nn', Eta), M]);
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
      16: if BoChance >= 75 then C := clrUp
          else if BoChance >= 55 then C := clrGold
          else C := clrDim;
      17: if SideCount = 0 then C := clrDim
          else if SideNet > 0 then C := clrUp
          else if SideNet < 0 then C := clrDown
          else C := clrGold;
      14: if Pos('BREAKOUT', Breakout) > 0 then C := clrGold
          else if Breakout <> '' then C := clrDown;
      15: if Signal = 'BELI' then C := clrUp
          else if Signal = 'JUAL' then C := clrDown
          else C := clrDim;
    end;
  Sender.Canvas.Font.Color := C;
  if SubItem in [1, 3, 13..15, 17] then
    Sender.Canvas.Font.Style := [fsBold]
  else
    Sender.Canvas.Font.Style := [];
end;

procedure TMainForm.ShowFrame;
begin
  if not FFrameInit then
  begin
    FFrameInit := True;
    SetWindowLong(FrmCoin.Handle, GWL_HWNDPARENT, Integer(Handle));   // selalu di atas jendela utama
  end;
  if not FrmCoin.Visible then
    ShowWindow(FrmCoin.Handle, SW_SHOWNOACTIVATE);   // jangan curi fokus dari tabel
  FrmCoin.Visible := True;
end;

procedure TMainForm.FrmCoinClose(Sender: TObject; var Action: TCloseAction);
begin
  Action := caHide;
end;

procedure TMainForm.PlaceGrip;
begin
  pnlGrip.SetBounds(pnlFrame.Width - 16, pnlFrame.Height - 16, 16, 16);
  pnlGrip.BringToFront;
end;

procedure TMainForm.FrameResize(Sender: TObject);
begin
  PlaceGrip;
end;

procedure TMainForm.RightResize(Sender: TObject);
begin
  if memoDetail.Width > pnlRight.ClientWidth - 200 then
    memoDetail.Width := pnlRight.ClientWidth - 200;
end;

function TMainForm.EdgeAt(X, Y: Integer): Integer;
const
  B = 8;
begin
  Result := 0;
  if X < B then Result := Result or 1;
  if X >= pnlFrame.Width - B then Result := Result or 2;
  if Y >= pnlFrame.Height - B then Result := Result or 4;
  if Y < B then Result := Result or 8;
end;

procedure TMainForm.EdgeMouseDown(Sender: TObject; Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
begin
  FFrameEdge := EdgeAt(X, Y);
  if (Button = mbLeft) and (FFrameEdge <> 0) and not FFrameMax then
  begin
    FFrameSize := True;
    FFramePt := Mouse.CursorPos;
  end;
end;

procedure TMainForm.EdgeMouseMove(Sender: TObject; Shift: TShiftState; X, Y: Integer);
var
  P: TPoint;
  L, T, W, H, E: Integer;
begin
  if not FFrameSize then
  begin
    E := EdgeAt(X, Y);
    case E of
      1, 2: pnlFrame.Cursor := crSizeWE;
      4, 8: pnlFrame.Cursor := crSizeNS;
      5, 10: pnlFrame.Cursor := crSizeNESW;
      6, 9: pnlFrame.Cursor := crSizeNWSE;
    else
      pnlFrame.Cursor := crDefault;
    end;
    Exit;
  end;
  P := Mouse.CursorPos;
  L := pnlFrame.Left; T := pnlFrame.Top;
  W := pnlFrame.Width; H := pnlFrame.Height;
  if (FFrameEdge and 2) <> 0 then Inc(W, P.X - FFramePt.X);
  if (FFrameEdge and 4) <> 0 then Inc(H, P.Y - FFramePt.Y);
  if (FFrameEdge and 1) <> 0 then begin Inc(L, P.X - FFramePt.X); Dec(W, P.X - FFramePt.X); end;
  if (FFrameEdge and 8) <> 0 then begin Inc(T, P.Y - FFramePt.Y); Dec(H, P.Y - FFramePt.Y); end;
  if W < 420 then begin if (FFrameEdge and 1) <> 0 then Dec(L, 420 - W); W := 420; end;
  if H < 320 then begin if (FFrameEdge and 8) <> 0 then Dec(T, 320 - H); H := 320; end;
  pnlFrame.SetBounds(L, T, W, H);
  FFramePt := P;
end;

procedure TMainForm.FrameCloseClick(Sender: TObject);
begin
  pnlFrame.Visible := False;
end;

procedure TMainForm.FrameMaxClick(Sender: TObject);
begin
  if FFrameMax then
  begin
    pnlFrame.BoundsRect := FFrameNormal;
    btnFrameMax.Caption := 'Besar';
  end
  else
  begin
    FFrameNormal := pnlFrame.BoundsRect;
    pnlFrame.SetBounds(lv.Left, lv.Top, lv.Width, lv.Height);
    btnFrameMax.Caption := 'Kecil';
  end;
  FFrameMax := not FFrameMax;
end;

procedure TMainForm.BarMouseDown(Sender: TObject; Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
begin
  if (Button = mbLeft) and not FFrameMax then
  begin
    FFrameDrag := True;
    FFramePt := Mouse.CursorPos;
  end;
end;

procedure TMainForm.BarMouseMove(Sender: TObject; Shift: TShiftState; X, Y: Integer);
var
  P: TPoint;
  L, T: Integer;
begin
  if not FFrameDrag then
    Exit;
  P := Mouse.CursorPos;
  L := pnlFrame.Left + P.X - FFramePt.X;
  T := pnlFrame.Top + P.Y - FFramePt.Y;
  if T < lv.Top then T := lv.Top;
  if L < 0 then L := 0;
  pnlFrame.SetBounds(L, T, pnlFrame.Width, pnlFrame.Height);
  FFramePt := P;
end;

procedure TMainForm.GripMouseDown(Sender: TObject; Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
begin
  if (Button = mbLeft) and not FFrameMax then
  begin
    FFrameSize := True;
    FFramePt := Mouse.CursorPos;
  end;
end;

procedure TMainForm.GripMouseMove(Sender: TObject; Shift: TShiftState; X, Y: Integer);
var
  P: TPoint;
  W, H: Integer;
begin
  if not FFrameSize then
    Exit;
  P := Mouse.CursorPos;
  W := pnlFrame.Width + P.X - FFramePt.X;
  H := pnlFrame.Height + P.Y - FFramePt.Y;
  if W < 380 then W := 380;
  if H < 320 then H := 320;
  pnlFrame.SetBounds(pnlFrame.Left, pnlFrame.Top, W, H);
  FFramePt := P;
end;

procedure TMainForm.FrameMouseUp(Sender: TObject; Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
begin
  FFrameDrag := False;
  FFrameSize := False;
end;

procedure TMainForm.lvClick(Sender: TObject);
var
  I: Integer;
  Sym: string;
begin
  if lv.Selected = nil then
    Exit;
  if tmrSelect.Enabled then
  begin
    { klik mouse: ambil data sekarang juga, tidak perlu menunggu jeda }
    tmrSelect.Enabled := False;
    RequestDetail;
  end;
  if edSearch.Text <> '' then
  begin
    { koin sudah dipilih dari hasil pencarian: kosongkan kotak cari, tampilkan semua koin }
    Sym := FSelected;
    edSearch.Text := '';
    for I := 0 to High(FView) do
      if FCoins[FView[I]].Symbol = Sym then
      begin
        lv.Items[I].MakeVisible(False);
        Break;
      end;
  end;
  if not FrmCoin.Visible then
    ShowFrame;
end;

procedure TMainForm.SetSelected(const Sym: string);
begin
  if Sym = FSelected then
    Exit;
  FSelected := Sym;
  if LabelSym(cbCoin.Text) <> Sym then
    cbCoin.Text := CoinLabel(Sym);
  FrmCoin.Caption := Sym + ' - Grafik & Analisa';
  ShowFrame;
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
  FBoMode := False;
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

procedure TMainForm.btnDemoClick(Sender: TObject);
begin
  if FSelected <> '' then
    ShowDemoForm(FIndex, DemoQuote, FSelected)
  else
    ShowDemoForm(FIndex, DemoQuote, 'BTCUSDT');
end;

function TMainForm.DemoQuote(const Sym: string; var Q: TDemoQuote): Boolean;
var
  Idx: Integer;
begin
  Idx := FindCoin(Sym);
  Result := Idx >= 0;
  if Result then
  begin
    Q.Price := FCoins[Idx].Price;
    Q.Chg := FCoins[Idx].Chg24;
    Q.High := FCoins[Idx].High24;
    Q.Low := FCoins[Idx].Low24;
    Q.Vol := FCoins[Idx].QuoteVol;
  end;
end;

procedure TMainForm.btnExnessClick(Sender: TObject);
begin
  if FSelected <> '' then
    ShowExnessForm(FIndex, DemoQuote, FSelected)
  else
    ShowExnessForm(FIndex, DemoQuote, 'XAUUSDT');
end;

procedure TMainForm.btnPersenClick(Sender: TObject);
begin
  FBoMode := False;
  FSortCol := 3;
  FSortDesc := True;
  RebuildView;
end;

procedure TMainForm.btnBOClick(Sender: TObject);
begin
  FBoMode := True;
  FSortCol := 16;
  FSortDesc := True;
  RebuildView;
end;

function TMainForm.TopVolumeCoins(N: Integer): TSymArr;
var
  I, J, K, P: Integer;
  Cand: array of Integer;
begin
  SetLength(Result, 0);
  N := Min(N, Length(FCoins));
  if N <= 0 then
    Exit;
  SetLength(Cand, N);
  K := 0;
  for I := 0 to High(FCoins) do
  begin
    J := K;   // posisi sisip pada daftar yang terurut volume turun
    while (J > 0) and (FCoins[Cand[J - 1]].QuoteVol < FCoins[I].QuoteVol) do
      Dec(J);
    if J >= N then
      Continue;
    if K < N then
      Inc(K);
    for P := K - 1 downto J + 1 do
      Cand[P] := Cand[P - 1];
    Cand[J] := I;
  end;
  SetLength(Result, K);
  for I := 0 to K - 1 do
    Result[I] := FCoins[Cand[I]].Symbol;
end;

{ koin terpilih (bila ada) + 30 koin volume terbesar }
procedure TMainForm.CandleSyms(var Syms: TSymArr);
var
  T: TSymArr;
  I, N: Integer;
begin
  T := TopVolumeCoins(30);
  SetLength(Syms, 0);
  if (FSelected <> '') and (FindCoin(FSelected) >= 0) then
  begin
    SetLength(Syms, 1);
    Syms[0] := FSelected;
  end;
  for I := 0 to High(T) do
    if T[I] <> FSelected then
    begin
      N := Length(Syms);
      SetLength(Syms, N + 1);
      Syms[N] := T[I];
    end;
end;

procedure TMainForm.btnCandleClick(Sender: TObject);
begin
  ShowCandleForm(CandleSyms);
end;

procedure TMainForm.btnSideClick(Sender: TObject);
begin
  if cbFilter.ItemIndex = 11 then
    cbFilter.ItemIndex := 0
  else
    cbFilter.ItemIndex := 11;
  FilterChange(nil);
end;

procedure TMainForm.SSClose(Sender: TObject; var Action: TCloseAction);
begin
  Action := caFree;
end;

{ Analisa SS: pilih screenshot grafik dari komputer, candle dibaca dari gambar }
procedure TMainForm.btnSSClick(Sender: TObject);
var
  Dlg: TOpenDialog;
  FileName, SHi, SLo, Info, Note: string;
  K: TKlines;
  A: TAnalysis;
  HiP, LoP: Double;
  Rel: Boolean;

  function ToNum(const S: string): Double;
  var
    Code: Integer;
  begin
    Val(StringReplace(StringReplace(Trim(S), ',', '', [rfReplaceAll]), ' ', '', [rfReplaceAll]), Result, Code);
    if Code <> 0 then
      Result := 0;
  end;

begin
  Dlg := TOpenDialog.Create(Self);
  try
    Dlg.Title := 'Pilih screenshot grafik candlestick';
    Dlg.Filter := 'Gambar grafik (*.png;*.jpg;*.jpeg;*.bmp)|*.png;*.jpg;*.jpeg;*.bmp|Semua file|*.*';
    Dlg.Options := [ofFileMustExist, ofPathMustExist, ofHideReadOnly];
    if not Dlg.Execute then
      Exit;
    FileName := Dlg.FileName;
  finally
    Dlg.Free;
  end;

  SHi := '';
  SLo := '';
  HiP := 0;
  LoP := 0;
  if InputQuery('Analisa SS', 'Harga TERTINGGI yang tampak di screenshot (puncak candle paling atas). Kosongkan bila tidak tahu:', SHi) then
    if InputQuery('Analisa SS', 'Harga TERENDAH yang tampak di screenshot (dasar candle paling bawah):', SLo) then
    begin
      HiP := ToNum(SHi);
      LoP := ToNum(SLo);
    end;
  Rel := (HiP <= LoP) or (LoP <= 0);
  if Rel then
  begin
    HiP := 0;
    LoP := 0;
  end;

  Screen.Cursor := crHourGlass;
  try
    if not ShotToKlines(FileName, HiP, LoP, K, Info) then
    begin
      Screen.Cursor := crDefault;
      Application.MessageBox(PChar(Info), 'Analisa SS', MB_OK or MB_ICONWARNING);
      Exit;
    end;
    A := Analyze('Screenshot', 'SS', K);
  finally
    Screen.Cursor := crDefault;
  end;
  if not A.Ok then
  begin
    Application.MessageBox(PChar(A.Err), 'Analisa SS', MB_OK or MB_ICONWARNING);
    Exit;
  end;
  Note := Info;
  if Rel then
    Note := Note + #13#10 + ' Harga tertinggi/terendah tidak diisi: harga ditampilkan sebagai indeks 0-100' + #13#10 +
      ' (0 = dasar candle terendah, 100 = puncak candle tertinggi).';
  if not A.MAValid[3] then
    Note := Note + #13#10 + Format(' MA99/MA200 hanya bisa dihitung bila gambar memuat >= 99/200 candle (terbaca %d).', [Length(K)])
  else if not A.MAValid[4] then
    Note := Note + #13#10 + Format(' MA200 butuh >= 200 candle di gambar (terbaca %d).', [Length(K)]);
  ShowSSReport(ExtractFileName(FileName), A, K, K[High(K)].C, Note, True);
end;

{ Laporan Analisa SS: status breakout/breakdown, posisi harga terhadap MA
  25/99/200, resisten & support, serta zona harga tempat pembelian paling
  banyak. Relative = True bila jumlah beli/jual hanya perkiraan dari gambar. }
procedure TMainForm.ShowSSReport(const Title: string; const A: TAnalysis; const K: TKlines;
  P: Double; const Note: string; Relative: Boolean);
const
  Bins = 24;
var
  F: TForm;
  M: TMemo;
  L: TStringList;
  Lo, Hi, Step, Buy, TotBuy: Double;
  BuyBin, SellBin: array[0..Bins - 1] of Double;
  I, B, Best, N, Score: Integer;

  function Amt(V: Double): string;
  begin
    if Relative then
    begin
      if TotBuy > 0 then Result := Format('%.1f%% dari beli', [V / TotBuy * 100])
      else Result := '-';
    end
    else
      Result := FmtUSD(V);
  end;

  function Pos2(Level: Double): string;
  begin
    if Level <= 0 then Result := '-'
    else Result := FmtPrice(Level) + ' ' + DistPct(Level, P);
  end;

  procedure MALine(const Nm: string; Idx2: Integer);
  begin
    if not A.MAValid[Idx2] then
      L.Add(Format(' %-8s: data belum cukup', [Nm]))
    else if P > A.MA[Idx2] then
    begin
      L.Add(Format(' %-8s: %s  -> harga DI ATAS (support) %s', [Nm, FmtPrice(A.MA[Idx2]), DistPct(A.MA[Idx2], P)]));
      Inc(Score);
    end
    else
    begin
      L.Add(Format(' %-8s: %s  -> harga DI BAWAH (resisten) %s', [Nm, FmtPrice(A.MA[Idx2]), DistPct(A.MA[Idx2], P)]));
      Dec(Score);
    end;
  end;

begin
  Score := 0;
  TotBuy := 0;

  L := TStringList.Create;
  try
    L.Add(Format(' ANALISA SS  %s   harga terakhir %s', [Title, FmtPrice(P)]));
    if Note <> '' then
      L.Add(' ' + Note);
    L.Add(' ------------------------------------------------------------');
    L.Add(' 1. BREAKOUT / BREAKDOWN (range 50 candle)');
    L.Add(Format('    Resisten range : %s   Support range : %s', [Pos2(A.RangeHigh), Pos2(A.RangeLow)]));
    if A.Breakout = '' then
      L.Add('    Status         : masih di dalam range (belum breakout/breakdown)')
    else
      L.Add('    Status         : ' + A.Breakout);
    if A.Breakout = 'BREAKOUT NAIK' then Inc(Score, 2)
    else if A.Breakout = 'MAU BREAKOUT' then Inc(Score)
    else if A.Breakout = 'BREAKDOWN' then Dec(Score, 2)
    else if A.Breakout = 'MAU BREAKDOWN' then Dec(Score);
    L.Add('');
    L.Add(' 2. MOVING AVERAGE');
    MALine('MA25', 1);
    MALine('MA99', 3);
    MALine('MA200', 4);
    L.Add('');
    L.Add(' 3. RESISTEN & SUPPORT');
    L.Add('    Resisten terdekat : ' + Pos2(A.SwingRes));
    L.Add('    Support terdekat  : ' + Pos2(A.SwingSup));
    if A.StrongSupHits > 0 then
      L.Add(Format('    Support terkuat   : %s (menahan %dx)', [Pos2(A.StrongSup), A.StrongSupHits]));
    if A.StrongResHits > 0 then
      L.Add(Format('    Resisten terkuat  : %s (menolak %dx)', [Pos2(A.StrongRes), A.StrongResHits]));
    L.Add('');

    { profil pembelian: taker buy per rentang harga, 200 candle terakhir }
    N := Min(200, Length(K));
    Lo := MaxDouble;
    Hi := 0;
    for I := Length(K) - N to High(K) do
    begin
      Lo := Min(Lo, K[I].L);
      Hi := Max(Hi, K[I].H);
    end;
    L.Add(Format(' 4. HARGA YANG PALING BANYAK DIBELI (%d candle terakhir)', [N]));
    if Hi > Lo then
    begin
      Step := (Hi - Lo) / Bins;
      FillChar(BuyBin, SizeOf(BuyBin), 0);
      FillChar(SellBin, SizeOf(SellBin), 0);
      for I := Length(K) - N to High(K) do
      begin
        B := Trunc(((K[I].H + K[I].L + K[I].C) / 3 - Lo) / Step);
        if B >= Bins then B := Bins - 1;
        if B < 0 then B := 0;
        BuyBin[B] := BuyBin[B] + K[I].TBQV;
        SellBin[B] := SellBin[B] + (K[I].QV - K[I].TBQV);
      end;
      for B := 0 to Bins - 1 do
        TotBuy := TotBuy + BuyBin[B];
      Best := 0;
      for B := 1 to Bins - 1 do
        if BuyBin[B] > BuyBin[Best] then
          Best := B;
      L.Add(Format('    Zona beli terbanyak : %s - %s  (%s dibeli, %s dijual)',
        [FmtPrice(Lo + Best * Step), FmtPrice(Lo + (Best + 1) * Step), Amt(BuyBin[Best]), Amt(SellBin[Best])]));
      Buy := Lo + (Best + 0.5) * Step;
      if P > Lo + (Best + 1) * Step then
      begin
        L.Add('    Harga di ATAS zona beli terbanyak -> zona itu jadi support');
        Inc(Score);
      end
      else if P < Lo + Best * Step then
      begin
        L.Add('    Harga di BAWAH zona beli terbanyak -> zona itu jadi resisten (pembeli lama tertahan rugi)');
        Dec(Score);
      end
      else
        L.Add('    Harga sedang di dalam zona beli terbanyak -> area keputusan');
      L.Add('    Jarak ke tengah zona : ' + DistPct(Buy, P));
      L.Add('    Sebaran pembelian (atas = harga tinggi):');
      for B := Bins - 1 downto 0 do
        if BuyBin[Best] > 0 then
          L.Add(Format('      %s %s %s', [Copy(FmtPrice(Lo + B * Step) + '            ', 1, 12),
            Bar(BuyBin[B] / BuyBin[Best] * 100, 24), Amt(BuyBin[B])]));
    end
    else
      L.Add('    data harga belum cukup');
    L.Add('');
    L.Add(' ------------------------------------------------------------');
    if Score >= 3 then
      L.Add(Format(' KESIMPULAN: CONDONG NAIK (skor %d)', [Score]))
    else if Score <= -3 then
      L.Add(Format(' KESIMPULAN: CONDONG TURUN (skor %d)', [Score]))
    else
      L.Add(Format(' KESIMPULAN: NETRAL / TUNGGU (skor %d)', [Score]));
    L.Add(' Catatan: berdasarkan indikator, bukan jaminan arah harga.');
    if Relative then
      L.Add(' Dibaca dari gambar: volume beli/jual hanya perkiraan dari warna & tinggi batang.');

    F := TForm.CreateNew(Self);
    F.Caption := 'Analisa SS - ' + Title;
    F.SetBounds(Left + 120, Top + 90, 700, 640);
    F.Color := clrBg;
    F.OnClose := SSClose;
    M := TMemo.Create(F);
    M.Parent := F;
    M.Align := alClient;
    M.ReadOnly := True;
    M.ScrollBars := ssVertical;
    M.Color := clrBg;
    M.Font.Name := 'Courier New';
    M.Font.Size := 10;
    M.Font.Color := clrText;
    M.BorderStyle := bsNone;
    M.Lines.Text := L.Text;
    F.Show;
  finally
    L.Free;
  end;
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

procedure TMainForm.SelectSymbol(const Sym: string; KeepSearch: Boolean);
var
  I: Integer;
begin
  SetSelected(Sym);
  cbFilter.ItemIndex := 0;
  if KeepSearch then
    edSearch.Text := Sym   { hasil pencarian tampil di tabel; klik barisnya akan mengosongkan lagi }
  else if edSearch.Text <> '' then
    edSearch.Text := '';
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
    Handled := BtcChartWheel(P, Delta) or DemoChartWheel(P, Delta) or
      ExnessChartWheel(P, Delta);
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
    if D.DepthOk then
    begin
      FDepthSym := A.Symbol;
      FDepthBid := D.BidUSD;
      FDepthAsk := D.AskUSD;
      FDepthWallPrice := D.AskWallPrice;
      FDepthWallUSD := D.AskWallUSD;
      FDepthBidWallPrice := D.BidWallPrice;
      FDepthBidWallUSD := D.BidWallUSD;
    end;
    UpdateCoinHeader;
    L.Add(Format(' %s   |   timeframe %s   |   %s', [A.Symbol, A.Interval, FormatDateTime('hh:nn:ss', Now)]));
    L.Add('');
    L.Add(Format(' SINYAL   : %s   (skor %d)', [SignalText(A.Signal), A.Score]));
    L.Add(' Trend MA : ' + A.Trend);
    if A.Reasons <> '' then
      L.Add(TrimRight(A.Reasons));
    L.Add('');

    S := PatternReport(FChartK);
    if S <> '' then
    begin
      L.Add(S);
      L.Add('');
    end;

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
