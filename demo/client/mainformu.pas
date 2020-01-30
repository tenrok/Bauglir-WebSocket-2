unit MainFormU;

{$mode delphi}{$H+}

interface

uses
  Classes, SysUtils, FileUtil, LResources, Forms, Controls, Graphics, Dialogs, StdCtrls, ComCtrls, ExtCtrls, ActnList,
  blcksock, websocket2, customserver2;

type
  { TTestWebSocketClientConnection }

  TTestWebSocketClientConnection = class(TWebSocketClientConnection)
    fFramedText: String;
    fFramedStream: TMemoryStream;
    fPing: String;
    fPong: String;
    procedure ProcessText(aFinal, aRes1, aRes2, aRes3: Boolean; aData: String); override;
    procedure ProcessTextContinuation(aFinal, aRes1, aRes2, aRes3: Boolean; aData: String); override;
    procedure ProcessStream(aFinal, aRes1, aRes2, aRes3: Boolean; aData: TMemoryStream); override;
    procedure ProcessStreamContinuation(aFinal, aRes1, aRes2, aRes3: Boolean; aData: TMemoryStream); override;
    procedure ProcessPing(aData: String); override;
    procedure ProcessPong(aData: String); override;
    procedure SyncTextFrame;
    procedure SyncBinFrame;
    procedure SyncPing;
    procedure SyncPong;
  public
    constructor Create(aHost, aPort, aResourceName: String; aOrigin: String = '-'; aProtocol: String = '-';
      aExtension: String = '-'; aCookie: String = '-'; aVersion: Integer = 8); override;
    destructor Destroy; override;
    property ReadFinal: Boolean read fReadFinal;
    property ReadRes1: Boolean read fReadRes1;
    property ReadRes2: Boolean read fReadRes2;
    property ReadRes3: Boolean read fReadRes3;
    property ReadCode: Integer read fReadCode;
    property ReadStream: TMemoryStream read fReadStream;
    property WriteFinal: Boolean read fWriteFinal;
    property WriteRes1: Boolean read fWriteRes1;
    property WriteRes2: Boolean read fWriteRes2;
    property WriteRes3: Boolean read fWriteRes3;
    property WriteCode: Integer read fWriteCode;
    property WriteStream: TMemoryStream read fWriteStream;
  end;

  { TMainForm }

  TMainForm = class(TForm)
    SendAction: TAction;
    EndAction: TAction;
    ActionList1: TActionList;
    Button1: TButton;
    EndButton: TButton;
    GroupBox1: TGroupBox;
    HostCombo: TComboBox;
    Image1: TImage;
    InfoMemo: TMemo;
    Label1: TLabel;
    Label2: TLabel;
    LastReceivedMemo: TMemo;
    LastSentMemo: TMemo;
    PageControl1: TPageControl;
    PageControl2: TPageControl;
    Panel3: TPanel;
    Panel4: TPanel;
    Panel6: TPanel;
    Panel8: TPanel;
    PortCombo: TComboBox;
    SendMemo: TMemo;
    FrameReceiveMemo: TMemo;
    ServerErrorLabel: TLabel;
    Splitter1: TSplitter;
    Splitter4: TSplitter;
    SSLCheck: TCheckBox;
    StartButton: TButton;
    TabSheet1: TTabSheet;
    TabSheet2: TTabSheet;
    TabSheet3: TTabSheet;
    TabSheet4: TTabSheet;
    procedure EndActionExecute(Sender: TObject);
    procedure EndActionUpdate(Sender: TObject);
    procedure FormClose(Sender: TObject; var CloseAction: TCloseAction);
    procedure SendActionExecute(Sender: TObject);
    procedure StartButtonClick(Sender: TObject);
  private
    fClient: TWebSocketClientConnection;
    fFrameString: String;
    procedure DoClientOpen(aSender: TWebSocketCustomConnection);
    procedure DoClientRead(aSender: TWebSocketCustomConnection; aFinal, aRes1, aRes2, aRes3: Boolean;
      aCode: Integer; aData: TMemoryStream);
    procedure DoClientWrite(aSender: TWebSocketCustomConnection; aFinal, aRes1, aRes2, aRes3: Boolean;
      aCode: Integer; aData: TMemoryStream);
    procedure DoClientClose(aSender: TWebSocketCustomConnection; aCloseCode: Integer; aCloseReason: String; aClosedByPeer: Boolean);
    procedure DoClientSocket(Sender: TObject; Reason: THookSocketReason; const Value: String);
  end;

