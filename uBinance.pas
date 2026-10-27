unit uBinance;

{ Akses API publik Binance (tanpa API key).
  Utama: USDT-M Futures (fapi.binance.com).
  Cadangan: data-api.binance.vision, dipakai otomatis bila fapi diblokir ISP. }

interface

uses
  Windows, SysUtils, Classes, Math, WinInet, ShellAPI, uJson, uAnalysis;

const
  FAPI_MAIN = 'https://fapi.binance.com';
  FAPI_BH = 'https://www.binance.bh';   // API futures yang sama, lewat domain binance.bh
  SPOT = 'https://data-api.binance.vision';
  BINANCE_WEB = 'https://www.binance.bh/en/futures/';

var
  FAPI: string = FAPI_MAIN;     // server futures yang sedang dipakai
  UseSpot: Boolean = False;     // True = memakai server cadangan spot
  SourceKnown: Boolean = False;

function HttpGet(const Url: string): string;
function FetchJson(const Url: string): TJNode;
procedure DetectSource;
procedure EnsureSource;
function FuturesReachable: Boolean;
function SourceName: string;
function TickerUrl: string;
function GetKlines(const Sym, Interval: string; Limit: Integer; EndTime: Double = 0): TKlines;
procedure GetTradingSymbols(List: TStrings);
function GetDepthUSD(const Sym: string; var BidUSD, AskUSD, AskWallPrice, AskWallUSD, BidWallPrice, BidWallUSD: Double): Boolean;
function GetDepthLevels(const Sym: string; Limit: Integer;
  out BidP, BidQ, AskP, AskQ: TDoubleArray): Boolean;
procedure OpenBinance(const Sym: string);

implementation

function HttpGet(const Url: string): string;
var
  hNet, hUrl: HINTERNET;
  Buf: array[0..32767] of Char;
  BytesRead, Code, Len, Idx, Timeout: DWORD;
  OldLen: Integer;
begin
  Result := '';
  hNet := InternetOpen('FernandaTaker/1.0', INTERNET_OPEN_TYPE_PRECONFIG, nil, nil, 0);
  if hNet = nil then
    raise Exception.Create('InternetOpen gagal');
  try
    Timeout := 15000;
    InternetSetOption(hNet, INTERNET_OPTION_CONNECT_TIMEOUT, @Timeout, SizeOf(Timeout));
    InternetSetOption(hNet, INTERNET_OPTION_RECEIVE_TIMEOUT, @Timeout, SizeOf(Timeout));
    hUrl := InternetOpenUrl(hNet, PChar(Url), nil, 0,
      INTERNET_FLAG_RELOAD or INTERNET_FLAG_NO_CACHE_WRITE or
      INTERNET_FLAG_PRAGMA_NOCACHE or INTERNET_FLAG_SECURE, 0);
    if hUrl = nil then
      raise Exception.CreateFmt('Tidak bisa terhubung ke Binance (WinInet error %d). Cek koneksi internet.', [GetLastError]);
    try
      Code := 0;
      Len := SizeOf(Code);
      Idx := 0;
      HttpQueryInfo(hUrl, HTTP_QUERY_STATUS_CODE or HTTP_QUERY_FLAG_NUMBER, @Code, Len, Idx);
      repeat
        BytesRead := 0;
        if not InternetReadFile(hUrl, @Buf, SizeOf(Buf), BytesRead) then
          Break;
        if BytesRead > 0 then
        begin
          OldLen := Length(Result);
          SetLength(Result, OldLen + Integer(BytesRead));
          Move(Buf, Result[OldLen + 1], BytesRead);
        end;
      until BytesRead = 0;
      if (Code = 451) or (Code = 403) then
        raise Exception.CreateFmt('Akses API Binance diblokir dari lokasi/IP ini (HTTP %d).', [Code]);
      if Code = 429 then
        raise Exception.Create('Terlalu banyak request ke Binance (HTTP 429), tunggu sebentar.');
      if Code <> 200 then
        raise Exception.CreateFmt('HTTP %d: %s', [Code, Copy(Result, 1, 200)]);
    finally
      InternetCloseHandle(hUrl);
    end;
  finally
    InternetCloseHandle(hNet);
  end;
end;

function FetchJson(const Url: string): TJNode;
begin
  Result := ParseJson(HttpGet(Url));
end;

function Ping(const Base: string): Boolean;
begin
  try
    HttpGet(Base + '/fapi/v1/ping');
    Result := True;
  except
    Result := False;
  end;
end;

{ Coba server futures utama, lalu binance.bh. Mengisi FAPI bila berhasil. }
function FuturesReachable: Boolean;
begin
  Result := True;
  if Ping(FAPI_MAIN) then
    FAPI := FAPI_MAIN
  else if Ping(FAPI_BH) then
    FAPI := FAPI_BH
  else
    Result := False;
end;

