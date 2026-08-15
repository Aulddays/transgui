{*************************************************************************************
  This file is part of Transmission Remote GUI.
  Copyright (c) 2008-2019 by Yury Sidorov and Transmission Remote GUI working group.

  Transmission Remote GUI is free software; you can redistribute it and/or modify
  it under the terms of the GNU General Public License as published by
  the Free Software Foundation; either version 2 of the License, or
  (at your option) any later version.

  Transmission Remote GUI is distributed in the hope that it will be useful,
  but WITHOUT ANY WARRANTY; without even the implied warranty of
  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
  GNU General Public License for more details.

  You should have received a copy of the GNU General Public License
  along with Transmission Remote GUI; if not, write to the Free Software
  Foundation, Inc., 51 Franklin St, Fifth Floor, Boston, MA  02110-1301  USA
*************************************************************************************}

unit TorrProps;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, FileUtil, LResources, Forms, Controls, Graphics, Dialogs, StdCtrls, Spin, ButtonPanel, ComCtrls, BaseForm,
  fpjson, rpc, utils;

type

  { TTorrPropsForm }

  TTorrPropsForm = class(TBaseForm)
    Buttons: TButtonPanel;
    cbIdleSeedLimit: TCheckBox;
    cbMaxDown: TCheckBox;
    cbMaxUp: TCheckBox;
    cbSeedRatio: TCheckBox;
    edIdleSeedLimit: TSpinEdit;
    edMaxUp: TSpinEdit;
    edPeerLimit: TSpinEdit;
    edSeedRatio: TFloatSpinEdit;
    edMaxDown: TSpinEdit;
    edTrackers: TMemo;
    txTrackers: TLabel;
    Page: TPageControl;
    tabGeneral: TTabSheet;
    tabAdvanced: TTabSheet;
    txKbs1: TLabel;
    txKbs2: TLabel;
    txMinutes: TLabel;
    txName: TLabel;
    txPeerLimit: TLabel;
    procedure cbIdleSeedLimitClick(Sender: TObject);
    procedure cbMaxDownClick(Sender: TObject);
    procedure cbMaxUpClick(Sender: TObject);
    procedure cbSeedRatioClick(Sender: TObject);
    procedure FormCreate(Sender: TObject);
    procedure FormDestroy(Sender: TObject);
    procedure FormShow(Sender: TObject);
    procedure OKButtonClick(Sender: TObject);
  private
    FTorrentIds: array of integer;
    FSelCount: integer;
    FOrigTrackers: TStringList;
    FRequestLifetime: TRpcRequestLifetime;
    FPageNo: integer;
    FLoaded: boolean;
    procedure EnableControls(AEnabled: Boolean);
    procedure TorrentGetCompleted(ARequest: TObject);
    procedure TorrentSetCompleted(ARequest: TObject);
  public
    procedure LoadTorrent(const ATorrentIds: array of integer; ASelCount: integer; PageNo: integer);
  end;

implementation

uses main;

const
  TR_RATIOLIMIT_GLOBAL    = 0; // follow the global settings
  TR_RATIOLIMIT_SINGLE    = 1; // override the global settings, seeding until a certain ratio
  TR_RATIOLIMIT_UNLIMITED = 2; // override the global settings, seeding regardless of ratio

  TR_IDLELIMIT_GLOBAL     = 0; // follow the global settings
  TR_IDLELIMIT_SINGLE     = 1; // override the global settings, seeding until a certain idle time
  TR_IDLELIMIT_UNLIMITED  = 2; // override the global settings, seeding regardless of activity

  TR_SPEEDLIMIT_SINGLE    = 1;
  TR_SPEEDLIMIT_UNLIMITED = 2;

{ TTorrPropsForm }

procedure TTorrPropsForm.cbMaxDownClick(Sender: TObject);
begin
  edMaxDown.Enabled:=cbMaxDown.Checked;
end;

procedure TTorrPropsForm.cbIdleSeedLimitClick(Sender: TObject);
begin
  edIdleSeedLimit.Enabled:=cbIdleSeedLimit.State = cbChecked;
