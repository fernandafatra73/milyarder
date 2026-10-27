unit uWorkers;

{ Thread latar belakang. Hasil dikirim ke form lewat PostMessage
  (LParam = objek data, form penerima yang membebaskannya). }

interface

uses
  Windows, Messages, SysUtils, Classes, Math, uJson, uAnalysis, uBinance;

const
  WM_FT_TICKERS = WM_USER + 201;
  WM_FT_SCAN    = WM_USER + 202;
  WM_FT_DETAIL  = WM_USER + 203;
  WM_FT_MSG     = WM_USER + 204;
  WM_FT_BTC     = WM_USER + 205;
  WM_FT_LIVE    = WM_USER + 206;
  WM_FT_OLDER   = WM_USER + 207;
  WM_FT_PREBO   = WM_USER + 208;
  WM_FT_SIDE    = WM_USER + 209;

  ScanInterval = '1h';
  ScanPerCycle = 12;

  BtcSymbol = 'BTCUSDT';
  BtcIntervals: array[0..3] of string = ('15m', '1h', '4h', '1d');
  BtcIntervalNames: array[0..3] of string = ('15 Menit', '1 Jam', '4 Jam', '1 Hari');

  // pilihan time frame grafik: label tombol & interval API Binance
  ChartTFCount = 9;
  ChartTFLabels: array[0..ChartTFCount - 1] of string =
    ('1m', '5m', '10m', '15m', '30m', '1 jam', '2 jam', '4 jam', '1 bln');
  ChartTFApi: array[0..ChartTFCount - 1] of string =
    ('1m', '5m', '10m', '15m', '30m', '1h', '2h', '4h', '1M');
  DefaultChartTF = 5;  // 1 jam

function ChartTFLabel(const Api: string): string;

type
  TTickerData = class
  public
    Count: Integer;
    Sym: array of string;
    Price, Chg, QV, High, Low: array of Double;
  end;

  TScanData = class
  public
    A: TAnalysis;
  end;

  TDetailData = class
  public
    ReqId: Integer;
    A: TAnalysis;
    K: TKlines;
    BidUSD, AskUSD, AskWallPrice, AskWallUSD, BidWallPrice, BidWallUSD: Double;
    DepthOk: Boolean;
    Err: string;
  end;

  TMsgData = class
  public
    Text: string;
    IsError: Boolean;
  end;

  TBtcData = class
  public
    Err: string;
    Price, Chg, High, Low, QV: Double;
    TF: array[0..3] of TAnalysis;
    KChart: TKlines;      // candle untuk grafik (time frame pilihan)
    AChart: TAnalysis;
    BidUSD, AskUSD, AskWallPrice, AskWallUSD, BidWallPrice, BidWallUSD: Double;
    DepthOk: Boolean;
  end;

  TScannerThread = class(TThread)
  private
    FWnd: HWND;
    procedure Post(Msg: UINT; Obj: TObject);
    procedure PostText(const S: string; IsError: Boolean);
    procedure SleepCheck(Ms: Integer);
    function FetchTickers(Valid: TStringList): TTickerData;
  protected
    procedure Execute; override;
  public
    constructor Create(AWnd: HWND);
  end;

  TDetailThread = class(TThread)
  private
    FWnd: HWND;
    FSym, FInterval: string;
    FReqId: Integer;
  protected
    procedure Execute; override;
  public
    constructor Create(AWnd: HWND; const Sym, Interval: string; ReqId: Integer);
  end;

  TLiveData = class
  public
    Sym, Interval, Err: string;
    K: TKlines;   // 1-2 candle terbaru
  end;

  { Ambil candle terbaru saja (ringan) untuk grafik real-time }
  TLiveThread = class(TThread)
  private
    FWnd: HWND;
    FSym, FInterval: string;
  protected
    procedure Execute; override;
  public
    constructor Create(AWnd: HWND; const Sym, Interval: string);
  end;

  { Ambil 1000 candle sebelum EndTime untuk riwayat grafik (geser ke masa lalu).
    Hasil dikirim sebagai TLiveData lewat WM_FT_OLDER. }
  TOlderThread = class(TThread)
  private
    FWnd: HWND;
    FSym, FInterval: string;
    FEndTime: Double;
  protected
    procedure Execute; override;
  public
    constructor Create(AWnd: HWND; const Sym, Interval: string; EndTime: Double);
  end;

  TPreBoData = class
  public
    Sym, Note, Err: string;
    Chance, EtaMin: Integer;
    Last: Boolean;   // pesan terakhir dari satu putaran
  end;

  { Analisa candle 1 menit untuk koin yang dekat resisten (peluang breakout) }
  TPreBoThread = class(TThread)
  private
    FWnd: HWND;
    FSyms: array of string;
    FHigh: array of Double;
  protected
    procedure Execute; override;
  public
    constructor Create(AWnd: HWND; const Syms: array of string; const Highs: array of Double);
  end;

  TSideData = class
  public
    Sym: string;
    Dir: array[0..SideTFCount - 1] of Integer;   // 0 = tidak sideways, +1 prediksi naik, -1 turun
    Ok: Boolean;
    Last: Boolean;   // pesan terakhir dari satu putaran
  end;

  { Cek sideways + prediksi arah di 1m/5m/10m/15m/30m/1j untuk koin pilihan }
  TSideThread = class(TThread)
  private
    FWnd: HWND;
    FSyms: array of string;
  protected
    procedure Execute; override;
  public
    constructor Create(AWnd: HWND; const Syms: array of string);
  end;

  TBtcThread = class(TThread)
  private
    FWnd: HWND;
    FChartTF: string;
  protected
    procedure Execute; override;
  public
    constructor Create(AWnd: HWND; const ChartTF: string);
  end;

