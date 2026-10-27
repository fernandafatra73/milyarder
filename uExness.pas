unit uExness;

{ Terminal trading bergaya Exness Web Terminal (SIMULASI / akun demo):
  daftar instrumen dengan harga Sell/Buy, grafik, tiket order (lot, Market/Pending,
  TP/SL), posisi terbuka, order pending, riwayat, Balance/Equity/Margin/Free Margin/
  Margin Level, pilihan leverage akun, Deposit. Harga dari Binance Futures
  (XAUUSDT dipakai sebagai emas). Tidak terhubung ke Exness dan tidak ada order sungguhan. }

interface

uses
  Windows, Messages, SysUtils, Classes, Graphics, Controls, Forms, StdCtrls,
  ExtCtrls, ComCtrls, Dialogs, Math, uAnalysis, uBinance, uWorkers, uChart, uDemo;

type
  TXPos = record
    Id: Integer;
    Sym: string;
    Dir: Integer;            // 1 buy, -1 sell
    Lots, CS, Open, TP, SL: Double;
    Opened: TDateTime;
  end;

  TXOrd = record
    Id: Integer;
    Sym: string;
    Dir, Kind: Integer;      // Kind 0 = limit, 1 = stop
    Lots, CS, Price, TP, SL: Double;
    Time: TDateTime;
  end;

  TXHist = record
    T, Id, Sym, Typ, Lots, Op, Cl, Pnl, Why: string;
  end;

  TExnessForm = class(TForm)
  private
    pnlTop, pnlSearch, pnlLeft, pnlRight, pnlCenter, pnlHead, pnlTF, pnlChart, pnlBottom, pnlTabs: TPanel;
    lblBrand, lblTerm: TLabel;
    lblBal, lblEq, lblMar, lblFree, lblLvl, lblPnl: TLabel;
    cbLev: TComboBox;
    btnDeposit, btnReset: TPanel;
    edSearch: TEdit;
    lvInst: TListView;
    lblChSym, lblChPrice, lblChChg: TLabel;
    FTFBtns: array[0..ChartTFCount - 1] of TPanel;
    pbChart: TPaintBox;
    lblTkSym, lblTkSub, lblPendCap, lblMargin, lblContract, lblSpread, lblMsg: TLabel;
    tabMarket, tabPend: TPanel;
    btnLotMinus, btnLotPlus, btnSell, btnBuy: TPanel;
    lblSellP, lblBuyP: TLabel;
    edLots, edPend, edTP, edSL: TEdit;
    tabPos, tabOrd, tabHist: TPanel;
    btnMod, btnCloseSel, btnCloseAll, btnCancel: TPanel;
    lvPos, lvOrd, lvHist: TListView;
    tmrTick, tmrLive, tmrDetail: TTimer;

    FSymbols: TStrings;
    FQuoteFn: TDemoQuoteFn;
    FInst: TStringList;
    FSym, FTF: string;
    FK: TKlines;
    FA: TAnalysis;
    FCV: TChartView;
    FHoverX: Integer;
    FLast: Double;
    FReqId: Integer;
    FOlderBusy, FNoMoreHistory, FLiveBusy: Boolean;
    FLiveStart: Cardinal;
    FTick: Integer;

    FWallet: Double;
    FAcctLev: Integer;
    FPos: array of TXPos;
    FOrd: array of TXOrd;
    FHist: array of TXHist;
    FNextId: Integer;
    FPending: Boolean;
    FTab: Integer;
    FUpdating: Boolean;

    function MkLabel(AParent: TWinControl; X, Y, W, H: Integer; const Txt: string;
      Fg: TColor; Size: Integer; Bold: Boolean): TLabel;
    function MkBtn(AParent: TWinControl; X, Y, W, H: Integer; const Txt: string;
      Bg, Fg: TColor; Click: TNotifyEvent): TPanel;
    function MkEdit(AParent: TWinControl; X, Y, W, H: Integer): TEdit;
    function MkList(AParent: TWinControl; const Cols: array of string;
      const Widths: array of Integer): TListView;
    procedure BuildUI;
    procedure BuildTop;
    procedure BuildLeft;
    procedure BuildRight;
    procedure BuildCenter;
    procedure BuildBottom;
    procedure BuildInst;

    function MidOf(const Sym: string): Double;
    function BidOf(const Sym: string): Double;
    function AskOf(const Sym: string): Double;
    function ProfitOf(const P: TXPos): Double;
    function TotalProfit: Double;
    function Equity: Double;
    function UsedMargin: Double;
    function FreeMargin: Double;
    procedure DeletePos(I: Integer);
    procedure DeleteOrd(I: Integer);
    procedure AddHist(const P: TXPos; ClosePrice, Pnl: Double; const Why: string);
    procedure OpenPos(const Sym: string; Dir: Integer; Lots, CS, Price, TP, SL: Double);
    procedure ClosePos(I: Integer; Price: Double; const Why: string);
    procedure PlaceOrder(Dir: Integer);
    procedure Say(const Txt: string; Ok: Boolean);

    procedure SaveState;
    procedure LoadState;
    procedure ResetAccount;

    procedure SwitchSym(const Sym: string);
    procedure RequestDetail;
    procedure SetPending(P: Boolean);
    procedure SetTab(T: Integer);
    procedure UpdateTFButtons;
    procedure UpdateHeader;
    procedure UpdateAccount;
    procedure UpdateTicket;
    procedure UpdateInst;
    procedure RefreshLists;
    procedure LoadOlderIfNeeded;

    procedure Tick(Sender: TObject);
    procedure LiveTick(Sender: TObject);
    procedure DetailTick(Sender: TObject);
    procedure WMLive(var M: TMessage); message WM_FT_LIVE;
    procedure WMDetail(var M: TMessage); message WM_FT_DETAIL;
    procedure WMOlder(var M: TMessage); message WM_FT_OLDER;

    procedure XClose(Sender: TObject; var Action: TCloseAction);
    procedure SearchChange(Sender: TObject);
    procedure InstClick(Sender: TObject);
    procedure TFClick(Sender: TObject);
    procedure ChartPaint(Sender: TObject);
    procedure ChartMouseMove(Sender: TObject; Shift: TShiftState; X, Y: Integer);
    procedure ChartMouseDown(Sender: TObject; Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
    procedure ChartMouseUp(Sender: TObject; Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
    procedure ChartDblClick(Sender: TObject);
    procedure TypeClick(Sender: TObject);
    procedure LotClick(Sender: TObject);
    procedure FieldChange(Sender: TObject);
    procedure BuyClick(Sender: TObject);
    procedure SellClick(Sender: TObject);
    procedure TabClick(Sender: TObject);
    procedure ModClick(Sender: TObject);
    procedure CloseSelClick(Sender: TObject);
    procedure CloseAllClick(Sender: TObject);
    procedure CancelClick(Sender: TObject);
    procedure DepositClick(Sender: TObject);
    procedure ResetClick(Sender: TObject);
    procedure LevChange(Sender: TObject);
    procedure ListDraw(Sender: TCustomListView; Item: TListItem;
      SubItem: Integer; State: TCustomDrawState; var DefaultDraw: Boolean);
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
  end;

procedure ShowExnessForm(Symbols: TStrings; QuoteFn: TDemoQuoteFn; const Sym: string);
function ExnessChartWheel(P: TPoint; Delta: Integer): Boolean;

implementation

const
  StartBalance = 10000;
  SaveFile = 'exness_akun.txt';
  MinLot = 0.01;
  MaxLot = 100;

  clrBrand = $0000E6FF;   // kuning Exness #FFE600
  clrBuyX  = $00FF7A2E;   // biru
  clrSellX = $004D48E5;   // merah

var
  XForm: TExnessForm = nil;

{ ---------- util ---------- }

function XParse(const S: string): Double;
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

function XNum(P: Double): string;
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

function XMoney(V: Double): string;
begin
  Result := FormatFloat('#,##0.00', V);
end;

function XSigned(V: Double): string;
begin
  if V >= 0 then
    Result := '+' + FormatFloat('#,##0.00', V)
  else
    Result := '-' + FormatFloat('#,##0.00', Abs(V));
end;

function XOpt(V: Double): string;
begin
  if V > 0 then Result := XNum(V) else Result := '-';
end;

function DispName(const Sym: string): string;
begin
  Result := Sym;
  if (Length(Result) > 4) and (Copy(Result, Length(Result) - 3, 4) = 'USDT') then
    Result := Copy(Result, 1, Length(Result) - 4) + 'USD';
end;

function ContractSize(const Sym: string; Price: Double): Double;
begin
  if Sym = 'XAUUSDT' then
  begin
    Result := 100;       // 1 lot emas = 100 oz
    Exit;
  end;
  Result := 1;
  if Price <= 0 then
    Exit;
  while (Result * Price < 1000) and (Result < 1e9) do
    Result := Result * 10;
end;

function SpreadFrac(const Sym: string): Double;
begin
  if Sym = 'XAUUSDT' then Result := 0.00008 else Result := 0.0002;
end;

function XSplit(const S: string): TStringList;
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

procedure XSetItem(Item: TListItem; const Cols: array of string);
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

function TypText(Dir, Kind: Integer; Pending: Boolean): string;
begin
  if not Pending then
  begin
    if Dir > 0 then Result := 'Buy' else Result := 'Sell';
    Exit;
  end;
  if Dir > 0 then Result := 'Buy ' else Result := 'Sell ';
  if Kind = 0 then Result := Result + 'Limit' else Result := Result + 'Stop';
end;

{ ---------- pembuatan UI ---------- }

procedure ShowExnessForm(Symbols: TStrings; QuoteFn: TDemoQuoteFn; const Sym: string);
begin
  if XForm = nil then
  begin
    XForm := TExnessForm.Create(Application);
    XForm.FSymbols := Symbols;
    XForm.FQuoteFn := QuoteFn;
    XForm.BuildInst;
    if Sym <> '' then
      XForm.SwitchSym(Sym)
    else
      XForm.SwitchSym('XAUUSDT');
  end
  else if (Sym <> '') and (Sym <> XForm.FSym) then
    XForm.SwitchSym(Sym);
  XForm.Show;
  if XForm.WindowState = wsMinimized then
    XForm.WindowState := wsNormal;
  XForm.BringToFront;
end;

function ExnessChartWheel(P: TPoint; Delta: Integer): Boolean;
begin
  Result := (XForm <> nil) and XForm.Visible and
    (WindowFromPoint(P) = XForm.pnlChart.Handle);
  if Result then
  begin
    ViewZoom(XForm.FCV, Delta);
    XForm.pbChart.Invalidate;
    XForm.LoadOlderIfNeeded;
  end;
end;

function TExnessForm.MkLabel(AParent: TWinControl; X, Y, W, H: Integer; const Txt: string;
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

function TExnessForm.MkBtn(AParent: TWinControl; X, Y, W, H: Integer; const Txt: string;
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

function TExnessForm.MkEdit(AParent: TWinControl; X, Y, W, H: Integer): TEdit;
begin
  Result := TEdit.Create(Self);
  Result.Parent := AParent;
  Result.AutoSize := False;
  Result.SetBounds(X, Y, W, H);
  Result.Color := clrPanel2;
  Result.Font.Color := clrText;
  Result.Font.Size := 11;
  Result.Font.Style := [fsBold];
  Result.BorderStyle := bsSingle;
  Result.OnChange := FieldChange;
end;

function TExnessForm.MkList(AParent: TWinControl; const Cols: array of string;
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
  Result.OnCustomDrawSubItem := ListDraw;
  for I := 0 to High(Cols) do
  begin
    C := Result.Columns.Add;
    C.Caption := Cols[I];
    C.Width := Widths[I];
  end;
end;

constructor TExnessForm.Create(AOwner: TComponent);
begin
  inherited CreateNew(AOwner);
  Caption := 'Exness Terminal - AKUN DEMO (simulasi, uang virtual)';
  Width := 1500;
  Height := 900;
  Constraints.MinWidth := 1300;
  Constraints.MinHeight := 760;
  Position := poScreenCenter;
  Color := clrBg;
  Font.Name := 'Segoe UI';
  Font.Size := 9;
  Font.Color := clrText;
  OnClose := XClose;
  FHoverX := -1;
  FTF := ChartTFApi[3];
  FNextId := 100001;
  FWallet := StartBalance;
  FAcctLev := 200;
  FInst := TStringList.Create;
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

destructor TExnessForm.Destroy;
begin
  SaveState;
  FInst.Free;
  inherited;
end;

procedure TExnessForm.BuildUI;
begin
  BuildTop;
  BuildLeft;
  BuildRight;
  BuildCenter;
  BuildBottom;
  SetPending(False);
  SetTab(0);
end;

procedure TExnessForm.BuildTop;
const
  Caps: array[0..5] of string =
    ('Balance', 'Equity', 'Margin', 'Free Margin', 'Margin Level', 'Profit');
var
  I: Integer;
  L: TLabel;
begin
  pnlTop := TPanel.Create(Self);
  pnlTop.Parent := Self;
  pnlTop.Align := alTop;
  pnlTop.Height := 58;
  pnlTop.BevelOuter := bvNone;
  pnlTop.Color := clrPanel;

  lblBrand := MkLabel(pnlTop, 14, 6, 150, 32, 'exness', clrBrand, 20, True);
  lblBrand.Font.Style := [fsBold, fsItalic];
  lblTerm := MkLabel(pnlTop, 16, 36, 260, 16, 'Terminal  |  Akun DEMO Standard  #' +
    IntToStr(7000000 + (GetTickCount mod 1000)), clrDim, 8, False);

  for I := 0 to 5 do
  begin
    MkLabel(pnlTop, 290 + I * 118, 8, 112, 16, Caps[I], clrDim, 8, False);
    L := MkLabel(pnlTop, 290 + I * 118, 26, 112, 22, '-', clrText, 11, True);
    case I of
      0: lblBal := L;
      1: lblEq := L;
      2: lblMar := L;
      3: lblFree := L;
      4: lblLvl := L;
      5: lblPnl := L;
    end;
  end;

  MkLabel(pnlTop, 1010, 8, 90, 16, 'Leverage akun', clrDim, 8, False);
  cbLev := TComboBox.Create(Self);
  cbLev.Parent := pnlTop;
  cbLev.Style := csDropDownList;
  cbLev.SetBounds(1010, 26, 90, 24);
  cbLev.Color := clrPanel2;
  cbLev.Font.Color := clrText;
  cbLev.Items.Add('1:50');
  cbLev.Items.Add('1:100');
  cbLev.Items.Add('1:200');
  cbLev.Items.Add('1:500');
  cbLev.Items.Add('1:1000');
  cbLev.ItemIndex := 2;
  cbLev.OnChange := LevChange;

  btnDeposit := MkBtn(pnlTop, 1120, 12, 110, 32, 'Deposit', clrBrand, clrBg, DepositClick);
  btnReset := MkBtn(pnlTop, 1240, 12, 110, 32, 'Reset Akun', clrPanel2, clrBrand, ResetClick);
end;

procedure TExnessForm.BuildLeft;
begin
  pnlLeft := TPanel.Create(Self);
  pnlLeft.Parent := Self;
  pnlLeft.Align := alLeft;
  pnlLeft.Width := 300;
  pnlLeft.BevelOuter := bvNone;
  pnlLeft.Color := clrPanel;

  pnlSearch := TPanel.Create(Self);
  pnlSearch.Parent := pnlLeft;
  pnlSearch.Align := alTop;
  pnlSearch.Height := 66;
  pnlSearch.BevelOuter := bvNone;
  pnlSearch.Color := clrPanel;
  MkLabel(pnlSearch, 12, 8, 200, 18, 'Instrumen', clrText, 10, True);
  edSearch := TEdit.Create(Self);
  edSearch.Parent := pnlSearch;
  edSearch.AutoSize := False;
  edSearch.SetBounds(10, 30, 280, 26);
  edSearch.Color := clrPanel2;
  edSearch.Font.Color := clrText;
  edSearch.Font.Size := 10;
  edSearch.Hint := 'Cari instrumen, contoh: XAU, BTC, ETH';
  edSearch.ShowHint := True;
  edSearch.OnChange := SearchChange;

  lvInst := TListView.Create(Self);
  lvInst.Parent := pnlLeft;
  lvInst.Align := alClient;
  lvInst.ViewStyle := vsReport;
  lvInst.ReadOnly := True;
  lvInst.RowSelect := True;
  lvInst.HideSelection := False;
  lvInst.BorderStyle := bsNone;
  lvInst.Color := clrBg;
  lvInst.Font.Color := clrText;
  lvInst.Font.Name := 'Consolas';
  lvInst.Font.Size := 9;
  lvInst.OnClick := InstClick;
  lvInst.OnCustomDrawSubItem := ListDraw;
  with lvInst.Columns.Add do begin Caption := 'Instrumen'; Width := 92; end;
  with lvInst.Columns.Add do begin Caption := 'Sell'; Width := 80; end;
  with lvInst.Columns.Add do begin Caption := 'Buy'; Width := 80; end;
  with lvInst.Columns.Add do begin Caption := '24j'; Width := 60; end;
end;

procedure TExnessForm.BuildRight;
begin
  pnlRight := TPanel.Create(Self);
  pnlRight.Parent := Self;
  pnlRight.Align := alRight;
  pnlRight.Width := 292;
  pnlRight.BevelOuter := bvNone;
  pnlRight.Color := clrPanel;

  lblTkSym := MkLabel(pnlRight, 14, 8, 264, 26, '-', clrText, 15, True);
  lblTkSub := MkLabel(pnlRight, 14, 36, 264, 16, '', clrDim, 8, False);

  tabMarket := MkBtn(pnlRight, 14, 62, 128, 28, 'Market', clrBrand, clrBg, TypeClick);
  tabMarket.Tag := 0;
  tabPend := MkBtn(pnlRight, 148, 62, 128, 28, 'Pending', clrPanel2, clrDim, TypeClick);
  tabPend.Tag := 1;

  MkLabel(pnlRight, 14, 102, 200, 16, 'Volume (lot)', clrDim, 8, False);
  btnLotMinus := MkBtn(pnlRight, 14, 120, 34, 30, '-', clrPanel2, clrText, LotClick);
  btnLotMinus.Tag := -1;
  edLots := MkEdit(pnlRight, 52, 120, 186, 30);
  edLots.Text := '0.01';
  btnLotPlus := MkBtn(pnlRight, 242, 120, 34, 30, '+', clrPanel2, clrText, LotClick);
  btnLotPlus.Tag := 1;

  lblPendCap := MkLabel(pnlRight, 14, 160, 260, 16, 'Harga pending (Limit / Stop otomatis)', clrDim, 8, False);
  edPend := MkEdit(pnlRight, 14, 178, 262, 30);

  MkLabel(pnlRight, 14, 216, 200, 16, 'Take Profit (harga, opsional)', clrDim, 8, False);
  edTP := MkEdit(pnlRight, 14, 234, 262, 30);
  MkLabel(pnlRight, 14, 272, 200, 16, 'Stop Loss (harga, opsional)', clrDim, 8, False);
  edSL := MkEdit(pnlRight, 14, 290, 262, 30);

  lblMargin := MkLabel(pnlRight, 14, 332, 264, 16, '', clrDim, 9, False);
  lblContract := MkLabel(pnlRight, 14, 350, 264, 16, '', clrDim, 9, False);
  lblSpread := MkLabel(pnlRight, 14, 368, 264, 16, '', clrDim, 9, False);

  btnSell := MkBtn(pnlRight, 14, 396, 128, 62, '', clrSellX, clrText, SellClick);
  MkLabel(btnSell, 0, 6, 128, 16, 'Sell', clrText, 9, True).Alignment := taCenter;
  lblSellP := MkLabel(btnSell, 0, 26, 128, 26, '-', clrText, 13, True);
  lblSellP.Alignment := taCenter;
  btnBuy := MkBtn(pnlRight, 148, 396, 128, 62, '', clrBuyX, clrText, BuyClick);
  MkLabel(btnBuy, 0, 6, 128, 16, 'Buy', clrText, 9, True).Alignment := taCenter;
  lblBuyP := MkLabel(btnBuy, 0, 26, 128, 26, '-', clrText, 13, True);
  lblBuyP.Alignment := taCenter;

  lblMsg := MkLabel(pnlRight, 14, 470, 264, 80, '', clrDim, 9, False);
  lblMsg.WordWrap := True;
end;

procedure TExnessForm.BuildCenter;
var
  I: Integer;
begin
  pnlCenter := TPanel.Create(Self);
  pnlCenter.Parent := Self;
  pnlCenter.Align := alClient;
  pnlCenter.BevelOuter := bvNone;
  pnlCenter.Color := clrBg;

  pnlHead := TPanel.Create(Self);
  pnlHead.Parent := pnlCenter;
  pnlHead.Align := alTop;
  pnlHead.Top := 0;
  pnlHead.Height := 48;
  pnlHead.BevelOuter := bvNone;
  pnlHead.Color := clrPanel;
  lblChSym := MkLabel(pnlHead, 14, 8, 200, 32, '-', clrText, 18, True);
  lblChPrice := MkLabel(pnlHead, 230, 8, 200, 32, '-', clrUp, 18, True);
  lblChChg := MkLabel(pnlHead, 440, 14, 200, 22, '', clrUp, 11, True);

  pnlTF := TPanel.Create(Self);
  pnlTF.Parent := pnlCenter;
  pnlTF.Align := alTop;
  pnlTF.Top := 49;
  pnlTF.Height := 34;
  pnlTF.BevelOuter := bvNone;
  pnlTF.Color := clrPanel;
  MkLabel(pnlTF, 12, 9, 70, 18, 'Timeframe', clrDim, 9, False);
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

procedure TExnessForm.BuildBottom;
begin
  pnlTabs := TPanel.Create(Self);
  pnlTabs.Parent := pnlBottom;
  pnlTabs.Align := alTop;
  pnlTabs.Height := 36;
  pnlTabs.BevelOuter := bvNone;
  pnlTabs.Color := clrPanel;

  tabPos := MkBtn(pnlTabs, 6, 4, 130, 28, 'Posisi Terbuka', clrBrand, clrBg, TabClick);
  tabPos.Tag := 0;
  tabOrd := MkBtn(pnlTabs, 142, 4, 120, 28, 'Order Pending', clrPanel2, clrDim, TabClick);
  tabOrd.Tag := 1;
  tabHist := MkBtn(pnlTabs, 268, 4, 100, 28, 'Riwayat', clrPanel2, clrDim, TabClick);
  tabHist.Tag := 2;

  btnMod := MkBtn(pnlTabs, 400, 4, 120, 28, 'Ubah TP / SL', clrBrand, clrBg, ModClick);
  btnCloseSel := MkBtn(pnlTabs, 526, 4, 120, 28, 'Tutup Posisi', clrPanel2, clrText, CloseSelClick);
  btnCloseAll := MkBtn(pnlTabs, 652, 4, 110, 28, 'Tutup Semua', clrPanel2, clrText, CloseAllClick);
  btnCancel := MkBtn(pnlTabs, 400, 4, 130, 28, 'Batalkan Order', clrPanel2, clrText, CancelClick);

  lvPos := MkList(pnlBottom, ['ID', 'Instrumen', 'Tipe', 'Lot', 'Harga Buka', 'Harga Kini',
    'TP', 'SL', 'Profit (USD)', 'Waktu'], [80, 100, 60, 60, 110, 110, 100, 100, 120, 130]);
  lvOrd := MkList(pnlBottom, ['ID', 'Instrumen', 'Tipe', 'Lot', 'Harga Order', 'Harga Kini',
    'TP', 'SL', 'Waktu'], [80, 100, 100, 60, 110, 110, 100, 100, 130]);
  lvHist := MkList(pnlBottom, ['Waktu Tutup', 'ID', 'Instrumen', 'Tipe', 'Lot', 'Harga Buka',
    'Harga Tutup', 'Profit (USD)', 'Keterangan'], [130, 80, 100, 70, 60, 110, 110, 120, 140]);
end;

procedure TExnessForm.BuildInst;
const
  Favs: array[0..7] of string = ('XAUUSDT', 'BTCUSDT', 'ETHUSDT', 'SOLUSDT', 'XRPUSDT',
    'BNBUSDT', 'DOGEUSDT', 'LTCUSDT');
var
  I: Integer;
  Rest: TStringList;
  Q, S: string;
begin
  Rest := TStringList.Create;
  try
    FInst.Clear;
    Q := UpperCase(Trim(edSearch.Text));
    for I := 0 to High(Favs) do
      if (FSymbols.IndexOf(Favs[I]) >= 0) and
         ((Q = '') or (Pos(Q, Favs[I]) > 0) or (Pos(Q, DispName(Favs[I])) > 0)) then
        FInst.Add(Favs[I]);
    for I := 0 to FSymbols.Count - 1 do
    begin
      S := FSymbols[I];
      if FInst.IndexOf(S) >= 0 then
        Continue;
      if (Q <> '') and (Pos(Q, S) = 0) then
        Continue;
      Rest.Add(S);
    end;
    Rest.Sort;
    for I := 0 to Rest.Count - 1 do
      if FInst.Count < 700 then
        FInst.Add(Rest[I]);
  finally
    Rest.Free;
  end;
  lvInst.Items.BeginUpdate;
  try
    lvInst.Items.Clear;
    for I := 0 to FInst.Count - 1 do
      lvInst.Items.Add.Caption := DispName(FInst[I]);
  finally
    lvInst.Items.EndUpdate;
  end;
  UpdateInst;
end;

{ ---------- harga & akun ---------- }

function TExnessForm.MidOf(const Sym: string): Double;
var
  Q: TDemoQuote;
begin
  Result := 0;
  if (Sym = FSym) and (FLast > 0) then
    Result := FLast
  else if Assigned(FQuoteFn) and FQuoteFn(Sym, Q) then
    Result := Q.Price;
end;

function TExnessForm.BidOf(const Sym: string): Double;
begin
  Result := MidOf(Sym);
  Result := Result * (1 - SpreadFrac(Sym) / 2);
end;

function TExnessForm.AskOf(const Sym: string): Double;
begin
  Result := MidOf(Sym);
  Result := Result * (1 + SpreadFrac(Sym) / 2);
end;

function TExnessForm.ProfitOf(const P: TXPos): Double;
var
  C: Double;
begin
  if P.Dir > 0 then C := BidOf(P.Sym) else C := AskOf(P.Sym);
  if C <= 0 then
    Result := 0
  else
    Result := P.Dir * (C - P.Open) * P.Lots * P.CS;
end;

function TExnessForm.TotalProfit: Double;
var
  I: Integer;
begin
  Result := 0;
  for I := 0 to High(FPos) do
    Result := Result + ProfitOf(FPos[I]);
end;

function TExnessForm.Equity: Double;
begin
  Result := FWallet + TotalProfit;
end;

function TExnessForm.UsedMargin: Double;
var
  I: Integer;
begin
  Result := 0;
  for I := 0 to High(FPos) do
    Result := Result + FPos[I].Lots * FPos[I].CS * FPos[I].Open / FAcctLev;
end;

function TExnessForm.FreeMargin: Double;
begin
  Result := Equity - UsedMargin;
end;

procedure TExnessForm.DeletePos(I: Integer);
var
  J: Integer;
begin
  for J := I to High(FPos) - 1 do
    FPos[J] := FPos[J + 1];
  SetLength(FPos, Length(FPos) - 1);
end;

procedure TExnessForm.DeleteOrd(I: Integer);
var
  J: Integer;
begin
  for J := I to High(FOrd) - 1 do
    FOrd[J] := FOrd[J + 1];
  SetLength(FOrd, Length(FOrd) - 1);
end;

procedure TExnessForm.AddHist(const P: TXPos; ClosePrice, Pnl: Double; const Why: string);
var
  J: Integer;
begin
  SetLength(FHist, Length(FHist) + 1);
  for J := High(FHist) downto 1 do
    FHist[J] := FHist[J - 1];
  FHist[0].T := FormatDateTime('dd/mm hh:nn:ss', Now);
  FHist[0].Id := IntToStr(P.Id);
  FHist[0].Sym := DispName(P.Sym);
  FHist[0].Typ := TypText(P.Dir, 0, False);
  FHist[0].Lots := Format('%.2f', [P.Lots]);
  FHist[0].Op := XNum(P.Open);
  FHist[0].Cl := XNum(ClosePrice);
  FHist[0].Pnl := XSigned(Pnl);
  FHist[0].Why := Why;
  if Length(FHist) > 300 then
    SetLength(FHist, 300);
end;

procedure TExnessForm.OpenPos(const Sym: string; Dir: Integer; Lots, CS, Price, TP, SL: Double);
var
  N: Integer;
begin
  N := Length(FPos);
  SetLength(FPos, N + 1);
  FPos[N].Id := FNextId;
  Inc(FNextId);
  FPos[N].Sym := Sym;
  FPos[N].Dir := Dir;
  FPos[N].Lots := Lots;
  FPos[N].CS := CS;
  FPos[N].Open := Price;
  FPos[N].TP := TP;
  FPos[N].SL := SL;
  FPos[N].Opened := Now;
end;

procedure TExnessForm.ClosePos(I: Integer; Price: Double; const Why: string);
var
  P: TXPos;
  Pnl: Double;
begin
  P := FPos[I];
  Pnl := P.Dir * (Price - P.Open) * P.Lots * P.CS;
  FWallet := FWallet + Pnl;
  if FWallet < 0 then
    FWallet := 0;      // proteksi saldo negatif seperti Exness
  AddHist(P, Price, Pnl, Why);
  DeletePos(I);
end;

procedure TExnessForm.Say(const Txt: string; Ok: Boolean);
begin
  lblMsg.Caption := Txt;
  if Ok then
    lblMsg.Font.Color := clrUp
  else
    lblMsg.Font.Color := clrDown;
end;

procedure TExnessForm.PlaceOrder(Dir: Integer);
var
  Lots, Px, TP, SL, CS, Need, B, A: Double;
  Kind, N: Integer;
begin
  Lots := XParse(edLots.Text);
  Lots := Round(Lots * 100) / 100;
  if (Lots < MinLot) or (Lots > MaxLot) then
  begin
    Say('Volume harus 0.01 - 100 lot.', False);
    Exit;
  end;
  B := BidOf(FSym);
  A := AskOf(FSym);
  if (B <= 0) or (A <= 0) then
  begin
    Say('Harga belum tersedia, coba lagi sebentar.', False);
    Exit;
  end;
  TP := XParse(edTP.Text);
  SL := XParse(edSL.Text);
  Kind := 0;
  if FPending then
  begin
    Px := XParse(edPend.Text);
    if Px <= 0 then
    begin
      Say('Isi harga pending.', False);
      Exit;
    end;
    if Dir > 0 then
    begin
      if Px < A then Kind := 0
      else if Px > A then Kind := 1
      else begin Say('Harga pending sama dengan harga pasar.', False); Exit; end;
    end
    else
    begin
      if Px > B then Kind := 0
      else if Px < B then Kind := 1
      else begin Say('Harga pending sama dengan harga pasar.', False); Exit; end;
    end;
  end
  else if Dir > 0 then
    Px := A
  else
    Px := B;

  if Dir > 0 then
  begin
    if ((TP > 0) and (TP <= Px)) or ((SL > 0) and (SL >= Px)) then
    begin
      Say('Buy: Take Profit harus di atas dan Stop Loss di bawah harga order.', False);
      Exit;
    end;
  end
  else if ((TP > 0) and (TP >= Px)) or ((SL > 0) and (SL <= Px)) then
  begin
    Say('Sell: Take Profit harus di bawah dan Stop Loss di atas harga order.', False);
    Exit;
  end;

  CS := ContractSize(FSym, Px);
  Need := Lots * CS * Px / FAcctLev;
  if Need > FreeMargin then
  begin
    Say('Margin tidak cukup. Dibutuhkan ' + XMoney(Need) + ' USD, free margin ' +
      XMoney(FreeMargin) + ' USD.', False);
    Exit;
  end;

  if FPending then
  begin
    N := Length(FOrd);
    SetLength(FOrd, N + 1);
    FOrd[N].Id := FNextId;
    Inc(FNextId);
    FOrd[N].Sym := FSym;
    FOrd[N].Dir := Dir;
    FOrd[N].Kind := Kind;
    FOrd[N].Lots := Lots;
    FOrd[N].CS := CS;
    FOrd[N].Price := Px;
    FOrd[N].TP := TP;
    FOrd[N].SL := SL;
    FOrd[N].Time := Now;
    Say('Order ' + TypText(Dir, Kind, True) + ' ' + Format('%.2f', [Lots]) + ' lot ' +
      DispName(FSym) + ' @ ' + XNum(Px) + ' dipasang.', True);
    SetTab(1);
  end
  else
  begin
    OpenPos(FSym, Dir, Lots, CS, Px, TP, SL);
    Say(TypText(Dir, 0, False) + ' ' + Format('%.2f', [Lots]) + ' lot ' + DispName(FSym) +
      ' dieksekusi @ ' + XNum(Px) + '.', True);
    SetTab(0);
  end;
  SaveState;
  RefreshLists;
  UpdateAccount;
end;

{ ---------- simpan / muat ---------- }

procedure TExnessForm.SaveState;
var
  L: TStringList;
  I: Integer;
begin
  L := TStringList.Create;
  try
    L.Add('W|' + FloatToStr(FWallet) + '|' + IntToStr(FNextId) + '|' + IntToStr(FAcctLev));
    for I := 0 to High(FPos) do
      with FPos[I] do
        L.Add('P|' + IntToStr(Id) + '|' + Sym + '|' + IntToStr(Dir) + '|' + FloatToStr(Lots) +
          '|' + FloatToStr(CS) + '|' + FloatToStr(Open) + '|' + FloatToStr(TP) + '|' +
          FloatToStr(SL) + '|' + FloatToStr(Opened));
    for I := 0 to High(FOrd) do
      with FOrd[I] do
        L.Add('O|' + IntToStr(Id) + '|' + Sym + '|' + IntToStr(Dir) + '|' + IntToStr(Kind) +
          '|' + FloatToStr(Lots) + '|' + FloatToStr(CS) + '|' + FloatToStr(Price) + '|' +
          FloatToStr(TP) + '|' + FloatToStr(SL) + '|' + FloatToStr(Time));
    for I := 0 to High(FHist) do
      with FHist[I] do
        L.Add('H|' + T + '|' + Id + '|' + Sym + '|' + Typ + '|' + Lots + '|' + Op + '|' +
          Cl + '|' + Pnl + '|' + Why);
    try
      L.SaveToFile(ExtractFilePath(ParamStr(0)) + SaveFile);
    except
    end;
  finally
    L.Free;
  end;
end;

procedure TExnessForm.LoadState;
var
  L, F: TStringList;
  I, N, Idx: Integer;
  Fn: string;
begin
  Fn := ExtractFilePath(ParamStr(0)) + SaveFile;
  if not FileExists(Fn) then
  begin
    UpdateAccount;
    Exit;
  end;
  L := TStringList.Create;
  try
    try
      L.LoadFromFile(Fn);
    except
      L.Clear;
    end;
    for I := 0 to L.Count - 1 do
    begin
      F := XSplit(L[I]);
      try
        if (F[0] = 'W') and (F.Count >= 4) then
        begin
          FWallet := XParse(F[1]);
          FNextId := Trunc(XParse(F[2]));
          FAcctLev := Trunc(XParse(F[3]));
          if FAcctLev < 1 then FAcctLev := 200;
          Idx := cbLev.Items.IndexOf('1:' + IntToStr(FAcctLev));
          if Idx >= 0 then
            cbLev.ItemIndex := Idx;
        end
        else if (F[0] = 'P') and (F.Count >= 10) then
        begin
          N := Length(FPos);
          SetLength(FPos, N + 1);
          FPos[N].Id := Trunc(XParse(F[1]));
          FPos[N].Sym := F[2];
          FPos[N].Dir := Trunc(XParse(F[3]));
          FPos[N].Lots := XParse(F[4]);
          FPos[N].CS := XParse(F[5]);
          FPos[N].Open := XParse(F[6]);
          FPos[N].TP := XParse(F[7]);
          FPos[N].SL := XParse(F[8]);
          FPos[N].Opened := XParse(F[9]);
        end
        else if (F[0] = 'O') and (F.Count >= 11) then
        begin
          N := Length(FOrd);
          SetLength(FOrd, N + 1);
          FOrd[N].Id := Trunc(XParse(F[1]));
          FOrd[N].Sym := F[2];
          FOrd[N].Dir := Trunc(XParse(F[3]));
          FOrd[N].Kind := Trunc(XParse(F[4]));
          FOrd[N].Lots := XParse(F[5]);
          FOrd[N].CS := XParse(F[6]);
          FOrd[N].Price := XParse(F[7]);
          FOrd[N].TP := XParse(F[8]);
          FOrd[N].SL := XParse(F[9]);
          FOrd[N].Time := XParse(F[10]);
        end
        else if (F[0] = 'H') and (F.Count >= 10) then
        begin
          N := Length(FHist);
          SetLength(FHist, N + 1);
          FHist[N].T := F[1];
          FHist[N].Id := F[2];
          FHist[N].Sym := F[3];
          FHist[N].Typ := F[4];
          FHist[N].Lots := F[5];
          FHist[N].Op := F[6];
          FHist[N].Cl := F[7];
          FHist[N].Pnl := F[8];
          FHist[N].Why := F[9];
        end;
      finally
        F.Free;
      end;
    end;
  finally
    L.Free;
  end;
  UpdateAccount;
  RefreshLists;
end;

procedure TExnessForm.ResetAccount;
begin
  FWallet := StartBalance;
  FNextId := 100001;
  SetLength(FPos, 0);
  SetLength(FOrd, 0);
  SetLength(FHist, 0);
  SaveState;
  RefreshLists;
  UpdateAccount;
  Say('Akun demo di-reset ke ' + XMoney(StartBalance) + ' USD.', True);
end;

{ ---------- grafik & data ---------- }

procedure TExnessForm.SwitchSym(const Sym: string);
begin
  if Sym = '' then
    Exit;
  FSym := Sym;
  FLast := 0;
  ResetView(FCV);
  FNoMoreHistory := False;
  SetLength(FK, 0);
  ClearAnalysis(FA);
  edPend.Text := '';
  pbChart.Invalidate;
  RequestDetail;
  UpdateHeader;
  UpdateTicket;
end;

procedure TExnessForm.RequestDetail;
begin
  if FSym = '' then
    Exit;
  Inc(FReqId);
  TDetailThread.Create(Handle, FSym, FTF, FReqId);
end;

procedure TExnessForm.LoadOlderIfNeeded;
begin
  if FCV.AtStart and not FOlderBusy and not FNoMoreHistory and (Length(FK) > 0) then
  begin
    FOlderBusy := True;
    TOlderThread.Create(Handle, FSym, FTF, FK[0].OpenTime - 1);
  end;
end;

procedure TExnessForm.LiveTick(Sender: TObject);
begin
  if not Visible or (FSym = '') then
    Exit;
  if (Length(FK) > 0) and not (FLiveBusy and (GetTickCount - FLiveStart < 10000)) then
  begin
    FLiveBusy := True;
    FLiveStart := GetTickCount;
    TLiveThread.Create(Handle, FSym, FTF);
  end;
end;

procedure TExnessForm.DetailTick(Sender: TObject);
begin
  if Visible then
    RequestDetail;
end;

procedure TExnessForm.WMLive(var M: TMessage);
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
    FLast := FK[High(FK)].C;
    pbChart.Invalidate;
  finally
    D.Free;
  end;
end;

procedure TExnessForm.WMDetail(var M: TMessage);
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
      FLast := FK[High(FK)].C;
    pbChart.Invalidate;
  finally
    D.Free;
  end;
end;

procedure TExnessForm.WMOlder(var M: TMessage);
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

{ ---------- tampilan ---------- }

procedure TExnessForm.UpdateTFButtons;
var
  I: Integer;
begin
  for I := 0 to ChartTFCount - 1 do
    if ChartTFApi[I] = FTF then
    begin
      FTFBtns[I].Color := clrBrand;
      FTFBtns[I].Font.Color := clrBg;
    end
    else
    begin
      FTFBtns[I].Color := clrPanel2;
      FTFBtns[I].Font.Color := clrDim;
    end;
end;

procedure TExnessForm.SetPending(P: Boolean);
begin
  FPending := P;
  if P then
  begin
    tabPend.Color := clrBrand;
    tabPend.Font.Color := clrBg;
    tabMarket.Color := clrPanel2;
    tabMarket.Font.Color := clrDim;
  end
  else
  begin
    tabMarket.Color := clrBrand;
    tabMarket.Font.Color := clrBg;
    tabPend.Color := clrPanel2;
    tabPend.Font.Color := clrDim;
  end;
  lblPendCap.Visible := P;
  edPend.Visible := P;
  if P and (edPend.Text = '') and (MidOf(FSym) > 0) then
    edPend.Text := XNum(MidOf(FSym));
  UpdateTicket;
end;

procedure TExnessForm.SetTab(T: Integer);
begin
  FTab := T;
  lvPos.Visible := T = 0;
  lvOrd.Visible := T = 1;
  lvHist.Visible := T = 2;
  if T = 0 then begin tabPos.Color := clrBrand; tabPos.Font.Color := clrBg; end
  else begin tabPos.Color := clrPanel2; tabPos.Font.Color := clrDim; end;
  if T = 1 then begin tabOrd.Color := clrBrand; tabOrd.Font.Color := clrBg; end
  else begin tabOrd.Color := clrPanel2; tabOrd.Font.Color := clrDim; end;
  if T = 2 then begin tabHist.Color := clrBrand; tabHist.Font.Color := clrBg; end
  else begin tabHist.Color := clrPanel2; tabHist.Font.Color := clrDim; end;
  btnMod.Visible := T = 0;
  btnCloseSel.Visible := T = 0;
  btnCloseAll.Visible := T = 0;
  btnCancel.Visible := T = 1;
end;

procedure TExnessForm.UpdateHeader;
begin
  lblChSym.Caption := DispName(FSym);
  lblTkSym.Caption := DispName(FSym);
  if FSym = 'XAUUSDT' then
    lblTkSub.Caption := 'Emas vs USD  |  1 lot = 100 oz'
  else
    lblTkSub.Caption := 'Kontrak CFD  |  Standard';
end;

procedure TExnessForm.UpdateAccount;
var
  Eq, Mar, Pr: Double;
begin
  Pr := TotalProfit;
  Eq := FWallet + Pr;
  Mar := UsedMargin;
  lblBal.Caption := XMoney(FWallet);
  lblEq.Caption := XMoney(Eq);
  lblMar.Caption := XMoney(Mar);
  lblFree.Caption := XMoney(Eq - Mar);
  if Mar > 0 then
    lblLvl.Caption := FormatFloat('#,##0.00', Eq / Mar * 100) + '%'
  else
    lblLvl.Caption := '-';
  lblPnl.Caption := XSigned(Pr);
  if Pr >= 0 then
    lblPnl.Font.Color := clrUp
  else
    lblPnl.Font.Color := clrDown;
  if (Mar > 0) and (Eq / Mar * 100 < 60) then
    lblLvl.Font.Color := clrDown
  else
    lblLvl.Font.Color := clrText;
end;

procedure TExnessForm.UpdateTicket;
var
  B, A, Lots, CS, Px: Double;
begin
  B := BidOf(FSym);
  A := AskOf(FSym);
  if B > 0 then lblSellP.Caption := XNum(B) else lblSellP.Caption := '-';
  if A > 0 then lblBuyP.Caption := XNum(A) else lblBuyP.Caption := '-';
  if A <= 0 then
  begin
    lblMargin.Caption := '';
    lblContract.Caption := '';
    lblSpread.Caption := '';
    Exit;
  end;
  Lots := XParse(edLots.Text);
  CS := ContractSize(FSym, A);
  Px := A;
  lblContract.Caption := '1 lot = ' + FormatFloat('#,##0.##', CS) + ' unit  (nilai ' +
    XMoney(CS * Px) + ' USD)';
  lblMargin.Caption := 'Margin: ' + XMoney(Lots * CS * Px / FAcctLev) + ' USD  (1:' +
    IntToStr(FAcctLev) + ')';
  lblSpread.Caption := 'Spread: ' + XNum(A - B) + '  (' + Format('%.2f', [(A - B) / A * 10000]) + ' bps)';
end;

procedure TExnessForm.UpdateInst;
var
  I: Integer;
  Q: TDemoQuote;
  B, A: Double;
  Chg: string;
begin
  if not Assigned(FQuoteFn) then
    Exit;
  for I := 0 to lvInst.Items.Count - 1 do
  begin
    if not FQuoteFn(FInst[I], Q) then
      Continue;
    B := Q.Price * (1 - SpreadFrac(FInst[I]) / 2);
    A := Q.Price * (1 + SpreadFrac(FInst[I]) / 2);
    if Q.Chg >= 0 then
      Chg := '+' + Format('%.2f', [Q.Chg]) + '%'
    else
      Chg := Format('%.2f', [Q.Chg]) + '%';
    XSetItem(lvInst.Items[I], [DispName(FInst[I]), XNum(B), XNum(A), Chg]);
  end;
end;

procedure TExnessForm.RefreshLists;
var
  I, N: Integer;
  Item: TListItem;
  Cur: Double;
begin
  // posisi
  N := Length(FPos);
  while lvPos.Items.Count < N do lvPos.Items.Add;
  while lvPos.Items.Count > N do lvPos.Items.Delete(lvPos.Items.Count - 1);
  for I := 0 to N - 1 do
  begin
    if FPos[I].Dir > 0 then Cur := BidOf(FPos[I].Sym) else Cur := AskOf(FPos[I].Sym);
    XSetItem(lvPos.Items[I], [IntToStr(FPos[I].Id), DispName(FPos[I].Sym),
      TypText(FPos[I].Dir, 0, False), Format('%.2f', [FPos[I].Lots]), XNum(FPos[I].Open),
      XNum(Cur), XOpt(FPos[I].TP), XOpt(FPos[I].SL), XSigned(ProfitOf(FPos[I])),
      FormatDateTime('dd/mm hh:nn:ss', FPos[I].Opened)]);
  end;
  // order pending
  N := Length(FOrd);
  while lvOrd.Items.Count < N do lvOrd.Items.Add;
  while lvOrd.Items.Count > N do lvOrd.Items.Delete(lvOrd.Items.Count - 1);
  for I := 0 to N - 1 do
  begin
    if FOrd[I].Dir > 0 then Cur := AskOf(FOrd[I].Sym) else Cur := BidOf(FOrd[I].Sym);
    XSetItem(lvOrd.Items[I], [IntToStr(FOrd[I].Id), DispName(FOrd[I].Sym),
      TypText(FOrd[I].Dir, FOrd[I].Kind, True), Format('%.2f', [FOrd[I].Lots]),
      XNum(FOrd[I].Price), XNum(Cur), XOpt(FOrd[I].TP), XOpt(FOrd[I].SL),
      FormatDateTime('dd/mm hh:nn:ss', FOrd[I].Time)]);
  end;
  // riwayat
  N := Length(FHist);
  if lvHist.Items.Count <> N then
  begin
    lvHist.Items.BeginUpdate;
    try
      while lvHist.Items.Count < N do lvHist.Items.Add;
      while lvHist.Items.Count > N do lvHist.Items.Delete(lvHist.Items.Count - 1);
      for I := 0 to N - 1 do
      begin
        Item := lvHist.Items[I];
        XSetItem(Item, [FHist[I].T, FHist[I].Id, FHist[I].Sym, FHist[I].Typ, FHist[I].Lots,
          FHist[I].Op, FHist[I].Cl, FHist[I].Pnl, FHist[I].Why]);
      end;
    finally
      lvHist.Items.EndUpdate;
    end;
  end;
end;

procedure TExnessForm.Tick(Sender: TObject);
var
  I: Integer;
  B, A: Double;
  Hit: Boolean;
  Worst, WI: Integer;
  WP, PP: Double;
begin
  Inc(FTick);
  if not Assigned(FQuoteFn) then
    Exit;

  // order pending
  I := 0;
  while I <= High(FOrd) do
  begin
    B := BidOf(FOrd[I].Sym);
    A := AskOf(FOrd[I].Sym);
    Hit := False;
    if (B > 0) and (A > 0) then
    begin
      if FOrd[I].Dir > 0 then
      begin
        if FOrd[I].Kind = 0 then Hit := A <= FOrd[I].Price else Hit := A >= FOrd[I].Price;
      end
      else if FOrd[I].Kind = 0 then
        Hit := B >= FOrd[I].Price
      else
        Hit := B <= FOrd[I].Price;
    end;
    if Hit then
    begin
      if FOrd[I].Lots * FOrd[I].CS * FOrd[I].Price / FAcctLev > FreeMargin then
        Say('Order pending #' + IntToStr(FOrd[I].Id) + ' dibatalkan: margin tidak cukup.', False)
      else
      begin
        OpenPos(FOrd[I].Sym, FOrd[I].Dir, FOrd[I].Lots, FOrd[I].CS, FOrd[I].Price,
          FOrd[I].TP, FOrd[I].SL);
        Say('Order pending #' + IntToStr(FOrd[I].Id) + ' (' +
          TypText(FOrd[I].Dir, FOrd[I].Kind, True) + ') tereksekusi @ ' +
          XNum(FOrd[I].Price) + '.', True);
      end;
      DeleteOrd(I);
    end
    else
      Inc(I);
  end;

  // TP / SL
  for I := High(FPos) downto 0 do
  begin
    B := BidOf(FPos[I].Sym);
    A := AskOf(FPos[I].Sym);
    if (B <= 0) or (A <= 0) then
      Continue;
    if FPos[I].Dir > 0 then
    begin
      if (FPos[I].TP > 0) and (B >= FPos[I].TP) then
        ClosePos(I, FPos[I].TP, 'Take Profit')
      else if (FPos[I].SL > 0) and (B <= FPos[I].SL) then
        ClosePos(I, FPos[I].SL, 'Stop Loss');
    end
    else
    begin
      if (FPos[I].TP > 0) and (A <= FPos[I].TP) then
        ClosePos(I, FPos[I].TP, 'Take Profit')
      else if (FPos[I].SL > 0) and (A >= FPos[I].SL) then
        ClosePos(I, FPos[I].SL, 'Stop Loss');
    end;
  end;

  // stop out (level 0%): tutup posisi yang paling rugi
  if (Length(FPos) > 0) and (UsedMargin > 0) and (Equity <= 0) then
  begin
    Worst := -1;
    WP := 0;
    WI := 0;
    for I := 0 to High(FPos) do
    begin
      PP := ProfitOf(FPos[I]);
      if (Worst < 0) or (PP < WP) then
      begin
        Worst := I;
        WP := PP;
        WI := FPos[I].Id;
      end;
    end;
    if Worst >= 0 then
    begin
      if FPos[Worst].Dir > 0 then PP := BidOf(FPos[Worst].Sym) else PP := AskOf(FPos[Worst].Sym);
      ClosePos(Worst, PP, 'Stop Out');
      Say('STOP OUT: posisi #' + IntToStr(WI) + ' ditutup otomatis (margin habis).', False);
    end;
  end;

  UpdateTicket;
  UpdateAccount;
  RefreshLists;
  if (FTick mod 2) = 0 then
    UpdateInst;
  if FLast > 0 then
    lblChPrice.Caption := XNum(FLast);
  if Length(FK) > 1 then
  begin
    // perubahan terhadap penutupan candle sebelumnya
    PP := FK[High(FK) - 1].C;
    if PP > 0 then
    begin
      lblChChg.Caption := XSigned((FLast - PP) / PP * 100) + '%';
      if FLast >= PP then
      begin
        lblChChg.Font.Color := clrUp;
        lblChPrice.Font.Color := clrUp;
      end
      else
      begin
        lblChChg.Font.Color := clrDown;
        lblChPrice.Font.Color := clrDown;
      end;
    end;
  end;
  if (FTick mod 5) = 0 then
    SaveState;
end;

{ ---------- event ---------- }

procedure TExnessForm.XClose(Sender: TObject; var Action: TCloseAction);
begin
  SaveState;
  Action := caHide;
end;

procedure TExnessForm.SearchChange(Sender: TObject);
begin
  BuildInst;
end;

procedure TExnessForm.InstClick(Sender: TObject);
begin
  if (lvInst.Selected <> nil) and (lvInst.Selected.Index < FInst.Count) then
    SwitchSym(FInst[lvInst.Selected.Index]);
end;

procedure TExnessForm.TFClick(Sender: TObject);
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

procedure TExnessForm.ChartPaint(Sender: TObject);
begin
  DrawCandles(pbChart.Canvas, pbChart.ClientRect, FK, FA, FHoverX,
    DispName(FSym) + '  ' + ChartTFLabel(FTF), FCV);
end;

procedure TExnessForm.ChartMouseMove(Sender: TObject; Shift: TShiftState; X, Y: Integer);
begin
  FHoverX := X;
  if ViewMouseMove(FCV, X, Y) then
    LoadOlderIfNeeded;
  pbChart.Invalidate;
end;

procedure TExnessForm.ChartMouseDown(Sender: TObject; Button: TMouseButton;
  Shift: TShiftState; X, Y: Integer);
begin
  if Button <> mbLeft then
    Exit;
  ViewMouseDown(FCV, X, Y);
  pbChart.Cursor := crSizeAll;
end;

procedure TExnessForm.ChartMouseUp(Sender: TObject; Button: TMouseButton;
  Shift: TShiftState; X, Y: Integer);
begin
  ViewMouseUp(FCV);
  pbChart.Cursor := crCross;
end;

procedure TExnessForm.ChartDblClick(Sender: TObject);
begin
  ResetView(FCV);
  pbChart.Invalidate;
end;

procedure TExnessForm.TypeClick(Sender: TObject);
begin
  SetPending(TPanel(Sender).Tag = 1);
end;

procedure TExnessForm.LotClick(Sender: TObject);
var
  L: Double;
begin
  L := XParse(edLots.Text) + TPanel(Sender).Tag * 0.01;
  if L < MinLot then L := MinLot;
  if L > MaxLot then L := MaxLot;
  edLots.Text := Format('%.2f', [L]);
end;

procedure TExnessForm.FieldChange(Sender: TObject);
begin
  UpdateTicket;
end;

procedure TExnessForm.BuyClick(Sender: TObject);
begin
  PlaceOrder(1);
end;

procedure TExnessForm.SellClick(Sender: TObject);
begin
  PlaceOrder(-1);
end;

procedure TExnessForm.TabClick(Sender: TObject);
begin
  SetTab(TPanel(Sender).Tag);
end;

procedure TExnessForm.ModClick(Sender: TObject);
var
  I: Integer;
  ST, SS: string;
  TP, SL, Px: Double;
begin
  if lvPos.Selected = nil then
  begin
    Say('Pilih posisi dulu di tabel Posisi Terbuka.', False);
    Exit;
  end;
  I := lvPos.Selected.Index;
  if (I < 0) or (I > High(FPos)) then
    Exit;
  if FPos[I].TP > 0 then ST := XNum(FPos[I].TP) else ST := '';
  if FPos[I].SL > 0 then SS := XNum(FPos[I].SL) else SS := '';
  if not InputQuery('Ubah posisi #' + IntToStr(FPos[I].Id), 'Take Profit (kosong = hapus):', ST) then
    Exit;
  if not InputQuery('Ubah posisi #' + IntToStr(FPos[I].Id), 'Stop Loss (kosong = hapus):', SS) then
    Exit;
  TP := XParse(ST);
  SL := XParse(SS);
  if FPos[I].Dir > 0 then Px := BidOf(FPos[I].Sym) else Px := AskOf(FPos[I].Sym);
  if FPos[I].Dir > 0 then
  begin
    if ((TP > 0) and (TP <= Px)) or ((SL > 0) and (SL >= Px)) then
    begin
      Say('Buy: TP harus di atas harga sekarang dan SL di bawahnya.', False);
      Exit;
    end;
  end
  else if ((TP > 0) and (TP >= Px)) or ((SL > 0) and (SL <= Px)) then
  begin
    Say('Sell: TP harus di bawah harga sekarang dan SL di atasnya.', False);
    Exit;
  end;
  FPos[I].TP := TP;
  FPos[I].SL := SL;
  Say('TP/SL posisi #' + IntToStr(FPos[I].Id) + ' diperbarui.', True);
  SaveState;
  RefreshLists;
end;

procedure TExnessForm.CloseSelClick(Sender: TObject);
var
  I: Integer;
  Px: Double;
begin
  if lvPos.Selected = nil then
  begin
    Say('Pilih posisi dulu di tabel Posisi Terbuka.', False);
    Exit;
  end;
  I := lvPos.Selected.Index;
  if (I < 0) or (I > High(FPos)) then
    Exit;
  if FPos[I].Dir > 0 then Px := BidOf(FPos[I].Sym) else Px := AskOf(FPos[I].Sym);
  if Px <= 0 then
    Exit;
  ClosePos(I, Px, 'Ditutup manual');
  Say('Posisi ditutup @ ' + XNum(Px) + '.', True);
  SaveState;
  RefreshLists;
  UpdateAccount;
end;

procedure TExnessForm.CloseAllClick(Sender: TObject);
var
  I: Integer;
  Px: Double;
begin
  if Length(FPos) = 0 then
    Exit;
  if MessageDlg('Tutup semua posisi terbuka?', mtConfirmation, [mbYes, mbNo], 0) <> mrYes then
    Exit;
  for I := High(FPos) downto 0 do
  begin
    if FPos[I].Dir > 0 then Px := BidOf(FPos[I].Sym) else Px := AskOf(FPos[I].Sym);
    if Px > 0 then
      ClosePos(I, Px, 'Ditutup manual');
  end;
  Say('Semua posisi ditutup.', True);
  SaveState;
  RefreshLists;
  UpdateAccount;
end;

procedure TExnessForm.CancelClick(Sender: TObject);
var
  I: Integer;
begin
  if lvOrd.Selected = nil then
  begin
    Say('Pilih order pending dulu.', False);
    Exit;
  end;
  I := lvOrd.Selected.Index;
  if (I < 0) or (I > High(FOrd)) then
    Exit;
  Say('Order pending #' + IntToStr(FOrd[I].Id) + ' dibatalkan.', True);
  DeleteOrd(I);
  SaveState;
  RefreshLists;
end;

procedure TExnessForm.DepositClick(Sender: TObject);
var
  S: string;
  V: Double;
begin
  S := '1000';
  if not InputQuery('Deposit (demo)', 'Jumlah saldo virtual yang ditambahkan (USD):', S) then
    Exit;
  V := XParse(S);
  if (V <= 0) or (V > 1000000) then
  begin
    Say('Jumlah deposit harus antara 0 dan 1.000.000 USD.', False);
    Exit;
  end;
  FWallet := FWallet + V;
  Say('Deposit demo +' + XMoney(V) + ' USD berhasil.', True);
  SaveState;
  UpdateAccount;
end;

procedure TExnessForm.ResetClick(Sender: TObject);
begin
  if MessageDlg('Reset akun demo ke ' + XMoney(StartBalance) +
     ' USD dan hapus semua posisi/riwayat?', mtConfirmation, [mbYes, mbNo], 0) = mrYes then
    ResetAccount;
end;

procedure TExnessForm.LevChange(Sender: TObject);
begin
  FAcctLev := Trunc(XParse(Copy(cbLev.Text, 3, MaxInt)));
  if FAcctLev < 1 then
    FAcctLev := 200;
  UpdateTicket;
  UpdateAccount;
  SaveState;
end;

procedure TExnessForm.ListDraw(Sender: TCustomListView; Item: TListItem;
  SubItem: Integer; State: TCustomDrawState; var DefaultDraw: Boolean);
var
  S: string;
begin
  Sender.Canvas.Font.Color := clrText;
  if Sender = lvInst then
  begin
    if SubItem = 1 then Sender.Canvas.Font.Color := clrSellX
    else if SubItem = 2 then Sender.Canvas.Font.Color := clrBuyX
    else if (SubItem = 3) and (Item.SubItems.Count >= 3) then
    begin
      if Copy(Item.SubItems[2], 1, 1) = '-' then
        Sender.Canvas.Font.Color := clrDown
      else
        Sender.Canvas.Font.Color := clrUp;
    end;
    Exit;
  end;
  if (Sender = lvPos) or (Sender = lvOrd) then
  begin
    if SubItem = 2 then
    begin
      if Copy(Item.SubItems[1], 1, 3) = 'Buy' then
        Sender.Canvas.Font.Color := clrBuyX
      else
        Sender.Canvas.Font.Color := clrSellX;
    end
    else if (Sender = lvPos) and (SubItem = 8) and (Item.SubItems.Count >= 8) then
    begin
      if Copy(Item.SubItems[7], 1, 1) = '-' then
        Sender.Canvas.Font.Color := clrDown
      else
        Sender.Canvas.Font.Color := clrUp;
    end;
    Exit;
  end;
  if Sender = lvHist then
  begin
    if SubItem = 3 then
    begin
      if Item.SubItems.Count >= 3 then S := Item.SubItems[2] else S := '';
      if Copy(S, 1, 3) = 'Buy' then
        Sender.Canvas.Font.Color := clrBuyX
      else
        Sender.Canvas.Font.Color := clrSellX;
    end
    else if (SubItem = 7) and (Item.SubItems.Count >= 7) then
    begin
      if Copy(Item.SubItems[6], 1, 1) = '-' then
        Sender.Canvas.Font.Color := clrDown
      else
        Sender.Canvas.Font.Color := clrUp;
    end;
  end;
end;

end.
