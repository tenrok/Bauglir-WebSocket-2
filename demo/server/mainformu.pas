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
    procedure DoConnectionClose(aSender: TWebSocketCustomConnection; aCloseCode: Integer; aCloseReason: String; aClosedByPeer: Boolean);
    procedure DoConnectionSocket(Sender: TObject; Reason: THookSocketReason; const Value: String);
    function ListItemByIndex(aConnectionIndex: Integer): TListItem;
  end;

  TTestWebSocketServerConnection = class;

  { TTestWebSocketServer }

  TTestWebSocketServer = class(TWebSocketServer)
  public
    function GetWebSocketConnectionClass(Socket: TTCPCustomConnectionSocket; Header: TStringList;
      ResourceName, Host, Port, Origin, Cookie: String; out HttpResult: Integer;
      var Protocol, Extensions: String): TWebSocketServerConnections; override;
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
  I: Integer;
begin
  fServer.LockTermination;
  for I := 0 to ConnectionList.Items.Count - 1 do
  begin
    if ConnectionList.Items[I].Selected then
    begin
      TWebSocketCustomConnection(ConnectionList.Items[I].Data).SendText(CharsetConversion(SendSelectedMemo.Text, GetCurCP, UTF_8));
      //ConnectionList.Items[I].Selected := false;
    end;
  end;
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
  I: Integer;
begin
  InfoMemo.Lines.Insert(0, Format('DoServerBeforeRemoveConnection %d', [aConnection.Index]));
  for I := 0 to ConnectionList.Items.Count - 1 do
  begin
    if TCustomConnection(ConnectionList.Items[I].Data).Index = aConnection.Index then
    begin
      ConnectionList.Items.Delete(I);
      Break;
    end;
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
  Item: TListItem;
begin
  InfoMemo.Lines.Insert(0, Format('DoConnectionRead %d, final: %d, ext1: %d, ext2: %d, ext3: %d, type: %d, length: %d',
    [aSender.Index, Ord(aFinal), Ord(aRes1), Ord(aRes2), Ord(aRes3), aCode, aData.Size]));
  Item := ListItemByIndex(aSender.Index);
  Item.SubItems[0] := IntToStr(StrToInt(Item.SubItems[0]) + 1);
end;

procedure TMainForm.DoConnectionWrite(aSender: TWebSocketCustomConnection; aFinal, aRes1, aRes2, aRes3: Boolean;
  aCode: Integer; aData: TMemoryStream);
var
  Item: TListItem;
begin
  InfoMemo.Lines.Insert(0, Format('DoConnectionWrite %d, final: %d, ext1: %d, ext2: %d, ext3: %d, type: %d, length: %d',
    [aSender.Index, Ord(aFinal), Ord(aRes1), Ord(aRes2), Ord(aRes3), aCode, aData.Size]));
  Item := ListItemByIndex(aSender.Index);
  Item.SubItems[1] := IntToStr(StrToInt(Item.SubItems[1]) + 1);
end;

procedure TMainForm.DoConnectionClose(aSender: TWebSocketCustomConnection; aCloseCode: Integer; aCloseReason: String;
  aClosedByPeer: Boolean);
begin
  InfoMemo.Lines.Insert(0, Format('DoConnectionClose %d, %d, %s, %s', [aSender.Index, aCloseCode, aCloseReason,
    IfThen(aClosedByPeer, 'closed by peer', 'closed by me')]));
end;

procedure TMainForm.DoConnectionSocket(Sender: TObject; Reason: THookSocketReason; const Value: String);
begin
  InfoMemo.Lines.Insert(0, Format('DoConnectionSocket %d, %s, %s', [TTCPCustomConnectionSocket(Sender).Connection.Index,
    GetEnumName(TypeInfo(THookSocketReason), Ord(Reason)), Value]));
end;

function TMainForm.ListItemByIndex(aConnectionIndex: Integer): TListItem;
var
  I: Integer;
begin
  fServer.LockTermination;
  Result := nil;
  for I := 0 to ConnectionList.Items.Count - 1 do
  begin
    if TCustomConnection(ConnectionList.Items[I].Data).Index = aConnectionIndex then
    begin
      Result := ConnectionList.Items[I];
      Break;
    end;
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
  I: Integer;
begin
  fServer.LockTermination;
  for I := 0 to ConnectionList.Items.Count - 1 do
  begin
    if ConnectionList.Items[I].Selected then
    begin
      ConnectionList.Items[I].Selected := False;
      TWebSocketCustomConnection(ConnectionList.Items[I].Data).Close(wsCloseNormal, 'closing connection');
    end;
  end;
  fServer.UnLockTermination;
end;

procedure TMainForm.ConnectionListChange(Sender: TObject; Item: TListItem; Change: TItemChange);
var
  S: String;
  C: TTestWebSocketServerConnection;
