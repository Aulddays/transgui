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

unit MoveTorrent;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, FileUtil, LResources, Forms, Controls, Graphics, Dialogs, StdCtrls, ButtonPanel, ExtCtrls, BaseForm,
  fpjson, rpc;

resourcestring
  SNoTorrentDir = 'No torrent location was specified.';
  SSelectFolder = 'Select torrent location';

type

  { TMoveTorrentForm }

  TMoveTorrentForm = class(TBaseForm)
    btBrowse: TButton;
    Buttons: TButtonPanel;
    cbMoveData: TCheckBox;
    edTorrentDir: TComboBox;
    Panel1: TPanel;
    txTorrentDir: TLabel;
    procedure btBrowseClick(Sender: TObject);
    procedure btOKClick(Sender: TObject);
    procedure FormCreate(Sender: TObject);
    procedure FormDestroy(Sender: TObject);
  private
    FTorrentIds: array of integer;
    FRequestLifetime: TRpcRequestLifetime;
    FTargetPath: string;
    FMoveStartTime: TDateTime;
    FPollTimer: TTimer;
    procedure EnableControls(AEnabled: Boolean);
    procedure MoveCompleted(ARequest: TObject);
    procedure CheckMoveProgress;
    procedure CheckMoveProgressCompleted(ARequest: TObject);
    procedure PollTimerTimer(Sender: TObject);
  public
    procedure SetTorrentIds(const Ids: array of integer);
  end;

implementation

uses main;

{ TMoveTorrentForm }

procedure TMoveTorrentForm.FormCreate(Sender: TObject);
begin
  FRequestLifetime:=TRpcRequestLifetime.Create;
  FPollTimer:=TTimer.Create(Self);
  FPollTimer.Interval:=500;
  FPollTimer.Enabled:=False;
  FPollTimer.OnTimer:=@PollTimerTimer;
  Buttons.OKButton.ModalResult:=mrNone;
  Buttons.OKButton.OnClick:=@btOKClick;
  bidiMode := GetBiDi();
  btBrowse.Left := edTorrentDir.Left + edTorrentDir.Width + 8; // fix button
end;

procedure TMoveTorrentForm.FormDestroy(Sender: TObject);
begin
  FPollTimer.Free;
  FRequestLifetime.Active:=False;
  FRequestLifetime.Release;
end;

procedure TMoveTorrentForm.SetTorrentIds(const Ids: array of integer);
var
  i: integer;
begin
  SetLength(FTorrentIds, Length(Ids));
  for i:=0 to High(Ids) do
    FTorrentIds[i]:=Ids[i];
end;

procedure TMoveTorrentForm.EnableControls(AEnabled: Boolean);
begin
  edTorrentDir.Enabled:=AEnabled;
  cbMoveData.Enabled:=AEnabled;
  btBrowse.Enabled:=AEnabled;
  Buttons.OKButton.Enabled:=AEnabled;
  Buttons.CancelButton.Enabled:=AEnabled;
  if AEnabled then
    Screen.Cursor:=crDefault
  else
    Screen.Cursor:=crHourGlass;
end;

procedure TMoveTorrentForm.btOKClick(Sender: TObject);
var
  req, args: TJSONObject;
  aids: TJSONArray;
  i: integer;
  request: TRpcUserRequest;
begin
  edTorrentDir.Text:=Trim(edTorrentDir.Text);
  if edTorrentDir.Text = '' then begin
    edTorrentDir.SetFocus;
    MessageDlg(SNoTorrentDir, mtError, [mbOK], 0);
    exit;
  end;

  req:=TJSONObject.Create;
  try
    req.Add('method', 'torrent-set-location');
    args:=TJSONObject.Create;
    aids:=TJSONArray.Create;
    for i:=0 to High(FTorrentIds) do
      aids.Add(FTorrentIds[i]);
    args.Add('ids', aids);
    args.Add('location', TJSONString.Create(UTF8Decode(edTorrentDir.Text)));
    args.Add('move', TJSONIntegerNumber.Create(integer(cbMoveData.Checked) and 1));
    req.Add('arguments', args);

    FRequestLifetime.AddRef;
    request:=TRpcUserRequest.Create(req, False, -1, @MoveCompleted, FRequestLifetime);
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