procedure DetectSource;
begin
  UseSpot := not FuturesReachable;
  SourceKnown := True;
end;

procedure EnsureSource;
begin
  if not SourceKnown then
    DetectSource;
end;

function SourceName: string;
begin
  if not SourceKnown then
    Result := 'mendeteksi server...'
  else if UseSpot then
    Result := 'server cadangan Binance (futures diblokir ISP)'
  else if FAPI = FAPI_BH then
    Result := 'Binance Futures (lewat binance.bh)'
  else
    Result := 'Binance Futures';
end;

function TickerUrl: string;
begin
  if UseSpot then
    Result := SPOT + '/api/v3/ticker/24hr'
  else
    Result := FAPI + '/fapi/v1/ticker/24hr';
end;

{ Binance tidak punya interval 10 menit: gabungkan 2 candle 5 menit }
function Get10mKlines(const Sym: string; Limit: Integer; EndTime: Double): TKlines;
var
  Raw: TKlines;
  I, N: Integer;
  Bucket, LastBucket: Int64;
begin
  Raw := GetKlines(Sym, '5m', Min(Limit * 2, 1000), EndTime);
  SetLength(Result, Length(Raw));
  N := 0;
  LastBucket := -1;
  for I := 0 to High(Raw) do
  begin
    Bucket := Trunc(Raw[I].OpenTime / 600000);
    if (N > 0) and (Bucket = LastBucket) then
      with Result[N - 1] do
      begin
        H := Max(H, Raw[I].H);
        L := Min(L, Raw[I].L);
        C := Raw[I].C;
        V := V + Raw[I].V;
        QV := QV + Raw[I].QV;
        TBQV := TBQV + Raw[I].TBQV;
      end
    else
    begin
      Result[N] := Raw[I];
      Result[N].OpenTime := Bucket * 600000.0;
      Inc(N);
      LastBucket := Bucket;
    end;
  end;
  SetLength(Result, N);
end;

function GetKlines(const Sym, Interval: string; Limit: Integer; EndTime: Double = 0): TKlines;
var
  Root, Row: TJNode;
  I: Integer;
  Url: string;
begin
  if Interval = '10m' then
  begin
    Result := Get10mKlines(Sym, Limit, EndTime);
    Exit;
  end;
  if UseSpot then
    Url := Format('%s/api/v3/klines?symbol=%s&interval=%s&limit=%d', [SPOT, Sym, Interval, Limit])
  else
    Url := Format('%s/fapi/v1/klines?symbol=%s&interval=%s&limit=%d', [FAPI, Sym, Interval, Limit]);
  if EndTime > 0 then
    Url := Url + Format('&endTime=%.0f', [EndTime]);  // ambil candle sebelum waktu ini
  Root := FetchJson(Url);
  try
    SetLength(Result, Root.Count);
    for I := 0 to Root.Count - 1 do
    begin
      Row := Root.Item(I);
      Result[I].OpenTime := Row.Item(0).AsFloat;
      Result[I].O := Row.Item(1).AsFloat;
      Result[I].H := Row.Item(2).AsFloat;
      Result[I].L := Row.Item(3).AsFloat;
      Result[I].C := Row.Item(4).AsFloat;
      Result[I].V := Row.Item(5).AsFloat;
      Result[I].QV := Row.Item(7).AsFloat;
      Result[I].TBQV := Row.Item(10).AsFloat;
    end;
  finally
    Root.Free;
  end;
end;

function EndsWith(const S, Suffix: string): Boolean;
begin
  Result := (Length(S) >= Length(Suffix)) and
    (Copy(S, Length(S) - Length(Suffix) + 1, Length(Suffix)) = Suffix);
end;

{ Server cadangan tidak punya daftar kontrak futures, jadi daftar koin diambil
  dari pasangan USDT yang aktif diperdagangkan (tanpa stablecoin & token leverage). }
procedure GetSpotUsdtSymbols(List: TStrings);
const
  Skip: array[0..9] of string = ('USDCUSDT', 'FDUSDUSDT', 'TUSDUSDT', 'BUSDUSDT',
    'USDPUSDT', 'DAIUSDT', 'EURUSDT', 'AEURUSDT', 'EURIUSDT', 'USD1USDT');
var
  Root, T: TJNode;
  I, J: Integer;
  Sym: string;
  Ok: Boolean;
