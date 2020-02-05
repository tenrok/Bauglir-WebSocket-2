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
| Project download homepage:                                                   |
|   http://code.google.com/p/bauglir-websocket/                                |
| Project homepage:                                                            |
|   http://www.webnt.eu/index.php                                              |
| WebSocket RFC:                                                               |
|   http://tools.ietf.org/html/rfc6455                                         |
|                                                                              |
|==============================================================================|
| Requirements: Ararat Synapse (http://www.ararat.cz/synapse/)                 |
|==============================================================================}
{
2.0.4
1/ change: send generic frame SendData public on WSConnection
2/ pascal bugfix: closing connection issues (e.g. infinite sleep)
3/ add: server CloseAllConnections
4/ change: default client version 13 (RFC)
5/ pascal change: CanReceiveOrSend public
6/ pascal bugfix: events missing on erratic traffic
7/ add: make Handschake public property

@todo
* move writing to separate thread
* test for simultaneous i/o operations

http://tools.ietf.org/html/draft-ietf-hybi-thewebsocketprotocol-17
http://tools.ietf.org/html/rfc6455
http://dev.w3.org/html5/websockets/#refsFILEAPI
}
unit WebSocket2;

{$IFDEF FPC}
  {$MODE DELPHI}
{$ENDIF}
{$H+}

interface

uses
  {$IFDEF UNIX}
  cthreads,
  {$ENDIF}
  Classes, SysUtils, blcksock, syncobjs, CustomServer2, StrUtils;

