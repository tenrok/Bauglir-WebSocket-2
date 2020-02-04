unit MainFormU;

{$mode DELPHI}{$H+}

interface

uses
  Classes, SysUtils, FileUtil, Forms, Controls, Graphics, Dialogs, ExtCtrls, StdCtrls, ActnList, ComCtrls, ExtDlgs, Menus, Math,
  blcksock, customserver2, WebSocket2;

type
  { TMainForm }

  TMainForm = class(TForm)
    CloseAction: TAction;
    MenuItem1: TMenuItem;
    PingAction: TAction;
    PongAction: TAction;
    LoadImageAction: TAction;
    OpenPictureDialog: TOpenPictureDialog;
    PopupMenu1: TPopupMenu;
    SendFramesAction: TAction;
    BroadcastAction: TAction;
    SendTextAction: TAction;
    Button1: TButton;
    Button2: TButton;
    Button3: TButton;
    Button4: TButton;
    Button5: TButton;
    Button6: TButton;
    EndAction: TAction;
    Image1: TImage;
    InfoMemo: TMemo;
    ConnectionList: TListView;
    SendSelectedMemo: TMemo;
    BroadcastMemo: TMemo;
    ConnectionInfoMemo: TMemo;
    LastSentMemo: TMemo;
    LastReceivedMemo: TMemo;
    SendSelectedMemo2: TMemo;
    PageControl1: TPageControl;
    PageControl2: TPageControl;
    Panel1: TPanel;
    Panel2: TPanel;
    Panel3: TPanel;
    Panel4: TPanel;
    Panel5: TPanel;
    Panel6: TPanel;
    Panel7: TPanel;
    Panel8: TPanel;
    ServerErrorLabel: TLabel;
    Splitter1: TSplitter;
    Splitter2: TSplitter;
    Splitter3: TSplitter;
    Splitter4: TSplitter;
    Splitter5: TSplitter;
    StartAction: TAction;
    ActionList1: TActionList;
    StartButton: TButton;
    EndButton: TButton;
    SSLCheck: TCheckBox;
    HostCombo: TComboBox;
    PortCombo: TComboBox;
    GroupBox1: TGroupBox;
    Label1: TLabel;
    Label2: TLabel;
    TabSheet1: TTabSheet;
    TabSheet2: TTabSheet;
    TabSheet3: TTabSheet;
    TabSheet4: TTabSheet;
    procedure BroadcastActionExecute(Sender: TObject);
    procedure CloseActionExecute(Sender: TObject);
    procedure ConnectionListChange(Sender: TObject; Item: TListItem; Change: TItemChange);
    procedure EndActionExecute(Sender: TObject);
    procedure EndActionUpdate(Sender: TObject);
    procedure LoadImageActionExecute(Sender: TObject);
    procedure PingActionExecute(Sender: TObject);
    procedure PongActionExecute(Sender: TObject);
    procedure SendFramesActionExecute(Sender: TObject);
    procedure StartActionExecute(Sender: TObject);
    procedure SendTextActionExecute(Sender: TObject);
    procedure FormClose(Sender: TObject; var Action: TCloseAction);
  private
    fServer: TWebSocketServer;
    procedure DoServerAfterAddConnection(Server: TCustomServer; aConnection: TCustomConnection);
    procedure DoServerBeforeAddConnection(Server: TCustomServer; aConnection: TCustomConnection; var CanAdd: Boolean);
    procedure DoServerAfterRemoveConnection(Server: TCustomServer; aConnection: TCustomConnection);
    procedure DoServerBeforeRemoveConnection(Server: TCustomServer; aConnection: TCustomConnection);
    procedure DoServerSocketError(Server: TCustomServer; Socket: TTCPBlockSocket);
    procedure DoConnectionOpen(aSender: TWebSocketCustomConnection);
    procedure DoConnectionRead(aSender: TWebSocketCustomConnection; aFinal, aRes1, aRes2, aRes3: Boolean;
      aCode: Integer; aData: TMemoryStream);
    procedure DoConnectionWrite(aSender: TWebSocketCustomConnection; aFinal, aRes1, aRes2, aRes3: Boolean;
      aCode: Integer; aData: TMemoryStream);
    procedure DoConnectionClose(aSender: TWebSocketCustomConnection; aCloseCode: Integer; aCloseReason: string; aClosedByPeer: Boolean);
    procedure DoConnectionSocket(Sender: TObject; Reason: THookSocketReason; const Value: string);
    function ListItemByIndex(aConnectionIndex: Integer): TListItem;
  end;

  TTestWebSocketServerConnection = class;

  { TTestWebSocketServer }

  TTestWebSocketServer = class(TWebSocketServer)
  public
    function GetWebSocketConnectionClass(Socket: TTCPCustomConnectionSocket; Header: TStringList;
      ResourceName, Host, Port, Origin, Cookie: string; out HttpResult: Integer;
      var Protocol, Extensions: string): TWebSocketServerConnections; override;
  end;

  TTestWebSocketServerConnection = class(TWebSocketServerConnection)
  public
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

