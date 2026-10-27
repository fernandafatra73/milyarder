unit uDemo;

{ Demo trading mirip Binance Futures: saldo virtual 10.000 USDT, harga real-time
  dari Binance, long/short, leverage, order Limit/Market, TP/SL, likuidasi.
  TIDAK ADA order sungguhan yang dikirim ke Binance. }

interface

uses
  Windows, Messages, SysUtils, Classes, Graphics, Controls, Forms, StdCtrls,
  ExtCtrls, ComCtrls, Dialogs, Math, uAnalysis, uBinance, uWorkers, uChart;

const
  WM_FT_BOOK = WM_USER + 209;

type
  TDemoQuote = record
    Price, Chg, High, Low, Vol: Double;
  end;
  TDemoQuoteFn = function(const Sym: string; var Q: TDemoQuote): Boolean of object;

  TDPos = record
    Sym: string;
    Dir: Integer;            // 1 long, -1 short
    Qty, Entry, Margin, TP, SL: Double;
    Lev: Integer;
    Opened: TDateTime;
  end;

  TDOrd = record
    Id: Integer;
    Sym: string;
    Dir: Integer;
    Price, Qty, TP, SL: Double;
    Lev: Integer;
    Time: TDateTime;
  end;

  THistRow = record
    T, Sym, Act, Price, Qty, Fee, Pnl: string;
  end;

  TBookData = class
  public
    Sym: string;
    BidP, BidQ, AskP, AskQ: TDoubleArray;
  end;

  TBookThread = class(TThread)
  private
    FWnd: HWND;
    FSym: string;
  protected
    procedure Execute; override;
  public
    constructor Create(AWnd: HWND; const Sym: string);
  end;

  TDemoForm = class(TForm)
  private
    pnlTop, pnlOrder, pnlBook, pnlCenter, pnlTF, pnlChart, pnlBottom, pnlTabs: TPanel;
    cbSym: TComboBox;
    lblLast, lblChg, lblStats, lblBadge, lblNote: TLabel;
    btnReset, btnDeposit: TPanel;
    FTFBtns: array[0..ChartTFCount - 1] of TPanel;
    pbChart, pbBook: TPaintBox;
    lblWallet, lblUnreal, lblMarginBal, lblAvail: TLabel;
    lblLev: TLabel;
    tbLev: TTrackBar;
    FLevBtns: array[0..5] of TPanel;
    tabLimit, tabMarket: TPanel;
    lblPriceCap: TLabel;
    edPrice, edAmount, edTP, edSL: TEdit;
    btnLast: TPanel;
    FPctBtns: array[0..3] of TPanel;
    lblInfo, lblMsg: TLabel;
    btnBuy, btnSell: TPanel;
    tabPos, tabOrd, tabHist: TPanel;
    btnCloseSel, btnCloseAll, btnCancelSel, btnTPSL: TPanel;
    lvPos, lvOrd, lvHist: TListView;
    tmrTick, tmrLive, tmrDetail: TTimer;

    FSymbols: TStrings;
    FQuoteFn: TDemoQuoteFn;
    FSym, FTF: string;
    FK: TKlines;
    FA: TAnalysis;
    FCV: TChartView;
    FHoverX: Integer;
    FLast, FPrevLast: Double;
    FReqId: Integer;
    FOlderBusy, FNoMoreHistory, FLiveBusy, FBookBusy: Boolean;
    FLiveStart, FBookStart: Cardinal;
    FBook: TBookData;
    FTick: Integer;

    FWallet: Double;
    FPos: array of TDPos;
    FOrd: array of TDOrd;
    FHist: array of THistRow;
    FNextId: Integer;
    FLev: Integer;
    FOrdType: Integer;       // 0 limit, 1 market
    FPriceTouched: Boolean;
    FUpdatingUI: Boolean;
    FTab: Integer;

    function MkLabel(AParent: TWinControl; X, Y, W, H: Integer; const Txt: string;
      Fg: TColor; Size: Integer; Bold: Boolean): TLabel;
    function MkBtn(AParent: TWinControl; X, Y, W, H: Integer; const Txt: string;
      Bg, Fg: TColor; Click: TNotifyEvent): TPanel;
    function MkEdit(AParent: TWinControl; X, Y, W, H: Integer): TEdit;
    function MkList(AParent: TWinControl; const Cols: array of string;
      const Widths: array of Integer): TListView;
    procedure BuildUI;
    procedure BuildTop;
    procedure TopResize(Sender: TObject);
    procedure BuildCenter;
    procedure BuildBook;
    procedure BuildOrder;
    procedure BuildBottom;

    function Mark(const Sym: string): Double;
    function FindPos(const Sym: string): Integer;
    function LiqPrice(const P: TDPos): Double;
    function UnrealOf(const P: TDPos; M: Double): Double;
    function TotalUnreal: Double;
    function UsedMargin: Double;
    function ReservedMargin: Double;
    function Available: Double;
    function CurPrice: Double;
    function NeedMargin(Dir: Integer; Qty, Price: Double; Lev: Integer): Double;
    procedure DeletePos(I: Integer);
    procedure DeleteOrd(I: Integer);
    procedure AddHist(const Sym, Act: string; Price, Qty, Fee, Pnl: Double);
    procedure Fill(const Sym: string; Dir: Integer; Qty, Price: Double; Lev: Integer;
      TP, SL: Double; Maker: Boolean);
    procedure ClosePos(I: Integer; Price: Double; const Why: string);
    procedure Liquidate(I: Integer);
    procedure PlaceOrder(Dir: Integer);
    procedure Say(const Txt: string; Ok: Boolean);

    procedure SaveState;
    procedure LoadState;
    procedure ResetAccount;

    procedure SwitchSym(const Sym: string);
    procedure RequestDetail;
    procedure RequestBook;
    procedure SetLev(L: Integer);
    procedure SetOrdType(T: Integer);
    procedure SetTab(T: Integer);
    procedure UpdateTFButtons;
    procedure UpdateTop;
    procedure UpdateAccount;
    procedure UpdatePreview;
    procedure RefreshLists;
    procedure LoadOlderIfNeeded;

    procedure Tick(Sender: TObject);
    procedure LiveTick(Sender: TObject);
    procedure DetailTick(Sender: TObject);
    procedure WMLive(var M: TMessage); message WM_FT_LIVE;
    procedure WMDetail(var M: TMessage); message WM_FT_DETAIL;
    procedure WMOlder(var M: TMessage); message WM_FT_OLDER;
    procedure WMBook(var M: TMessage); message WM_FT_BOOK;

    procedure DemoClose(Sender: TObject; var Action: TCloseAction);
    procedure cbSymSelect(Sender: TObject);
    procedure cbSymKeyDown(Sender: TObject; var Key: Word; Shift: TShiftState);
    procedure TFClick(Sender: TObject);
    procedure ChartPaint(Sender: TObject);
    procedure ChartMouseMove(Sender: TObject; Shift: TShiftState; X, Y: Integer);
    procedure ChartMouseDown(Sender: TObject; Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
    procedure ChartMouseUp(Sender: TObject; Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
    procedure ChartDblClick(Sender: TObject);
    procedure BookPaint(Sender: TObject);
    procedure LevChange(Sender: TObject);
    procedure LevBtnClick(Sender: TObject);
    procedure TypeClick(Sender: TObject);
    procedure LastClick(Sender: TObject);
    procedure PctClick(Sender: TObject);
    procedure PriceChange(Sender: TObject);
    procedure FieldChange(Sender: TObject);
    procedure BuyClick(Sender: TObject);
    procedure SellClick(Sender: TObject);
    procedure TabClick(Sender: TObject);
    procedure TPSLClick(Sender: TObject);
    procedure CloseSelClick(Sender: TObject);
    procedure CloseAllClick(Sender: TObject);
    procedure CancelSelClick(Sender: TObject);
    procedure ResetClick(Sender: TObject);
    procedure DepositClick(Sender: TObject);
    procedure lvPosDblClick(Sender: TObject);
    procedure lvPosCustomDrawSubItem(Sender: TCustomListView; Item: TListItem;
      SubItem: Integer; State: TCustomDrawState; var DefaultDraw: Boolean);
    procedure lvHistCustomDrawSubItem(Sender: TCustomListView; Item: TListItem;
      SubItem: Integer; State: TCustomDrawState; var DefaultDraw: Boolean);
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
  end;

procedure ShowDemoForm(Symbols: TStrings; QuoteFn: TDemoQuoteFn; const Sym: string);
function DemoChartWheel(P: TPoint; Delta: Integer): Boolean;

implementation

const
  StartBalance = 10000;
  FeeTaker = 0.0004;
  FeeMaker = 0.0002;
  MaintRate = 0.005;
  MinNotional = 5;
  BookRows = 12;
  SaveFile = 'demo_akun.txt';

  clrBuyBtn  = $0081CB0E;
  clrSellBtn = $005C3BFF;

var
  DemoForm: TDemoForm = nil;

{ ---------- util ---------- }

function ParseF(const S: string): Double;
var
  T: string;
begin
  T := Trim(S);
  if Pos('.', T) > 0 then
    T := StringReplace(T, ',', '', [rfReplaceAll])
  else
    T := StringReplace(T, ',', '.', [rfReplaceAll]);
  Result := StrToFloatDef(T, 0);
end;

function PlainNum(P: Double): string;
var
  Dec: Integer;
begin
  if P >= 1000 then Dec := 2
  else if P >= 10 then Dec := 3
  else if P >= 1 then Dec := 4
  else if P >= 0.01 then Dec := 5
  else Dec := 7;
  Result := Format('%.*f', [Dec, P]);
end;

function FmtQty(Q: Double): string;
begin
  if Q >= 1000 then Result := FormatFloat('#,##0', Q)
  else if Q >= 1 then Result := Format('%.3f', [Q])
  else Result := Format('%.5f', [Q]);
end;

function FmtMoney(V: Double): string;
begin
  Result := FormatFloat('#,##0.00', V);
end;

function FmtSigned(V: Double): string;
begin
  if V >= 0 then
    Result := '+' + FormatFloat('#,##0.00', V)
  else
    Result := '-' + FormatFloat('#,##0.00', Abs(V));
end;

function SplitBar(const S: string): TStringList;
var
  P: Integer;
  T: string;
begin
  Result := TStringList.Create;
  T := S;
  P := Pos('|', T);
  while P > 0 do
  begin
    Result.Add(Copy(T, 1, P - 1));
    T := Copy(T, P + 1, MaxInt);
    P := Pos('|', T);
  end;
  Result.Add(T);
end;

function IfThenS(C: Boolean; const A, B: string): string;
begin
  if C then Result := A else Result := B;
end;

function DirText(Dir: Integer): string;
begin
  if Dir > 0 then Result := 'Long' else Result := 'Short';
end;

procedure SetItem(Item: TListItem; const Cols: array of string);
var
  I: Integer;
begin
  if Item.Caption <> Cols[0] then
    Item.Caption := Cols[0];
  while Item.SubItems.Count < High(Cols) do
    Item.SubItems.Add('');
  for I := 1 to High(Cols) do
    if Item.SubItems[I - 1] <> Cols[I] then
      Item.SubItems[I - 1] := Cols[I];
end;

{ ---------- thread order book ---------- }

constructor TBookThread.Create(AWnd: HWND; const Sym: string);
begin
  FWnd := AWnd;
  FSym := Sym;
  FreeOnTerminate := True;
  inherited Create(False);
end;

procedure TBookThread.Execute;
var
  D: TBookData;
begin
  D := TBookData.Create;
  D.Sym := FSym;
  try
    EnsureSource;
    if not GetDepthLevels(FSym, 20, D.BidP, D.BidQ, D.AskP, D.AskQ) then
    begin
      SetLength(D.BidP, 0);
      SetLength(D.AskP, 0);
    end;
  except
    SetLength(D.BidP, 0);
    SetLength(D.AskP, 0);
  end;
  PostObj(FWnd, WM_FT_BOOK, D);
end;

{ ---------- pembuatan UI ---------- }

procedure ShowDemoForm(Symbols: TStrings; QuoteFn: TDemoQuoteFn; const Sym: string);
begin
  if DemoForm = nil then
  begin
    DemoForm := TDemoForm.Create(Application);
    DemoForm.FSymbols := Symbols;
    DemoForm.FQuoteFn := QuoteFn;
    DemoForm.cbSym.Items.Assign(Symbols);
    DemoForm.SwitchSym(Sym);
  end
  else if (Sym <> '') and (Sym <> DemoForm.FSym) then
    DemoForm.SwitchSym(Sym);
  DemoForm.Show;
  if DemoForm.WindowState = wsMinimized then
    DemoForm.WindowState := wsNormal;
  DemoForm.BringToFront;
end;

function DemoChartWheel(P: TPoint; Delta: Integer): Boolean;
begin
  Result := (DemoForm <> nil) and DemoForm.Visible and
    (WindowFromPoint(P) = DemoForm.pnlChart.Handle);
  if Result then
  begin
    ViewZoom(DemoForm.FCV, Delta);
    DemoForm.pbChart.Invalidate;
    DemoForm.LoadOlderIfNeeded;
  end;
end;

function TDemoForm.MkLabel(AParent: TWinControl; X, Y, W, H: Integer; const Txt: string;
  Fg: TColor; Size: Integer; Bold: Boolean): TLabel;
begin
  Result := TLabel.Create(Self);
  Result.Parent := AParent;
  Result.AutoSize := False;
  Result.SetBounds(X, Y, W, H);
  Result.Caption := Txt;
  Result.Font.Color := Fg;
  Result.Font.Size := Size;
  if Bold then
    Result.Font.Style := [fsBold];
  Result.Transparent := True;
end;

function TDemoForm.MkBtn(AParent: TWinControl; X, Y, W, H: Integer; const Txt: string;
  Bg, Fg: TColor; Click: TNotifyEvent): TPanel;
begin
  Result := TPanel.Create(Self);
  Result.Parent := AParent;
  Result.SetBounds(X, Y, W, H);
  Result.BevelOuter := bvNone;
  Result.Color := Bg;
  Result.Font.Color := Fg;
  Result.Font.Style := [fsBold];
  Result.Font.Size := 9;
  Result.Caption := Txt;
  Result.Cursor := crHandPoint;
  Result.OnClick := Click;
end;

function TDemoForm.MkEdit(AParent: TWinControl; X, Y, W, H: Integer): TEdit;
begin
  Result := TEdit.Create(Self);
  Result.Parent := AParent;
  Result.AutoSize := False;
  Result.SetBounds(X, Y, W, H);
  Result.Color := clrPanel2;
  Result.Font.Color := clrText;
  Result.Font.Size := 10;
  Result.Font.Style := [fsBold];
  Result.BorderStyle := bsSingle;
  Result.OnChange := FieldChange;
end;

function TDemoForm.MkList(AParent: TWinControl; const Cols: array of string;
  const Widths: array of Integer): TListView;
var
  I: Integer;
  C: TListColumn;
begin
  Result := TListView.Create(Self);
  Result.Parent := AParent;
  Result.Align := alClient;
  Result.ViewStyle := vsReport;
  Result.ReadOnly := True;
  Result.RowSelect := True;
  Result.HideSelection := False;
  Result.BorderStyle := bsNone;
  Result.Color := clrBg;
  Result.Font.Color := clrText;
  Result.Font.Name := 'Consolas';
  Result.Font.Size := 9;
  for I := 0 to High(Cols) do
  begin
    C := Result.Columns.Add;
    C.Caption := Cols[I];
    C.Width := Widths[I];
  end;
end;

constructor TDemoForm.Create(AOwner: TComponent);
begin
  inherited CreateNew(AOwner);
  Caption := 'Fernanda Taker - DEMO Futures (uang virtual)';
  Width := 1500;
  Height := 900;
  Constraints.MinWidth := 1100;
  Constraints.MinHeight := 760;
  Position := poScreenCenter;
  Color := clrBg;
  Font.Name := 'Segoe UI';
  Font.Size := 9;
  Font.Color := clrText;
  OnClose := DemoClose;
  FHoverX := -1;
  FTF := ChartTFApi[3];   // 15m seperti kebiasaan trading futures
  FLev := 20;
  FNextId := 1;
  FWallet := StartBalance;
  BuildUI;
  LoadState;

  tmrTick := TTimer.Create(Self);
  tmrTick.Interval := 1000;
  tmrTick.OnTimer := Tick;
  tmrLive := TTimer.Create(Self);
  tmrLive.Interval := 1000;
  tmrLive.OnTimer := LiveTick;
  tmrDetail := TTimer.Create(Self);
  tmrDetail.Interval := 30000;
  tmrDetail.OnTimer := DetailTick;
end;

destructor TDemoForm.Destroy;
begin
  SaveState;
  FBook.Free;
  inherited;
end;

procedure TDemoForm.BuildUI;
begin
  BuildTop;
  BuildOrder;
  BuildBook;
  BuildCenter;
  BuildBottom;
  SetLev(FLev);
  SetOrdType(0);
  SetTab(0);
end;

procedure TDemoForm.BuildTop;
begin
  pnlTop := TPanel.Create(Self);
  pnlTop.Parent := Self;
  pnlTop.Align := alTop;
  pnlTop.Height := 64;
  pnlTop.BevelOuter := bvNone;
  pnlTop.Color := clrPanel;

  cbSym := TComboBox.Create(Self);
  cbSym.Parent := pnlTop;
  cbSym.Style := csDropDown;
  cbSym.SetBounds(14, 16, 190, 30);
  cbSym.Color := clrPanel2;
  cbSym.Font.Color := clrText;
  cbSym.Font.Size := 13;
  cbSym.Font.Style := [fsBold];
  cbSym.DropDownCount := 20;
  cbSym.OnSelect := cbSymSelect;
  cbSym.OnKeyDown := cbSymKeyDown;

  MkLabel(pnlTop, 214, 22, 70, 20, 'Perpetual', clrDim, 9, False);
  lblLast := MkLabel(pnlTop, 290, 12, 190, 38, '-', clrUp, 22, True);
  lblChg := MkLabel(pnlTop, 490, 14, 150, 20, '', clrUp, 11, True);
  lblStats := MkLabel(pnlTop, 490, 36, 560, 18, '', clrDim, 9, False);

  lblBadge := MkLabel(pnlTop, 1060, 10, 190, 20, 'MODE DEMO', clrBg, 11, True);
  lblBadge.Transparent := False;
  lblBadge.Color := clrGold;
  lblBadge.Alignment := taCenter;
  lblNote := MkLabel(pnlTop, 1060, 34, 230, 18, 'Uang virtual - tanpa order sungguhan', clrDim, 8, False);
  btnReset := MkBtn(pnlTop, 1300, 14, 170, 34, 'Reset Akun (10.000)', clrPanel2, clrGold, ResetClick);
  OnResize := TopResize;
  TopResize(nil);
end;

procedure TDemoForm.TopResize(Sender: TObject);
begin
  if btnReset = nil then
    Exit;
  btnReset.Left := pnlTop.Width - btnReset.Width - 14;
  lblBadge.Left := btnReset.Left - lblBadge.Width - 16;
  lblNote.Left := lblBadge.Left;
end;

procedure TDemoForm.BuildCenter;
var
  I: Integer;
begin
  pnlCenter := TPanel.Create(Self);
  pnlCenter.Parent := Self;
  pnlCenter.Align := alClient;
  pnlCenter.BevelOuter := bvNone;
  pnlCenter.Color := clrBg;

  pnlTF := TPanel.Create(Self);
  pnlTF.Parent := pnlCenter;
  pnlTF.Align := alTop;
  pnlTF.Height := 34;
  pnlTF.BevelOuter := bvNone;
  pnlTF.Color := clrPanel;
  MkLabel(pnlTF, 10, 9, 70, 18, 'Time frame', clrDim, 9, False);
  for I := 0 to ChartTFCount - 1 do
  begin
    FTFBtns[I] := MkBtn(pnlTF, 84 + I * 56, 5, 52, 24, ChartTFLabels[I], clrPanel2, clrDim, TFClick);
    FTFBtns[I].Tag := I;
  end;
  UpdateTFButtons;

  pnlBottom := TPanel.Create(Self);
  pnlBottom.Parent := pnlCenter;
  pnlBottom.Align := alBottom;
  pnlBottom.Height := 250;
  pnlBottom.BevelOuter := bvNone;
  pnlBottom.Color := clrBg;

  with TSplitter.Create(Self) do
  begin
    Parent := pnlCenter;
    Align := alBottom;
    Top := pnlBottom.Top - 1;
    Height := 5;
    Color := clrPanel2;
  end;

  pnlChart := TPanel.Create(Self);
  pnlChart.Parent := pnlCenter;
  pnlChart.Align := alClient;
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
end;

procedure TDemoForm.BuildBook;
begin
  pnlBook := TPanel.Create(Self);
  pnlBook.Parent := Self;
  pnlBook.Align := alRight;
  pnlBook.Width := 250;
  pnlBook.BevelOuter := bvNone;
  pnlBook.Color := clrPanel;
  MkLabel(pnlBook, 10, 8, 200, 20, 'Order Book', clrText, 10, True);
  MkLabel(pnlBook, 10, 30, 80, 16, 'Harga', clrDim, 8, False);
  MkLabel(pnlBook, 90, 30, 70, 16, 'Jumlah', clrDim, 8, False).Alignment := taRightJustify;
  MkLabel(pnlBook, 160, 30, 80, 16, 'Total', clrDim, 8, False).Alignment := taRightJustify;
  pbBook := TPaintBox.Create(Self);
  pbBook.Parent := pnlBook;
  pbBook.Align := alNone;
  pbBook.SetBounds(0, 48, 250, 500);
  pbBook.Anchors := [akLeft, akTop, akRight, akBottom];
  pbBook.OnPaint := BookPaint;
end;

procedure TDemoForm.BuildOrder;
var
  I: Integer;
const
  Levs: array[0..5] of Integer = (5, 10, 20, 50, 100, 125);
  Pcts: array[0..3] of Integer = (25, 50, 75, 100);
begin
  pnlOrder := TPanel.Create(Self);
  pnlOrder.Parent := Self;
  pnlOrder.Align := alRight;
  pnlOrder.Width := 344;
  pnlOrder.BevelOuter := bvNone;
  pnlOrder.Color := clrPanel;

  { akun }
  MkLabel(pnlOrder, 14, 8, 200, 18, 'AKUN DEMO (USDT)', clrGold, 9, True);
  btnDeposit := MkBtn(pnlOrder, 226, 4, 104, 22, '+ Tambah Saldo', clrGold, clrBg, DepositClick);
  btnDeposit.Font.Size := 8;
  MkLabel(pnlOrder, 14, 30, 150, 18, 'Saldo Wallet', clrDim, 9, False);
  lblWallet := MkLabel(pnlOrder, 164, 30, 166, 18, '', clrText, 9, True);
  lblWallet.Alignment := taRightJustify;
  MkLabel(pnlOrder, 14, 50, 150, 18, 'PnL Belum Realisasi', clrDim, 9, False);
  lblUnreal := MkLabel(pnlOrder, 164, 50, 166, 18, '', clrText, 9, True);
  lblUnreal.Alignment := taRightJustify;
  MkLabel(pnlOrder, 14, 70, 150, 18, 'Margin Balance', clrDim, 9, False);
  lblMarginBal := MkLabel(pnlOrder, 164, 70, 166, 18, '', clrText, 9, True);
  lblMarginBal.Alignment := taRightJustify;
  MkLabel(pnlOrder, 14, 90, 150, 18, 'Tersedia', clrDim, 9, False);
  lblAvail := MkLabel(pnlOrder, 164, 90, 166, 18, '', clrText, 9, True);
  lblAvail.Alignment := taRightJustify;
  with TPanel.Create(Self) do
  begin
    Parent := pnlOrder;
    SetBounds(14, 116, 316, 1);
    BevelOuter := bvNone;
    Color := clrBorder;
  end;

  { leverage }
  MkLabel(pnlOrder, 14, 126, 150, 18, 'Isolated  |  Perpetual', clrDim, 9, False);
  lblLev := MkLabel(pnlOrder, 164, 124, 166, 22, '', clrGold, 12, True);
  lblLev.Alignment := taRightJustify;
  tbLev := TTrackBar.Create(Self);
  tbLev.Parent := pnlOrder;
  tbLev.SetBounds(10, 148, 324, 30);
  tbLev.Min := 1;
  tbLev.Max := 125;
  tbLev.Position := FLev;
  tbLev.TickStyle := tsNone;
  tbLev.ThumbLength := 16;
  tbLev.OnChange := LevChange;
  for I := 0 to 5 do
  begin
    FLevBtns[I] := MkBtn(pnlOrder, 14 + I * 53, 182, 49, 24, IntToStr(Levs[I]) + 'x', clrPanel2, clrDim, LevBtnClick);
    FLevBtns[I].Tag := Levs[I];
  end;

  { tipe order }
  tabLimit := MkBtn(pnlOrder, 14, 216, 155, 28, 'Limit', clrPanel2, clrGold, TypeClick);
  tabLimit.Tag := 0;
  tabMarket := MkBtn(pnlOrder, 175, 216, 155, 28, 'Market', clrPanel2, clrDim, TypeClick);
  tabMarket.Tag := 1;

  lblPriceCap := MkLabel(pnlOrder, 14, 252, 200, 16, 'Harga (USDT)', clrDim, 8, False);
  edPrice := MkEdit(pnlOrder, 14, 270, 256, 28);
  edPrice.OnChange := PriceChange;
  btnLast := MkBtn(pnlOrder, 276, 270, 54, 28, 'Last', clrPanel2, clrGold, LastClick);

  MkLabel(pnlOrder, 14, 304, 200, 16, 'Jumlah (USDT, nilai posisi)', clrDim, 8, False);
  edAmount := MkEdit(pnlOrder, 14, 322, 316, 28);
  for I := 0 to 3 do
  begin
    FPctBtns[I] := MkBtn(pnlOrder, 14 + I * 80, 356, 74, 24, IntToStr(Pcts[I]) + '%', clrPanel2, clrDim, PctClick);
    FPctBtns[I].Tag := Pcts[I];
  end;

  MkLabel(pnlOrder, 14, 390, 150, 16, 'Take Profit (opsional)', clrDim, 8, False);
  MkLabel(pnlOrder, 176, 390, 150, 16, 'Stop Loss (opsional)', clrDim, 8, False);
  edTP := MkEdit(pnlOrder, 14, 408, 154, 28);
  edSL := MkEdit(pnlOrder, 176, 408, 154, 28);

  lblInfo := MkLabel(pnlOrder, 14, 444, 316, 74, '', clrDim, 9, False);
  lblInfo.WordWrap := True;

  btnBuy := MkBtn(pnlOrder, 14, 524, 155, 46, 'Beli / Long', clrBuyBtn, clrBg, BuyClick);
  btnBuy.Font.Size := 11;
  btnSell := MkBtn(pnlOrder, 175, 524, 155, 46, 'Jual / Short', clrSellBtn, clrText, SellClick);
  btnSell.Font.Size := 11;

  lblMsg := MkLabel(pnlOrder, 14, 578, 316, 44, '', clrDim, 9, False);
  lblMsg.WordWrap := True;
end;

procedure TDemoForm.BuildBottom;
begin
  pnlTabs := TPanel.Create(Self);
  pnlTabs.Parent := pnlBottom;
  pnlTabs.Align := alTop;
  pnlTabs.Height := 32;
  pnlTabs.BevelOuter := bvNone;
  pnlTabs.Color := clrPanel;
  tabPos := MkBtn(pnlTabs, 6, 4, 130, 24, 'Posisi (0)', clrPanel2, clrGold, TabClick);
  tabPos.Tag := 0;
  tabOrd := MkBtn(pnlTabs, 142, 4, 150, 24, 'Order Terbuka (0)', clrPanel2, clrDim, TabClick);
  tabOrd.Tag := 1;
  tabHist := MkBtn(pnlTabs, 298, 4, 130, 24, 'Riwayat Trade', clrPanel2, clrDim, TabClick);
  tabHist.Tag := 2;
  btnTPSL := MkBtn(pnlTabs, 450, 4, 150, 24, 'Atur TP / SL', clrGold, clrBg, TPSLClick);
  btnCloseSel := MkBtn(pnlTabs, 606, 4, 130, 24, 'Tutup Terpilih', clrPanel2, clrText, CloseSelClick);
  btnCloseAll := MkBtn(pnlTabs, 742, 4, 120, 24, 'Tutup Semua', clrPanel2, clrDown, CloseAllClick);
  btnCancelSel := MkBtn(pnlTabs, 450, 4, 130, 24, 'Batalkan Order', clrPanel2, clrText, CancelSelClick);

  lvPos := MkList(pnlBottom, ['Simbol', 'Ukuran', 'Harga Masuk', 'Harga Mark', 'Harga Likuidasi',
    'Margin', 'PnL (ROE%)', 'TP / SL'], [170, 110, 105, 105, 115, 95, 170, 160]);
  lvPos.OnDblClick := lvPosDblClick;
  lvPos.OnCustomDrawSubItem := lvPosCustomDrawSubItem;
  lvOrd := MkList(pnlBottom, ['Waktu', 'Simbol', 'Tipe', 'Harga', 'Jumlah', 'Leverage', 'TP / SL'],
    [130, 120, 150, 110, 110, 90, 160]);
  lvHist := MkList(pnlBottom, ['Waktu', 'Simbol', 'Aksi', 'Harga', 'Jumlah', 'Fee', 'PnL Realisasi'],
    [130, 120, 190, 110, 110, 90, 130]);
  lvHist.OnCustomDrawSubItem := lvHistCustomDrawSubItem;
end;

{ ---------- harga & akun ---------- }

function TDemoForm.Mark(const Sym: string): Double;
var
  Q: TDemoQuote;
begin
  Result := 0;
  if (Sym = FSym) and (FLast > 0) then
    Result := FLast
  else if Assigned(FQuoteFn) and FQuoteFn(Sym, Q) then
    Result := Q.Price;
end;

function TDemoForm.CurPrice: Double;
begin
  Result := Mark(FSym);
end;

function TDemoForm.FindPos(const Sym: string): Integer;
var
  I: Integer;
begin
  Result := -1;
  for I := 0 to High(FPos) do
    if FPos[I].Sym = Sym then
    begin
      Result := I;
      Exit;
    end;
end;

function TDemoForm.LiqPrice(const P: TDPos): Double;
begin
  if P.Dir > 0 then
    Result := P.Entry * (1 - 1 / P.Lev + MaintRate)
  else
    Result := P.Entry * (1 + 1 / P.Lev - MaintRate);
  if Result < 0 then
    Result := 0;
end;

function TDemoForm.UnrealOf(const P: TDPos; M: Double): Double;
begin
  Result := (M - P.Entry) * P.Qty * P.Dir;
end;

function TDemoForm.TotalUnreal: Double;
var
  I: Integer;
  M: Double;
begin
  Result := 0;
  for I := 0 to High(FPos) do
  begin
    M := Mark(FPos[I].Sym);
    if M > 0 then
      Result := Result + UnrealOf(FPos[I], M);
  end;
end;

function TDemoForm.UsedMargin: Double;
var
  I: Integer;
begin
  Result := 0;
  for I := 0 to High(FPos) do
    Result := Result + FPos[I].Margin;
end;

function TDemoForm.ReservedMargin: Double;
var
  I: Integer;
begin
  Result := 0;
  for I := 0 to High(FOrd) do
    Result := Result + FOrd[I].Qty * FOrd[I].Price / FOrd[I].Lev;
end;

function TDemoForm.Available: Double;
begin
  Result := FWallet - UsedMargin - ReservedMargin;
  if Result < 0 then
    Result := 0;
end;

{ margin tambahan yang dibutuhkan; menutup posisi lawan tidak butuh margin }
function TDemoForm.NeedMargin(Dir: Integer; Qty, Price: Double; Lev: Integer): Double;
var
  PI: Integer;
  Extra: Double;
begin
  Extra := Qty;
  PI := FindPos(FSym);
  if (PI >= 0) and (FPos[PI].Dir <> Dir) then
    Extra := Max(0, Qty - FPos[PI].Qty);
  Result := Extra * Price / Lev + Qty * Price * FeeTaker;
end;

procedure TDemoForm.DeletePos(I: Integer);
var
  J: Integer;
begin
  for J := I to High(FPos) - 1 do
    FPos[J] := FPos[J + 1];
  SetLength(FPos, Length(FPos) - 1);
end;

procedure TDemoForm.DeleteOrd(I: Integer);
var
  J: Integer;
begin
  for J := I to High(FOrd) - 1 do
    FOrd[J] := FOrd[J + 1];
  SetLength(FOrd, Length(FOrd) - 1);
end;

procedure TDemoForm.AddHist(const Sym, Act: string; Price, Qty, Fee, Pnl: Double);
var
  J, N: Integer;
begin
  N := Length(FHist);
  if N >= 300 then
    N := 299
  else
    SetLength(FHist, N + 1);
  for J := N downto 1 do
    FHist[J] := FHist[J - 1];
  FHist[0].T := FormatDateTime('dd/mm hh:nn:ss', Now);
  FHist[0].Sym := Sym;
  FHist[0].Act := Act;
  FHist[0].Price := PlainNum(Price);
  FHist[0].Qty := FmtQty(Qty);
  FHist[0].Fee := Format('%.4f', [Fee]);
  if Pnl = 0 then
    FHist[0].Pnl := '-'
  else
    FHist[0].Pnl := FmtSigned(Pnl);
end;

procedure TDemoForm.Fill(const Sym: string; Dir: Integer; Qty, Price: Double; Lev: Integer;
  TP, SL: Double; Maker: Boolean);
var
  PI: Integer;
  Rate, Fee, CloseQty, Pnl, Rem, NewQty: Double;
  Act: string;
begin
  if Maker then Rate := FeeMaker else Rate := FeeTaker;
  PI := FindPos(Sym);
  Rem := Qty;
  if (PI >= 0) and (FPos[PI].Dir <> Dir) then
  begin
    CloseQty := Min(Rem, FPos[PI].Qty);
    Pnl := (Price - FPos[PI].Entry) * CloseQty * FPos[PI].Dir;
    Fee := CloseQty * Price * Rate;
    FWallet := FWallet + Pnl - Fee;
    AddHist(Sym, 'Tutup ' + DirText(FPos[PI].Dir), Price, CloseQty, Fee, Pnl - Fee);
    FPos[PI].Margin := FPos[PI].Margin * (1 - CloseQty / FPos[PI].Qty);
    FPos[PI].Qty := FPos[PI].Qty - CloseQty;
    Rem := Rem - CloseQty;
    if FPos[PI].Qty < 1E-12 then
    begin
      DeletePos(PI);
      PI := -1;
    end;
  end;
  if Rem > 1E-12 then
  begin
    Fee := Rem * Price * Rate;
    FWallet := FWallet - Fee;
    if PI < 0 then
    begin
      SetLength(FPos, Length(FPos) + 1);
      PI := High(FPos);
      FPos[PI].Sym := Sym;
      FPos[PI].Dir := Dir;
      FPos[PI].Qty := Rem;
      FPos[PI].Entry := Price;
      FPos[PI].Lev := Lev;
      FPos[PI].Margin := Rem * Price / Lev;
      FPos[PI].TP := 0;
      FPos[PI].SL := 0;
      FPos[PI].Opened := Now;
    end
    else
    begin
      NewQty := FPos[PI].Qty + Rem;
      FPos[PI].Entry := (FPos[PI].Entry * FPos[PI].Qty + Price * Rem) / NewQty;
      FPos[PI].Qty := NewQty;
      FPos[PI].Lev := Lev;
      FPos[PI].Margin := NewQty * FPos[PI].Entry / Lev;
    end;
    if Dir > 0 then Act := 'Buka Long' else Act := 'Buka Short';
    AddHist(Sym, Act, Price, Rem, Fee, -Fee);
  end;
  if PI >= 0 then
  begin
    if TP > 0 then FPos[PI].TP := TP;
    if SL > 0 then FPos[PI].SL := SL;
  end;
end;

procedure TDemoForm.ClosePos(I: Integer; Price: Double; const Why: string);
var
  P: TDPos;
  Pnl, Fee: Double;
begin
  P := FPos[I];
  Pnl := (Price - P.Entry) * P.Qty * P.Dir;
  Fee := P.Qty * Price * FeeTaker;
  FWallet := FWallet + Pnl - Fee;
  AddHist(P.Sym, Why + ' ' + DirText(P.Dir), Price, P.Qty, Fee, Pnl - Fee);
  DeletePos(I);
end;

procedure TDemoForm.Liquidate(I: Integer);
var
  P: TDPos;
begin
  P := FPos[I];
  FWallet := FWallet - P.Margin;
  AddHist(P.Sym, 'LIKUIDASI ' + DirText(P.Dir), LiqPrice(P), P.Qty, 0, -P.Margin);
  DeletePos(I);
  Say('POSISI ' + P.Sym + ' ' + DirText(P.Dir) + ' TERLIKUIDASI. Margin ' +
    FmtMoney(P.Margin) + ' USDT hilang.', False);
end;

procedure TDemoForm.Say(const Txt: string; Ok: Boolean);
begin
  lblMsg.Caption := Txt;
  if Ok then lblMsg.Font.Color := clrUp else lblMsg.Font.Color := clrDown;
end;

procedure TDemoForm.PlaceOrder(Dir: Integer);
var
  Notional, Price, Last, Qty, Need, TP, SL: Double;
  Id: Integer;
begin
  Last := CurPrice;
  if Last <= 0 then
  begin
    Say('Harga belum tersedia, tunggu sebentar.', False);
    Exit;
  end;
  Notional := ParseF(edAmount.Text);
  if Notional < MinNotional then
  begin
    Say(Format('Nilai order minimal %d USDT.', [MinNotional]), False);
    Exit;
  end;
  if FOrdType = 0 then
  begin
    Price := ParseF(edPrice.Text);
    if Price <= 0 then
    begin
      Say('Isi harga limit.', False);
      Exit;
    end;
  end
  else
    Price := Last;
  Qty := Notional / Price;
  TP := ParseF(edTP.Text);
  SL := ParseF(edSL.Text);
  if Dir > 0 then
  begin
    if ((TP > 0) and (TP <= Price)) or ((SL > 0) and (SL >= Price)) then
    begin
      Say('Long: Take Profit harus di atas harga dan Stop Loss di bawah harga.', False);
      Exit;
    end;
  end
  else if ((TP > 0) and (TP >= Price)) or ((SL > 0) and (SL <= Price)) then
  begin
    Say('Short: Take Profit harus di bawah harga dan Stop Loss di atas harga.', False);
    Exit;
  end;
  Need := NeedMargin(Dir, Qty, Price, FLev);
  if Need > Available then
  begin
    Say(Format('Saldo tidak cukup. Butuh %s USDT, tersedia %s USDT.',
      [FmtMoney(Need), FmtMoney(Available)]), False);
    Exit;
  end;

  if (FOrdType = 1) or ((Dir > 0) and (Price >= Last)) or ((Dir < 0) and (Price <= Last)) then
  begin
    { eksekusi langsung di harga pasar }
    Qty := Notional / Last;
    Fill(FSym, Dir, Qty, Last, FLev, TP, SL, False);
    Say(Format('%s %s %s @ %s terisi.', [DirText(Dir), FSym, FmtQty(Qty), PlainNum(Last)]), True);
  end
  else
  begin
    Id := FNextId;
    Inc(FNextId);
    SetLength(FOrd, Length(FOrd) + 1);
    FOrd[High(FOrd)].Id := Id;
    FOrd[High(FOrd)].Sym := FSym;
    FOrd[High(FOrd)].Dir := Dir;
    FOrd[High(FOrd)].Price := Price;
    FOrd[High(FOrd)].Qty := Qty;
    FOrd[High(FOrd)].TP := TP;
    FOrd[High(FOrd)].SL := SL;
    FOrd[High(FOrd)].Lev := FLev;
    FOrd[High(FOrd)].Time := Now;
    Say(Format('Order limit %s %s @ %s dipasang.', [DirText(Dir), FSym, PlainNum(Price)]), True);
  end;
  SaveState;
  UpdateAccount;
  RefreshLists;
end;

{ ---------- simpan / muat ---------- }

procedure TDemoForm.SaveState;
var
  L: TStringList;
  I: Integer;
begin
  L := TStringList.Create;
  try
    L.Add('W|' + FloatToStr(FWallet) + '|' + IntToStr(FNextId) + '|' + IntToStr(FLev));
    for I := 0 to High(FPos) do
      with FPos[I] do
        L.Add(Format('P|%s|%d|%s|%s|%s|%s|%s|%d|%s',
          [Sym, Dir, FloatToStr(Qty), FloatToStr(Entry), FloatToStr(Margin),
           FloatToStr(TP), FloatToStr(SL), Lev, FloatToStr(Opened)]));
    for I := 0 to High(FOrd) do
      with FOrd[I] do
        L.Add(Format('O|%d|%s|%d|%s|%s|%s|%s|%d|%s',
          [Id, Sym, Dir, FloatToStr(Price), FloatToStr(Qty), FloatToStr(TP),
           FloatToStr(SL), Lev, FloatToStr(Time)]));
    for I := High(FHist) downto 0 do
      with FHist[I] do
        L.Add('H|' + T + '|' + Sym + '|' + Act + '|' + Price + '|' + Qty + '|' + Fee + '|' + Pnl);
    try
      L.SaveToFile(ExtractFilePath(ParamStr(0)) + SaveFile);
    except
    end;
  finally
    L.Free;
  end;
end;

procedure TDemoForm.LoadState;
var
  L, F: TStringList;
  I, N: Integer;
  FN: string;
begin
  FN := ExtractFilePath(ParamStr(0)) + SaveFile;
  if not FileExists(FN) then
    Exit;
  L := TStringList.Create;
  try
    try
      L.LoadFromFile(FN);
    except
      Exit;
    end;
    for I := 0 to L.Count - 1 do
    begin
      F := SplitBar(L[I]);
      try
        if (F[0] = 'W') and (F.Count >= 4) then
        begin
          FWallet := StrToFloatDef(F[1], StartBalance);
          FNextId := StrToIntDef(F[2], 1);
          FLev := StrToIntDef(F[3], 20);
        end
        else if (F[0] = 'P') and (F.Count >= 10) then
        begin
          N := Length(FPos);
          SetLength(FPos, N + 1);
          FPos[N].Sym := F[1];
          FPos[N].Dir := StrToIntDef(F[2], 1);
          FPos[N].Qty := StrToFloatDef(F[3], 0);
          FPos[N].Entry := StrToFloatDef(F[4], 0);
          FPos[N].Margin := StrToFloatDef(F[5], 0);
          FPos[N].TP := StrToFloatDef(F[6], 0);
          FPos[N].SL := StrToFloatDef(F[7], 0);
          FPos[N].Lev := Max(1, StrToIntDef(F[8], 1));
          FPos[N].Opened := StrToFloatDef(F[9], 0);
        end
        else if (F[0] = 'O') and (F.Count >= 10) then
        begin
          N := Length(FOrd);
          SetLength(FOrd, N + 1);
          FOrd[N].Id := StrToIntDef(F[1], 0);
          FOrd[N].Sym := F[2];
          FOrd[N].Dir := StrToIntDef(F[3], 1);
          FOrd[N].Price := StrToFloatDef(F[4], 0);
          FOrd[N].Qty := StrToFloatDef(F[5], 0);
          FOrd[N].TP := StrToFloatDef(F[6], 0);
          FOrd[N].SL := StrToFloatDef(F[7], 0);
          FOrd[N].Lev := Max(1, StrToIntDef(F[8], 1));
          FOrd[N].Time := StrToFloatDef(F[9], 0);
        end
        else if (F[0] = 'H') and (F.Count >= 8) then
        begin
          N := Length(FHist);
          SetLength(FHist, N + 1);
          // file menyimpan dari lama ke baru; yang terbaru harus di indeks 0
          for N := High(FHist) downto 1 do
            FHist[N] := FHist[N - 1];
          FHist[0].T := F[1];
          FHist[0].Sym := F[2];
          FHist[0].Act := F[3];
          FHist[0].Price := F[4];
          FHist[0].Qty := F[5];
          FHist[0].Fee := F[6];
          FHist[0].Pnl := F[7];
        end;
      finally
        F.Free;
      end;
    end;
  finally
    L.Free;
  end;
  SetLev(FLev);
end;

procedure TDemoForm.ResetAccount;
begin
  FWallet := StartBalance;
  SetLength(FPos, 0);
  SetLength(FOrd, 0);
  SetLength(FHist, 0);
  FNextId := 1;
  SaveState;
  Say('Akun demo di-reset ke 10.000 USDT.', True);
  UpdateAccount;
  RefreshLists;
end;

{ ---------- koin, time frame, data ---------- }

procedure TDemoForm.SwitchSym(const Sym: string);
var
  PI: Integer;
begin
  if Sym = '' then
    Exit;
  FSym := Sym;
  cbSym.Text := Sym;
  FLast := 0;
  FPrevLast := 0;
  ResetView(FCV);
  FNoMoreHistory := False;
  SetLength(FK, 0);
  ClearAnalysis(FA);
  FreeAndNil(FBook);
  FPriceTouched := False;
  edPrice.Text := '';
  PI := FindPos(Sym);
  if PI >= 0 then
    SetLev(FPos[PI].Lev);
  pbChart.Invalidate;
  pbBook.Invalidate;
  RequestDetail;
  RequestBook;
  UpdateTop;
  UpdatePreview;
end;

procedure TDemoForm.RequestDetail;
begin
  if FSym = '' then
    Exit;
  Inc(FReqId);
  TDetailThread.Create(Handle, FSym, FTF, FReqId);
end;

procedure TDemoForm.RequestBook;
begin
  if (FSym = '') or (FBookBusy and (GetTickCount - FBookStart < 8000)) then
    Exit;
  FBookBusy := True;
  FBookStart := GetTickCount;
  TBookThread.Create(Handle, FSym);
end;

procedure TDemoForm.SetLev(L: Integer);
var
  I: Integer;
begin
  if L < 1 then L := 1;
  if L > 125 then L := 125;
  FLev := L;
  lblLev.Caption := IntToStr(L) + 'x';
  if tbLev.Position <> L then
  begin
    FUpdatingUI := True;
    try
      tbLev.Position := L;
    finally
      FUpdatingUI := False;
    end;
  end;
  for I := 0 to 5 do
    if FLevBtns[I].Tag = L then
    begin
      FLevBtns[I].Color := clrGold;
      FLevBtns[I].Font.Color := clrBg;
    end
    else
    begin
      FLevBtns[I].Color := clrPanel2;
      FLevBtns[I].Font.Color := clrDim;
    end;
  UpdatePreview;
end;

procedure TDemoForm.SetOrdType(T: Integer);
begin
  FOrdType := T;
  if T = 0 then
  begin
    tabLimit.Color := clrPanel2; tabLimit.Font.Color := clrGold;
    tabMarket.Color := clrPanel; tabMarket.Font.Color := clrDim;
    lblPriceCap.Caption := 'Harga limit (USDT)';
    edPrice.Enabled := True;
    btnLast.Visible := True;
    if (edPrice.Text = '') or (edPrice.Text = 'Harga Pasar') then
    begin
      FPriceTouched := False;
      if CurPrice > 0 then
        edPrice.Text := PlainNum(CurPrice)
      else
        edPrice.Text := '';
    end;
  end
  else
  begin
    tabMarket.Color := clrPanel2; tabMarket.Font.Color := clrGold;
    tabLimit.Color := clrPanel; tabLimit.Font.Color := clrDim;
    lblPriceCap.Caption := 'Harga (otomatis harga pasar)';
    edPrice.Enabled := False;
    btnLast.Visible := False;
    edPrice.Text := 'Harga Pasar';
  end;
  UpdatePreview;
end;

procedure TDemoForm.SetTab(T: Integer);
begin
  FTab := T;
  lvPos.Visible := T = 0;
  lvOrd.Visible := T = 1;
  lvHist.Visible := T = 2;
  btnTPSL.Visible := T = 0;
  btnCloseSel.Visible := T = 0;
  btnCloseAll.Visible := T = 0;
  btnCancelSel.Visible := T = 1;
  if T = 0 then begin tabPos.Font.Color := clrGold; tabOrd.Font.Color := clrDim; tabHist.Font.Color := clrDim; end;
  if T = 1 then begin tabPos.Font.Color := clrDim; tabOrd.Font.Color := clrGold; tabHist.Font.Color := clrDim; end;
  if T = 2 then begin tabPos.Font.Color := clrDim; tabOrd.Font.Color := clrDim; tabHist.Font.Color := clrGold; end;
end;

procedure TDemoForm.UpdateTFButtons;
var
  I: Integer;
begin
  for I := 0 to ChartTFCount - 1 do
    if ChartTFApi[I] = FTF then
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

procedure TDemoForm.UpdateTop;
var
  Q: TDemoQuote;
  C: TColor;
begin
  if FLast > 0 then
  begin
    lblLast.Caption := FmtPrice(FLast);
    if FLast >= FPrevLast then C := clrUp else C := clrDown;
    lblLast.Font.Color := C;
  end
  else
    lblLast.Caption := '...';
  if Assigned(FQuoteFn) and FQuoteFn(FSym, Q) then
  begin
    lblChg.Caption := FmtPct(Q.Chg) + '  (24j)';
    if Q.Chg >= 0 then lblChg.Font.Color := clrUp else lblChg.Font.Color := clrDown;
    lblStats.Caption := Format('24j Tertinggi %s    Terendah %s    Volume %s',
      [FmtPrice(Q.High), FmtPrice(Q.Low), FmtUSD(Q.Vol)]);
  end;
end;

procedure TDemoForm.UpdateAccount;
var
  U: Double;
begin
  U := TotalUnreal;
  lblWallet.Caption := FmtMoney(FWallet);
  lblUnreal.Caption := FmtSigned(U);
  if U >= 0 then lblUnreal.Font.Color := clrUp else lblUnreal.Font.Color := clrDown;
  lblMarginBal.Caption := FmtMoney(FWallet + U);
  lblAvail.Caption := FmtMoney(Available);
  tabPos.Caption := Format('Posisi (%d)', [Length(FPos)]);
  tabOrd.Caption := Format('Order Terbuka (%d)', [Length(FOrd)]);
end;

procedure TDemoForm.UpdatePreview;
var
  Notional, Price, Mg, Fee, MaxN, LiqL, LiqS: Double;
begin
  if (lblInfo = nil) or (btnBuy = nil) then
    Exit;
  if FOrdType = 0 then Price := ParseF(edPrice.Text) else Price := CurPrice;
  if Price <= 0 then Price := CurPrice;
  Notional := ParseF(edAmount.Text);
  Mg := Notional / FLev;
  Fee := Notional * FeeTaker;
  MaxN := Available * FLev;
  if Price > 0 then
  begin
    LiqL := Price * (1 - 1 / FLev + MaintRate);
    LiqS := Price * (1 + 1 / FLev - MaintRate);
    if LiqL < 0 then LiqL := 0;
  end
  else
  begin
    LiqL := 0;
    LiqS := 0;
  end;
  lblInfo.Caption := Format('Margin dibutuhkan: %s USDT   Fee ~ %s' + #13#10 +
    'Maks nilai posisi: %s USDT (%dx)' + #13#10 +
    'Est. likuidasi  Long: %s   Short: %s',
    [FmtMoney(Mg), FmtMoney(Fee), FmtMoney(MaxN), FLev, FmtPrice(LiqL), FmtPrice(LiqS)]);
end;

procedure TDemoForm.RefreshLists;
var
  I: Integer;
  P: TDPos;
  M, U, Roe: Double;
  Item: TListItem;
  SLTP: string;
  Side: string;
begin
  { posisi }
  lvPos.Items.BeginUpdate;
  try
    while lvPos.Items.Count > Length(FPos) do
      lvPos.Items.Delete(lvPos.Items.Count - 1);
    while lvPos.Items.Count < Length(FPos) do
      lvPos.Items.Add;
    for I := 0 to High(FPos) do
    begin
      P := FPos[I];
      M := Mark(P.Sym);
      U := UnrealOf(P, M);
      if P.Margin > 0 then Roe := U / P.Margin * 100 else Roe := 0;
      if M <= 0 then U := 0;
      if (P.TP > 0) or (P.SL > 0) then
        SLTP := Format('%s / %s', [IfThenS(P.TP > 0, PlainNum(P.TP), '-'), IfThenS(P.SL > 0, PlainNum(P.SL), '-')])
      else
        SLTP := '-';
      SetItem(lvPos.Items[I], [Format('%s  %s %dx', [P.Sym, DirText(P.Dir), P.Lev]),
        IfThenS(P.Dir > 0, '', '-') + FmtQty(P.Qty), PlainNum(P.Entry), IfThenS(M > 0, PlainNum(M), '-'),
        PlainNum(LiqPrice(P)), FmtMoney(P.Margin),
        Format('%s (%s%.2f%%)', [FmtSigned(U), IfThenS(Roe >= 0, '+', ''), Roe]), SLTP]);
    end;
  finally
    lvPos.Items.EndUpdate;
  end;

  { order terbuka }
  lvOrd.Items.BeginUpdate;
  try
    while lvOrd.Items.Count > Length(FOrd) do
      lvOrd.Items.Delete(lvOrd.Items.Count - 1);
    while lvOrd.Items.Count < Length(FOrd) do
      lvOrd.Items.Add;
    for I := 0 to High(FOrd) do
    begin
      if FOrd[I].Dir > 0 then Side := 'Limit Beli (Long)' else Side := 'Limit Jual (Short)';
      if (FOrd[I].TP > 0) or (FOrd[I].SL > 0) then
        SLTP := Format('%s / %s', [IfThenS(FOrd[I].TP > 0, PlainNum(FOrd[I].TP), '-'),
          IfThenS(FOrd[I].SL > 0, PlainNum(FOrd[I].SL), '-')])
      else
        SLTP := '-';
      SetItem(lvOrd.Items[I], [FormatDateTime('dd/mm hh:nn:ss', FOrd[I].Time), FOrd[I].Sym, Side,
        PlainNum(FOrd[I].Price), FmtQty(FOrd[I].Qty), IntToStr(FOrd[I].Lev) + 'x', SLTP]);
    end;
  finally
    lvOrd.Items.EndUpdate;
  end;

  { riwayat }
  lvHist.Items.BeginUpdate;
  try
    while lvHist.Items.Count > Length(FHist) do
      lvHist.Items.Delete(lvHist.Items.Count - 1);
    while lvHist.Items.Count < Length(FHist) do
      lvHist.Items.Add;
    for I := 0 to High(FHist) do
      SetItem(lvHist.Items[I], [FHist[I].T, FHist[I].Sym, FHist[I].Act, FHist[I].Price,
        FHist[I].Qty, FHist[I].Fee, FHist[I].Pnl]);
  finally
    lvHist.Items.EndUpdate;
  end;
end;

{ ---------- timer ---------- }

procedure TDemoForm.Tick(Sender: TObject);
var
  I: Integer;
  M: Double;
  Done: Boolean;
begin
  Inc(FTick);
  { posisi: likuidasi, take profit, stop loss }
  I := 0;
  while I < Length(FPos) do
  begin
    M := Mark(FPos[I].Sym);
    Done := False;
    if M > 0 then
    begin
      if ((FPos[I].Dir > 0) and (M <= LiqPrice(FPos[I]))) or
         ((FPos[I].Dir < 0) and (M >= LiqPrice(FPos[I]))) then
      begin
        Liquidate(I);
        Done := True;
      end
      else if (FPos[I].TP > 0) and (((FPos[I].Dir > 0) and (M >= FPos[I].TP)) or
              ((FPos[I].Dir < 0) and (M <= FPos[I].TP))) then
      begin
        ClosePos(I, FPos[I].TP, 'TP');
        Done := True;
      end
      else if (FPos[I].SL > 0) and (((FPos[I].Dir > 0) and (M <= FPos[I].SL)) or
              ((FPos[I].Dir < 0) and (M >= FPos[I].SL))) then
      begin
        ClosePos(I, FPos[I].SL, 'SL');
        Done := True;
      end;
    end;
    if not Done then
      Inc(I);
  end;
  { order limit }
  I := 0;
  while I < Length(FOrd) do
  begin
    M := Mark(FOrd[I].Sym);
    Done := False;
    if M > 0 then
      if ((FOrd[I].Dir > 0) and (M <= FOrd[I].Price)) or
         ((FOrd[I].Dir < 0) and (M >= FOrd[I].Price)) then
      begin
        Fill(FOrd[I].Sym, FOrd[I].Dir, FOrd[I].Qty, FOrd[I].Price, FOrd[I].Lev,
          FOrd[I].TP, FOrd[I].SL, True);
        Say(Format('Order limit %s %s @ %s terisi.', [DirText(FOrd[I].Dir), FOrd[I].Sym,
          PlainNum(FOrd[I].Price)]), True);
        DeleteOrd(I);
        Done := True;
      end;
    if not Done then
      Inc(I);
  end;
  UpdateTop;
  UpdateAccount;
  UpdatePreview;
  RefreshLists;
  if (FTick mod 5) = 0 then
    SaveState;
end;

procedure TDemoForm.LiveTick(Sender: TObject);
begin
  if not Visible or (FSym = '') then
    Exit;
  if (Length(FK) > 0) and not (FLiveBusy and (GetTickCount - FLiveStart < 10000)) then
  begin
    FLiveBusy := True;
    FLiveStart := GetTickCount;
    TLiveThread.Create(Handle, FSym, FTF);
  end;
  if (FTick mod 2) = 0 then
    RequestBook;
end;

procedure TDemoForm.DetailTick(Sender: TObject);
begin
  if Visible then
    RequestDetail;
end;

procedure TDemoForm.WMLive(var M: TMessage);
var
  D: TLiveData;
begin
  D := TLiveData(M.LParam);
  try
    FLiveBusy := False;
    if (D.Err <> '') or (D.Sym <> FSym) or (D.Interval <> FTF) or
       (Length(D.K) = 0) or (Length(FK) = 0) then
      Exit;
    MergeKlines(FK, D.K);
    FPrevLast := FLast;
    FLast := FK[High(FK)].C;
    if (FOrdType = 0) and not FPriceTouched and (edPrice.Text = '') then
      edPrice.Text := PlainNum(FLast);
    pbChart.Invalidate;
  finally
    D.Free;
  end;
end;

procedure TDemoForm.WMDetail(var M: TMessage);
var
  D: TDetailData;
begin
  D := TDetailData(M.LParam);
  try
    if (D.ReqId <> FReqId) or (D.Err <> '') or (D.A.Symbol <> FSym) then
      Exit;
    if (Length(FK) > 0) and (FA.Symbol = D.A.Symbol) and (FA.Interval = D.A.Interval) then
      MergeKlines(FK, D.K)
    else
      FK := D.K;
    FA := D.A;
    if Length(FK) > 0 then
    begin
      FPrevLast := FLast;
      FLast := FK[High(FK)].C;
      if (FOrdType = 0) and not FPriceTouched and (edPrice.Text = '') then
        edPrice.Text := PlainNum(FLast);
    end;
    pbChart.Invalidate;
  finally
    D.Free;
  end;
end;

procedure TDemoForm.WMOlder(var M: TMessage);
var
  D: TLiveData;
begin
  D := TLiveData(M.LParam);
  try
    FOlderBusy := False;
    if (D.Err <> '') or (D.Interval <> FTF) or (D.Sym <> FSym) then
      Exit;
    if PrependKlines(FK, D.K) = 0 then
      FNoMoreHistory := True;
    pbChart.Invalidate;
  finally
    D.Free;
  end;
end;

procedure TDemoForm.WMBook(var M: TMessage);
var
  D: TBookData;
begin
  D := TBookData(M.LParam);
  FBookBusy := False;
  if (D.Sym <> FSym) or (Length(D.BidP) = 0) then
  begin
    D.Free;
    Exit;
  end;
  FBook.Free;
  FBook := D;
  pbBook.Invalidate;
end;

procedure TDemoForm.LoadOlderIfNeeded;
begin
  if FCV.AtStart and not FOlderBusy and not FNoMoreHistory and (Length(FK) > 0) then
  begin
    FOlderBusy := True;
    TOlderThread.Create(Handle, FSym, FTF, FK[0].OpenTime - 1);
  end;
end;

{ ---------- event ---------- }

procedure TDemoForm.DemoClose(Sender: TObject; var Action: TCloseAction);
begin
  SaveState;
  Action := caHide;
end;

procedure TDemoForm.cbSymSelect(Sender: TObject);
begin
  SwitchSym(cbSym.Text);
end;

procedure TDemoForm.cbSymKeyDown(Sender: TObject; var Key: Word; Shift: TShiftState);
var
  S: string;
begin
  if Key = VK_RETURN then
  begin
    Key := 0;
    S := UpperCase(Trim(cbSym.Text));
    if (FSymbols.IndexOf(S) < 0) and (FSymbols.IndexOf(S + 'USDT') >= 0) then
      S := S + 'USDT';
    if FSymbols.IndexOf(S) >= 0 then
      SwitchSym(S)
    else
      Say('Koin ' + S + ' tidak ditemukan.', False);
  end;
end;

procedure TDemoForm.TFClick(Sender: TObject);
begin
  FTF := ChartTFApi[TPanel(Sender).Tag];
  UpdateTFButtons;
  ResetView(FCV);
  FNoMoreHistory := False;
  SetLength(FK, 0);
  ClearAnalysis(FA);
  pbChart.Invalidate;
  RequestDetail;
end;

procedure TDemoForm.ChartPaint(Sender: TObject);
begin
  DrawCandles(pbChart.Canvas, pbChart.ClientRect, FK, FA, FHoverX,
    FSym + ' Perp  ' + ChartTFLabel(FTF), FCV);
end;

procedure TDemoForm.ChartMouseMove(Sender: TObject; Shift: TShiftState; X, Y: Integer);
begin
  FHoverX := X;
  if ViewMouseMove(FCV, X, Y) then
    LoadOlderIfNeeded;
  pbChart.Invalidate;
end;

procedure TDemoForm.ChartMouseDown(Sender: TObject; Button: TMouseButton;
  Shift: TShiftState; X, Y: Integer);
begin
  if Button <> mbLeft then
    Exit;
  ViewMouseDown(FCV, X, Y);
  pbChart.Cursor := crSizeAll;
end;

procedure TDemoForm.ChartMouseUp(Sender: TObject; Button: TMouseButton;
  Shift: TShiftState; X, Y: Integer);
begin
  ViewMouseUp(FCV);
  pbChart.Cursor := crCross;
end;

procedure TDemoForm.ChartDblClick(Sender: TObject);
begin
  ResetView(FCV);
  pbChart.Invalidate;
end;

procedure TDemoForm.BookPaint(Sender: TObject);
var
  Cv: TCanvas;
  W, H, RowH, I, Y, N: Integer;
  MaxCum, Cum: Double;
  CumA, CumB: array of Double;

  procedure Row(Y: Integer; P, Q, Tot: Double; Clr, BarClr: TColor);
  var
    BarW: Integer;
    S: string;
  begin
    if MaxCum > 0 then
      BarW := Round(W * Tot / MaxCum)
    else
      BarW := 0;
    Cv.Brush.Color := BarClr;
    Cv.FillRect(Rect(W - BarW, Y, W, Y + RowH));
    Cv.Brush.Style := bsClear;
    Cv.Font.Color := Clr;
    Cv.TextOut(10, Y + 2, PlainNum(P));
    Cv.Font.Color := clrText;
    S := FmtQty(Q);
    Cv.TextOut(160 - Cv.TextWidth(S), Y + 2, S);
    S := FormatFloat('#,##0', Tot);
    Cv.TextOut(W - 10 - Cv.TextWidth(S), Y + 2, S);
    Cv.Brush.Style := bsSolid;
  end;

begin
  Cv := pbBook.Canvas;
  W := pbBook.Width;
  H := pbBook.Height;
  Cv.Brush.Color := clrPanel;
  Cv.FillRect(Rect(0, 0, W, H));
  Cv.Font.Name := 'Consolas';
  Cv.Font.Size := 9;
  if (FBook = nil) or (Length(FBook.BidP) = 0) or (Length(FBook.AskP) = 0) then
  begin
    Cv.Font.Color := clrDim;
    Cv.Brush.Style := bsClear;
    Cv.TextOut(10, 10, 'Memuat order book ...');
    Exit;
  end;
  RowH := 20;
  N := Min(BookRows, Min(Length(FBook.BidP), Length(FBook.AskP)));
  SetLength(CumA, N);
  SetLength(CumB, N);
  Cum := 0;
  for I := 0 to N - 1 do
  begin
    Cum := Cum + FBook.AskQ[I] * FBook.AskP[I];
    CumA[I] := Cum;
  end;
  MaxCum := Cum;
  Cum := 0;
  for I := 0 to N - 1 do
  begin
    Cum := Cum + FBook.BidQ[I] * FBook.BidP[I];
    CumB[I] := Cum;
  end;
  if Cum > MaxCum then
    MaxCum := Cum;

  { jual (merah): harga tertinggi di atas, terendah menempel di tengah }
  for I := N - 1 downto 0 do
  begin
    Y := (N - 1 - I) * RowH;
    Row(Y, FBook.AskP[I], FBook.AskQ[I], CumA[I], clrDown, clrDownBg);
  end;
  { tengah: harga terakhir }
  Y := N * RowH;
  Cv.Brush.Color := clrPanel2;
  Cv.FillRect(Rect(0, Y, W, Y + 30));
  Cv.Brush.Style := bsClear;
  Cv.Font.Size := 12;
  Cv.Font.Style := [fsBold];
  if FLast >= FPrevLast then Cv.Font.Color := clrUp else Cv.Font.Color := clrDown;
  Cv.TextOut(10, Y + 5, FmtPrice(FLast));
  Cv.Font.Size := 8;
  Cv.Font.Style := [];
  Cv.Font.Color := clrDim;
  Cv.TextOut(130, Y + 10, Format('Spread %s', [FmtPrice(FBook.AskP[0] - FBook.BidP[0])]));
  Cv.Font.Size := 9;
  Cv.Brush.Style := bsSolid;
  { beli (hijau) }
  for I := 0 to N - 1 do
  begin
    Y := N * RowH + 30 + I * RowH;
    Row(Y, FBook.BidP[I], FBook.BidQ[I], CumB[I], clrUp, clrUpBg);
  end;
end;

procedure TDemoForm.LevChange(Sender: TObject);
begin
  if FUpdatingUI then
    Exit;
  SetLev(tbLev.Position);
end;

procedure TDemoForm.LevBtnClick(Sender: TObject);
begin
  SetLev(TPanel(Sender).Tag);
end;

procedure TDemoForm.TypeClick(Sender: TObject);
begin
  SetOrdType(TPanel(Sender).Tag);
end;

procedure TDemoForm.LastClick(Sender: TObject);
begin
  if CurPrice > 0 then
  begin
    FPriceTouched := False;
    edPrice.Text := PlainNum(CurPrice);
  end;
end;

procedure TDemoForm.PctClick(Sender: TObject);
var
  Pct, Max_: Double;
begin
  Pct := TPanel(Sender).Tag;
  Max_ := Available * FLev * 0.99 / (1 + FeeTaker * FLev);
  edAmount.Text := Format('%.2f', [Max_ * Pct / 100]);
end;

procedure TDemoForm.PriceChange(Sender: TObject);
begin
  if edPrice.Enabled then
    FPriceTouched := edPrice.Focused;
  UpdatePreview;
end;

procedure TDemoForm.FieldChange(Sender: TObject);
begin
  UpdatePreview;
end;

procedure TDemoForm.BuyClick(Sender: TObject);
begin
  PlaceOrder(1);
end;

procedure TDemoForm.SellClick(Sender: TObject);
begin
  PlaceOrder(-1);
end;

procedure TDemoForm.TabClick(Sender: TObject);
begin
  SetTab(TPanel(Sender).Tag);
end;

{ Atur Take Profit & Stop Loss posisi terpilih (kosongkan = hapus) }
procedure TDemoForm.TPSLClick(Sender: TObject);
var
  I: Integer;
  F: TForm;
  eTP, eSL: TEdit;
  bOk, bNo: TButton;
  TP, SL, M: Double;
begin
  I := lvPos.ItemIndex;
  if (I < 0) or (I > High(FPos)) then
  begin
    Say('Pilih posisi di tabel dulu, lalu klik Atur TP / SL.', False);
    Exit;
  end;
  F := TForm.CreateNew(Self);
  try
    F.Caption := Format('TP / SL  %s  %s', [FPos[I].Sym, DirText(FPos[I].Dir)]);
    F.BorderStyle := bsDialog;
    F.Position := poOwnerFormCenter;
    F.ClientWidth := 340;
    F.ClientHeight := 190;
    F.Color := clrPanel;
    F.Font.Name := 'Segoe UI';
    F.Font.Color := clrText;
    MkLabel(F, 16, 12, 308, 18, Format('Harga masuk %s   |   Mark %s',
      [PlainNum(FPos[I].Entry), PlainNum(Mark(FPos[I].Sym))]), clrDim, 9, False);
    MkLabel(F, 16, 40, 308, 16, 'Take Profit (harga, kosong = tanpa TP)', clrUp, 9, True);
    eTP := TEdit.Create(F);
    eTP.Parent := F;
    eTP.SetBounds(16, 58, 308, 26);
    eTP.Color := clrPanel2;
    eTP.Font.Color := clrText;
    eTP.Font.Size := 10;
    if FPos[I].TP > 0 then eTP.Text := PlainNum(FPos[I].TP);
    MkLabel(F, 16, 94, 308, 16, 'Stop Loss (harga, kosong = tanpa SL)', clrDown, 9, True);
    eSL := TEdit.Create(F);
    eSL.Parent := F;
    eSL.SetBounds(16, 112, 308, 26);
    eSL.Color := clrPanel2;
    eSL.Font.Color := clrText;
    eSL.Font.Size := 10;
    if FPos[I].SL > 0 then eSL.Text := PlainNum(FPos[I].SL);
    bOk := TButton.Create(F);
    bOk.Parent := F;
    bOk.SetBounds(150, 150, 84, 28);
    bOk.Caption := 'Simpan';
    bOk.Default := True;
    bOk.ModalResult := mrOk;
    bNo := TButton.Create(F);
    bNo.Parent := F;
    bNo.SetBounds(240, 150, 84, 28);
    bNo.Caption := 'Batal';
    bNo.Cancel := True;
    bNo.ModalResult := mrCancel;
    if F.ShowModal <> mrOk then
      Exit;
    TP := ParseF(eTP.Text);
    SL := ParseF(eSL.Text);
  finally
    F.Free;
  end;
  M := Mark(FPos[I].Sym);
  if FPos[I].Dir > 0 then
  begin
    if ((TP > 0) and (TP <= M)) or ((SL > 0) and (SL >= M)) then
    begin
      Say('Long: TP harus di atas harga sekarang dan SL di bawah harga sekarang.', False);
      Exit;
    end;
  end
  else if ((TP > 0) and (TP >= M)) or ((SL > 0) and (SL <= M)) then
  begin
    Say('Short: TP harus di bawah harga sekarang dan SL di atas harga sekarang.', False);
    Exit;
  end;
  FPos[I].TP := TP;
  FPos[I].SL := SL;
  Say(Format('TP/SL %s diperbarui.', [FPos[I].Sym]), True);
  SaveState;
  RefreshLists;
end;

procedure TDemoForm.CloseSelClick(Sender: TObject);
var
  I: Integer;
  M: Double;
begin
  I := lvPos.ItemIndex;
  if (I < 0) or (I > High(FPos)) then
  begin
    Say('Pilih posisi di tabel dulu.', False);
    Exit;
  end;
  M := Mark(FPos[I].Sym);
  if M <= 0 then
    Exit;
  Say(Format('Posisi %s ditutup di %s.', [FPos[I].Sym, PlainNum(M)]), True);
  ClosePos(I, M, 'Tutup');
  SaveState;
  UpdateAccount;
  RefreshLists;
end;

procedure TDemoForm.CloseAllClick(Sender: TObject);
var
  I: Integer;
  M: Double;
begin
  if Length(FPos) = 0 then
    Exit;
  for I := High(FPos) downto 0 do
  begin
    M := Mark(FPos[I].Sym);
    if M > 0 then
      ClosePos(I, M, 'Tutup');
  end;
  Say('Semua posisi ditutup di harga pasar.', True);
  SaveState;
  UpdateAccount;
  RefreshLists;
end;

procedure TDemoForm.CancelSelClick(Sender: TObject);
var
  I: Integer;
begin
  I := lvOrd.ItemIndex;
  if (I < 0) or (I > High(FOrd)) then
  begin
    Say('Pilih order di tabel dulu.', False);
    Exit;
  end;
  DeleteOrd(I);
  Say('Order dibatalkan.', True);
  SaveState;
  UpdateAccount;
  RefreshLists;
end;

procedure TDemoForm.DepositClick(Sender: TObject);
var
  S: string;
  V: Double;
begin
  S := '1000';
  if not InputQuery('Tambah Saldo Demo', 'Jumlah USDT virtual yang ditambahkan:', S) then
    Exit;
  V := ParseF(S);
  if (V <= 0) or (V > 1E9) then
  begin
    Say('Jumlah tidak valid.', False);
    Exit;
  end;
  FWallet := FWallet + V;
  AddHist('USDT', 'Deposit demo', 0, V, 0, V);
  Say(Format('Saldo bertambah %s USDT.', [FmtMoney(V)]), True);
  SaveState;
  UpdateAccount;
  RefreshLists;
end;

procedure TDemoForm.ResetClick(Sender: TObject);
begin
  if MessageBox(Handle, 'Reset akun demo ke 10.000 USDT?' + #13#10 +
     'Semua posisi, order, dan riwayat akan dihapus.', 'Reset Akun Demo',
     MB_YESNO or MB_ICONQUESTION) = IDYES then
    ResetAccount;
end;

procedure TDemoForm.lvPosDblClick(Sender: TObject);
var
  I: Integer;
begin
  I := lvPos.ItemIndex;
  if (I >= 0) and (I <= High(FPos)) then
    SwitchSym(FPos[I].Sym);
end;

procedure TDemoForm.lvPosCustomDrawSubItem(Sender: TCustomListView; Item: TListItem;
  SubItem: Integer; State: TCustomDrawState; var DefaultDraw: Boolean);
var
  I: Integer;
begin
  Sender.Canvas.Font.Color := clrText;
  I := Item.Index;
  if (I < 0) or (I > High(FPos)) then
    Exit;
  case SubItem of
    1: if FPos[I].Dir > 0 then Sender.Canvas.Font.Color := clrUp else Sender.Canvas.Font.Color := clrDown;
    4: Sender.Canvas.Font.Color := clrGold;
    6: if (Item.SubItems.Count >= 6) and (Copy(Item.SubItems[5], 1, 1) = '-') then
         Sender.Canvas.Font.Color := clrDown
       else
         Sender.Canvas.Font.Color := clrUp;
  end;
end;

procedure TDemoForm.lvHistCustomDrawSubItem(Sender: TCustomListView; Item: TListItem;
  SubItem: Integer; State: TCustomDrawState; var DefaultDraw: Boolean);
var
  S: string;
begin
  Sender.Canvas.Font.Color := clrText;
  if (SubItem = 6) and (Item.SubItems.Count >= 6) then
  begin
    S := Item.SubItems[5];
    if Copy(S, 1, 1) = '-' then
    begin
      if Length(S) > 1 then Sender.Canvas.Font.Color := clrDown else Sender.Canvas.Font.Color := clrDim;
    end
    else if Copy(S, 1, 1) = '+' then
      Sender.Canvas.Font.Color := clrUp;
  end
  else if SubItem = 2 then
  begin
    S := Item.SubItems[1];
    if Pos('LIKUIDASI', S) > 0 then Sender.Canvas.Font.Color := clrDown
    else if Pos('Long', S) > 0 then Sender.Canvas.Font.Color := clrUp
    else if Pos('Short', S) > 0 then Sender.Canvas.Font.Color := clrDown;
  end;
end;

end.
