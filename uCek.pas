unit uCek;

{ Cek Grafik: capture grafik + analisa koin ke folder "cek_grafik" (gambar PNG,
  teks analisa, dan daftar index), lalu halaman berisi tabel semua capture.
  Klik satu baris untuk melihat grafik yang tersimpan dan analisanya; tabel
  juga menunjukkan harga kini dan apakah prakiraan saat capture sesuai. }

interface

uses
  Windows, Messages, SysUtils, Classes, Graphics, Controls, Forms, StdCtrls,
  ExtCtrls, ComCtrls, ShellAPI, Math, uAnalysis, uChart, uShot;

type
  TPriceLookup = function(const Sym: string; var Price: Double): Boolean of object;

function SaveCekCapture(const Sym, TF, Title: string; const K: TKlines; const A: TAnalysis;
  View: TChartView; const AnalysisText: string; var Err: string): Boolean;
procedure ShowCekGrafik(Lookup: TPriceLookup);

implementation

const
  CapW = 1280;
  CapH = 640;

type
  TCekEntry = record
    Id, Sym, TF, Signal, Head: string;
    Price: Double;
    Dir: Integer;
  end;

function CekDir: string;
begin
  Result := ExtractFilePath(ParamStr(0)) + 'cek_grafik\';
end;

function IndexFile: string;
begin
  Result := CekDir + 'index.txt';
end;

function ImageFile(const Id: string): string;
begin
  Result := CekDir + Id + '.png';
  if not FileExists(Result) then
    Result := CekDir + Id + '.bmp';
end;

{ ---------- simpan ---------- }

var
  CekForm: TForm = nil;   // diisi unit ini; dipakai untuk memuat ulang daftar

procedure ReloadCek; forward;

function SaveCekCapture(const Sym, TF, Title: string; const K: TKlines; const A: TAnalysis;
  View: TChartView; const AnalysisText: string; var Err: string): Boolean;
var
  Bmp: TBitmap;
  Id, Stamp: string;
  Early: TEarly;
  L: TStringList;
  V: TChartView;
begin
  Result := False;
  Err := '';
  if (Length(K) < 30) or not A.Ok then
  begin
    Err := 'Grafik belum siap. Klik koin dan tunggu grafiknya tampil.';
    Exit;
  end;
  try
    ForceDirectories(CekDir);
    Stamp := FormatDateTime('dd/mm/yyyy hh:nn:ss', Now);
    Id := FormatDateTime('yyyymmdd_hhnnss', Now) + '_' + Sym + '_' + StringReplace(TF, ' ', '', [rfReplaceAll]);

    Bmp := TBitmap.Create;
    try
      Bmp.PixelFormat := pf24bit;
      Bmp.Width := CapW;
      Bmp.Height := CapH;
      V := View;
      DrawCandles(Bmp.Canvas, Rect(0, 0, CapW, CapH), K, A, -1, Title, V);
      Bmp.Canvas.Brush.Style := bsClear;
      Bmp.Canvas.Font.Name := 'Segoe UI';
      Bmp.Canvas.Font.Size := 9;
      Bmp.Canvas.Font.Color := clrDim;
      Bmp.Canvas.TextOut(12, CapH - 20, 'Cek Grafik - capture ' + Stamp + ' - harga ' + FmtPrice(A.Price));
      if not SaveBitmapPng(Bmp, CekDir + Id + '.png') then
        Bmp.SaveToFile(CekDir + Id + '.bmp');
    finally
      Bmp.Free;
    end;

    L := TStringList.Create;
    try
      L.Text := ' CEK GRAFIK  ' + Sym + '  ' + TF + '  -  capture ' + Stamp + #13#10 +
        ' Harga saat capture: ' + FmtPrice(A.Price) + #13#10 + #13#10 + AnalysisText;
      L.SaveToFile(CekDir + Id + '.txt');
      Early := EarlyMove(A, K);
      L.Clear;
      if FileExists(IndexFile) then
        L.LoadFromFile(IndexFile);
      L.Add(Format('%s'#9'%d'#9'%s'#9'%s'#9'%s'#9'%s'#9'%s',
        [Id, Early.Dir, Sym, TF, FloatToStr(A.Price), A.Signal, Early.Head]));
      L.SaveToFile(IndexFile);
    finally
      L.Free;
    end;
    Result := True;
    ReloadCek;
  except
    on E: Exception do
      Err := E.Message;
  end;