const
  {:Constants section defining what kind of data are sent from one pont to another}
  {:Continuation frame}
  wsCodeContinuation = $0;
  {:Text frame}
  wsCodeText = $1;
  {:Binary frame}
  wsCodeBinary = $2;
  {:Close frame}
  wsCodeClose = $8;
  {:Ping frame}
  wsCodePing = $9;
  {:Frame frame}
  wsCodePong = $A;

  {:Constants section defining close codes}
  {:Normal valid closure, connection purpose was fulfilled}
  wsCloseNormal = 1000;
  {:Endpoint is going away (like server shutdown)}
  wsCloseShutdown = 1001;
  {:Protocol error}
  wsCloseErrorProtocol = 1002;
  {:Unknown frame data type or data type application cannot handle}
  wsCloseErrorData = 1003;
  {:Reserved}
  wsCloseReserved1 = 1004;
  {:Close received by peer but without any close code. This close code MUST NOT be sent by application.}
  wsCloseNoStatus = 1005;
  {:Abnotmal connection shutdown close code. This close code MUST NOT be sent by application.}
  wsCloseErrorClose = 1006;
  {:Received text data are not valid UTF-8.}
  wsCloseErrorUTF8 = 1007;
  {:Endpoint is terminating the connection because it has received a message that violates its policy. Generic error.}
  wsCloseErrorPolicy = 1008;
  {:Too large message received}
  wsCloseTooLargeMessage = 1009;
  {:Client is terminating the connection because it has expected the server to negotiate one or more extension, but the server didn't return them in the response message of the WebSocket handshake}
  wsCloseClientExtensionError = 1010;
  {:Server is terminating the connection because it encountered an unexpected condition that prevented it from fulfilling the request}
  wsCloseErrorServerRequest = 1011;
  {:Connection was closed due to a failure to perform a TLS handshake. This close code MUST NOT be sent by application.}
  wsCloseErrorTLS = 1015;

type
  TWebSocketCustomConnection = class;

  {:Event procedural type to hook OnOpen events on connection}
  TWebSocketConnectionEvent = procedure(aSender: TWebSocketCustomConnection) of object;

  {:Event procedural type to hook OnPing, OnPong events on connection
  TWebSocketConnectionPingPongEvent = procedure(aSender: TWebSocketCustomConnection; aData: String) of object;}

  {:Event procedural type to hook OnClose event on connection}
  TWebSocketConnectionClose = procedure(aSender: TWebSocketCustomConnection; aCloseCode: Integer;
    aCloseReason: string; aClosedByPeer: Boolean) of object;

  {:Event procedural type to hook OnRead on OnWrite event on connection}
  TWebSocketConnectionData = procedure(aSender: TWebSocketCustomConnection; aFinal, aRes1, aRes2, aRes3: Boolean;
    aCode: Integer; aData: TMemoryStream) of object;

  {:Event procedural type to hook OnReadFull}
  TWebSocketConnectionDataFull = procedure(aSender: TWebSocketCustomConnection; aCode: Integer; aData: TMemoryStream) of object;

  {:abstract(WebSocket connection)
    class is parent class for server and client connection 
  }
  TWebSocketCustomConnection = class(TCustomConnection)
  protected
    fOnRead: TWebSocketConnectionData;
    fOnReadFull: TWebSocketConnectionDataFull;
    fOnWrite: TWebSocketConnectionData;
    fOnClose: TWebSocketConnectionClose;
    fOnOpen: TWebSocketConnectionEvent;
    //fOnPing: TWebSocketConnectionPingPongEvent;
    //fOnPong: TWebSocketConnectionPingPongEvent;
    fCookie: string;
    fVersion: Integer;
    fProtocol: string;
    fResourceName: string;
    fOrigin: string;
    fExtension: string;
    fPort: string;
    fHost: string;
    fHeaders: TStringList;
    fClosedByMe: Boolean;
    fClosedByPeer: Boolean;
    fMasking: Boolean;
    fRequireMasking: Boolean;
    fHandshake: Boolean;
    fCloseCode: Integer;
    fCloseReason: string;
    fClosingByPeer: Boolean;
    fReadFinal: Boolean;
    fReadRes1: Boolean;
    fReadRes2: Boolean;
    fReadRes3: Boolean;
    fReadCode: Integer;
    fReadStream: TMemoryStream;
    fWriteFinal: Boolean;
    fWriteRes1: Boolean;
    fWriteRes2: Boolean;
    fWriteRes3: Boolean;
    fWriteCode: Integer;
    fWriteStream: TMemoryStream;
    fSendCriticalSection: syncobjs.TCriticalSection;
    fFullDataProcess: Boolean;
    fFullDataStream: TMemoryStream;
    function GetClosed: Boolean;
    function GetClosing: Boolean;
    procedure ExecuteConnection; override;
    function ReadData(var aFinal, aRes1, aRes2, aRes3: Boolean; var aCode: Integer; aData: TMemoryStream): Integer; virtual;
    function ValidConnection: Boolean;
    procedure DoSyncClose;
    procedure DoSyncOpen;
    procedure DoSyncRead;
    procedure DoSyncReadFull;
    procedure DoSyncWrite;
    procedure SyncClose;
    procedure SyncOpen;
    procedure SyncRead;
    procedure SyncReadFull;
    procedure SyncWrite;
    {:Overload this function to process connection close (not at socket level, but as an actual WebSocket frame)
      aCloseCode represents close code (see wsClose constants)
      aCloseReason represents textual information transfered with frame (there is no specified format or meaning)
      aClosedByPeer whether connection has been closed by this connection object or by peer endpoint
    }
    procedure ProcessClose(aCloseCode: Integer; aCloseReason: string; aClosedByPeer: Boolean); virtual;
    {:Overload this function to process data as soon as they are read before other Process<data> function is called
      this function should be used by extensions to modify incomming data before the are process based on code
    }
    procedure ProcessData(var aFinal: Boolean; var aRes1: Boolean; var aRes2: Boolean; var aRes3: Boolean;
      var aCode: Integer; aData: TMemoryStream); virtual;
    {:Overload this function to process ping frame)
      aData represents textual information transfered with frame (there is no specified format or meaning)
    }
    procedure ProcessPing(aData: string); virtual;
    {:Overload this function to process pong frame)
      aData represents textual information transfered with frame (there is no specified format or meaning)
    }
    procedure ProcessPong(aData: string); virtual;
    {:Overload this function to process binary frame)
      aFinal whether frame is final frame or continuing
      aRes1 whether 1st extension bit is set up
      aRes2 whether 2nd extension bit is set up
      aRes3 whether 3rd extension bit is set up
      aData data stream

      second version is for contuniation frames
    }
    procedure ProcessStream(aFinal, aRes1, aRes2, aRes3: Boolean; aData: TMemoryStream); virtual;
    procedure ProcessStreamContinuation(aFinal, aRes1, aRes2, aRes3: Boolean; aData: TMemoryStream); virtual;
    procedure ProcessStreamFull(aData: TMemoryStream); virtual;
    {:Overload this function to process text frame)
      aFinal whether frame is final frame or continuing
      aRes1 whether 1st extension bit is set up
      aRes2 whether 2nd extension bit is set up
      aRes3 whether 3rd extension bit is set up
      aData textual data

      second version is for contuniation frames
    }
    procedure ProcessText(aFinal, aRes1, aRes2, aRes3: Boolean; aData: string); virtual;
    procedure ProcessTextContinuation(aFinal, aRes1, aRes2, aRes3: Boolean; aData: string); virtual;
    procedure ProcessTextFull(aData: string); virtual;
  public
    constructor Create(aSocket: TTCPCustomConnectionSocket); override;
    destructor Destroy; override;
    {:Whether connection is in active state (not closed, closing, socket, exists, i/o  threads not terminated..)}
    function CanReceiveOrSend: Boolean;
    {:Procedure to close connection
      aCloseCode represents close code (see wsClose constants)
      aCloseReason represents textual information transfered with frame (there is no specified format or meaning) the string can only be 123 bytes length
    }
    procedure Close(aCode: Integer; aCloseReason: string); virtual; abstract;
    {:Send binary frame
      aData data stream
      aFinal whether frame is final frame or continuing
      aRes1 1st extension bit
      aRes2 2nd extension bit
      aRes3 3rd extension bit
    }
    procedure SendBinary(aData: TStream; aFinal: Boolean = True; aRes1: Boolean = False; aRes2: Boolean = False; aRes3: Boolean = False);
    {:Send binary continuation frame
      aData data stream
      aFinal whether frame is final frame or continuing
      aRes1 1st extension bit
      aRes2 2nd extension bit
      aRes3 3rd extension bit
    }
    procedure SendBinaryContinuation(aData: TStream; aFinal: Boolean = True; aRes1: Boolean = False;
      aRes2: Boolean = False; aRes3: Boolean = False);
    {:Send generic frame
      aFinal whether frame is final frame or continuing
      aRes1 1st extension bit
      aRes2 2nd extension bit
      aRes3 3rd extension bit
      aCode frame code
      aData data stream or string
    }
    function SendData(aFinal, aRes1, aRes2, aRes3: Boolean; aCode: Integer; aData: TStream): Integer; overload; virtual;
    function SendData(aFinal, aRes1, aRes2, aRes3: Boolean; aCode: Integer; aData: string): Integer; overload; virtual;
    {:Send textual frame
      aData data string (MUST be UTF-8)
      aFinal whether frame is final frame or continuing
      aRes1 1st extension bit
      aRes2 2nd extension bit
      aRes3 3rd extension bit
    }
    procedure SendText(aData: string; aFinal: Boolean = True; aRes1: Boolean = False; aRes2: Boolean = False;
      aRes3: Boolean = False); virtual;
    {:Send textual continuation frame
      aData data string (MUST be UTF-8)
      aFinal whether frame is final frame or continuing
      aRes1 1st extension bit
      aRes2 2nd extension bit
      aRes3 3rd extension bit
    }
    procedure SendTextContinuation(aData: string; aFinal: Boolean = True; aRes1: Boolean = False;
      aRes2: Boolean = False; aRes3: Boolean = False);
    {:Send Ping
      aData ping informations
    }
    procedure Ping(aData: string);
    {:Send Pong
      aData pong informations
    }
    procedure Pong(aData: string);
    {:Temination procedure
      This method should be called instead of Terminate to terminate thread,
      it internally calls Terminate, but can be overloaded,
      and can be used for data clean up
    }
    procedure TerminateThread; override;
    {:Whether connection has been closed
      (either socket has been closed or thread has been terminated or WebSocket has been closed by this and peer connection)
    }
    property Closed: Boolean read GetClosed;
    {:Whether WebSocket has been closed by this and peer connection}
    property Closing: Boolean read GetClosing;
    {:WebSocket connection cookies
      Property is regular unparsed Cookie header string
      e.g. cookie1=value1;cookie2=value2

      empty string represents that no cookies are present
    }
    property Cookie: string read fCookie;
    {:WebSocket connection extensions
      Property is regular unparsed Sec-WebSocket-Extensions header string
      e.g. foo, bar; baz=2

      On both client and server connection this value represents the extension(s) selected by server to be used
      as a result of extension negotioation

      value - represents that no extension was negotiated and no header will be sent to client
      it is the default value
    }
    property Extension: string read fExtension;
    {:Whether to register for full data processing
      (callink @link(ProcessFullText), @link(ProcessFullStream) @link(OnFullRead)
      those methods/events are called if FullDataProcess is @true and whole message is read (after final frame)
    }
    property FullDataProcess: Boolean read fFullDataProcess write fFullDataProcess;
    {:Whether WebSocket handshake was succecfull (and connection is afer WS handshake)}
    property Handshake: Boolean read fHandshake;
    {:WebSocket connection host
      Property is regular unparsed Host header string
      e.g. server.example.com
    }
    property Host: string read fHost;
    {:WebSocket connection origin
      Property is regular unparsed Sec-WebSocket-Origin header string
      e.g. http://example.com
    }
    property Origin: string read fOrigin;
    {:WebSocket connection protocol
      Property is regular unparsed Sec-WebSocket-Protocol header string
      e.g. chat, superchat

      On both client and server connection this value represents the protocol(s) selected by server to be used
      as a result of protocol negotioation

      value - represents that no protocol was negotiated and no header will be sent to client
      it is the default value
    }
    property Protocol: string read fProtocol;
    {:Connection port}
    property Port: string read fPort;
    {:Connection resource
      e.g. /path1/path2/path3/file.ext
    }
    property ResourceName: string read fResourceName;
    {:WebSocket version (either 7 or 8 or 13)}
    property Version: Integer read fVersion;
    {:WebSocket Close frame event}
    property OnClose: TWebSocketConnectionClose read fOnClose write fOnClose;
    {:WebSocket connection successfully}
    property OnOpen: TWebSocketConnectionEvent read fOnOpen write fOnOpen;
    {:WebSocket ping
    property OnPing: TWebSocketConnectionPingPongEvent read fOnPing write fOnPing;
    }
    {:WebSocket pong
    property OnPong: TWebSocketConnectionPingPongEvent read fOnPong write fOnPong;
    }
    {:WebSocket frame read}
    property OnRead: TWebSocketConnectionData read fOnRead write fOnRead;
    {:WebSocket read full data}
    property OnReadFull: TWebSocketConnectionDataFull read fOnReadFull write fOnReadFull;
    {:WebSocket frame written}
    property OnWrite: TWebSocketConnectionData read fOnWrite write fOnWrite;
  end;

  {:Class of WebSocket connections}
  TWebSocketCustomConnections = class of TWebSocketCustomConnection;

  {:WebSocket server connection automatically created by server on incoming connection}
  TWebSocketServerConnection = class(TWebSocketCustomConnection)
  public
    constructor Create(aSocket: TTCPCustomConnectionSocket); override;
    procedure Close(aCode: Integer; aCloseReason: string); override;
    procedure TerminateThread; override;
    {:List of all headers
      keys are lowercased header name
      e.g host, connection, sec-websocket-key
    }
    property Header: TStringList read fHeaders;
  end;

  {:Class of WebSocket server connections }
  TWebSocketServerConnections = class of TWebSocketServerConnection;

  {:WebSocket client connection, this object shoud be created to establish client to server connection}
  TWebSocketClientConnection = class(TWebSocketCustomConnection)
  protected
    function BeforeExecuteConnection: Boolean; override;
  public
    {:construstor to create connection,
      parameters has the same meaning as corresponging connection properties (see 2 differences below) and
      should be formated according to headers values

      aProtocol and aExtension in constructor represents protocol(s) and extension(s)
      client is trying to negotiate, obejst properties then represents
      protocol(s) and extension(s) the server is supporting (the negotiation result)

      Version must be >= 8
    }
    constructor Create(aHost, aPort, aResourceName: string; aOrigin: string = '-'; aProtocol: string = '-';
      aExtension: string = '-'; aCookie: string = '-'; aVersion: Integer = 13); reintroduce; virtual;
    procedure Close(aCode: Integer; aCloseReason: string); override;
    procedure Execute; override;
  end;

  TWebSocketServer = class;

  {:Event procedural type to hook OnReceiveConnection events on server
    every time new server connection is about to be created (client is connecting to server)
    this event is called

    properties are representing connection properties as defined in @link(TWebSocketServerConnection)

    Protocol and Extension represents corresponding headers sent by client, as their out value
    server must define what kind of protocol(s) and extension(s) server is supporting, if event
    is not implemented, both values are considered as - (no value at all)

    HttpResult represents the HTTP result to be send in response, if connection is about to be
    accepted, the value MUST BE 101, any other value meand that the client will be informed about the
    result (using the HTTP code meaning) and connection will be closed, if event is not implemented
    101 is used as a default value 
  }
  TWebSocketServerReceiveConnection = procedure(Server: TWebSocketServer; Socket: TTCPCustomConnectionSocket;
    Header: TStringList; ResourceName, Host, Port, Origin, Cookie: string; HttpResult: Integer; Protocol, Extensions: string) of object;

  TWebSocketServer = class(TCustomServer)
  protected
    {CreateServerConnection sync variables}
    fncSocket: TTCPCustomConnectionSocket;
    fncResourceName: string;
    fncHost: string;
    fncPort: string;
    fncOrigin: string;
    fncProtocol: string;
    fncExtensions: string;
    fncCookie: string;
    fncHeaders: string;
    fncResultHttp: Integer;
    fOnReceiveConnection: TWebSocketServerReceiveConnection;
    function CreateServerConnection(aSocket: TTCPCustomConnectionSocket): TCustomConnection; override;
    procedure DoSyncReceiveConnection;
    procedure SyncReceiveConnection;
    property Terminated;
    {:This function defines what kind of TWebSocketServerConnection implementation should be used as
      a connection object.
      The servers default return value is TWebSocketServerConnection.

      If new connection class based on TWebSocketServerConnection is implemented,
      new server should be implemented as well with this method overloaded

      properties are representing connection properties as defined in @link(TWebSocketServerConnection)

      Protocol and Extension represents corresponding headers sent by client, as their out value
      server must define what kind of protocol(s) and extension(s) server is supporting, if event
      is not implemented, both values are cosidered as - (no value at all)

      HttpResult represents the HTTP result to be send in response, if connection is about to be
      accepted, the value MUST BE 101, any other value meand that the client will be informed about the
      result (using the HTTP code meaning) and connection will be closed, if event is not implemented
      101 is used as a default value
    }
    function GetWebSocketConnectionClass(Socket: TTCPCustomConnectionSocket; Header: TStringList;
      ResourceName, Host, Port, Origin, Cookie: string; out HttpResult: Integer;
      var Protocol, Extensions: string): TWebSocketServerConnections; virtual;
  public
    {:WebSocket connection received}
    property OnReceiveConnection: TWebSocketServerReceiveConnection read fOnReceiveConnection write fOnReceiveConnection;
    {:close all connections
    for parameters see connection Close method
    }
    procedure CloseAllConnections(aCloseCode: Integer; aReason: string);
    {:Temination procedure
      This method should be called instead of Terminate to terminate thread,
      it internally calls Terminate, but can be overloaded,
      and can be used for data clean up
    }
    procedure TerminateThread; override;
    {:Method to send binary data to all connected clients
      see @link(TWebSocketServerConnection.SendBinary) for parameters description
    }
    procedure BroadcastBinary(aData: TStream; aFinal: Boolean = True; aRes1: Boolean = False; aRes2: Boolean = False;
      aRes3: Boolean = False);
    {:Method to send text data to all connected clients
      see @link(TWebSocketServerConnection.SendText) for parameters description
    }
    procedure BroadcastText(aData: string; aFinal: Boolean = True; aRes1: Boolean = False; aRes2: Boolean = False; aRes3: Boolean = False);
  end;

implementation

uses
  Math, synautil, synacode, synsock, {$IFDEF WINDOWS}Windows,{$ENDIF} BClasses, synachar;

{$IFDEF WINDOWS}{$O-}{$ENDIF}

function httpCode(code: Integer): string;
begin
  case code of
    100: Result := 'Continue';
    101: Result := 'Switching Protocols';
    200: Result := 'OK';
    201: Result := 'Created';
    202: Result := 'Accepted';
    203: Result := 'Non-Authoritative Information';
    204: Result := 'No Content';
    205: Result := 'Reset Content';
    206: Result := 'Partial Content';
    300: Result := 'Multiple Choices';
    301: Result := 'Moved Permanently';
    302: Result := 'Found';
    303: Result := 'See Other';
    304: Result := 'Not Modified';
    305: Result := 'Use Proxy';
    307: Result := 'Temporary Redirect';
    400: Result := 'Bad Request';
    401: Result := 'Unauthorized';
    402: Result := 'Payment Required';
    403: Result := 'Forbidden';
    404: Result := 'Not Found';
    405: Result := 'Method Not Allowed';
    406: Result := 'Not Acceptable';
    407: Result := 'Proxy Authentication Required';
    408: Result := 'Request Time-out';
    409: Result := 'Conflict';
    410: Result := 'Gone';
    411: Result := 'Length Required';
    412: Result := 'Precondition Failed';
    413: Result := 'Request Entity Too Large';
    414: Result := 'Request-URI Too Large';
    415: Result := 'Unsupported Media Type';
    416: Result := 'Requested range not satisfiable';
    417: Result := 'Expectation Failed';
    500: Result := 'Internal Server Error';
    501: Result := 'Not Implemented';
    502: Result := 'Bad Gateway';
    503: Result := 'Service Unavailable';
    504: Result := 'Gateway Time-out';
    else
      Result := 'unknown code: ' + IntToStr(code);
  end;
end;

function ReadHttpHeaders(aSocket: TTCPCustomConnectionSocket; var aGet: string; aHeaders: TStrings): Boolean;
var
  s, Name: string;
begin
  aGet := '';
  aHeaders.Clear;
  Result := True;
  repeat
    aSocket.MaxLineLength := 1024 * 1024; // not to attack memory on server
    s := aSocket.RecvString(30 * 1000); // not to hang up connection
    if aSocket.LastError <> 0 then
    begin
      Result := False;
      Break;
    end;
    if s = '' then
      Break;
    if aGet = '' then
      aGet := s
    else
    begin
      Name := LowerCase(Trim(SeparateLeft(s, ':')));
      if aHeaders.Values[Name] = '' then
        aHeaders.Values[Name] := Trim(SeparateRight(s, ':'))
      else
        aHeaders.Values[Name] := aHeaders.Values[Name] + ',' + Trim(SeparateRight(s, ':'));
    end;
  until {IsTerminated} False;
  aSocket.MaxLineLength := 0;
end;

procedure ODS(aStr: string); overload;
begin
  {$IFDEF WINDOWS}
  OutputDebugString(PChar(FormatDateTime('yyyy-mm-dd hh:nn:ss', Now) + ': ' + aStr));
  {$ENDIF}
end;

procedure ODS(aStr: string; aData: array of const); overload;
begin
  {$IFDEF WINDOWS}
  ODS(Format(aStr, aData));
  {$ENDIF}
end;

{ TWebSocketServer }

procedure TWebSocketServer.BroadcastBinary(aData: TStream; aFinal: Boolean = True; aRes1: Boolean = False;
  aRes2: Boolean = False; aRes3: Boolean = False);
var
  i: Integer;
begin
  LockTermination;
  for i := 0 to fConnections.Count - 1 do
    if not TWebSocketServerConnection(fConnections[i]).IsTerminated then
      TWebSocketServerConnection(fConnections[i]).SendBinary(aData, aFinal, aRes1, aRes2, aRes3);
  UnLockTermination;
end;

procedure TWebSocketServer.BroadcastText(aData: string; aFinal: Boolean = True; aRes1: Boolean = False;
  aRes2: Boolean = False; aRes3: Boolean = False);
var
  i: Integer;
begin
  LockTermination;
  for i := 0 to fConnections.Count - 1 do
    if not TWebSocketServerConnection(fConnections[i]).IsTerminated then
      TWebSocketServerConnection(fConnections[i]).SendText(aData, aFinal, aRes1, aRes2, aRes3);
  UnLockTermination;
end;

procedure TWebSocketServer.CloseAllConnections(aCloseCode: Integer; aReason: string);
var
  i: Integer;
begin
  LockTermination;
  for i := fConnections.Count - 1 downto 0 do
    if not TWebSocketServerConnection(fConnections[i]).IsTerminated then
      TWebSocketServerConnection(fConnections[i]).Close(aCloseCode, aReason); // SendBinary(aData, aFinal, aRes1, aRes2, aRes3);
  UnLockTermination;
end;

function TWebSocketServer.CreateServerConnection(aSocket: TTCPCustomConnectionSocket): TCustomConnection;
var
  headers, hrs: TStringList;
  get: string;
  s, key, version, tmpExtension, tmpWord, extensionKey, extensionValue: string;
  iversion, vv, extCounter: Integer;
  res: Boolean;
  r: TWebSocketServerConnections;
begin
  fncSocket := aSocket;
  Result := inherited CreateServerConnection(aSocket);
  headers := TStringList.Create;
  try
    res := ReadHttpHeaders(aSocket, get, headers);
    if res then
    begin
      res := False;
      try
        // CHECK HTTP GET
        if (Pos('GET ', UpperCase(get)) <> 0) and (Pos(' HTTP/1.1', UpperCase(get)) <> 0) then
        begin
          fncResourceName := SeparateRight(get, ' ');
          fncResourceName := SeparateLeft(fncResourceName, ' ');
        end
        else
          Exit;

        fncResourceName := Trim(fncResourceName);

        // CHECK HOST AND PORT
        s := headers.Values['host'];
        if s <> '' then
        begin
          fncHost := Trim(s);
          fncPort := SeparateRight(fncHost, ':');
          fncHost := SeparateLeft(fncHost, ':');
        end;
        fncHost := Trim(fncHost);
        fncPort := Trim(fncPort);

        if fncHost = '' then
          Exit;

        // WEBSOCKET KEY
        s := headers.Values['sec-websocket-key'];
        if s <> '' then
          if Length(DecodeBase64(s)) = 16 then
            key := s;
        if key = '' then
          Exit;
        key := Trim(key);

        // WEBSOCKET VERSION
        s := headers.Values['sec-websocket-version'];
        if s <> '' then
        begin
          vv := StrToIntDef(s, -1);
          if (vv >= 7) and (vv <= 13) then
            version := s;
        end;
        if version = '' then
          Exit;
        version := Trim(version);
        iversion := StrToIntDef(version, 13);

        if (LowerCase(headers.Values['upgrade']) <> LowerCase('websocket')) or
          (Pos('upgrade', LowerCase(headers.Values['connection'])) = 0) then
          Exit;

        // COOKIES
        fncProtocol := '-';
        tmpExtension := '-';
        fncCookie := '-';
        fncOrigin := '-';

        if iversion < 13 then
        begin
          if headers.IndexOfName('sec-websocket-origin') > -1 then
            fncOrigin := Trim(headers.Values['sec-websocket-origin']);
        end
        else
        if headers.IndexOfName('origin') > -1 then
          fncOrigin := Trim(headers.Values['origin']);

        if headers.IndexOfName('sec-websocket-protocol') > -1 then
          fncProtocol := Trim(headers.Values['sec-websocket-protocol']);
        if headers.IndexOfName('sec-websocket-extensions') > -1 then
          tmpExtension := Trim(headers.Values['sec-websocket-extensions']);
        if headers.IndexOfName('cookie') > -1 then
          fncCookie := Trim(headers.Values['cookie']);

        fncHeaders := Trim(headers.Text);

        {
        ODS(get);
        ODS(fncHeaders);
        ODS('ResourceName: %s', [fncResourceName]);
        ODS('Host: %s', [fncHost]);
        ODS('Post: %s', [fncPort]);
        ODS('Key: %s', [key]);
        ODS('Version: %s', [version]);
        ODS('Origin: %s', [fncOrigin]);
        ODS('Protocol: %s', [fncProtocol]);
        ODS('Extensions: %s', [fncExtensions]);
        ODS('Cookie: %s', [fncCookie]);
        }

        // Account for client_max_window_bits, probably add more later on
        for extCounter := 1 to WordCount(tmpExtension, [';']) do
        begin
          tmpWord := ExtractWord(extCounter, tmpExtension, [' ', ';']);

          extensionKey := ExtractWord(1, tmpWord, ['=']);
          extensionValue := ExtractWord(2, tmpWord, ['=']);

          if not IsWordPresent(extensionKey, fncExtensions, [' ', ';', '=']) then
          begin
            fncExtensions := fncExtensions + extensionKey;

            if (extensionKey = 'client_max_window_bits') and (Length(extensionValue) = 0) then
              fncExtensions := fncExtensions + '=15;'
            else
            if Length(extensionValue) > 0 then
              fncExtensions := fncExtensions + '=' + extensionValue + ';'
            else
              fncExtensions := fncExtensions + ';';
          end;
        end;

        if fncExtensions[Length(fncExtensions)] = ';' then
          Delete(fncExtensions, Length(fncExtensions), 1);

        res := True;

      finally
        if res then
        begin
          fncResultHttp := 101;
          hrs := TStringList.Create;
          hrs.Assign(headers);
          r := GetWebSocketConnectionClass(fncSocket, hrs, fncResourceName, fncHost, fncPort, fncOrigin,
            fncCookie, fncResultHttp, fncProtocol, fncExtensions);
          if Assigned(r) then
          begin
            DoSyncReceiveConnection;
            if fncResultHttp <> 101 then // HTTP ERROR FALLBACK
            begin
              aSocket.SendString(Format('HTTP/1.1 %d %s' + #13#10, [fncResultHttp, httpCode(fncResultHttp)]));
              aSocket.SendString(Format('%d %s' + #13#10#13#10, [fncResultHttp, httpCode(fncResultHttp)]));
            end
            else
            begin
              key := EncodeBase64(SHA1(key + '258EAFA5-E914-47DA-95CA-C5AB0DC85B11'));

              s := 'HTTP/1.1 101 Switching Protocols' + #13#10;
              s := s + 'Upgrade: websocket' + #13#10;
              s := s + 'Connection: Upgrade' + #13#10;
              s := s + 'Sec-WebSocket-Accept: ' + key + #13#10;
              if fncProtocol <> '-' then
                s := s + 'Sec-WebSocket-Protocol: ' + fncProtocol + #13#10;
              if fncExtensions <> '-' then
                s := s + 'Sec-WebSocket-Extensions: ' + fncExtensions + #13#10;
              s := s + #13#10;

              aSocket.SendString(s);
              if aSocket.LastError = 0 then
              begin
                Result := r.Create(aSocket);
                TWebSocketCustomConnection(Result).fCookie := fncCookie;
                TWebSocketCustomConnection(Result).fVersion := StrToInt(version);
                TWebSocketCustomConnection(Result).fProtocol := fncProtocol;
                TWebSocketCustomConnection(Result).fResourceName := fncResourceName;
                TWebSocketCustomConnection(Result).fOrigin := fncOrigin;
                TWebSocketCustomConnection(Result).fExtension := fncExtensions;
                TWebSocketCustomConnection(Result).fPort := fncPort;
                TWebSocketCustomConnection(Result).fHost := fncHost;
                TWebSocketCustomConnection(Result).fHeaders.Assign(headers);
                TWebSocketCustomConnection(Result).fHandshake := True;
              end;
            end;
          end;
          hrs.Free;
        end;
      end;
    end;
  finally
    headers.Free;
  end;
end;

procedure TWebSocketServer.DoSyncReceiveConnection;
begin
  if Assigned(fOnReceiveConnection) then
    Synchronize(SyncReceiveConnection);
end;

function TWebSocketServer.GetWebSocketConnectionClass(Socket: TTCPCustomConnectionSocket; Header: TStringList;
  ResourceName, Host, Port, Origin, Cookie: string; out HttpResult: Integer;
  var Protocol, Extensions: string): TWebSocketServerConnections;
begin
  Result := TWebSocketServerConnection;
end;

procedure TWebSocketServer.SyncReceiveConnection;
var
  h: TStringList;
begin
  if Assigned(fOnReceiveConnection) then
  begin
    h := TStringList.Create;
    h.Text := fncHeaders;
    fOnReceiveConnection(Self, fncSocket, h, fncResourceName, fncHost, fncPort, fncOrigin, fncCookie, fncResultHttp,
      fncProtocol, fncExtensions);
    h.Free;
  end;
end;

procedure TWebSocketServer.TerminateThread;
begin
  if Terminated then
    Exit;
  fOnReceiveConnection := nil;
  inherited;
end;

{ TWebSocketCustomConnection }

function TWebSocketCustomConnection.CanReceiveOrSend: Boolean;
begin
  Result := ValidConnection and not (fClosedByMe or fClosedByPeer) and fHandshake;
end;

constructor TWebSocketCustomConnection.Create(aSocket: TTCPCustomConnectionSocket);
begin
  fHeaders := TStringList.Create;
  fCookie := '';
  fVersion := 0;
  fProtocol := '-';
  fResourceName := '';
  fOrigin := '';
  fExtension := '-';
  fPort := '';
  fHost := '';
  fClosedByMe := False;
  fClosedByPeer := False;
  fMasking := False;
  fClosingByPeer := False;
  fRequireMasking := False;
  fReadFinal := False;
  fReadRes1 := False;
  fReadRes2 := False;
  fReadRes3 := False;
  fReadCode := 0;
  fReadStream := TMemoryStream.Create;
  fWriteFinal := False;
  fWriteRes1 := False;
  fWriteRes2 := False;
  fWriteRes3 := False;
  fWriteCode := 0;
  fWriteStream := TMemoryStream.Create;
  fFullDataProcess := False;
  fFullDataStream := TMemoryStream.Create;
  fSendCriticalSection := syncobjs.TCriticalSection.Create;
  fHandshake := False;
  inherited;
end;

destructor TWebSocketCustomConnection.Destroy;
begin
  fSendCriticalSection.Free;
  fFullDataStream.Free;
  fWriteStream.Free;
  fReadStream.Free;
  fHeaders.Free;
  inherited;
end;

procedure TWebSocketCustomConnection.DoSyncClose;
begin
  if Assigned(fOnClose) then
    Synchronize(SyncClose);
end;

procedure TWebSocketCustomConnection.DoSyncOpen;
begin
  if Assigned(fOnOpen) then
    Synchronize(SyncOpen);
end;

procedure TWebSocketCustomConnection.DoSyncRead;
begin
  fReadStream.Position := 0;
  if Assigned(fOnRead) then
    Synchronize(SyncRead);
end;

procedure TWebSocketCustomConnection.DoSyncReadFull;
begin
  fFullDataStream.Position := 0;
  if Assigned(fOnReadFull) then
    Synchronize(SyncReadFull);
end;

procedure TWebSocketCustomConnection.DoSyncWrite;
begin
  if Assigned(fOnWrite) then
    Synchronize(SyncWrite);
end;

procedure TWebSocketCustomConnection.ExecuteConnection;
var
  result: Integer;
  //Data: String;
  closeCode: Integer;
  closeResult: string;
  s: string;
  lastDataCode, lastDataCode2: Integer;
  //Data: TStringStream;
begin
  DoSyncOpen;
  try
    lastDataCode := -1;
    lastDataCode2 := -1;
    while CanReceiveOrSend do
    begin
      //ODS(Format('execute %d', [fIndex]));
      result := ReadData(fReadFinal, fReadRes1, fReadRes2, fReadRes3, fReadCode, fReadStream);
      if CanReceiveOrSend then
        if result = 0 then // no socket error occured
        begin
          fReadStream.Position := 0;
          ProcessData(fReadFinal, fReadRes1, fReadRes2, fReadRes3, fReadCode, fReadStream);
          fReadStream.Position := 0;
          if (fReadCode in [wsCodeText, wsCodeBinary]) and fFullDataProcess then
          begin
            fFullDataStream.Size := 0;
            fFullDataStream.Position := 0;
          end;
          if (fReadCode in [wsCodeContinuation, wsCodeText, wsCodeBinary]) and fFullDataProcess then
          begin
            fReadStream.Position := 0;
            fFullDataStream.CopyFrom(fReadStream, fReadStream.Size);
            fReadStream.Position := 0;
          end;
          //if (fReadFinal) then // final frame
          begin
            case fReadCode of
              wsCodeContinuation:
              begin
                if lastDataCode = wsCodeText then
                begin
                  s := ReadStrFromStream(fReadStream, fReadStream.Size);
                  ProcessTextContinuation(fReadFinal, fReadRes1, fReadRes2, fReadRes3, s);
                  DoSyncRead;
                end
                else if lastDataCode = wsCodeBinary then
                begin
                  ProcessStreamContinuation(fReadFinal, fReadRes1, fReadRes2, fReadRes3, fReadStream);
                  DoSyncRead;
                end
                else
                  Close(wsCloseErrorProtocol, 'Unknown continuaton');
                if fReadFinal then
                  lastDataCode := -1;
              end;
              wsCodeText: // text, binary frame
              begin
                s := ReadStrFromStream(fReadStream, fReadStream.Size);
                ProcessText(fReadFinal, fReadRes1, fReadRes2, fReadRes3, s);
                DoSyncRead;
                if not fReadFinal then
                  lastDataCode := wsCodeText
                else
                  lastDataCode := -1;
                lastDataCode2 := wsCodeText;
              end;
              wsCodeBinary: // text, binary frame
              begin
                ProcessStream(fReadFinal, fReadRes1, fReadRes2, fReadRes3, fReadStream);
                DoSyncRead;
                if not fReadFinal then
                  lastDataCode := wsCodeBinary
                else
                  lastDataCode := -1;
                lastDataCode2 := wsCodeBinary;
              end;
              wsCodeClose: // connection close
              begin
                closeCode := wsCloseNoStatus;
                closeResult := ReadStrFromStream(fReadStream, fReadStream.Size);
                if Length(closeResult) > 1 then
                begin
                  closeCode := Ord(closeResult[1]) * 256 + Ord(closeResult[2]);
                  Delete(closeResult, 1, 2);
                end;
                fClosedByPeer := True;
                //ODS(Format('closing1 %d', [fIndex]));
                ProcessClose(closeCode, closeResult, True);
                //ODS(Format('closing2 %d', [fIndex]));
                TerminateThread;
                //ODS(Format('closing3 %d', [fIndex]));
                fSendCriticalSection.Enter;
              end;
              wsCodePing: // ping
              begin
                ProcessPing(ReadStrFromStream(fReadStream, fReadStream.Size));
                DoSyncRead;
              end;
              wsCodePong: // pong
              begin
                ProcessPong(ReadStrFromStream(fReadStream, fReadStream.Size));
                DoSyncRead;
              end
              else // ERROR
                Close(wsCloseErrorData, Format('Unknown data type: %d', [fReadCode]));
            end;
          end;

          if (fReadCode in [wsCodeContinuation, wsCodeText, wsCodeBinary]) and fFullDataProcess and fReadFinal then
          begin
            fFullDataStream.Position := 0;
            if lastDataCode2 = wsCodeText then
            begin
              s := ReadStrFromStream(fFullDataStream, fFullDataStream.Size);
              ProcessTextFull(s);
            end
            else if lastDataCode2 = wsCodeBinary then
              ProcessStreamFull(fFullDataStream);
            SyncReadFull;
          end;
        end
        else
          TerminateThread;
    end;
  finally
{$IFDEF UNIX}
    Sleep(2000);
{$ENDIF}
  end;
  while not Terminated do
    Sleep(500);
  //ODS(Format('terminating %d', [fIndex]));
  fSendCriticalSection.Enter;
end;

function TWebSocketCustomConnection.GetClosed: Boolean;
begin
  Result := not CanReceiveOrSend;
end;

function TWebSocketCustomConnection.GetClosing: Boolean;
begin
  Result := fClosedByMe or fClosedByPeer;
end;

procedure TWebSocketCustomConnection.Ping(aData: string);
begin
  if CanReceiveOrSend then
    SendData(True, False, False, False, wsCodePing, aData);
end;

procedure TWebSocketCustomConnection.Pong(aData: string);
begin
  if CanReceiveOrSend then
    SendData(True, False, False, False, wsCodePong, aData);
end;

procedure TWebSocketCustomConnection.ProcessClose(aCloseCode: Integer; aCloseReason: string; aClosedByPeer: Boolean);
begin
  fCloseCode := aCloseCode;
  fCloseReason := aCloseReason;
  fClosingByPeer := aClosedByPeer;
  DoSyncClose;
end;

procedure TWebSocketCustomConnection.ProcessData(var aFinal, aRes1, aRes2, aRes3: Boolean; var aCode: Integer; aData: TMemoryStream);
begin

end;

procedure TWebSocketCustomConnection.ProcessPing(aData: string);
begin
  Pong(aData);
end;

procedure TWebSocketCustomConnection.ProcessPong(aData: string);
begin

end;

procedure TWebSocketCustomConnection.ProcessStream(aFinal, aRes1, aRes2, aRes3: Boolean; aData: TMemoryStream);
begin

end;

procedure TWebSocketCustomConnection.ProcessStreamContinuation(aFinal, aRes1, aRes2, aRes3: Boolean; aData: TMemoryStream);
begin

end;

procedure TWebSocketCustomConnection.ProcessStreamFull(aData: TMemoryStream);
begin

end;

procedure TWebSocketCustomConnection.ProcessText(aFinal, aRes1, aRes2, aRes3: Boolean; aData: string);
begin

end;

procedure TWebSocketCustomConnection.ProcessTextContinuation(aFinal, aRes1, aRes2, aRes3: Boolean; aData: string);
begin

end;

procedure TWebSocketCustomConnection.ProcessTextFull(aData: string);
begin

end;

function GetByte(aSocket: TTCPCustomConnectionSocket; var aByte: Byte; var aTimeout: Integer): Integer;
begin
  aByte := aSocket.RecvByte(aTimeout);
  Result := aSocket.LastError;
end;

function HexToStr(aDec: Integer; aLength: Integer): string;
var
  tmp: string;
  i: Integer;
begin
  tmp := IntToHex(aDec, aLength);
  Result := '';
  for i := 1 to (Length(tmp) + 1) div 2 do
    Result := Result + AnsiChar(StrToInt('$' + Copy(tmp, i * 2 - 1, 2)));
end;

function StrToHexStr2(str: string): string;
var
  i: Integer;
begin
  Result := '';
  for i := 1 to Length(str) do
    Result := Result + IntToHex(Ord(str[i]), 2) + ' ';
end;

function TWebSocketCustomConnection.ReadData(var aFinal, aRes1, aRes2, aRes3: Boolean; var aCode: Integer; aData: TMemoryStream): Integer;
var
  timeout: Integer;
  b: Byte;
  mask: Boolean;
  len, i: Int64;
  mBytes: array[0..3] of Byte;
  ms: TMemoryStream;
begin
  Result := 0;
  len := 0;
  //aCode := 0;
  repeat
    timeout := 10 * 1000;
    if CanReceiveOrSend then
    begin
      //ODS(Format('%d', [Index]));
      if fSocket.CanReadEx(1000) then
      begin
        if CanReceiveOrSend then
        begin
          b := fSocket.RecvByte(1000);
          if fSocket.LastError = 0 then
          begin
            try
              try
                // BASIC INFORMATIONS
                aFinal := (b and $80) = $80;
                aRes1 := (b and $40) = $40;
                aRes2 := (b and $20) = $20;
                aRes3 := (b and $10) = $10;
                aCode := b and $F;

                // MASK AND LENGTH
                mask := False;
                Result := GetByte(fSocket, b, timeout);
                if Result = 0 then
                begin
                  mask := (b and $80) = $80;
                  len := b and $7F;
                  if len = 126 then
                  begin
                    Result := GetByte(fSocket, b, timeout);
                    if Result = 0 then
                    begin
                      len := b * $100; // 00 00
                      Result := GetByte(fSocket, b, timeout);
                      if Result = 0 then
                        len := len + b;
                    end;
                  end
                  else if len = 127 then // 00 00 00 00 00 00 00 00
                  begin
                    // TODO nesting og get byte should be different
                    Result := GetByte(fSocket, b, timeout);
                    if Result = 0 then
                    begin
                      len := b * $100000000000000;
                      if Result = 0 then
                      begin
                        Result := GetByte(fSocket, b, timeout);
                        len := len + b * $1000000000000;
                      end;
                      if Result = 0 then
                      begin
                        Result := GetByte(fSocket, b, timeout);
                        len := len + b * $10000000000;
                      end;
                      if Result = 0 then
                      begin
                        Result := GetByte(fSocket, b, timeout);
                        len := len + b * $100000000;
                      end;
                      if Result = 0 then
                      begin
                        Result := GetByte(fSocket, b, timeout);
                        len := len + b * $1000000;
                      end;
                      if Result = 0 then
                      begin
                        Result := GetByte(fSocket, b, timeout);
                        len := len + b * $10000;
                      end;
                      if Result = 0 then
                      begin
                        Result := GetByte(fSocket, b, timeout);
                        len := len + b * $100;
                      end;
                      if Result = 0 then
                      begin
                        Result := GetByte(fSocket, b, timeout);
                        len := len + b;
                      end;
                    end;
                  end;
                end;

                if (Result = 0) and fRequireMasking and (not mask) then
                  raise Exception.Create('mask'); // TODO some protocol error

                // MASKING KEY
                if mask and (Result = 0) then
                begin
                  Result := GetByte(fSocket, mBytes[0], timeout);
                  if Result = 0 then
                    Result := GetByte(fSocket, mBytes[1], timeout);
                  if Result = 0 then
                    Result := GetByte(fSocket, mBytes[2], timeout);
                  if Result = 0 then
                    Result := GetByte(fSocket, mBytes[3], timeout);
                end;

                // READ DATA
                if Result = 0 then
                begin
                  aData.Clear;
                  ms := TMemoryStream.Create;
                  try
                    timeout := 1000 * 60 * 60 * 2; // (len div (1024 * 1024)) * 1000 * 60;
                    if mask then
                      fSocket.RecvStreamSize(ms, timeout, len)
                    else
                      fSocket.RecvStreamSize(aData, timeout, len);

                    ms.Position := 0;
                    aData.Position := 0;
                    Result := fSocket.LastError;
                    if Result = 0 then
                      if mask then
                      begin
                        i := 0;
                        while i < len do
                        begin
                          ms.ReadBuffer(b, SizeOf(b));
                          b := b xor mBytes[i mod 4];
                          aData.WriteBuffer(b, SizeOf(b));
                          Inc(i);
                        end;
                      end;
                  finally
                    ms.Free;
                  end;
                  aData.Position := 0;
                  Break;
                end;
              except
                Result := -1;
              end;
            finally
            end;
          end
          else
          begin
            Result := -1;
          end;
        end
        else
        begin
          Result := -1;
        end;
      end
      else
      begin
        //if (fSocket.CanRead(0)) then
        //  ODS(StrToHexStr2(fSocket.RecvBufferStr(10, 1000)));
        if (fSocket.LastError <> WSAETIMEDOUT) and (fSocket.LastError <> 0) then
          Result := -1;
      end;
    end
    else
      Result := -1;

    if Result <> 0 then
    begin
      if not Terminated then
        if fSocket.LastError = WSAECONNRESET then
        begin
          Result := 0;
          aCode := wsCodeClose;
          aFinal := True;
          aRes1 := False;
          aRes2 := False;
          aRes3 := False;
          aData.Size := 0;
          WriteStrToStream(aData, AnsiChar(wsCloseErrorClose div 256) + AnsiChar(wsCloseErrorClose mod 256));
          aData.Position := 0;
        end
        else
        if not fClosedByMe then
        begin
          Close(wsCloseErrorProtocol, '');
          TerminateThread;
        end;
      Break;
    end
  until False;
end;

function TWebSocketCustomConnection.SendData(aFinal, aRes1, aRes2, aRes3: Boolean; aCode: Integer; aData: TStream): Integer;
var
  b: Byte;
  s: AnsiString;
  mBytes: array[0..3] of Byte;
  ms: TMemoryStream;
  i, len: Int64;
begin
  Result := 0;
  if CanReceiveOrSend or ((aCode = wsCodeClose) and (not fClosedByPeer)) then
  begin
    fSendCriticalSection.Enter;
    try
      s := '';

      // BASIC INFORMATIONS
      b := IfThen(aFinal, 1, 0) * $80;
      b := b + IfThen(aRes1, 1, 0) * $40;
      b := b + IfThen(aRes2, 1, 0) * $20;
      b := b + IfThen(aRes3, 1, 0) * $10;
      b := b + aCode;
      s := s + AnsiChar(b);

      // MASK AND LENGTH
      b := IfThen(fMasking, 1, 0) * $80;
      if aData.Size < 126 then
        b := b + aData.Size
      else if aData.Size < 65536 then
        b := b + 126
      else
        b := b + 127;
      s := s + AnsiChar(b);
      if aData.Size >= 126 then
        if aData.Size < 65536 then
          s := s + HexToStr(aData.Size, 4)
        else
          s := s + HexToStr(aData.Size, 16);

      // MASKING KEY
      if fMasking then
      begin
        mBytes[0] := Random(256);
        mBytes[1] := Random(256);
        mBytes[2] := Random(256);
        mBytes[3] := Random(256);
        s := s + AnsiChar(mBytes[0]);
        s := s + AnsiChar(mBytes[1]);
        s := s + AnsiChar(mBytes[2]);
        s := s + AnsiChar(mBytes[3]);
      end;

      fSocket.SendString(s);
      Result := fSocket.LastError;
      if Result = 0 then
      begin
        aData.Position := 0;
        ms := TMemoryStream.Create;
        try
          if not fMasking then
            fSocket.SendStreamRaw(aData)
          else
          begin
            i := 0;
            len := aData.Size;
            while i < len do
            begin
              aData.ReadBuffer(b, sizeOf(b));
              b := b xor mBytes[i mod 4];
              ms.WriteBuffer(b, SizeOf(b));
              Inc(i);
            end;
            ms.Position := 0;
            fSocket.SendStreamRaw(ms);
          end;

          Result := fSocket.LastError;
          if Result = 0 then
          begin
            fWriteFinal := aFinal;
            fWriteRes1 := aRes1;
            fWriteRes2 := aRes2;
            fWriteRes3 := aRes3;
            fWriteCode := aCode;
            aData.Position := 0;
            fWriteStream.Clear;
            fWriteStream.LoadFromStream(aData);
            DoSyncWrite;
          end;

        finally
          ms.Free;
        end;
      end;
    finally
      if aCode <> wsCodeClose then
        while not fSocket.CanWrite(10) do
          Sleep(10);
      fSendCriticalSection.Leave;
    end;
  end;
end;

function TWebSocketCustomConnection.SendData(aFinal, aRes1, aRes2, aRes3: Boolean; aCode: Integer; aData: string): Integer;
var
  ms: TMemoryStream;
begin
  ms := TMemoryStream.Create;
  try
    WriteStrToStream(ms, aData);
    Result := SendData(aFinal, aRes1, aRes2, aRes3, aCode, ms);
  finally
    ms.Free;
  end;
end;

procedure TWebSocketCustomConnection.SendBinary(aData: TStream; aFinal: Boolean = True; aRes1: Boolean = False;
  aRes2: Boolean = False; aRes3: Boolean = False);
begin
  SendData(aFinal, aRes1, aRes2, aRes3, wsCodeBinary, aData);
end;

procedure TWebSocketCustomConnection.SendBinaryContinuation(aData: TStream; aFinal, aRes1, aRes2, aRes3: Boolean);
begin
  SendData(aFinal, aRes1, aRes2, aRes3, wsCodeContinuation, aData);
end;

procedure TWebSocketCustomConnection.SendText(aData: string; aFinal: Boolean = True; aRes1: Boolean = False;
  aRes2: Boolean = False; aRes3: Boolean = False);
begin
  SendData(aFinal, aRes1, aRes2, aRes3, wsCodeText, aData);
end;

procedure TWebSocketCustomConnection.SendTextContinuation(aData: string; aFinal, aRes1, aRes2, aRes3: Boolean);
begin
  SendData(aFinal, aRes1, aRes2, aRes3, wsCodeContinuation, aData);
end;

{
procedure TWebSocketCustomConnection.SendStream(aFinal, aRes1, aRes2, aRes3: Boolean; aData: TStream);
begin
  if CanReceiveOrSend then
    SendData(aFinal, aRes1, aRes2, aRes3, wsCodeBinary, aData);
end;
}
{
procedure TWebSocketCustomConnection.SendStream(aData: TStream);
begin
  //SendStream(aFinal, False, False, False, aData);
end;
}
{
procedure TWebSocketCustomConnection.SendText(aFinal, aRes1, aRes2, aRes3: Boolean; aData: string);
begin
  if CanReceiveOrSend then
    SendData(aFinal, False, False, False, wsCodeText, aData);
end;
}
{
procedure TWebSocketCustomConnection.SendText(aData: string);
begin
  //SendText(True, False, False, False, aData);
  //SendData(True, False, False
end;
}
procedure TWebSocketCustomConnection.SyncClose;
begin
  if Assigned(fOnClose) then
    fOnClose(Self, fCloseCode, fCloseReason, fClosingByPeer);
end;

procedure TWebSocketCustomConnection.SyncOpen;
begin
  if Assigned(fOnOpen) then
    fOnOpen(Self);
end;

procedure TWebSocketCustomConnection.SyncRead;
begin
  fReadStream.Position := 0;
  if Assigned(fOnRead) then
    fOnRead(Self, fReadFinal, fReadRes1, fReadRes2, fReadRes3, fReadCode, fReadStream);
end;

procedure TWebSocketCustomConnection.SyncReadFull;
begin
  fFullDataStream.Position := 0;
  if Assigned(fOnReadFull) then
    fOnReadFull(Self, fReadCode, fFullDataStream);
end;

procedure TWebSocketCustomConnection.SyncWrite;
begin
  fWriteStream.Position := 0;
  if Assigned(fOnWrite) then
    fOnWrite(Self, fWriteFinal, fWriteRes1, fWriteRes2, fWriteRes3, fWriteCode, fWriteStream);
end;

procedure TWebSocketCustomConnection.TerminateThread;
begin
  if Terminated then
    Exit;
  if not Closed then
    DoSyncClose;
  Socket.OnSyncStatus := nil;
  Socket.OnStatus := nil;
  fOnRead := nil;
  fOnReadFull := nil;
  fOnWrite := nil;
  fOnClose := nil;
  fOnOpen := nil;
  {
  if not Closing then
    SendData(True, False, False, False, wsCodeClose, '1001');
  }
  inherited;
end;

function TWebSocketCustomConnection.ValidConnection: Boolean;
begin
  Result := (not IsTerminated) and (Socket.Socket <> INVALID_SOCKET);
end;

{ TWebSocketServerConnection }

procedure TWebSocketServerConnection.Close(aCode: Integer; aCloseReason: string);
begin
  if (Socket.Socket <> INVALID_SOCKET) and (not fClosedByMe) then
  begin
    fClosedByMe := True;
    if not fClosedByPeer then
    begin
      SendData(True, False, False, False, wsCodeClose, HexToStr(aCode, 4) + Copy(aCloseReason, 1, 123));
      //Sleep(2000);
      ProcessClose(aCode, aCloseReason, False);
    end;
    TerminateThread;
  end;
end;

constructor TWebSocketServerConnection.Create(aSocket: TTCPCustomConnectionSocket);
begin
  inherited;
  fRequireMasking := True;
end;

procedure TWebSocketServerConnection.TerminateThread;
begin
  if Terminated then
    Exit;
  //if (not TWebSocketServer(fParent).Terminated) and (not fClosedByMe) then DoSyncClose;
  fOnClose := nil;
  inherited;
end;

{ TWebSocketClientConnection }

function TWebSocketClientConnection.BeforeExecuteConnection: Boolean;
var
  key, s, get: string;
  i: Integer;
  headers: TStringList;
begin
  Result := not IsTerminated;
  if Result then
  begin
    s := Format('GET %s HTTP/1.1' + #13#10, [fResourceName]);
    s := s + Format('Upgrade: websocket' + #13#10, []);
    s := s + Format('Connection: Upgrade' + #13#10, []);
    s := s + Format('Host: %s:%s' + #13#10, [fHost, fPort]);

    for I := 1 to 16 do
      key := key + AnsiChar(Random(85) + 32);
    key := EncodeBase64(key);
    s := s + Format('Sec-WebSocket-Key: %s' + #13#10, [key]);
    s := s + Format('Sec-WebSocket-Version: %d' + #13#10, [fVersion]);

    // TODO extensions
    if fProtocol <> '-' then
      s := s + Format('Sec-WebSocket-Protocol: %s' + #13#10, [fProtocol]);
    if fOrigin <> '-' then
      if fVersion < 13 then
        s := s + Format('Sec-WebSocket-Origin: %s' + #13#10, [fOrigin])
      else
        s := s + Format('Origin: %s' + #13#10, [fOrigin]);
    if fCookie <> '-' then
      s := s + Format('Cookie: %s' + #13#10, [fCookie]);
    if fExtension <> '-' then
      s := s + Format('Sec-WebSocket-Extensions: %s' + #13#10, [fExtension]);
    s := s + #13#10;
    fSocket.SendString(s);
    Result := (not IsTerminated) and (fSocket.LastError = 0);
    if Result then
    begin
      headers := TStringList.Create;
      try
        Result := ReadHttpHeaders(fSocket, get, headers);
        if Result then
          Result := Pos(LowerCase('HTTP/1.1 101'), LowerCase(get)) = 1;
        if Result then
          Result := (LowerCase(headers.Values['upgrade']) = LowerCase('websocket')) and
            (LowerCase(headers.Values['connection']) = 'upgrade');
        fProtocol := '-';
        fExtension := '-';
        if headers.IndexOfName('sec-websocket-protocol') > -1 then
          fProtocol := Trim(headers.Values['sec-websocket-protocol']);
        if headers.IndexOfName('sec-websocket-extensions') > -1 then
          fExtension := Trim(headers.Values['sec-websocket-extensions']);
        if Result then
          Result := (headers.Values['sec-websocket-accept'] = EncodeBase64(SHA1(key + '258EAFA5-E914-47DA-95CA-C5AB0DC85B11')));
      finally
        headers.Free;
      end;
    end;
  end;
  if Result then
    fHandshake := True;
end;

procedure TWebSocketClientConnection.Close(aCode: Integer; aCloseReason: string);
begin
  if ValidConnection and (not fClosedByMe) then
  begin
    fClosedByMe := True;
    if not fClosedByPeer then
    begin
      SendData(True, False, False, False, wsCodeClose, HexToStr(aCode, 4) + Copy(aCloseReason, 1, 123));
      //Sleep(2000);
      ProcessClose(aCode, aCloseReason, False);
    end;
    TerminateThread;
  end;
end;

constructor TWebSocketClientConnection.Create(aHost, aPort, aResourceName, aOrigin, aProtocol: string;
  aExtension: string; aCookie: string; aVersion: Integer);
begin
  fSocket := TTCPCustomConnectionSocket.Create;
  inherited Create(fSocket);
  fOrigin := aOrigin;
  fHost := aHost;
  fPort := aPort;
  fResourceName := aResourceName;
  fProtocol := aProtocol;
  fVersion := aVersion;
  fMasking := True;
  fCookie := aCookie;
  fExtension := aExtension;
end;

procedure TWebSocketClientConnection.Execute;
begin
  if (not IsTerminated) and (fVersion >= 8) then
  begin
    fSocket.Connect(fHost, fPort);
    if SSL then
      fSocket.SSLDoConnect;
    if fSocket.LastError = 0 then
      inherited Execute
    else
      TerminateThread;
  end;
end;

initialization

  Randomize;

{
GET / HTTP/1.1
Upgrade: websocket
Connection: Upgrade
Host: 81.0.231.149:81
Sec-WebSocket-Origin: http://html5.bauglir.dev
Sec-WebSocket-Key: Q9ceXTuzjdF2o23CRYvnuA==
Sec-WebSocket-Version: 8

GET / HTTP/1.1
Host: 81.0.231.149:81
User-Agent: Mozilla/5.0 (Windows NT 6.1; WOW64; rv:6.0) Gecko/20100101 Firefox/6.0
Accept: text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8
Accept-Language: sk,cs;q=0.8,en-us;q=0.5,en;q=0.3
Accept-Encoding: gzip, deflate
Accept-Charset: ISO-8859-2,utf-8;q=0.7,*;q=0.7
Connection: keep-alive, Upgrade
Sec-WebSocket-Version: 7
Sec-WebSocket-Origin: http://html5.bauglir.dev
Sec-WebSocket-Key: HgBKcPfdBSzjCYxGnWCO3g==
Pragma: no-cache
Cache-Control: no-cache
Upgrade: websocket
Cookie: __utma=72544661.1949147240.1313811966.1313811966.1313811966.1; __utmb=72544661.3.10.1313811966; __utmc=72544661; __utmz=72544661.1313811966.1.1.utmcsr=localhost|utmccn=(referral)|utmcmd=referral|utmcct=/websocket/index.php
1300}

end.