end;

procedure TTorrPropsForm.cbMaxUpClick(Sender: TObject);
begin
  edMaxUp.Enabled:=cbMaxUp.Checked;
end;

procedure TTorrPropsForm.cbSeedRatioClick(Sender: TObject);
begin
  edSeedRatio.Enabled:=cbSeedRatio.State = cbChecked;
end;

procedure TTorrPropsForm.FormCreate(Sender: TObject);
begin
  FRequestLifetime:=TRpcRequestLifetime.Create;
  FOrigTrackers:=TStringList.Create;
  Page.ActivePageIndex:=0;
  bidiMode := GetBiDi();
  Buttons.OKButton.ModalResult:=mrNone;
  Buttons.OKButton.OnClick:=@OKButtonClick;
  OnShow:=@FormShow;
end;

procedure TTorrPropsForm.FormDestroy(Sender: TObject);
begin
  FRequestLifetime.Active:=False;
  FRequestLifetime.Release;
  FOrigTrackers.Free;
end;

procedure TTorrPropsForm.EnableControls(AEnabled: Boolean);
var
  i: integer;
begin
  for i:=0 to ComponentCount - 1 do
    if Components[i] is TWinControl then
      TWinControl(Components[i]).Enabled:=AEnabled;
  Buttons.CancelButton.Enabled:=AEnabled;
  if AEnabled then
    AppNormal
  else
    AppBusy;
end;

procedure TTorrPropsForm.LoadTorrent(const ATorrentIds: array of integer; ASelCount: integer; PageNo: integer);
var
  i: integer;
begin
  FSelCount:=ASelCount;
  FPageNo:=PageNo;
  SetLength(FTorrentIds, Length(ATorrentIds));
  for i:=0 to High(ATorrentIds) do
    FTorrentIds[i]:=ATorrentIds[i];
  Page.ActivePageIndex:=PageNo;
end;

procedure TTorrPropsForm.FormShow(Sender: TObject);
var
  req, args: TJSONObject;
  _fields: TJSONArray;
  request: TRpcUserRequest;
begin
  if FLoaded then exit;
  FLoaded:=True;
  if Length(FTorrentIds) = 0 then begin
    ModalResult:=mrCancel;
    exit;
  end;
  EnableControls(False);

  req:=TJSONObject.Create;
  try
    req.Add('method', 'torrent-get');
    args:=TJSONObject.Create;
    args.Add('ids', TJSONArray.Create([FTorrentIds[0]]));
    _fields:=TJSONArray.Create(['downloadLimit', 'downloadLimitMode', 'downloadLimited',
      'uploadLimit', 'uploadLimitMode', 'uploadLimited',
      'name', 'maxConnectedPeers', 'seedRatioMode', 'seedRatioLimit',
      'seedIdleLimit', 'seedIdleMode', 'trackers']);
    args.Add('fields', _fields);
    req.Add('arguments', args);

    request:=TRpcUserRequest.Create(req, True, -1, @TorrentGetCompleted, FRequestLifetime);
    if not RpcObj.QueueUserRequest(request) then begin
      EnableControls(True);
      MessageDlg('Unable to queue RPC request.', mtError, [mbOK], 0);
      ModalResult:=mrCancel;
      exit;
    end;
    req:=nil;
  finally
    req.Free;
  end;
end;

procedure TTorrPropsForm.TorrentGetCompleted(ARequest: TObject);
var
  res: TJSONObject;
  t: TJSONObject;
  Trackers: TJSONArray;
  tr: TJSONObject;
  i, j: integer;
  s: string;