var
  MainForm: TMainForm;

implementation

{$R *.lfm}

uses
  StrUtils, synachar, synautil, Math, TypInfo;

{ TMainForm }

procedure TMainForm.FormClose(Sender: TObject; var CloseAction: TCloseAction);
begin
  if EndButton.Enabled then
    EndAction.Execute;
end;

procedure TMainForm.SendActionExecute(Sender: TObject);
begin
  fClient.SendText(CharsetConversion(SendMemo.Text, GetCurCP, UTF_8));
end;

procedure TMainForm.StartButtonClick(Sender: TObject);
begin
  fClient := TTestWebSocketClientConnection.Create(HostCombo.Text, PortCombo.Text, '/');
  fClient.OnRead := DoClientRead;
  fClient.OnWrite := DoClientWrite;
  fClient.OnClose := DoClientClose;
  fClient.OnOpen := DoClientOpen;
  //fClient.Socket.OnSyncStatus := DoClientSocket;
  fClient.SSL := Boolean(SslCheck.Checked);
  fClient.Start;
end;

procedure TMainForm.EndActionExecute(Sender: TObject);
begin
  //fClient.TerminateThread;
  fClient.Close(wsCloseNormal, 'bye bye');
  //Sleep(2000);
end;

procedure TMainForm.EndActionUpdate(Sender: TObject);
begin
  TAction(Sender).Enabled := not StartButton.Enabled;
end;

procedure TMainForm.DoClientOpen(aSender: TWebSocketCustomConnection);
begin
  InfoMemo.Lines.Insert(0, Format('DoClientOpen %d', [aSender.Index]));
  StartButton.Enabled := False;
end;

procedure TMainForm.DoClientRead(aSender: TWebSocketCustomConnection; aFinal, aRes1, aRes2, aRes3: Boolean;
  aCode: Integer; aData: TMemoryStream);
var
  S: String;
  C: TTestWebSocketClientConnection;
begin
  C := TTestWebSocketClientConnection(aSender);
  InfoMemo.Lines.Insert(0, Format('DoClientRead %d, final: %d, ext1: %d, ext2: %d, ext3: %d, type: %d, length: %d',
    [aSender.Index, Ord(aFinal), Ord(aRes1), Ord(aRes2), Ord(aRes3), aCode, aData.Size]));
  S := ReadStrFromStream(C.ReadStream, Min(C.ReadStream.Size, 10 * 1024));
  if C.ReadCode = wsCodeText then
    LastReceivedMemo.Lines.Text := CharsetConversion(S, UTF_8, GetCurCP)
  else
    LastReceivedMemo.Lines.Text := S;
end;

procedure TMainForm.DoClientWrite(aSender: TWebSocketCustomConnection; aFinal, aRes1, aRes2, aRes3: Boolean;
  aCode: Integer; aData: TMemoryStream);
var
  S: String;
  C: TTestWebSocketClientConnection;
begin
  C := TTestWebSocketClientConnection(aSender);
  InfoMemo.Lines.Insert(0, Format('DoClientWrite %d, final: %d, ext1: %d, ext2: %d, ext3: %d, type: %d, length: %d',
    [aSender.Index, Ord(aFinal), Ord(aRes1), Ord(aRes2), Ord(aRes3), aCode, aData.Size]));
  S := ReadStrFromStream(C.WriteStream, min(C.WriteStream.Size, 10 * 1024));
  if C.ReadCode = wsCodeText then
    LastSentMemo.Lines.Text := CharsetConversion(S, UTF_8, GetCurCP)
  else
    LastSentMemo.Lines.Text := S;
end;

