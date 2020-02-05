{==============================================================================|
| Project : Bauglir Internet Library                                           |
|==============================================================================|
| Content: Generic connection and server                                       |
|==============================================================================|
| Copyright (c)2011-2012, Bronislav Klucka                                     |
| All rights reserved.                                                         |
| Source code is licenced under original 4-clause BSD licence:                 |
| http://licence.bauglir.com/bsd4.php                                          |
|                                                                              |
|                                                                              |
|==============================================================================|
| Requirements: Ararat Synapse (http://www.ararat.cz/synapse/)                 |
|==============================================================================}
unit CustomServer2;

{$IFDEF FPC}
  {$MODE DELPHI}
{$ENDIF}
{$H+}

interface

uses
  {$IFDEF UNIX}
  cthreads,
  {$ENDIF}
  Classes, SysUtils, blcksock, syncobjs, Sockets, ssl_openssl, BClasses;

type
  TCustomServer = class;
  TCustomConnection = class;

  {:abstract(Socket used for @link(TCustomConnection))}
  TTCPCustomConnectionSocket = class(TTCPBlockSocket)
  protected
    fConnection: TCustomConnection;
    fCurrentStatusReason: THookSocketReason;
    fCurrentStatusValue: string;
    fOnSyncStatus: THookSocketStatus;
    procedure DoOnStatus(Sender: TObject; Reason: THookSocketReason; const Value: string);
    procedure SyncOnStatus;
  public
    constructor Create;
    destructor Destroy; override;
    {:Owner (@link(TCustomConnection))}
    property Connection: TCustomConnection read fConnection;
    {:Socket status event (synchronized to main thread)}
    property OnSyncStatus: THookSocketStatus read fOnSyncStatus write fOnSyncStatus;
  end;

  {:abstract(Basic connection thread)
    This object is used from server and client as working thread.

    When object is server connection: object is created automatically by @link(Parent) server.
    Thread can be terminated from outside. If server is terminated, all remaining
    connections are closed. This object is used to communicate with client.
    Object should not be created directly.
  }
  TCustomConnection = class(TBThread)
  private
  protected
    fIndex: Integer;
    fParent: TCustomServer;
    fSocket: TTCPCustomConnectionSocket;
    fSSL: Boolean;
    procedure AfterConnectionExecute; virtual;
    function BeforeExecuteConnection: Boolean; virtual;
    procedure ExecuteConnection; virtual;
    function GetIsTerminated: Boolean;
  public
    constructor Create(aSocket: TTCPCustomConnectionSocket); virtual;
    destructor Destroy; override;
    {:Thread execute method}
    procedure Execute; override;
    {:Thread resume method}
    procedure Start;
    {:Thread suspend method}
    procedure Stop;
    {:Temination procedure
      One should call this procedure to terminate thread,
      it internally calls Terminate, but can be overloaded,
      and can be used for clean um
    }
    procedure TerminateThread; virtual;
    {:@Connection index.
      Automatically generated.
    }
    property Index: Integer read fIndex;
    {:@True if thread is not terminated and @link(Socket) exists}
    property IsTerminated: Boolean read GetIsTerminated;
    {:@Connection parent
      If client connection, this property is always nil, if server
      connection, this property is @link(TCustomServer) that created this connection
    }
    property Parent: TCustomServer read fParent;
    {:@Connection socket}
    property Socket: TTCPCustomConnectionSocket read fSocket;
    {:Whether SSL is used}
    property SSL: Boolean read fSSL write fSSL;
  end;

  {:Event procedural type to hook OnAfterAddConnection in server
    Use this hook to get informations about connection accepted server that was added
  }
  TServerAfterAddConnection = procedure(Server: TCustomServer; aConnection: TCustomConnection) of object;
  {:Event procedural type to hook OnBeforeAddConnection in server
    Use this hook to be informed that connection is about to be accepred by server.
    Use CanAdd parameter (@false) to refuse connection
  }
  TServerBeforeAddConnection = procedure(Server: TCustomServer; aConnection: TCustomConnection; var CanAdd: Boolean) of object;
  {:Event procedural type to hook OnAfterRemoveConnection in server
    Use this hook to get informations about connection removed from server (connection is closed)
  }
  TServerAfterRemoveConnection = procedure(Server: TCustomServer; aConnection: TCustomConnection) of object;
  {:Event procedural type to hook OnAfterRemoveConnection in server
    Use this hook to get informations about connection removed from server (connection is closed)
  }
  TServerBeforeRemoveConnection = procedure(Server: TCustomServer; aConnection: TCustomConnection) of object;
  {:Event procedural type to hook OnSockedError in server
    Use this hook to get informations about error on server binding
  }
  TServerSocketError = procedure(Server: TCustomServer; Socket: TTCPBlockSocket) of object;

  {:abstract(Server listening on address and port and spawning @link(TCustomConnection))
    Use this object to create server. Object is accepting connections and creating new
    server connection objects (@link(TCustomConnection))
  }
  TCustomServer = class(TBThread)
  protected
    fBind: string;
    fPort: string;
    fCanAddConnection: Boolean;
    fConnections: TList;
    fConnectionTermLock: syncobjs.TCriticalSection;
    fCurrentAddConnection: TCustomConnection;
    fCurrentRemoveConnection: TCustomConnection;
    fCurrentSocket: TTCPBlockSocket;
    fIndex: Integer;
    fMaxConnectionsCount: Integer;
    fOnAfterAddConnection: TServerAfterAddConnection;
    fOnAfterRemoveConnection: TServerAfterRemoveConnection;
    fOnBeforeAddConnection: TServerBeforeAddConnection;
    fOnBeforeRemoveConnection: TServerBeforeRemoveConnection;
    fOnSocketErrot: TServerSocketError;
    fSSL: Boolean;
    fSSLCertificateFile: string;
    fSSLKeyPassword: string;
    fSSLPrivateKeyFile: string;
    function AddConnection(var aSocket: TTCPCustomConnectionSocket): TCustomConnection; virtual;
    {:Main function to determine what kind of connection will be used
      @link(AddConnection) uses this functino to actually create connection thread
    }
    function CreateServerConnection(aSocket: TTCPCustomConnectionSocket): TCustomConnection; virtual;
    procedure DoAfterAddConnection; virtual;
    procedure DoBeforeAddConnection;
    procedure DoAfterRemoveConnection;
    procedure DoBeforeRemoveConnection;
    procedure DoSocketError;
    function GetConnection(index: Integer): TCustomConnection;
    function GetConnectionByIndex(index: Integer): TCustomConnection;
    function GetCount: Integer;
    procedure OnConnectionTerminate(Sender: TObject);
    procedure RemoveConnection(aConnection: TCustomConnection);
    procedure SyncAfterAddConnection;
    procedure SyncBeforeAddConnection;
    procedure SyncAfterRemoveConnection;
    procedure SyncBeforeRemoveConnection;
    procedure SyncSocketError;
  public
    {:Create new server
      aBind represents local IP address server will be listening on.
      IP address may be numeric or symbolic ('192.168.74.50', 'cosi.nekde.cz', 'ff08::1').
      You can use for listening 0.0.0.0 for localhost

      The same for aPort it may be number or mnemonic port ('23', 'telnet').

      If port value is '0', system chooses itself and conects unused port in the
      range 1024 to 4096 (this depending by operating system!).

      Warning: when you call : Bind('0.0.0.0','0'); then is nothing done! In this
      case is used implicit system bind instead.
    }
    constructor Create(aBind: string; aPort: string); virtual;
    destructor Destroy; override;
    procedure Execute; override;
    {:Temination procedure
      This method should be called instead of Terminate to terminate thread,
      it internally calls Terminate, but can be overloaded,
      and can be used for data clean up
    }
    procedure TerminateThread; virtual;
    {:Method used co send the same data to all server connections.
      Method only stores data in connection (append to existing data).
      Connection must send and delete the data itself.
    }
    //procedure Broadcast(aData: string); virtual;
    {:Procedure to stop removing connections from connections list in case there
      is need to walk through it
    }
    procedure LockTermination;
    {:Thread resume method}
    procedure Start;
    {:Thread suspend method}
    procedure Stop;
    {:Procedure to resume removing connections. see LockTermination}
    procedure UnLockTermination;
    {:Get connection from connection list
      Index represent index within connection list (not Connection.Index property)
    }
    property Connection[index: Integer]: TCustomConnection read GetConnection; default;
    {:Get connection by its Index}
    property ConnectionByIndex[index: Integer]: TCustomConnection read GetConnectionByIndex;
    {:Valid connections count}
    property Count: Integer read GetCount;
    {:IP address where server is listening (see aBind in constructor)}
    property Host: string read fBind;
    {:Server index. Automatically generated.}
    property Index: Integer read fIndex;
    {:Maximum number of accepted connections. -1 (default value) represents unlimited number.
      If limit is reached and new client is trying to connection, it's refused
    }
    property MaxConnectionsCount: Integer read fMaxConnectionsCount write fMaxConnectionsCount;
    {:Port where server is listening (see aPort in constructor)}
    property Port: string read fPort;
    {:Whether SSL is used}
    property SSL: Boolean read fSSL write fSSL;
    {:SSL certification file}
    property SSLCertificateFile: string read fSSLCertificateFile write fSSLCertificateFile;
    {:SSL key file}
    property SSLKeyPassword: string read fSSLKeyPassword write fSSLKeyPassword;
    {:SSL key file}
    property SSLPrivateKeyFile: string read fSSLPrivateKeyFile write fSSLPrivateKeyFile;
    {:See @link(TServerAfterAddConnection)}
    property OnAfterAddConnection: TServerAfterAddConnection read fOnAfterAddConnection write fOnAfterAddConnection;
    {:See @link(TServerBeforeAddConnection)}
    property OnBeforeAddConnection: TServerBeforeAddConnection read fOnBeforeAddConnection write fOnBeforeAddConnection;
    {:See @link(TServerAfterRemoveConnection)}
    property OnAfterRemoveConnection: TServerAfterRemoveConnection read fOnAfterRemoveConnection write fOnAfterRemoveConnection;
    {:See @link(TServerBeforeRemoveConnection)}
    property OnBeforeRemoveConnection: TServerBeforeRemoveConnection read fOnBeforeRemoveConnection write fOnBeforeRemoveConnection;
    {:See @link(TServerSocketError)}
    property OnSocketError: TServerSocketError read fOnSocketErrot write fOnSocketErrot;
  end;

implementation

uses
  SynSock {$IFDEF WINDOWS}, Windows {$ENDIF};

var
  fConnectionsIndex: Integer = 0;

function GetConnectionIndex: Integer;
begin
  Result := fConnectionsIndex;
  Inc(fConnectionsIndex);
end;

{ TCustomServer }

procedure TCustomServer.OnConnectionTerminate(Sender: TObject);
begin
  try
    //OutputDebugString(PChar(Format('srv terminating 1 %d', [TCustomConnection(Sender).Index])));
    //fConnectionTermLock.Enter;
    //OutputDebugString(PChar(Format('srv terminating 2 %d', [TCustomConnection(Sender).Index])));
    RemoveConnection(TCustomConnection(Sender));
    //OutputDebugString(PChar(Format('srv terminating 3 %d', [TCustomConnection(Sender).Index])));
    //fConnectionTermLock.Leave;
  finally
  end;
  //OutputDebugString(PChar(Format('srv terminating e %d', [TCustomConnection(Sender).Index])));
end;

procedure TCustomServer.RemoveConnection(aConnection: TCustomConnection);
var
  index: Integer;
begin
  index := fConnections.IndexOf(aConnection);
  if index <> -1 then
  begin
    fCurrentRemoveConnection := aConnection;
    DoBeforeRemoveConnection;
    fConnectionTermLock.Enter;
    //OutputDebugString(PChar(Format('removing %d %d %d', [aConnection.fIndex, index, fConnections.Count])));
    fConnections.Extract(aConnection);
    //fConnections.Delete(index);
    //OutputDebugString(PChar(Format('removed %d %d %d', [aConnection.fIndex, index, fConnections.Count])));
    fConnectionTermLock.Leave;
    DoAfterRemoveConnection;
  end;
end;

procedure TCustomServer.DoAfterAddConnection;
begin
  if Assigned(fOnAfterAddConnection) then
    Synchronize(SyncAfterAddConnection);
end;

procedure TCustomServer.DoBeforeAddConnection;
begin
  if Assigned(fOnBeforeAddConnection) then
    Synchronize(SyncBeforeAddConnection);
end;

procedure TCustomServer.DoAfterRemoveConnection;
begin
  if Assigned(fOnAfterRemoveConnection) then
    Synchronize(SyncAfterRemoveConnection);
end;

procedure TCustomServer.DoBeforeRemoveConnection;
begin
  if Assigned(fOnBeforeRemoveConnection) then
    Synchronize(SyncBeforeRemoveConnection);
end;

procedure TCustomServer.DoSocketError;
begin
  if Assigned(fOnSocketErrot) then
    Synchronize(SyncSocketError);
end;

procedure TCustomServer.SyncAfterAddConnection;
begin
  if Assigned(fOnAfterAddConnection) then
    fOnAfterAddConnection(Self, fCurrentAddConnection);
end;

procedure TCustomServer.SyncBeforeAddConnection;
begin
  if Assigned(fOnBeforeAddConnection) then
    fOnBeforeAddConnection(Self, fCurrentAddConnection, fCanAddConnection);
end;

procedure TCustomServer.SyncAfterRemoveConnection;
begin
  if Assigned(fOnAfterRemoveConnection) then
    fOnAfterRemoveConnection(Self, fCurrentRemoveConnection);
end;

procedure TCustomServer.SyncBeforeRemoveConnection;
begin
  if Assigned(fOnBeforeRemoveConnection) then
    fOnBeforeRemoveConnection(Self, fCurrentRemoveConnection);
end;

procedure TCustomServer.SyncSocketError;
begin
  if Assigned(fOnSocketErrot) then
    fOnSocketErrot(Self, fCurrentSocket);
end;

procedure TCustomServer.TerminateThread;
begin
  if Terminated then
    Exit;
  Terminate;
end;

constructor TCustomServer.Create(aBind: string; aPort: string);
begin
  fBind := aBind;
  fPort := aPort;
  FreeOnTerminate := True;
  fConnections := TList.Create;
  fConnectionTermLock := syncobjs.TCriticalSection.Create;
  fMaxConnectionsCount := -1;
  fCanAddConnection := True;
  fCurrentAddConnection := nil;
  fCurrentRemoveConnection := nil;
  fCurrentSocket := nil;
  fIndex := GetConnectionIndex;
  inherited Create(True);
end;

destructor TCustomServer.Destroy;
begin
  fConnectionTermLock.Free;
  fConnections.Free;
  inherited Destroy;
end;

function TCustomServer.GetCount: Integer;
begin
  Result := fConnections.Count;
end;

{
procedure TCustomServer.Broadcast(aData: String);
var
  i: Integer;
begin
  fConnectionTermLock.Enter;
  for i := 0 to fConnections.Count - 1 do
    if not TCustomConnection(fConnections[i]).IsTerminated then
      TCustomServerConnection(fConnections[i]).Broadcast(aData);
  fConnectionTermLock.Leave;
end;
}
function TCustomServer.GetConnection(index: Integer): TCustomConnection;
begin
  fConnectionTermLock.Enter;
  Result := TCustomConnection(fConnections[index]);
  fConnectionTermLock.Leave;
end;

function TCustomServer.GetConnectionByIndex(index: Integer): TCustomConnection;
var
  i: Integer;
begin
  Result := nil;
  fConnectionTermLock.Enter;
  for i := 0 to fConnections.Count - 1 do
    if TCustomConnection(fConnections[i]).Index = index then
    begin
      Result := TCustomConnection(fConnections[i]);
      Break;
    end;
  fConnectionTermLock.Leave;
end;

function TCustomServer.CreateServerConnection(aSocket: TTCPCustomConnectionSocket): TCustomConnection;
begin
  Result := nil;
end;

function TCustomServer.AddConnection(var aSocket: TTCPCustomConnectionSocket): TCustomConnection;
begin
  if (fMaxConnectionsCount = -1) or (fConnections.Count < fMaxConnectionsCount) then
  begin
    Result := CreateServerConnection(aSocket);
    if Result <> nil then
    begin
      Result.fParent := Self;
      fCurrentAddConnection := Result;
      fCanAddConnection := True;
      DoBeforeAddConnection;
      if fCanAddConnection then
      begin
        fConnections.Add(Result);
        DoAfterAddConnection;
        Result.Resume;
      end
      else
        FreeAndNil(Result);
    end;
  end;
end;

procedure TCustomServer.Execute;
var
  c: TCustomConnection;
  s: TTCPCustomConnectionSocket;
  sock: TSocket;
  i: Integer;
begin
  fCurrentSocket := TTCPBlockSocket.Create;
  with fCurrentSocket do
  begin
    CreateSocket;
    if LastError <> 0 then
      DoSocketError;

    SetLinger(True, 10000);
    if LastError <> 0 then
      DoSocketError;

    bind(fBind, fPort);
    if LastError <> 0 then
      DoSocketError;

    listen;
    if LastError <> 0 then
      DoSocketError;

    repeat
      if Terminated then
        Break;

      if CanRead(1000) then
        if LastError = 0 then
        begin
          sock := Accept;
          if LastError = 0 then
          begin
            s := TTCPCustomConnectionSocket.Create;
            s.Socket := sock;

            if fSSL then
            begin
              s.SSL.CertificateFile := fSSLCertificateFile;
              s.SSL.PrivateKeyFile := fSSLPrivateKeyFile;
              //s.SSL.SSLType := LT_SSLv3;
              if SSLKeyPassword <> '' then
                s.SSL.KeyPassword := fSSLKeyPassword;
              s.SSLAcceptConnection;
              i := s.SSL.LastError;
              if i <> 0 then
                FreeAndNil(s);
            end;
            if s <> nil then
            begin
              s.GetSins;
              c := AddConnection(s);
              if (c = nil) and (s <> nil) then
                s.Free;
            end;
          end
          else
          begin
            DoSocketError;
          end;
        end
        else
        if LastError <> WSAETIMEDOUT then
          DoSocketError;
    until False;
  end;
  fOnAfterAddConnection := nil;
  fOnBeforeAddConnection := nil;
  fOnAfterRemoveConnection := nil;
  fOnBeforeRemoveConnection := nil;
  fOnSocketErrot := nil;

  for i := fConnections.Count - 1 downto 0 do
  begin
    c := TCustomConnection(fConnections[i]);
    try
      OnConnectionTerminate(c);
      c.TerminateThread;
{$IFDEF WINDOWS}
      WaitForSingleObject(c.Handle, 100);
{$ELSE}
      Sleep(100);
{$ENDIF}
    finally
    end;
  end;

  FreeAndNil(fCurrentSocket);
  //while fConnections.Count > 0 do Sleep(500);
end;

procedure TCustomServer.LockTermination;
begin
  fConnectionTermLock.Enter;
end;

procedure TCustomServer.Start;
begin
  Resume;
end;

procedure TCustomServer.Stop;
begin
  Suspend;
end;

procedure TCustomServer.UnLockTermination;
begin
  fConnectionTermLock.Leave;
end;

{ TTCPCustomConnectionSocket }

destructor TTCPCustomConnectionSocket.Destroy;
begin
  OnStatus := nil;
  OnSyncStatus := nil;
  inherited;
end;

procedure TTCPCustomConnectionSocket.DoOnStatus(Sender: TObject; Reason: THookSocketReason; const Value: string);
begin
  if (fConnection <> nil) and (not fConnection.Terminated) and Assigned(fOnSyncStatus) then
  begin
    fCurrentStatusReason := Reason;
    fCurrentStatusValue := Value;
    fConnection.Synchronize(SyncOnStatus);
    {
    if (fCurrentStatusReason = HR_Error) and (LastError = WSAECONNRESET) then
      fConnection.Terminate;
    }
  end;
end;

procedure TTCPCustomConnectionSocket.SyncOnStatus;
begin
  if Assigned(fOnSyncStatus) then
    fOnSyncStatus(Self, fCurrentStatusReason, fCurrentStatusValue);
end;

constructor TTCPCustomConnectionSocket.Create;
begin
  inherited Create;
  fConnection := nil;
  OnStatus := DoOnStatus;
end;

{ TCustomConnection }

constructor TCustomConnection.Create(aSocket: TTCPCustomConnectionSocket);
begin
  fSocket := aSocket;
  fSocket.fConnection := Self;
  FreeOnTerminate := True;
  fIndex := GetConnectionIndex;
  inherited Create(True);
end;

destructor TCustomConnection.Destroy;
begin
  if fSocket <> nil then
  begin
    fSocket.OnSyncStatus := nil;
    fSocket.OnStatus := nil;
    fSocket.Free;
  end;
  inherited Destroy;
end;

procedure TCustomConnection.Execute;
begin
  if BeforeExecuteConnection then
  begin
    ExecuteConnection;
    AfterConnectionExecute;
  end;
  if fParent <> nil then
    if not fParent.Terminated then
      fParent.OnConnectionTerminate(Self);
end;

procedure TCustomConnection.Start;
begin
  Resume;
end;

procedure TCustomConnection.Stop;
begin
  Suspend;
end;

procedure TCustomConnection.TerminateThread;
begin
  if Terminated then
    Exit;
  Socket.OnSyncStatus := nil;
  Socket.OnStatus := nil;
  Terminate;
end;

function TCustomConnection.GetIsTerminated: Boolean;
begin
  Result := Terminated or (fSocket = nil); // or (fSocket.Socket = INVALID_SOCKET);
end;

procedure TCustomConnection.AfterConnectionExecute;
begin

end;

function TCustomConnection.BeforeExecuteConnection: Boolean;
begin
  Result := True;
end;

procedure TCustomConnection.ExecuteConnection;
begin

end;

end.