procedure PostObj(Wnd: HWND; Msg: UINT; Obj: TObject);

implementation

function ChartTFLabel(const Api: string): string;
var
  I: Integer;
begin
  Result := Api;
  for I := 0 to ChartTFCount - 1 do
    if ChartTFApi[I] = Api then
      Result := ChartTFLabels[I];
end;

procedure PostObj(Wnd: HWND; Msg: UINT; Obj: TObject);
begin
  if not PostMessage(Wnd, Msg, 0, Integer(Obj)) then
    Obj.Free;
end;

{ TScannerThread }

constructor TScannerThread.Create(AWnd: HWND);
begin
  FWnd := AWnd;
  FreeOnTerminate := False;
  inherited Create(False);
end;

procedure TScannerThread.Post(Msg: UINT; Obj: TObject);
begin
  PostObj(FWnd, Msg, Obj);
end;

procedure TScannerThread.PostText(const S: string; IsError: Boolean);
var
  M: TMsgData;
begin
  M := TMsgData.Create;
  M.Text := S;
  M.IsError := IsError;
  Post(WM_FT_MSG, M);
end;

procedure TScannerThread.SleepCheck(Ms: Integer);
begin
  while (Ms > 0) and not Terminated do
  begin
    Sleep(100);
    Dec(Ms, 100);
  end;
end;

function TScannerThread.FetchTickers(Valid: TStringList): TTickerData;
var
  Root, T: TJNode;
  I, N: Integer;
  Sym: string;
begin
  Root := FetchJson(TickerUrl);
  Result := TTickerData.Create;
  try
    SetLength(Result.Sym, Root.Count);
    SetLength(Result.Price, Root.Count);
    SetLength(Result.Chg, Root.Count);
    SetLength(Result.QV, Root.Count);
    SetLength(Result.High, Root.Count);
    SetLength(Result.Low, Root.Count);
    N := 0;
    for I := 0 to Root.Count - 1 do
    begin
      T := Root.Item(I);
      Sym := T.Str('symbol');
      if Valid.IndexOf(Sym) < 0 then
        Continue;
      Result.Sym[N] := Sym;
      Result.Price[N] := T.Num('lastPrice');
      Result.Chg[N] := T.Num('priceChangePercent');
      Result.QV[N] := T.Num('quoteVolume');
      Result.High[N] := T.Num('highPrice');
      Result.Low[N] := T.Num('lowPrice');
      Inc(N);
    end;
    Result.Count := N;
  finally
    Root.Free;
  end;
end;

procedure TScannerThread.Execute;
var
  Valid, Queue, Sorter: TStringList;
  TD: TTickerData;
  SD: TScanData;
  K: TKlines;
  I: Integer;
  Sym, Key: string;
  LastProbe: Cardinal;