begin
  EnableControls(True);
  if TRpcUserRequest(ARequest).Cancelled then begin
    ModalResult:=mrCancel;
    exit;
  end;
  res:=TRpcUserRequest(ARequest).Result;
  if res = nil then begin
    MainForm.CheckStatus(False);
    ModalResult:=mrCancel;
    exit;
  end;

  t:=res.Arrays['torrents'].Objects[0];

  if FSelCount > 1 then
    s:=Format(sSeveralTorrents, [FSelCount])
  else
    s:=UTF8Encode(t.Strings['name']);

  txName.Caption:=txName.Caption + ' ' + s;
  Caption:=Caption + ' - ' + s;

  if RpcObj.RPCVersion < 5 then begin
    // RPC versions prior to v5
    j:=t.Integers['downloadLimitMode'];
    cbMaxDown.Checked:=j = TR_SPEEDLIMIT_SINGLE;
    i:=t.Integers['downloadLimit'];
    if (i < 0) or (j = TR_SPEEDLIMIT_UNLIMITED) then
      edMaxDown.ValueEmpty:=True
    else
      edMaxDown.Value:=i;

    j:=t.Integers['uploadLimitMode'];
    cbMaxUp.Checked:=j = TR_SPEEDLIMIT_SINGLE;
    i:=t.Integers['uploadLimit'];
    if (i < 0) or (j = TR_SPEEDLIMIT_UNLIMITED) then
      edMaxUp.ValueEmpty:=True
    else
      edMaxUp.Value:=i;
    cbSeedRatio.Visible:=False;
    edSeedRatio.Visible:=False;
  end
  else begin
    // RPC version 5
    cbMaxDown.Checked:=t.Booleans['downloadLimited'];
    i:=t.Integers['downloadLimit'];
    if i < 0 then
      edMaxDown.ValueEmpty:=True
    else
      edMaxDown.Value:=i;

    cbMaxUp.Checked:=t.Booleans['uploadLimited'];
    i:=t.Integers['uploadLimit'];
    if i < 0 then
      edMaxUp.ValueEmpty:=True
    else
      edMaxUp.Value:=i;

    case t.Integers['seedRatioMode'] of
      TR_RATIOLIMIT_SINGLE:
        cbSeedRatio.State:=cbChecked;
      TR_RATIOLIMIT_UNLIMITED:
        cbSeedRatio.State:=cbUnchecked;
      else
        cbSeedRatio.State:=cbGrayed;
    end;
    edSeedRatio.Value:=t.Floats['seedRatioLimit'];
  end;

  if RpcObj.RPCVersion >= 10 then begin
    case t.Integers['seedIdleMode'] of
      TR_IDLELIMIT_SINGLE:
        cbIdleSeedLimit.State:=cbChecked;
      TR_IDLELIMIT_UNLIMITED:
        cbIdleSeedLimit.State:=cbUnchecked;
      else
        cbIdleSeedLimit.State:=cbGrayed;
    end;
    edIdleSeedLimit.Value:=t.Integers['seedIdleLimit'];
    cbIdleSeedLimitClick(nil);

    Trackers:=t.Arrays['trackers'];
    for i:=0 to Trackers.Count - 1 do begin
      tr:=Trackers[i] as TJSONObject;
      FOrigTrackers.AddObject(UTF8Decode(tr.Strings['announce']), TObject(PtrUInt(tr.Integers['id'])));
    end;
    edTrackers.Lines.Assign(FOrigTrackers);
  end
  else begin
    cbIdleSeedLimit.Visible:=False;
    edIdleSeedLimit.Visible:=False;
    txMinutes.Visible:=False;
    tabAdvanced.TabVisible:=False;
  end;

  edPeerLimit.Value:=t.Integers['maxConnectedPeers'];

  cbMaxDownClick(nil);
  cbMaxUpClick(nil);
  cbSeedRatioClick(nil);
end;

procedure TTorrPropsForm.OKButtonClick(Sender: TObject);
var
  req, args: TJSONObject;
  ids: TJSONArray;
  i, j: integer;
  s: string;
  sl: TStringList;
  AddT, EditT, DelT: TJSONArray;
  request: TRpcUserRequest;