begin
  LastSentMemo.Lines.Text := '';
  LastReceivedMemo.Lines.Text := '';
  ConnectionInfoMemo.Text := '';
  if (Change = ctState) and (Item.Selected) and (ConnectionList.SelCount = 1) then
  begin
    //TWebSocketCustomConnection(ConnectionList.Items[I]. Data).SendText(SendSelectedMemo.Text)
    C := TTestWebSocketServerConnection(Item.Data);
    S := ReadStrFromStream(C.ReadStream, Min(C.ReadStream.Size, 10 * 1024));
    if C.ReadCode = wsCodeText then
      LastReceivedMemo.Lines.Text := CharsetConversion(S, UTF_8, GetCurCP)
    else
      LastReceivedMemo.Lines.Text := S;
    S := ReadStrFromStream(C.WriteStream, Min(C.WriteStream.Size, 10 * 1024));
    if C.WriteCode = wsCodeText then
      LastSentMemo.Lines.Text := CharsetConversion(S, UTF_8, GetCurCP)
    else
      LastSentMemo.Lines.Text := S;
    C.ReadStream.Position := 0;
    C.WriteStream.Position := 0;
    ConnectionInfoMemo.Text := C.Header.Text;
  end;
end;

procedure TMainForm.EndActionUpdate(Sender: TObject);
begin
  TAction(Sender).Enabled := not StartButton.Enabled;
end;

procedure TMainForm.LoadImageActionExecute(Sender: TObject);
var
  MS1, MS2, MS3: TMemoryStream;
  FS: TFileStream;
  L, I: Integer;
  C: TWebSocketCustomConnection;
begin
  OpenPictureDialog.Filter :=
    'All (*.png;*.bmp;*.ico;*.emf;*.wmf)|*.png;*.bmp;*.ico;*.emf;*.wmf|PNG Image File (*.png)|*.png|Bitmaps (*.bmp)|*.bmp|Icons (*.ico)|*.ico|Enhanced Metafiles (*.emf)|*.emf|Metafiles (*.wmf)|*.wmf';
  if OpenPictureDialog.Execute then
  begin
    Image1.Picture.LoadFromFile(OpenPictureDialog.FileName);

    MS1 := TMemoryStream.Create;
    MS2 := TMemoryStream.Create;
    MS3 := TMemoryStream.Create;
    FS := TFileStream.Create(OpenPictureDialog.FileName, fmOpenRead);
    try
      FS.Position := 0;
      L := FS.Size div 3;
      MS1.CopyFrom(FS, L);
      MS2.CopyFrom(FS, L);
      MS3.CopyFrom(FS, FS.Size - 2 * L);
      fServer.LockTermination;
      for I := 0 to ConnectionList.Items.Count - 1 do
      begin
        if ConnectionList.Items[I].Selected then
        begin
          C := TWebSocketCustomConnection(ConnectionList.Items[I].Data);
          C.SendBinary(MS1, False);
          C.SendBinaryContinuation(MS2, False);
          C.SendBinaryContinuation(MS3, True);
          {
          FS.Position := 0;
          C.SendBinary(FS, True);
          }
        end;
      end;
      fServer.UnLockTermination;
    finally
      MS1.Free;
      MS2.Free;
      MS3.Free;
      FS.Free;
    end;
  end;
end;

procedure TMainForm.PingActionExecute(Sender: TObject);
var
  I: Integer;
begin
  fServer.LockTermination;
  for I := 0 to ConnectionList.Items.Count - 1 do
  begin
    if ConnectionList.Items[I].Selected then
      TWebSocketCustomConnection(ConnectionList.Items[I].Data).Ping('ping you');
  end;
  fServer.UnLockTermination;
end;

procedure TMainForm.PongActionExecute(Sender: TObject);
var
  I: Integer;
begin
  fServer.LockTermination;
  for I := 0 to ConnectionList.Items.Count - 1 do
  begin
    if ConnectionList.Items[I].Selected then
      TWebSocketCustomConnection(ConnectionList.Items[I].Data).Pong('pong you');
  end;
  fServer.UnLockTermination;
end;

procedure TMainForm.SendFramesActionExecute(Sender: TObject);
var
  I, L: Integer;
  S, S1, S2, S3: String;
  C: TWebSocketCustomConnection;
  US: UnicodeString;
begin
  S := CharsetConversion(SendSelectedMemo2.Text, GetCurCP, UTF_8);
  US := UTF8Decode(S);
  L := Length(US) div 3;
  S1 := Copy(US, 1, L);
  S2 := Copy(US, L + 1, L);
  S3 := Copy(US, 2 * L + 1, length(S));
  S1 := UTF8Encode(S1);
  S2 := UTF8Encode(S2);
  S3 := UTF8Encode(S3);
  fServer.LockTermination;
  for I := 0 to ConnectionList.Items.Count - 1 do
  begin
    if ConnectionList.Items[I].Selected then
    begin
      C := TWebSocketCustomConnection(ConnectionList.Items[I].Data);
      C.SendText(S1, False);
      C.SendTextContinuation(S2, False);
      C.SendTextContinuation(S3, True);
    end;
  end;
  fServer.UnLockTermination;
end;

{ TTestWebSocketServer }

function TTestWebSocketServer.GetWebSocketConnectionClass(Socket: TTCPCustomConnectionSocket; Header: TStringList;
  ResourceName, Host, Port, Origin, Cookie: String; out HttpResult: Integer;
  var Protocol, Extensions: String): TWebSocketServerConnections;
begin
  Result := TTestWebSocketServerConnection;
end;

end.