begin
  Valid := TStringList.Create;
  Valid.Sorted := True;
  Queue := TStringList.Create;
  Sorter := TStringList.Create;
  LastProbe := GetTickCount;
  try
    while not Terminated do
    begin
      try
        if not SourceKnown then
        begin
          PostText('Mendeteksi server Binance...', False);
          DetectSource;
        end;
        // saat memakai server cadangan, coba lagi server futures tiap 5 menit
        if UseSpot and (GetTickCount - LastProbe > 300000) then
        begin
          LastProbe := GetTickCount;
          if FuturesReachable then
          begin
            UseSpot := False;
            Valid.Clear;
            Queue.Clear;
            PostText('Server Binance Futures bisa diakses lagi, beralih ke Futures.', False);
          end;
        end;
        if Valid.Count = 0 then
        begin
          PostText('Mengambil daftar koin (' + SourceName + ')...', False);
          GetTradingSymbols(Valid);
        end;

        TD := FetchTickers(Valid);
        if Queue.Count = 0 then
        begin
          // urutkan antrian scan: volume terbesar duluan
          Sorter.Clear;
          for I := 0 to TD.Count - 1 do
          begin
            Key := IntToStr(Trunc(TD.QV[I]));
            while Length(Key) < 18 do
              Key := '0' + Key;
            Sorter.Add(Key + '|' + TD.Sym[I]);
          end;
          Sorter.Sort;
          for I := Sorter.Count - 1 downto 0 do
            Queue.Add(Copy(Sorter[I], Pos('|', Sorter[I]) + 1, MaxInt));
        end;
        Post(WM_FT_TICKERS, TD);

        for I := 1 to ScanPerCycle do
        begin
          if Terminated or (Queue.Count = 0) then
            Break;
          Sym := Queue[0];
          Queue.Delete(0);
          try
            K := GetKlines(Sym, ScanInterval, KlineLimit);
            SD := TScanData.Create;
            SD.A := Analyze(Sym, ScanInterval, K);
            Post(WM_FT_SCAN, SD);
          except
            on E: Exception do
              PostText(Sym + ': ' + E.Message, True);
          end;
          SleepCheck(200);
        end;
        SleepCheck(2000);
      except
        on E: Exception do
        begin
          PostText(E.Message, True);
          SleepCheck(8000);
        end;
      end;
    end;
  finally
    Sorter.Free;
    Queue.Free;
    Valid.Free;
  end;
end;

{ TDetailThread }

constructor TDetailThread.Create(AWnd: HWND; const Sym, Interval: string; ReqId: Integer);
begin
  FWnd := AWnd;
  FSym := Sym;
  FInterval := Interval;
  FReqId := ReqId;
  FreeOnTerminate := True;
  inherited Create(False);
end;

procedure TDetailThread.Execute;
var
  D, D2: TDetailData;
  K: TKlines;
begin
  D := TDetailData.Create;
  D2 := nil;
  D.ReqId := FReqId;
  try
    EnsureSource;
    K := GetKlines(FSym, FInterval, KlineLimit);
    D.K := K;
    D.A := Analyze(FSym, FInterval, K);
  except
    on E: Exception do
    begin
      D.A.Symbol := FSym;
      D.Err := E.Message;
    end;
  end;
  { grafik & analisa dikirim dulu; order book menyusul agar tampilan tidak menunggu }
  if D.Err = '' then
  begin
    D2 := TDetailData.Create;
    D2.ReqId := D.ReqId;
    D2.A := D.A;
    D2.K := D.K;
  end;
  PostObj(FWnd, WM_FT_DETAIL, D);
  if D2 <> nil then
  begin
    try
      D2.DepthOk := GetDepthUSD(FSym, D2.BidUSD, D2.AskUSD, D2.AskWallPrice, D2.AskWallUSD, D2.BidWallPrice, D2.BidWallUSD);
    except
    end;
    if D2.DepthOk then
      PostObj(FWnd, WM_FT_DETAIL, D2)
    else
      D2.Free;
  end;
end;

{ TPreBoThread }

constructor TPreBoThread.Create(AWnd: HWND; const Syms: array of string; const Highs: array of Double);
var
  I: Integer;
begin
  FWnd := AWnd;
  SetLength(FSyms, Length(Syms));
  SetLength(FHigh, Length(Syms));
  for I := 0 to High(Syms) do
  begin
    FSyms[I] := Syms[I];
    FHigh[I] := Highs[I];
  end;
  FreeOnTerminate := True;
  inherited Create(False);
end;

procedure TPreBoThread.Execute;
var
  I: Integer;
  D: TPreBoData;
  K: TKlines;
begin
  EnsureSource;
  for I := 0 to High(FSyms) do
  begin
    if Terminated then
      Break;
    D := TPreBoData.Create;
    D.Sym := FSyms[I];
    try
      K := GetKlines(FSyms[I], '1m', 100);
      D.Chance := BreakoutChance(K, FHigh[I], D.Note, D.EtaMin);
    except
      on E: Exception do
        D.Err := E.Message;
    end;
    PostObj(FWnd, WM_FT_PREBO, D);
    Sleep(150);
  end;
  D := TPreBoData.Create;
  D.Last := True;
  PostObj(FWnd, WM_FT_PREBO, D);