begin
  Root := FetchJson(SPOT + '/api/v3/ticker/24hr');
  try
    List.Clear;
    for I := 0 to Root.Count - 1 do
    begin
      T := Root.Item(I);
      Sym := T.Str('symbol');
      if not EndsWith(Sym, 'USDT') then Continue;
      if EndsWith(Sym, 'UPUSDT') or EndsWith(Sym, 'DOWNUSDT') or
         EndsWith(Sym, 'BULLUSDT') or EndsWith(Sym, 'BEARUSDT') then Continue;
      if (T.Num('count') <= 0) or (T.Num('quoteVolume') < 50000) then Continue;
      // stablecoin: harga ~1 dollar dan hampir tidak bergerak
      if (T.Num('lastPrice') > 0.97) and (T.Num('lastPrice') < 1.03) and
         (T.Num('lowPrice') > 0) and ((T.Num('highPrice') - T.Num('lowPrice')) / T.Num('lowPrice') < 0.01) then
        Continue;
      Ok := True;
      for J := 0 to High(Skip) do
        if Sym = Skip[J] then Ok := False;
      if Ok then
        List.Add(Sym);
    end;
  finally
    Root.Free;
  end;
end;

procedure GetTradingSymbols(List: TStrings);
var
  Root, Syms, S: TJNode;
  I: Integer;
begin
  if UseSpot then
  begin
    GetSpotUsdtSymbols(List);
    Exit;
  end;
  Root := FetchJson(FAPI + '/fapi/v1/exchangeInfo');
  try
    Syms := Root.Get('symbols');
    List.Clear;
    if Syms = nil then
      Exit;
    for I := 0 to Syms.Count - 1 do
    begin
      S := Syms.Item(I);
      if S.Str('status') = 'TRADING' then
        List.Add(S.Str('symbol'));
    end;
  finally
    Root.Free;
  end;
end;

function GetDepthUSD(const Sym: string; var BidUSD, AskUSD, AskWallPrice, AskWallUSD, BidWallPrice, BidWallUSD: Double): Boolean;
var
  Root, Arr: TJNode;
  I: Integer;
  Url: string;
  Lvl: Double;
begin
  BidUSD := 0;
  AskUSD := 0;
  AskWallPrice := 0;
  AskWallUSD := 0;
  BidWallPrice := 0;
  BidWallUSD := 0;
  Result := False;
  if UseSpot then
    Url := Format('%s/api/v3/depth?symbol=%s&limit=100', [SPOT, Sym])
  else
    Url := Format('%s/fapi/v1/depth?symbol=%s&limit=100', [FAPI, Sym]);
  try
    Root := FetchJson(Url);
    try
      Arr := Root.Get('bids');
      if Arr <> nil then
        for I := 0 to Arr.Count - 1 do
        begin
          Lvl := Arr.Item(I).Item(0).AsFloat * Arr.Item(I).Item(1).AsFloat;
          BidUSD := BidUSD + Lvl;
          if Lvl > BidWallUSD then   // antrian beli terbesar pada satu harga
          begin
            BidWallUSD := Lvl;
            BidWallPrice := Arr.Item(I).Item(0).AsFloat;
          end;
        end;
      Arr := Root.Get('asks');
      if Arr <> nil then
        for I := 0 to Arr.Count - 1 do
        begin
          Lvl := Arr.Item(I).Item(0).AsFloat * Arr.Item(I).Item(1).AsFloat;
          AskUSD := AskUSD + Lvl;
          if Lvl > AskWallUSD then   // antrian jual terbesar pada satu harga
          begin
            AskWallUSD := Lvl;
            AskWallPrice := Arr.Item(I).Item(0).AsFloat;
          end;
        end;
      Result := True;
    finally
      Root.Free;
    end;
  except
    Result := False;
  end;
end;

{ Daftar level order book (harga & jumlah koin), terbaik dulu. }
function GetDepthLevels(const Sym: string; Limit: Integer;
  out BidP, BidQ, AskP, AskQ: TDoubleArray): Boolean;
var
  Root: TJNode;
  Url: string;

  procedure Load(Arr: TJNode; var P, Q: TDoubleArray);
  var
    I: Integer;
  begin
    SetLength(P, 0);
    SetLength(Q, 0);
    if Arr = nil then
      Exit;
    SetLength(P, Arr.Count);
    SetLength(Q, Arr.Count);
    for I := 0 to Arr.Count - 1 do
    begin
      P[I] := Arr.Item(I).Item(0).AsFloat;
      Q[I] := Arr.Item(I).Item(1).AsFloat;
    end;
  end;

begin
  Result := False;
  if UseSpot then
    Url := Format('%s/api/v3/depth?symbol=%s&limit=%d', [SPOT, Sym, Limit])
  else
    Url := Format('%s/fapi/v1/depth?symbol=%s&limit=%d', [FAPI, Sym, Limit]);
  try
    Root := FetchJson(Url);
    try
      Load(Root.Get('bids'), BidP, BidQ);
      Load(Root.Get('asks'), AskP, AskQ);
      Result := (Length(BidP) > 0) and (Length(AskP) > 0);
    finally
      Root.Free;
    end;
  except
    Result := False;
  end;
end;

procedure OpenBinance(const Sym: string);
begin
  ShellExecute(0, 'open', PChar(BINANCE_WEB + Sym), nil, nil, SW_SHOWNORMAL);
end;

end.