procedure TMainForm.DoClientClose(aSender: TWebSocketCustomConnection; aCloseCode: Integer; aCloseReason: String; aClosedByPeer: Boolean);
begin
  InfoMemo.Lines.Insert(0, Format('DoClientClose %d, %d, %s, %s', [aSender.Index, aCloseCode, aCloseReason,
    IfThen(aClosedByPeer, 'closed by peer', 'closed by me')]));
  EndButton.Enabled := False;
  StartButton.Enabled := True;
end;

procedure TMainForm.DoClientSocket(Sender: TObject; Reason: THookSocketReason; const Value: String);
begin
  InfoMemo.Lines.Insert(0, Format('DoClientSocket %d, %s, %s', [TTCPCustomConnectionSocket(Sender).Connection.Index,
    GetEnumName(TypeInfo(THookSocketReason), Ord(Reason)), Value]));
end;

{ TTestWebSocketClientConnection }

procedure TTestWebSocketClientConnection.ProcessText(aFinal, aRes1, aRes2, aRes3: Boolean; aData: String);
begin
  fFramedText := aData;
end;

procedure TTestWebSocketClientConnection.ProcessTextContinuation(aFinal, aRes1, aRes2, aRes3: Boolean; aData: String);
begin
  fFramedText := fFramedText + aData;
  if aFinal then
    Synchronize(SyncTextFrame);
end;

procedure TTestWebSocketClientConnection.ProcessStream(aFinal, aRes1, aRes2, aRes3: Boolean; aData: TMemoryStream);
begin
  fFramedStream.Size := 0;
  fFramedStream.CopyFrom(aData, aData.Size);
  MainForm.InfoMemo.Lines.Insert(0, Format('ProcessStream %d, %d, %d, %d, %d, %d ', [Index, Ord(aFinal),
    Ord(aRes1), Ord(aRes2), Ord(aRes3), aData.Size]));
  if aFinal then
    Synchronize(SyncBinFrame);
end;

procedure TTestWebSocketClientConnection.ProcessStreamContinuation(aFinal, aRes1, aRes2, aRes3: Boolean; aData: TMemoryStream);
begin
  fFramedStream.CopyFrom(aData, aData.Size);
  MainForm.InfoMemo.Lines.Insert(0, Format('ProcessStreamContinuation %d, %d, %d, %d, %d, %d ',
    [Index, Ord(aFinal), Ord(aRes1), Ord(aRes2), Ord(aRes3), aData.Size]));
  if aFinal then
    Synchronize(SyncBinFrame);
end;

procedure TTestWebSocketClientConnection.ProcessPing(aData: String);
begin
  Pong(aData);
  fPing := aData;
  Synchronize(SyncPing);
end;

procedure TTestWebSocketClientConnection.ProcessPong(aData: String);
begin
  fPong := aData;
  Synchronize(SyncPong);
end;

procedure TTestWebSocketClientConnection.SyncTextFrame;
begin
  MainForm.FrameReceiveMemo.Text := CharsetConversion(fFramedText, UTF_8, GetCurCP);
end;

procedure TTestWebSocketClientConnection.SyncBinFrame;
var
  png: TPortableNetworkGraphic;
begin
  MainForm.InfoMemo.Lines.Insert(0, Format('SyncBinFrame %d', [fFramedStream.Size]));
  png := TPortableNetworkGraphic.Create;
  fFramedStream.Position := 0;
  png.LoadFromStream(fFramedStream);
  MainForm.Image1.Picture.Assign(png);
  png.Free;
end;

procedure TTestWebSocketClientConnection.SyncPing;
begin
  MainForm.InfoMemo.Lines.Insert(0, Format('SyncPing %s', [fPing]));
end;

procedure TTestWebSocketClientConnection.SyncPong;
begin
  MainForm.InfoMemo.Lines.Insert(0, Format('SyncPong %s', [fPong]));
end;

constructor TTestWebSocketClientConnection.Create(aHost, aPort, aResourceName: String; aOrigin: String = '-';
  aProtocol: String = '-'; aExtension: String = '-'; aCookie: String = '-'; aVersion: Integer = 8);
begin
  inherited;
  fFramedText := '';
  fFramedStream := TMemoryStream.Create;
end;

destructor TTestWebSocketClientConnection.Destroy;
begin
  fFramedStream.Free;
  inherited;
end;

end.