end;

{ TSideThread }

constructor TSideThread.Create(AWnd: HWND; const Syms: array of string);
var
  I: Integer;
begin
  FWnd := AWnd;
  SetLength(FSyms, Length(Syms));
  for I := 0 to High(Syms) do
    FSyms[I] := Syms[I];
  FreeOnTerminate := True;
  inherited Create(False);
end;

procedure TSideThread.Execute;
var
  I, T, Dir: Integer;
  D: TSideData;
  K: TKlines;
begin
  EnsureSource;
  for I := 0 to High(FSyms) do
  begin
    if Terminated then
      Break;
    D := TSideData.Create;
    D.Sym := FSyms[I];
    for T := 0 to SideTFCount - 1 do
    begin
      try
        K := GetKlines(FSyms[I], SideTFApi[T], 60);
        if SidewaysForecast(K, SideMaxRange[T], Dir) then
          D.Dir[T] := Dir;
        D.Ok := True;
      except
      end;
      Sleep(60);
    end;
    PostObj(FWnd, WM_FT_SIDE, D);
  end;
  D := TSideData.Create;
  D.Last := True;
  PostObj(FWnd, WM_FT_SIDE, D);
end;

{ TLiveThread }

constructor TLiveThread.Create(AWnd: HWND; const Sym, Interval: string);
begin
  FWnd := AWnd;
  FSym := Sym;
  FInterval := Interval;
  FreeOnTerminate := True;
  inherited Create(False);
end;

procedure TLiveThread.Execute;
var
  D: TLiveData;
  K: TKlines;
  Lim: Integer;
begin
  D := TLiveData.Create;
  D.Sym := FSym;
  D.Interval := FInterval;
  try
    EnsureSource;
    // 10m dibentuk dari 5m: ambil lebih banyak agar candle terakhir utuh
    if FInterval = '10m' then Lim := 3 else Lim := 2;
    K := GetKlines(FSym, FInterval, Lim);
    if Length(K) > 2 then
      K := Copy(K, Length(K) - 2, 2);
    D.K := K;
  except
    on E: Exception do
      D.Err := E.Message;
  end;
  PostObj(FWnd, WM_FT_LIVE, D);
end;

{ TOlderThread }

constructor TOlderThread.Create(AWnd: HWND; const Sym, Interval: string; EndTime: Double);
begin
  FWnd := AWnd;
  FSym := Sym;
  FInterval := Interval;
  FEndTime := EndTime;
  FreeOnTerminate := True;
  inherited Create(False);
end;

procedure TOlderThread.Execute;
var
  D: TLiveData;
begin
  D := TLiveData.Create;
  D.Sym := FSym;
  D.Interval := FInterval;
  try
    EnsureSource;
    D.K := GetKlines(FSym, FInterval, 1000, FEndTime);
  except
    on E: Exception do
      D.Err := E.Message;
  end;
  PostObj(FWnd, WM_FT_OLDER, D);
end;

{ TBtcThread }

constructor TBtcThread.Create(AWnd: HWND; const ChartTF: string);
begin
  FWnd := AWnd;
  FChartTF := ChartTF;
  FreeOnTerminate := True;
  inherited Create(False);
end;

procedure TBtcThread.Execute;
var
  D: TBtcData;
  T: TJNode;
  I: Integer;
  K: TKlines;
begin
  D := TBtcData.Create;
  try
    EnsureSource;
    T := FetchJson(TickerUrl + '?symbol=' + BtcSymbol);
    try
      D.Price := T.Num('lastPrice');
      D.Chg := T.Num('priceChangePercent');
      D.High := T.Num('highPrice');
      D.Low := T.Num('lowPrice');
      D.QV := T.Num('quoteVolume');
    finally
      T.Free;
    end;
    for I := 0 to 3 do
      D.TF[I] := Analyze(BtcSymbol, BtcIntervals[I], GetKlines(BtcSymbol, BtcIntervals[I], KlineLimit));
    K := GetKlines(BtcSymbol, FChartTF, KlineLimit);
    D.KChart := K;
    D.AChart := Analyze(BtcSymbol, FChartTF, K);
    D.DepthOk := GetDepthUSD(BtcSymbol, D.BidUSD, D.AskUSD, D.AskWallPrice, D.AskWallUSD, D.BidWallPrice, D.BidWallUSD);
  except
    on E: Exception do
      D.Err := E.Message;
  end;
  PostObj(FWnd, WM_FT_BTC, D);
end;

end.