begin
  EnableControls(False);

  req:=TJSONObject.Create;
  try
    req.Add('method', 'torrent-set');
    args:=TJSONObject.Create;
    ids:=TJSONArray.Create;
    for i:=0 to High(FTorrentIds) do
      ids.Add(FTorrentIds[i]);
    args.Add('ids', ids);

    if RpcObj.RPCVersion < 5 then
    begin
      // RPC versions prior to v5
      args.Add('speed-limit-down-enabled', integer(cbMaxDown.Checked) and 1);
      args.Add('speed-limit-up-enabled', integer(cbMaxUp.Checked) and 1);
      if cbMaxDown.Checked then
        args.Add('speed-limit-down', edMaxDown.Value);
      if cbMaxUp.Checked then
        args.Add('speed-limit-up', edMaxUp.Value);
    end
    else begin
      // RPC version 5
      args.Add('downloadLimited', integer(cbMaxDown.Checked) and 1);
      args.Add('uploadLimited', integer(cbMaxUp.Checked) and 1);
      if cbMaxDown.Checked then
        args.Add('downloadLimit', edMaxDown.Value);
      if cbMaxUp.Checked then
        args.Add('uploadLimit', edMaxUp.Value);
      case cbSeedRatio.State of
        cbChecked:
          i:=TR_RATIOLIMIT_SINGLE;
        cbUnchecked:
          i:=TR_RATIOLIMIT_UNLIMITED;
        else
          i:=TR_RATIOLIMIT_GLOBAL;
      end;
      args.Add('seedRatioMode', i);
      if cbSeedRatio.State = cbChecked then
        args.Add('seedRatioLimit', edSeedRatio.Value);
    end;

    if RpcObj.RPCVersion >= 10 then begin
      case cbIdleSeedLimit.State of
        cbChecked:
          i:=TR_IDLELIMIT_SINGLE;
        cbUnchecked:
          i:=TR_IDLELIMIT_UNLIMITED;
        else
          i:=TR_IDLELIMIT_GLOBAL;
      end;
      args.Add('seedIdleMode', i);
      if cbIdleSeedLimit.State = cbChecked then
        args.Add('seedIdleLimit', edIdleSeedLimit.Value);

      sl:=TStringList.Create;
      try
        sl.Assign(edTrackers.Lines);
        // Removing unchanged trackers
        i:=0;
        while i < sl.Count do begin
          s:=Trim(sl[i]);
          if s = '' then begin
            sl.Delete(i);
            continue;
          end;
          j:=FOrigTrackers.IndexOf(s);
          if j >= 0 then begin
            FOrigTrackers.Delete(j);
            sl.Delete(i);
            continue;
          end;
          Inc(i);
        end;

        AddT:=TJSONArray.Create;
        EditT:=TJSONArray.Create;
        DelT:=TJSONArray.Create;
        try
          for i:=0 to sl.Count - 1 do begin
            s:=Trim(sl[i]);
            if FOrigTrackers.Count > 0 then begin
              EditT.Add(PtrUInt(FOrigTrackers.Objects[0]));
              EditT.Add(UTF8Decode(s));
              FOrigTrackers.Delete(0);
            end
            else
              AddT.Add(UTF8Decode(s));
          end;

          for i:=0 to FOrigTrackers.Count - 1 do
            DelT.Add(PtrUInt(FOrigTrackers.Objects[i]));

          if AddT.Count > 0 then begin
            args.Add('trackerAdd', AddT);
            AddT:=nil;
          end;
          if EditT.Count > 0 then begin
            args.Add('trackerReplace', EditT);
            EditT:=nil;
          end;
          if DelT.Count > 0 then begin
            args.Add('trackerRemove', DelT);
            DelT:=nil;
          end;
        finally
          DelT.Free;
          EditT.Free;
          AddT.Free;
        end;
      finally
        sl.Free;
      end;
    end;

    args.Add('peer-limit', edPeerLimit.Value);
    req.Add('arguments', args);

    request:=TRpcUserRequest.Create(req, False, -1, @TorrentSetCompleted, FRequestLifetime);
    if not RpcObj.QueueUserRequest(request) then begin
      EnableControls(True);
      MessageDlg('Unable to queue RPC request.', mtError, [mbOK], 0);
      exit;
    end;
    req:=nil;
  finally
    req.Free;
  end;
end;

procedure TTorrPropsForm.TorrentSetCompleted(ARequest: TObject);
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
  {$I torrprops.lrs}

end.