procedure TMoveTorrentForm.MoveCompleted(ARequest: TObject);
begin
  if TRpcUserRequest(ARequest).Cancelled then begin
    EnableControls(True);
    exit;
  end;
  if TRpcUserRequest(ARequest).Result = nil then begin
    EnableControls(True);
    MainForm.CheckStatus(False);
    exit;
  end;

  // torrent-set-location 已提交成功，但 daemon 在后台移动数据。
  // 开始轮询等待路径实际更新到位，对话框保持禁用状态。
  FTargetPath:=Trim(edTorrentDir.Text);
  FMoveStartTime:=Now;
  CheckMoveProgress;
end;

procedure TMoveTorrentForm.CheckMoveProgress;
var
  req, args: TJSONObject;
  _fields: TJSONArray;
  aids: TJSONArray;
  i: integer;
  request: TRpcUserRequest;
begin
  // 超时保护（20 秒）
  if Now - FMoveStartTime >= 20 / SecsPerDay then begin
    EnableControls(True);
    ModalResult:=mrOK;
    exit;
  end;

  req:=TJSONObject.Create;
  try
    req.Add('method', 'torrent-get');
    args:=TJSONObject.Create;
    aids:=TJSONArray.Create;
    for i:=0 to High(FTorrentIds) do
      aids.Add(FTorrentIds[i]);
    args.Add('ids', aids);
    _fields:=TJSONArray.Create(['downloadDir']);
    args.Add('fields', _fields);
    req.Add('arguments', args);

    FRequestLifetime.AddRef;
    request:=TRpcUserRequest.Create(req, True, -1, @CheckMoveProgressCompleted, FRequestLifetime);
    if not RpcObj.QueueUserRequest(request) then begin
      FRequestLifetime.Release;
      EnableControls(True);
      ModalResult:=mrOK;
      exit;
    end;
    req:=nil;
  finally
    req.Free;
  end;
end;

procedure TMoveTorrentForm.CheckMoveProgressCompleted(ARequest: TObject);
var
  res: TJSONObject;
  torrents: TJSONArray;
  i: integer;
  allDone: boolean;
  downloadDir: string;
begin
  if TRpcUserRequest(ARequest).Cancelled then begin
    EnableControls(True);
    exit;
  end;
  res:=TRpcUserRequest(ARequest).Result;
  if res = nil then begin
    // 查询失败，不中断，等下次再查
    CheckMoveProgress;
    exit;
  end;

  allDone:=True;
  torrents:=res.Arrays['torrents'];
  for i:=0 to torrents.Count - 1 do begin
    downloadDir:=UTF8Encode(torrents.Objects[i].Strings['downloadDir']);
    if AnsiCompareText(downloadDir, FTargetPath) <> 0 then begin
      allDone:=False;
      break;
    end;
  end;

  if allDone then begin
    EnableControls(True);
    ModalResult:=mrOK;
  end
  else begin
    // 还没完成，500ms 后再查（用定时器避免卡主线程）
    FPollTimer.Enabled:=True;
  end;
end;

procedure TMoveTorrentForm.PollTimerTimer(Sender: TObject);
begin
  FPollTimer.Enabled:=False;
  CheckMoveProgress;
end;

procedure TMoveTorrentForm.btBrowseClick(Sender: TObject);
var
  s: string;
begin
  s:=MainForm.SelectRemoteFolder(edTorrentDir.Text, SSelectFolder);
  if s <> '' then
    edTorrentDir.Text:=s;
end;

initialization
  {$I movetorrent.lrs}

end.