end;

{ ---------- halaman Cek Grafik ---------- }

type
  TCekForm = class(TForm)
  private
    pnlTop, pnlBottom, pnlImg, btnDel, btnFolder, btnRefresh, btnZin, btnZout, btnFit: TPanel;
    lblInfo: TLabel;
    lv: TListView;
    pbImg: TPaintBox;
    memo: TMemo;
    tmr: TTimer;
    Rows: array of TCekEntry;
    FBmp: TBitmap;
    FLookup: TPriceLookup;
    FZoom: Double;            // 1 = muat di layar
    FOffX, FOffY: Integer;    // geser gambar (piksel)
    FDrag: Boolean;
    FDragX, FDragY, FDragOffX, FDragOffY: Integer;
    function MakeBtn(X, W: Integer; const Txt: string; Click: TNotifyEvent): TPanel;
    function Eval(const E: TCekEntry; var Now, Chg: Double): string;
    procedure LoadRows;
    procedure FillList;
    procedure RefreshPrices;
    procedure ShowSelected;
    procedure lvSelect(Sender: TObject; Item: TListItem; Selected: Boolean);
    procedure lvDrawItem(Sender: TCustomListView; Item: TListItem; State: TCustomDrawState;
      var DefaultDraw: Boolean);
    procedure lvDblClick(Sender: TObject);
    procedure ImgPaint(Sender: TObject);
    function ImgScale: Double;
    procedure ImgRect(var X0, Y0, W, H: Integer);
    procedure ZoomAt(Factor: Double; Px, Py: Integer);
    procedure ZoomIn(Sender: TObject);
    procedure ZoomOut(Sender: TObject);
    procedure ZoomFit(Sender: TObject);
    procedure ImgMouseDown(Sender: TObject; Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
    procedure ImgMouseMove(Sender: TObject; Shift: TShiftState; X, Y: Integer);
    procedure ImgMouseUp(Sender: TObject; Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
    procedure FormWheel(Sender: TObject; Shift: TShiftState; WheelDelta: Integer;
      MousePos: TPoint; var Handled: Boolean);
    procedure DelClick(Sender: TObject);
    procedure FolderClick(Sender: TObject);
    procedure RefreshClick(Sender: TObject);
    procedure TimerTick(Sender: TObject);
    procedure FormClose(Sender: TObject; var Action: TCloseAction);
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
    procedure Reload;
  end;

function TCekForm.MakeBtn(X, W: Integer; const Txt: string; Click: TNotifyEvent): TPanel;
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

constructor TCekForm.Create(AOwner: TComponent);
const
  Cols: array[0..9] of string = ('No', 'Waktu capture', 'Koin', 'TF', 'Harga capture', 'Prakiraan saat capture',
    'Sinyal', 'Harga kini', 'Selisih', 'Hasil prakiraan');
  Wid: array[0..9] of Integer = (40, 125, 100, 55, 110, 280, 70, 110, 80, 120);
var
  I: Integer;
  Col: TListColumn;
begin
  inherited CreateNew(AOwner);
  Caption := 'Cek Grafik - capture grafik & analisa tersimpan';
  SetBounds(70, 50, 1500, 880);
  Color := clrBg;
  Font.Name := 'Segoe UI';
  Font.Size := 9;
  Font.Color := clrText;
  OnClose := FormClose;
  FBmp := TBitmap.Create;

  pnlTop := TPanel.Create(Self);
  pnlTop.Parent := Self;
  pnlTop.Align := alTop;
  pnlTop.Height := 44;
  pnlTop.BevelOuter := bvNone;
  pnlTop.Color := clrPanel;
  btnRefresh := MakeBtn(10, 110, 'Segarkan harga', RefreshClick);
  btnDel := MakeBtn(130, 90, 'Hapus', DelClick);
  btnDel.Font.Color := clrDown;
  btnFolder := MakeBtn(230, 110, 'Buka folder', FolderClick);
  btnZin := MakeBtn(360, 64, 'Zoom +', ZoomIn);
  btnZout := MakeBtn(428, 64, 'Zoom -', ZoomOut);
  btnFit := MakeBtn(496, 90, 'Pas layar', ZoomFit);
  FZoom := 1;
  OnMouseWheel := FormWheel;
  lblInfo := TLabel.Create(Self);
  lblInfo.Parent := pnlTop;
  lblInfo.SetBounds(600, 14, 1000, 18);
  lblInfo.Font.Color := clrDim;

  pnlBottom := TPanel.Create(Self);
  pnlBottom.Parent := Self;
  pnlBottom.Align := alBottom;
  pnlBottom.Height := 560;
  pnlBottom.BevelOuter := bvNone;
  pnlBottom.Color := clrBg;

  with TSplitter.Create(Self) do
  begin
    Parent := Self;
    Align := alBottom;
    Height := 5;
    Color := clrBorder;
  end;

  pnlImg := TPanel.Create(Self);
  pnlImg.Parent := pnlBottom;
  pnlImg.Align := alLeft;
  pnlImg.Width := 900;
  pnlImg.BevelOuter := bvNone;
  pnlImg.Color := clrPanel;
  pbImg := TPaintBox.Create(Self);
  pbImg.Parent := pnlImg;
  pbImg.Align := alClient;
  pbImg.OnPaint := ImgPaint;
  pbImg.OnMouseDown := ImgMouseDown;
  pbImg.OnMouseMove := ImgMouseMove;
  pbImg.OnMouseUp := ImgMouseUp;
  pbImg.OnDblClick := ZoomFit;
  pbImg.Cursor := crSizeAll;

  memo := TMemo.Create(Self);
  memo.Parent := pnlBottom;
  memo.Align := alClient;
  memo.ReadOnly := True;
  memo.ScrollBars := ssBoth;
  memo.WordWrap := False;
  memo.BorderStyle := bsNone;
  memo.Color := clrBg;
  memo.Font.Name := 'Consolas';
  memo.Font.Size := 10;
  memo.Font.Color := clrText;

  lv := TListView.Create(Self);
  lv.Parent := Self;
  lv.Align := alClient;
  lv.ViewStyle := vsReport;
  lv.ReadOnly := True;
  lv.RowSelect := True;
  lv.HideSelection := False;
  lv.Color := clrBg;
  lv.Font.Color := clrText;
  lv.OnSelectItem := lvSelect;
  lv.OnCustomDrawItem := lvDrawItem;
  lv.OnDblClick := lvDblClick;
  for I := 0 to High(Cols) do
  begin
    Col := lv.Columns.Add;
    Col.Caption := Cols[I];
    Col.Width := Wid[I];
  end;

  tmr := TTimer.Create(Self);
  tmr.Interval := 5000;
  tmr.OnTimer := TimerTick;
end;

destructor TCekForm.Destroy;
begin
  FBmp.Free;
  inherited;
end;

procedure TCekForm.FormClose(Sender: TObject; var Action: TCloseAction);
begin
  Action := caHide;
end;

procedure TCekForm.LoadRows;
var
  L, F: TStringList;
  I, J, N: Integer;
  S: string;
  E: TCekEntry;
  T: TCekEntry;
begin
  SetLength(Rows, 0);
  if not FileExists(IndexFile) then
    Exit;
  L := TStringList.Create;
  F := TStringList.Create;
  try
    L.LoadFromFile(IndexFile);
    for I := 0 to L.Count - 1 do
    begin
      S := L[I];
      F.Clear;
      while S <> '' do
      begin
        J := Pos(#9, S);
        if J = 0 then
        begin
          F.Add(S);
          S := '';
        end
        else
        begin
          F.Add(Copy(S, 1, J - 1));
          Delete(S, 1, J);
        end;
      end;
      if F.Count < 7 then
        Continue;
      E.Id := F[0];
      E.Dir := StrToIntDef(F[1], 0);
      E.Sym := F[2];
      E.TF := F[3];
      E.Price := StrToFloatDef(F[4], 0);
      E.Signal := F[5];
      E.Head := F[6];
      N := Length(Rows);
      SetLength(Rows, N + 1);
      Rows[N] := E;
    end;
  finally
    F.Free;
    L.Free;
  end;
  for I := 1 to High(Rows) do   // terbaru di atas
  begin
    T := Rows[I];
    J := I - 1;
    while (J >= 0) and (Rows[J].Id < T.Id) do
    begin
      Rows[J + 1] := Rows[J];
      Dec(J);
    end;
    Rows[J + 1] := T;
  end;
end;

{ Hasil prakiraan: harga kini dibanding harga capture }
function TCekForm.Eval(const E: TCekEntry; var Now, Chg: Double): string;
begin
  Result := '-';
  Now := 0;
  Chg := 0;
  if not (Assigned(FLookup) and FLookup(E.Sym, Now)) or (Now <= 0) or (E.Price <= 0) then
    Exit;
  Chg := (Now - E.Price) / E.Price * 100;
  if E.Dir = 0 then
    Result := 'tanpa prakiraan'
  else if Abs(Chg) < 0.05 then
    Result := 'datar'
  else if ((E.Dir > 0) and (Chg > 0)) or ((E.Dir < 0) and (Chg < 0)) then
    Result := 'SESUAI'
  else
    Result := 'MELESET';
end;

procedure TCekForm.FillList;
var
  I, Sel: Integer;
  Item: TListItem;
  Id, Tm: string;
begin
  Sel := -1;
  if lv.Selected <> nil then
    Sel := Integer(lv.Selected.Data);
  lv.Items.BeginUpdate;
  try
    lv.Items.Clear;
    for I := 0 to High(Rows) do
    begin
      Id := Rows[I].Id;
      Tm := Copy(Id, 7, 2) + '/' + Copy(Id, 5, 2) + ' ' + Copy(Id, 10, 2) + ':' + Copy(Id, 12, 2) + ':' + Copy(Id, 14, 2);
      Item := lv.Items.Add;
      Item.Data := Pointer(I);
      Item.Caption := IntToStr(I + 1);
      Item.SubItems.Add(Tm);
      Item.SubItems.Add(Rows[I].Sym);
      Item.SubItems.Add(Rows[I].TF);
      Item.SubItems.Add(FmtPrice(Rows[I].Price));
      Item.SubItems.Add(Rows[I].Head);
      Item.SubItems.Add(SignalText(Rows[I].Signal));
      Item.SubItems.Add('-');
      Item.SubItems.Add('-');
      Item.SubItems.Add('-');
    end;
  finally
    lv.Items.EndUpdate;
  end;
  RefreshPrices;
  if (Sel >= 0) and (Sel < lv.Items.Count) then
    lv.Items[Sel].Selected := True
  else if lv.Items.Count > 0 then
    lv.Items[0].Selected := True;
  lblInfo.Caption := Format('%d capture tersimpan di %s - klik baris untuk melihat grafik & analisanya, klik 2x untuk membuka gambar',
    [Length(Rows), CekDir]);
end;

procedure TCekForm.RefreshPrices;
var
  I, K: Integer;
  Pn, Chg: Double;
  R: string;
begin
  for I := 0 to lv.Items.Count - 1 do
  begin
    K := Integer(lv.Items[I].Data);
    R := Eval(Rows[K], Pn, Chg);
    if Pn > 0 then
    begin
      lv.Items[I].SubItems[6] := FmtPrice(Pn);
      lv.Items[I].SubItems[7] := FmtPct(Chg);
    end;
    lv.Items[I].SubItems[8] := R;
  end;
  lv.Invalidate;
end;

procedure TCekForm.Reload;
begin
  LoadRows;
  FillList;
end;

procedure TCekForm.TimerTick(Sender: TObject);
begin
  if Visible then
    RefreshPrices;
end;

procedure TCekForm.RefreshClick(Sender: TObject);
begin
  RefreshPrices;
end;

procedure TCekForm.ShowSelected;
var
  I: Integer;
  F: string;
begin
  FBmp.Width := 0;
  FZoom := 1;
  FOffX := 0;
  FOffY := 0;
  memo.Lines.Clear;
  if lv.Selected = nil then
  begin
    pbImg.Invalidate;
    Exit;
  end;
  I := Integer(lv.Selected.Data);
  F := ImageFile(Rows[I].Id);
  if FileExists(F) then
  begin
    if not LoadAnyPicture(F, FBmp) then
      try
        FBmp.LoadFromFile(F);
      except
        FBmp.Width := 0;
      end;
  end;
  F := CekDir + Rows[I].Id + '.txt';
  if FileExists(F) then
    memo.Lines.LoadFromFile(F);
  pbImg.Invalidate;
end;

procedure TCekForm.lvSelect(Sender: TObject; Item: TListItem; Selected: Boolean);
begin
  if Selected then
    ShowSelected;
end;

procedure TCekForm.lvDrawItem(Sender: TCustomListView; Item: TListItem; State: TCustomDrawState;
  var DefaultDraw: Boolean);
var
  R: string;
begin
  DefaultDraw := True;
  if Item.SubItems.Count < 9 then
    Exit;
  R := Item.SubItems[8];
  if R = 'SESUAI' then
  begin
    Sender.Canvas.Font.Color := clrUp;
    Sender.Canvas.Brush.Color := clrUpBg;
  end
  else if R = 'MELESET' then
  begin
    Sender.Canvas.Font.Color := clrDown;
    Sender.Canvas.Brush.Color := clrDownBg;
  end
  else
    Sender.Canvas.Font.Color := clrText;
end;

procedure TCekForm.lvDblClick(Sender: TObject);
begin
  if lv.Selected = nil then
    Exit;
  ShellExecute(0, 'open', PChar(ImageFile(Rows[Integer(lv.Selected.Data)].Id)), nil, nil, SW_SHOWNORMAL);
end;

{ skala "pas layar" dikali zoom }
function TCekForm.ImgScale: Double;
begin
  Result := 1;
  if (FBmp.Width = 0) or (FBmp.Height = 0) then
    Exit;
  Result := Min(pbImg.Width / FBmp.Width, pbImg.Height / FBmp.Height) * FZoom;
end;

procedure TCekForm.ImgRect(var X0, Y0, W, H: Integer);
var
  Sc: Double;
begin
  Sc := ImgScale;
  W := Round(FBmp.Width * Sc);
  H := Round(FBmp.Height * Sc);
  X0 := (pbImg.Width - W) div 2 + FOffX;
  Y0 := (pbImg.Height - H) div 2 + FOffY;
end;

procedure TCekForm.ImgPaint(Sender: TObject);
var
  C: TCanvas;
  X0, Y0, W, H: Integer;
  S: string;
begin
  C := pbImg.Canvas;
  C.Brush.Style := bsSolid;
  C.Brush.Color := clrPanel;
  C.FillRect(Rect(0, 0, pbImg.Width, pbImg.Height));
  if FBmp.Width = 0 then
  begin
    C.Brush.Style := bsClear;
    C.Font.Color := clrDim;
    C.Font.Size := 10;
    C.TextOut(14, 14, 'Pilih satu baris di tabel untuk melihat grafik yang tersimpan.');
    Exit;
  end;
  ImgRect(X0, Y0, W, H);
  SetStretchBltMode(C.Handle, HALFTONE);
  C.StretchDraw(Rect(X0, Y0, X0 + W, Y0 + H), FBmp);
  C.Brush.Style := bsClear;
  C.Font.Size := 8;
  C.Font.Color := clrGold;
  S := Format('zoom %d%%   scroll = zoom   drag = geser   klik 2x = pas layar', [Round(FZoom * 100)]);
  C.TextOut(8, pbImg.Height - 16, S);
end;

{ zoom di sekitar titik (Px, Py) agar bagian di bawah kursor tidak bergeser }
procedure TCekForm.ZoomAt(Factor: Double; Px, Py: Integer);
var
  X0, Y0, W, H, W1, H1: Integer;
  Ix, Iy, NewZ: Double;
begin
  if FBmp.Width = 0 then
    Exit;
  NewZ := Min(12, Max(0.2, FZoom * Factor));
  if NewZ = FZoom then
    Exit;
  ImgRect(X0, Y0, W, H);
  if W = 0 then
    Exit;
  Ix := (Px - X0) / W;   // posisi kursor pada gambar (0..1)
  Iy := (Py - Y0) / H;
  FZoom := NewZ;
  W1 := Round(FBmp.Width * ImgScale);
  H1 := Round(FBmp.Height * ImgScale);
  FOffX := Round(Px - Ix * W1 - (pbImg.Width - W1) div 2);
  FOffY := Round(Py - Iy * H1 - (pbImg.Height - H1) div 2);
  pbImg.Invalidate;
end;

procedure TCekForm.ZoomIn(Sender: TObject);
begin
  ZoomAt(1.25, pbImg.Width div 2, pbImg.Height div 2);
end;

procedure TCekForm.ZoomOut(Sender: TObject);
begin
  ZoomAt(1 / 1.25, pbImg.Width div 2, pbImg.Height div 2);
end;

procedure TCekForm.ZoomFit(Sender: TObject);
begin
  FZoom := 1;
  FOffX := 0;
  FOffY := 0;
  pbImg.Invalidate;
end;

procedure TCekForm.ImgMouseDown(Sender: TObject; Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
begin
  if Button <> mbLeft then
    Exit;
  FDrag := True;
  FDragX := X;
  FDragY := Y;
  FDragOffX := FOffX;
  FDragOffY := FOffY;
end;

procedure TCekForm.ImgMouseMove(Sender: TObject; Shift: TShiftState; X, Y: Integer);
begin
  if ActiveControl <> nil then
    ActiveControl := nil;   // agar scroll mouse di atas gambar masuk ke FormWheel
  if FDrag then
  begin
    FOffX := FDragOffX + (X - FDragX);
    FOffY := FDragOffY + (Y - FDragY);
    pbImg.Invalidate;
  end;
end;

procedure TCekForm.ImgMouseUp(Sender: TObject; Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
begin
  FDrag := False;
end;

procedure TCekForm.FormWheel(Sender: TObject; Shift: TShiftState; WheelDelta: Integer;
  MousePos: TPoint; var Handled: Boolean);
var
  P: TPoint;
begin
  P := pbImg.ScreenToClient(MousePos);
  if PtInRect(pbImg.ClientRect, P) then
  begin
    if WheelDelta > 0 then ZoomAt(1.2, P.X, P.Y) else ZoomAt(1 / 1.2, P.X, P.Y);
    Handled := True;
  end;
end;

procedure TCekForm.DelClick(Sender: TObject);
var
  I, K: Integer;
  Id: string;
  L: TStringList;
begin
  if lv.Selected = nil then
    Exit;
  K := Integer(lv.Selected.Data);
  Id := Rows[K].Id;
  if Application.MessageBox(PChar('Hapus capture ' + Rows[K].Sym + ' ' + Rows[K].TF + ' (' + Id + ')?'),
    'Cek Grafik', MB_YESNO or MB_ICONQUESTION) <> IDYES then
    Exit;
  DeleteFile(CekDir + Id + '.png');
  DeleteFile(CekDir + Id + '.bmp');
  DeleteFile(CekDir + Id + '.txt');
  L := TStringList.Create;
  try
    if FileExists(IndexFile) then
      L.LoadFromFile(IndexFile);
    for I := L.Count - 1 downto 0 do
      if Copy(L[I], 1, Length(Id) + 1) = Id + #9 then
        L.Delete(I);
    L.SaveToFile(IndexFile);
  finally
    L.Free;
  end;
  Reload;
end;

procedure TCekForm.FolderClick(Sender: TObject);
begin
  ForceDirectories(CekDir);
  ShellExecute(0, 'open', PChar(CekDir), nil, nil, SW_SHOWNORMAL);
end;

procedure ReloadCek;
begin
  if CekForm <> nil then
    TCekForm(CekForm).Reload;
end;

procedure ShowCekGrafik(Lookup: TPriceLookup);
begin
  if CekForm = nil then
    CekForm := TCekForm.Create(Application);
  TCekForm(CekForm).FLookup := Lookup;
  TCekForm(CekForm).Reload;
  CekForm.Show;
  CekForm.BringToFront;
end;

end.