var
  MainForm: TMainForm;

implementation

{$R *.lfm}

uses
  StrUtils, synachar, synautil, TypInfo;

{ TMainForm }

procedure TMainForm.StartActionExecute(Sender: TObject);
begin
  ServerErrorLabel.Caption := '';
  fServer := TTestWebSocketServer.Create(HostCombo.Text, PortCombo.Text);
  fServer.OnAfterAddConnection := DoServerAfterAddConnection;
  fServer.OnBeforeAddConnection := DoServerBeforeAddConnection;
  fServer.OnAfterRemoveConnection := DoServerAfterRemoveConnection;
  fServer.OnBeforeRemoveConnection := DoServerBeforeRemoveConnection;
  fServer.OnSocketError := DoServerSocketError;
  fServer.SSL := Boolean(SslCheck.Checked);
  fServer.SSLCertificateFile := ExtractFilePath(ParamStr(0)) + 'test.crt';
  fServer.SSLPrivateKeyFile := ExtractFilePath(ParamStr(0)) + 'test.key';
  fServer.Start;
  StartButton.Enabled := False;
end;

procedure TMainForm.SendTextActionExecute(Sender: TObject);
var
  i: Integer;
begin
  fServer.LockTermination;
  for i := 0 to ConnectionList.Items.Count - 1 do
    if ConnectionList.Items[i].Selected then
      TWebSocketCustomConnection(ConnectionList.Items[i].Data).SendText(CharsetConversion(SendSelectedMemo.Text, GetCurCP, UTF_8));
  fServer.UnLockTermination;
end;

procedure TMainForm.FormClose(Sender: TObject; var Action: TCloseAction);
begin
  if EndButton.Enabled then
    EndAction.Execute;
end;

procedure TMainForm.DoServerAfterAddConnection(Server: TCustomServer; aConnection: TCustomConnection);
begin
  InfoMemo.Lines.Insert(0, Format('DoServerAfterAddConnection %d', [aConnection.Index]));
  with ConnectionList.Items.Add do
  begin
    Data := aConnection;
    Caption := (Format('(%d) %s:%d', [aConnection.Index, aConnection.Socket.GetRemoteSinIP, aConnection.Socket.GetLocalSinPort]));
    SubItems.Add('0');
    SubItems.Add('0');
    TWebSocketServerConnection(aConnection).OnWrite := DoConnectionWrite;
    TWebSocketServerConnection(aConnection).OnRead := DoConnectionRead;
    TWebSocketServerConnection(aConnection).OnClose := DoConnectionClose;
    TWebSocketServerConnection(aConnection).OnOpen := DoConnectionOpen;
    //TWebSocketServerConnection(aConnection).Socket.OnSyncStatus := DoConnectionSocket;
  end;
end;

procedure TMainForm.DoServerBeforeAddConnection(Server: TCustomServer; aConnection: TCustomConnection; var CanAdd: Boolean);
begin
  InfoMemo.Lines.Insert(0, Format('DoServerBeforeAddConnection %d', [aConnection.Index]));
end;

procedure TMainForm.DoServerAfterRemoveConnection(Server: TCustomServer; aConnection: TCustomConnection);
begin
  InfoMemo.Lines.Insert(0, Format('DoServerAfterRemoveConnection %d', [aConnection.Index]));
end;

procedure TMainForm.DoServerBeforeRemoveConnection(Server: TCustomServer; aConnection: TCustomConnection);
var
  i: Integer;
begin
  InfoMemo.Lines.Insert(0, Format('DoServerBeforeRemoveConnection %d', [aConnection.Index]));
  for i := 0 to ConnectionList.Items.Count - 1 do
    if TCustomConnection(ConnectionList.Items[i].Data).Index = aConnection.Index then
    begin
      ConnectionList.Items.Delete(i);
      Break;
    end;
end;

procedure TMainForm.DoServerSocketError(Server: TCustomServer; Socket: TTCPBlockSocket);
begin
  ServerErrorLabel.Caption := Format('%s - %d (%s)', [FormatDateTime('yyyy-mm-dd hh:nn:ss', Now), Socket.LastError, Socket.LastErrorDesc]);
  InfoMemo.Lines.Insert(0, ServerErrorLabel.Caption);
  ServerErrorLabel.Repaint;
end;

procedure TMainForm.DoConnectionOpen(aSender: TWebSocketCustomConnection);
begin
  InfoMemo.Lines.Insert(0, Format('DoConnectionOpen %d', [aSender.Index]));
