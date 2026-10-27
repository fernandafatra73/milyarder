program FernandaTaker;

uses
  Forms,
  SysUtils,
  uJson in 'uJson.pas',
  uAnalysis in 'uAnalysis.pas',
  uBinance in 'uBinance.pas',
  uWorkers in 'uWorkers.pas',
  uChart in 'uChart.pas',
  uBtc in 'uBtc.pas',
  uDemo in 'uDemo.pas',
  uExness in 'uExness.pas',
  uCandle in 'uCandle.pas',
  uShot in 'uShot.pas',
  uMain in 'uMain.pas';

begin
  // format angka konsisten seperti Binance: 1,234.56
  DecimalSeparator := '.';
  ThousandSeparator := ',';
  Application.Initialize;
  Application.UpdateFormatSettings := False;
  Application.Title := 'Fernanda Taker';
  Application.CreateForm(TMainForm, MainForm);
  Application.Run;
end.
