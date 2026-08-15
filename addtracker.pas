unit AddTracker;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, FileUtil, LResources, Forms, Controls, Graphics, Dialogs, ButtonPanel, StdCtrls, ExtCtrls, BaseForm,
  fpjson, rpc;

resourcestring
  STrackerProps = 'Tracker properties';
  SNoTracker = 'No tracker URL was specified.';

type

  { TAddTrackerForm }

  TAddTrackerForm = class(TBaseForm)
    Buttons: TButtonPanel;
    edTracker: TEdit;
    Panel1: TPanel;
    txTrackerURL: TLabel;
    procedure FormCreate(Sender: TObject);
    procedure FormDestroy(Sender: TObject);
    procedure OKButtonClick(Sender: TObject);
  private
    FEditMode: boolean;
    FTorrentId: integer;
    FTrackerId: integer;
    FRequestLifetime: TRpcRequestLifetime;
    procedure EnableControls(AEnabled: Boolean);
    procedure TrackerSetCompleted(ARequest: TObject);
  public
    property EditMode: boolean read FEditMode write FEditMode;
    property TorrentId: integer read FTorrentId write FTorrentId;
    property TrackerId: integer read FTrackerId write FTrackerId;
    property RequestLifetime: TRpcRequestLifetime read FRequestLifetime write FRequestLifetime;
  end;

implementation

uses main;

{ TAddTrackerForm }

procedure TAddTrackerForm.FormCreate(Sender: TObject);
begin
  FRequestLifetime:=TRpcRequestLifetime.Create;
  Buttons.OKButton.ModalResult:=mrNone;
  Buttons.OKButton.OnClick:=@OKButtonClick;
end;

procedure TAddTrackerForm.FormDestroy(Sender: TObject);
begin
  FRequestLifetime.Active:=False;
  FRequestLifetime.Release;
end;

procedure TAddTrackerForm.EnableControls(AEnabled: Boolean);
begin
  edTracker.Enabled:=AEnabled;
  Buttons.OKButton.Enabled:=AEnabled;
  Buttons.CancelButton.Enabled:=AEnabled;
  if AEnabled then
    Screen.Cursor:=crDefault
  else
    Screen.Cursor:=crHourGlass;
end;

procedure TAddTrackerForm.OKButtonClick(Sender: TObject);
var
  req, args: TJSONObject;
  request: TRpcUserRequest;
begin
  edTracker.Text:=Trim(edTracker.Text);
  if edTracker.Text = '' then begin
    edTracker.SetFocus;
    MessageDlg(SNoTracker, mtError, [mbOK], 0);
    exit;
  end;

  req:=TJSONObject.Create;
  try
    req.Add('method', 'torrent-set');
    args:=TJSONObject.Create;
    args.Add('ids', TJSONArray.Create([FTorrentId]));
    if FEditMode then
      args.Add('trackerReplace', TJSONArray.Create([FTrackerId, UTF8Encode(edTracker.Text)]))
    else
      args.Add('trackerAdd', TJSONArray.Create([UTF8Encode(edTracker.Text)]));
    req.Add('arguments', args);

    FRequestLifetime.AddRef;
    request:=TRpcUserRequest.Create(req, False, -1, @TrackerSetCompleted, FRequestLifetime);
    EnableControls(False);
    if not RpcObj.QueueUserRequest(request) then begin
      EnableControls(True);
      FRequestLifetime.Release;
      MessageDlg('Unable to queue RPC request.', mtError, [mbOK], 0);
      exit;
    end;
    req:=nil;
  finally
    req.Free;
  end;
end;

procedure TAddTrackerForm.TrackerSetCompleted(ARequest: TObject);
begin
  EnableControls(True);
  if TRpcUserRequest(ARequest).Cancelled then
    exit;
  if TRpcUserRequest(ARequest).Result = nil then begin
    MainForm.CheckStatus(False);
    exit;
  end;
  ModalResult:=mrOK;
end;

initialization
  {$I addtracker.lrs}

end.