end;

procedure TMainForm.DoConnectionRead(aSender: TWebSocketCustomConnection; aFinal, aRes1, aRes2, aRes3: Boolean;
  aCode: Integer; aData: TMemoryStream);
var
  item: TListItem;
begin
  InfoMemo.Lines.Insert(0, Format('DoConnectionRead %d, final: %d, ext1: %d, ext2: %d, ext3: %d, type: %d, length: %d',
    [aSender.Index, Ord(aFinal), Ord(aRes1), Ord(aRes2), Ord(aRes3), aCode, aData.Size]));
  item := ListItemByIndex(aSender.Index);
  item.SubItems[0] := IntToStr(StrToInt(item.SubItems[0]) + 1);
end;

procedure TMainForm.DoConnectionWrite(aSender: TWebSocketCustomConnection; aFinal, aRes1, aRes2, aRes3: Boolean;
  aCode: Integer; aData: TMemoryStream);
var
  item: TListItem;
begin
  InfoMemo.Lines.Insert(0, Format('DoConnectionWrite %d, final: %d, ext1: %d, ext2: %d, ext3: %d, type: %d, length: %d',
    [aSender.Index, Ord(aFinal), Ord(aRes1), Ord(aRes2), Ord(aRes3), aCode, aData.Size]));
  item := ListItemByIndex(aSender.Index);
  item.SubItems[1] := IntToStr(StrToInt(item.SubItems[1]) + 1);
end;

procedure TMainForm.DoConnectionClose(aSender: TWebSocketCustomConnection; aCloseCode: Integer; aCloseReason: string;
  aClosedByPeer: Boolean);
begin
  InfoMemo.Lines.Insert(0, Format('DoConnectionClose %d, %d, %s, %s', [aSender.Index, aCloseCode, aCloseReason,
    IfThen(aClosedByPeer, 'closed by peer', 'closed by me')]));
end;

procedure TMainForm.DoConnectionSocket(Sender: TObject; Reason: THookSocketReason; const Value: string);
begin
  InfoMemo.Lines.Insert(0, Format('DoConnectionSocket %d, %s, %s', [TTCPCustomConnectionSocket(Sender).Connection.Index,
    GetEnumName(TypeInfo(THookSocketReason), Ord(Reason)), Value]));
end;

function TMainForm.ListItemByIndex(aConnectionIndex: Integer): TListItem;
var
  i: Integer;
begin
  fServer.LockTermination;
  Result := nil;
  for i := 0 to ConnectionList.Items.Count - 1 do
    if TCustomConnection(ConnectionList.Items[i].Data).Index = aConnectionIndex then
    begin
      Result := ConnectionList.Items[i];
      Break;
    end;
  fServer.UnLockTermination;
end;

procedure TMainForm.EndActionExecute(Sender: TObject);
begin
  ServerErrorLabel.Caption := '';
  fServer.TerminateThread;
  {$IFDEF WIN32}
  WaitForSingleObject(fServer.Handle, 60 * 1000);
  {$ELSE WIN32}
  Sleep(2000);
  {$ENDIF WIN32}
  ConnectionList.Items.Clear;
  StartButton.Enabled := True;
end;

procedure TMainForm.BroadcastActionExecute(Sender: TObject);
begin
  fServer.BroadcastText(CharsetConversion(BroadcastMemo.Text, GetCurCP, UTF_8));
end;

procedure TMainForm.CloseActionExecute(Sender: TObject);
var
  i: Integer;
begin
  fServer.LockTermination;
  for i := 0 to ConnectionList.Items.Count - 1 do
    if ConnectionList.Items[i].Selected then
    begin
      ConnectionList.Items[i].Selected := False;
      TWebSocketCustomConnection(ConnectionList.Items[i].Data).Close(wsCloseNormal, 'closing connection');
    end;
  fServer.UnLockTermination;
end;

procedure TMainForm.ConnectionListChange(Sender: TObject; Item: TListItem; Change: TItemChange);
var
  s: string;
  c: TTestWebSocketServerConnection;
begin
  LastSentMemo.Lines.Text := '';
  LastReceivedMemo.Lines.Text := '';
  ConnectionInfoMemo.Text := '';
  if (Change = ctState) and Item.Selected and (ConnectionList.SelCount = 1) then
  begin
    //TWebSocketCustomConnection(ConnectionList.Items[I]. Data).SendText(SendSelectedMemo.Text)
    c := TTestWebSocketServerConnection(Item.Data);
    s := ReadStrFromStream(c.ReadStream, Min(c.ReadStream.Size, 10 * 1024));
    if c.ReadCode = wsCodeText then
      LastReceivedMemo.Lines.Text := CharsetConversion(s, UTF_8, GetCurCP)
    else
      LastReceivedMemo.Lines.Text := s;
    s := ReadStrFromStream(c.WriteStream, Min(c.WriteStream.Size, 10 * 1024));
    if c.WriteCode = wsCodeText then
      LastSentMemo.Lines.Text := CharsetConversion(s, UTF_8, GetCurCP)
    else
      LastSentMemo.Lines.Text := s;
    c.ReadStream.Position := 0;
    c.WriteStream.Position := 0;
    ConnectionInfoMemo.Text := c.Header.Text;
  end;
