unit uJson;

{ Parser JSON sederhana untuk Delphi 7 (Delphi 7 belum punya System.JSON) }

interface

uses
  SysUtils, Classes;

type
  TJKind = (jkNull, jkBool, jkNumber, jkString, jkArray, jkObject);

  TJNode = class
  private
    FItems: TList;
    FNames: TStringList;
  public
    Kind: TJKind;
    Value: string;
    constructor Create(AKind: TJKind);
    destructor Destroy; override;
    procedure Add(const AName: string; Node: TJNode);
    function Count: Integer;
    function Item(I: Integer): TJNode;
    function Get(const AName: string): TJNode;
    function Str(const AName: string): string;
    function Num(const AName: string): Double;
    function AsFloat: Double;
  end;

function ParseJson(const Text: string): TJNode;
function JFloat(const S: string): Double;

implementation

type
  TJParser = class
  private
    S: string;
    P, L: Integer;
    function Cur: Char;
    procedure SkipWs;
    procedure Error(const Msg: string);
    function ParseString: string;
    function ParseValue: TJNode;
  end;

function JFloat(const S: string): Double;
var
  Code: Integer;
begin
  Val(S, Result, Code);
  if Code <> 0 then
    Result := 0;
end;

{ TJNode }

constructor TJNode.Create(AKind: TJKind);
begin
  inherited Create;
  Kind := AKind;
  if AKind in [jkArray, jkObject] then
    FItems := TList.Create;
  if AKind = jkObject then
    FNames := TStringList.Create;
end;

destructor TJNode.Destroy;
var
  I: Integer;
begin
  if FItems <> nil then
  begin
    for I := 0 to FItems.Count - 1 do
      TJNode(FItems[I]).Free;
    FItems.Free;
  end;
  FNames.Free;
  inherited;
end;

procedure TJNode.Add(const AName: string; Node: TJNode);
begin
  FItems.Add(Node);
  if FNames <> nil then
    FNames.Add(AName);
end;

function TJNode.Count: Integer;
begin
  if FItems = nil then
    Result := 0
  else
    Result := FItems.Count;
end;

function TJNode.Item(I: Integer): TJNode;
begin
  if (FItems = nil) or (I < 0) or (I >= FItems.Count) then
    Result := nil
  else
    Result := TJNode(FItems[I]);
end;

function TJNode.Get(const AName: string): TJNode;
var
  I: Integer;
begin
  Result := nil;
  if FNames = nil then
    Exit;
  I := FNames.IndexOf(AName);
  if I >= 0 then
    Result := TJNode(FItems[I]);
end;

function TJNode.Str(const AName: string): string;
var
  N: TJNode;
begin
  N := Get(AName);
  if N <> nil then
    Result := N.Value
  else
    Result := '';
end;

function TJNode.Num(const AName: string): Double;
begin
  Result := JFloat(Str(AName));
end;

function TJNode.AsFloat: Double;
begin
  Result := JFloat(Value);
end;

{ TJParser }

function TJParser.Cur: Char;
begin
  if P <= L then
    Result := S[P]
  else
    Result := #0;
end;

procedure TJParser.SkipWs;
begin
  while (P <= L) and (S[P] in [' ', #9, #10, #13]) do
    Inc(P);
end;

procedure TJParser.Error(const Msg: string);
begin
  raise Exception.CreateFmt('JSON error pada posisi %d: %s', [P, Msg]);
end;

function TJParser.ParseString: string;
var
  Start, Code: Integer;
  C: Char;
begin
  Inc(P); // lewati tanda kutip pembuka
  Start := P;
  while (P <= L) and (S[P] <> '"') and (S[P] <> '\') do
    Inc(P);
  Result := Copy(S, Start, P - Start);
  if Cur = '"' then
  begin
    Inc(P);
    Exit;
  end;
  // jalur lambat: ada karakter escape
  while True do
  begin
    C := Cur;
    if C = #0 then
      Error('string tidak ditutup');
    if C = '"' then
    begin
      Inc(P);
      Break;
    end;
    if C = '\' then
    begin
      Inc(P);
      case Cur of
        'n': Result := Result + #10;
        'r': Result := Result + #13;
        't': Result := Result + #9;
        'b': Result := Result + #8;
        'f': Result := Result + #12;
        'u':
          begin
            Code := StrToIntDef('$' + Copy(S, P + 1, 4), 63);
            if Code < 256 then
              Result := Result + Chr(Code)
            else
              Result := Result + '?';
            Inc(P, 4);
          end;
      else
        Result := Result + Cur;
      end;
      Inc(P);
    end
    else
    begin
      Result := Result + C;
      Inc(P);
    end;
  end;
end;

function TJParser.ParseValue: TJNode;
var
  Name: string;
  Start: Integer;
begin
  SkipWs;
  case Cur of
    '{':
      begin
        Result := TJNode.Create(jkObject);
        try
          Inc(P);
          SkipWs;
          if Cur = '}' then
          begin
            Inc(P);
            Exit;
          end;
          while True do
          begin
            SkipWs;
            if Cur <> '"' then
              Error('nama field diharapkan');
            Name := ParseString;
            SkipWs;
            if Cur <> ':' then
              Error('":" diharapkan');
            Inc(P);
            Result.Add(Name, ParseValue);
            SkipWs;
            if Cur = ',' then
              Inc(P)
            else if Cur = '}' then
            begin
              Inc(P);
              Break;
            end
            else
              Error('"," atau "}" diharapkan');
          end;
        except
          Result.Free;
          raise;
        end;
      end;
    '[':
      begin
        Result := TJNode.Create(jkArray);
        try
          Inc(P);
          SkipWs;
          if Cur = ']' then
          begin
            Inc(P);
            Exit;
          end;
          while True do
          begin
            Result.Add('', ParseValue);
            SkipWs;
            if Cur = ',' then
              Inc(P)
            else if Cur = ']' then
            begin
              Inc(P);
              Break;
            end
            else
              Error('"," atau "]" diharapkan');
          end;
        except
          Result.Free;
          raise;
        end;
      end;
    '"':
      begin
        Result := TJNode.Create(jkString);
        Result.Value := ParseString;
      end;
    't', 'f':
      begin
        Result := TJNode.Create(jkBool);
        if Copy(S, P, 4) = 'true' then
        begin
          Result.Value := 'true';
          Inc(P, 4);
        end
        else
        begin
          Result.Value := 'false';
          Inc(P, 5);
        end;
      end;
    'n':
      begin
        Result := TJNode.Create(jkNull);
        Inc(P, 4);
      end;
  else
    Start := P;
    while (P <= L) and (S[P] in ['0'..'9', '-', '+', '.', 'e', 'E']) do
      Inc(P);
    if P = Start then
      Error('nilai tidak valid');
    Result := TJNode.Create(jkNumber);
    Result.Value := Copy(S, Start, P - Start);
  end;
end;

function ParseJson(const Text: string): TJNode;
var
  Parser: TJParser;
begin
  Parser := TJParser.Create;
  try
    Parser.S := Text;
    Parser.P := 1;
    Parser.L := Length(Text);
    Result := Parser.ParseValue;
  finally
    Parser.Free;
  end;
end;

end.