end;

procedure TMainForm.EndActionUpdate(Sender: TObject);
begin
  TAction(Sender).Enabled := not StartButton.Enabled;
end;

procedure TMainForm.LoadImageActionExecute(Sender: TObject);
var
  ms1, ms2, ms3: TMemoryStream;
  fs: TFileStream;
  len, i: Integer;
  c: TWebSocketCustomConnection;
begin
  OpenPictureDialog.Filter :=
    'All (*.png;*.bmp;*.ico;*.emf;*.wmf)|*.png;*.bmp;*.ico;*.emf;*.wmf|PNG Image File (*.png)|*.png|Bitmaps (*.bmp)|*.bmp|Icons (*.ico)|*.ico|Enhanced Metafiles (*.emf)|*.emf|Metafiles (*.wmf)|*.wmf';
  if OpenPictureDialog.Execute then
  begin
    Image1.Picture.LoadFromFile(OpenPictureDialog.FileName);

    ms1 := TMemoryStream.Create;
    ms2 := TMemoryStream.Create;
    ms3 := TMemoryStream.Create;
    fs := TFileStream.Create(OpenPictureDialog.FileName, fmOpenRead);
    try
      fs.Position := 0;
      len := fs.Size div 3;
      ms1.CopyFrom(fs, len);
      ms2.CopyFrom(fs, len);
      ms3.CopyFrom(fs, fs.Size - 2 * len);
      fServer.LockTermination;
      for i := 0 to ConnectionList.Items.Count - 1 do
        if ConnectionList.Items[i].Selected then
        begin
          c := TWebSocketCustomConnection(ConnectionList.Items[i].Data);
          c.SendBinary(ms1, False);
          c.SendBinaryContinuation(ms2, False);
          c.SendBinaryContinuation(ms3, True);
          {
          fs.Position := 0;
          c.SendBinary(fs, True);
          }
        end;
      fServer.UnLockTermination;
    finally
      ms1.Free;
      ms2.Free;
      ms3.Free;
      fs.Free;
    end;
  end;
end;

procedure TMainForm.PingActionExecute(Sender: TObject);
var
  i: Integer;
begin
  fServer.LockTermination;
  for i := 0 to ConnectionList.Items.Count - 1 do
    if ConnectionList.Items[i].Selected then
      TWebSocketCustomConnection(ConnectionList.Items[i].Data).Ping('ping you');
  fServer.UnLockTermination;
end;

procedure TMainForm.PongActionExecute(Sender: TObject);
var
  i: Integer;
begin
  fServer.LockTermination;
  for i := 0 to ConnectionList.Items.Count - 1 do
    if ConnectionList.Items[i].Selected then
      TWebSocketCustomConnection(ConnectionList.Items[i].Data).Pong('pong you');
  fServer.UnLockTermination;
end;

procedure TMainForm.SendFramesActionExecute(Sender: TObject);
var
  i, len: Integer;
  s, s1, s2, s3: string;
  c: TWebSocketCustomConnection;
  us: UnicodeString;
begin
  s := CharsetConversion(SendSelectedMemo2.Text, GetCurCP, UTF_8);
  us := UTF8Decode(s);
  len := Length(us) div 3;
  s1 := Copy(us, 1, len);
  s2 := Copy(us, len + 1, len);
  s3 := Copy(us, 2 * len + 1, length(s));
  s1 := UTF8Encode(s1);
  s2 := UTF8Encode(s2);
  s3 := UTF8Encode(s3);
  fServer.LockTermination;
  for i := 0 to ConnectionList.Items.Count - 1 do
    if ConnectionList.Items[i].Selected then
    begin
      c := TWebSocketCustomConnection(ConnectionList.Items[i].Data);
      c.SendText(s1, False);
      c.SendTextContinuation(s2, False);
      c.SendTextContinuation(s3, True);
    end;
  fServer.UnLockTermination;
end;

{ TTestWebSocketServer }

function TTestWebSocketServer.GetWebSocketConnectionClass(Socket: TTCPCustomConnectionSocket; Header: TStringList;
  ResourceName, Host, Port, Origin, Cookie: string; out HttpResult: Integer;
  var Protocol, Extensions: string): TWebSocketServerConnections;
begin
  Result := TTestWebSocketServerConnection;
end;

end.
