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

unit AddTorrent;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, FileUtil, LResources, Forms, Controls, Graphics, Dialogs,
  StdCtrls, Spin, VarGrid, Grids, ButtonPanel, ExtCtrls, Buttons, BaseForm,
  varlist, fpjson, StrUtils, DateUtils, LazUTF8, rpc, bencode;

resourcestring
  SSize = 'Size';
  SSelectDownloadFolder = 'Select a folder for download';
  SInvalidName = 'Invalid name specified.';

type
  TPostAddFilterKind = (pafNone, pafPath, pafTracker);

  TFilesTree = class;

  { TAddTorrentForm }

  TAddTorrentForm = class(TBaseForm)
    DelButton: TBitBtn;
    btSelectAll: TButton;
    btSelectNone: TButton;
    btBrowse: TButton;
    Buttons: TButtonPanel;
    cbStartTorrent: TCheckBox;
    cbDestFolder: TComboBox;
    edSaveAs: TEdit;
    edExtension: TEdit;
    gbSaveAs: TGroupBox;
    gbContents: TGroupBox;
    edPeerLimit: TSpinEdit;
    DiskSpaceTimer: TTimer;
    txSaveAs: TLabel;
    txSaveAs1: TLabel;
    txSize: TLabel;
    txDiskSpace: TLabel;
    txPeerLimit: TLabel;
    lvFiles: TVarGrid;
    txDestFolder: TLabel;
    procedure btBrowseClick(Sender: TObject);
    procedure btSelectAllClick(Sender: TObject);
    procedure btSelectNoneClick(Sender: TObject);
    procedure cbDestFolderChange(Sender: TObject);
    procedure cbStartTorrentChange(Sender: TObject);
    procedure DelButtonClick(Sender: TObject);
    procedure DiskSpaceTimerTimer(Sender: TObject);
    procedure edSaveAsChange(Sender: TObject);
    procedure FormCreate(Sender: TObject);
    procedure FormDestroy(Sender: TObject);
    procedure FormShow(Sender: TObject);
    procedure OKButtonClick(Sender: TObject);
    procedure SearchGoodExtension ();
    function  GetTempate (ext:string; var e: array of string):integer;
    function  IsFileTemplate(filename:string; cntE : integer; e: array of string):boolean;
    function  CorrectPath (path: string): string;
    procedure DeleteDirs(maxdel : Integer);

  private
    FDiskSpaceCaption: string;
    FTree: TFilesTree;
    FRequestLifetime: TRpcRequestLifetime;
    // ---- 异步添加流程状态 ----
    FFileName: Utf8String;       // 原始文件名或URL
    FTorrentData: string;        // base64 编码的 torrent 数据，或 '-' 表示 URL/magnet
    FTorrentId: integer;         // 当前添加的 torrent id
    FOldName: string;            // 原始名称（用于重命名判断）
    FOldDownloadDir: string;     // 原始下载目录（用于目录变更判断）
    FIniSec: string;             // Ini section: 'AddTorrent.' + FCurConn
    FPostAddFilterKind: TPostAddFilterKind;
    FIsAppHidden: boolean;
    FWaitForm: TBaseForm;
    FStep: integer;              // 当前步骤（调试/状态追踪用）
    FAddTrackersTorrentId: integer; // _AddTrackers 子流程用
    FAddTrackersHash: string;    // _AddTrackers 子流程用 hash
    FAddTrackersList: TStringList; // _AddTrackers 子流程用 tracker 列表
    FOKClicked: boolean;         // 用户是否点了OK
    FInitialized: boolean;       // FormShow 是否已初始化（防止重复触发）
    FInitError: string;          // 初始化错误信息
    procedure TreeStateChanged(Sender: TObject);
    procedure UpdateSize;
    procedure FreeSpaceCompleted(ARequest: TObject);
    procedure EnableControls(AEnabled: Boolean);
    // ---- 异步流程回调 ----
    procedure AsyncFinish(ASuccess: boolean);
    procedure ShowWaitMsg(const AText: string);
    procedure HideWaitMsg;
    procedure StepSessionGet;
    procedure SessionGetCompleted(ARequest: TObject);
    procedure StepTorrentAdd;
    procedure TorrentAddCompleted(ARequest: TObject);
    procedure StepTorrentGetInfo;
    procedure TorrentGetInfoCompleted(ARequest: TObject);
    procedure StepOKAfterModal;
    procedure StepTorrentSet;
    procedure TorrentSetCompleted(ARequest: TObject);
    procedure StepTorrentRename;
    procedure TorrentRenameCompleted(ARequest: TObject);
    procedure StepTorrentStart;
    procedure TorrentStartCompleted(ARequest: TObject);
    // ---- _AddTrackers 子流程 ----
    procedure BeginAddTrackers(TorrentId: integer);
    procedure AddTrackersConfirmYes;
    procedure AddTrackersGetCompleted(ARequest: TObject);
    procedure AddTrackersSetCompleted(ARequest: TObject);
    procedure AddTrackersFinish;
  public
    OrigCaption: string;
    Extension : string;
    property FilesTree: TFilesTree read FTree;
    property ResultTorrentId: integer read FTorrentId;
    property ResultFilterKind: TPostAddFilterKind read FPostAddFilterKind;
    procedure Execute(const AFileName: Utf8String); // 入口（内部 ShowModal）
  end;

  TFolderInfo = record
    Size: double;
    DoneSize: double;
    Priority: integer;
    chk: TCheckBoxState;
  end;

  { TFilesTree }

  TFilesTree = class(TComponent)
  private
    FCheckboxes: boolean;
    FDownloadDir: string;
    FGrid: TVarGrid;
    FHasFolders: boolean;
    FIsPlain: boolean;
    FOnStateChange: TNotifyEvent;
    FFiles: TVarList;
    FTorrentId: integer;
    FLastFileCount: integer;
    FCommonPathLen: integer;
    FHasDone: boolean;
    FHasPriority: boolean;

    procedure CollapseFolder(ARow: integer);
    procedure DoCellAttributes(Sender: TVarGrid; ACol, ARow, ADataCol: integer; AState: TGridDrawState; var CellAttribs: TCellAttributes);
    procedure DoCheckBoxClick(Sender: TVarGrid; ACol, ARow, ADataCol: integer);
    procedure DoDrawCell(Sender: TVarGrid; ACol, ARow, ADataCol: integer; AState: TGridDrawState; const R: TRect; var ADefaultDrawing: boolean);
    procedure DoQuickSearch(Sender: TVarGrid; var SearchText: string; var ARow: integer);
    procedure DoTreeButtonClick(Sender: TVarGrid; ACol, ARow, ADataCol: integer);
    procedure DoAfterSort(Sender: TObject);
    procedure ExpandFolder(ARow: integer);
    function GetChecked(ARow: integer): TCheckBoxState;
    function GetExpanded(ARow: integer): boolean;
    function GetLevel(ARow: integer): integer;
    procedure SetCheckboxes(const AValue: boolean);
    procedure IntSetChecked(ARow: integer; const AValue: TCheckBoxState);
    procedure SetChecked(ARow: integer; const AValue: TCheckBoxState);
    procedure SetExpanded(ARow: integer; const AValue: boolean);
    procedure SetIsPlain(const AValue: boolean);
    procedure TreeChanged;
    procedure DoOnStateChange;
    function DoCompareVarRows(Sender: TVarList; Row1, Row2: PVariant; DescendingSort: boolean): integer;
    procedure SetRowOption(ARow, AOption: integer; DoSet: boolean);
  public
    constructor Create(AGrid: TVarGrid); reintroduce;
    destructor Destroy; override;
    function IsFolder(ARow: integer): boolean;
    procedure CollapseAll;
    procedure FillTree(ATorrentId: integer; files, priorities, wanted: TJSONArray);
    procedure SetStateAll(AState: TCheckBoxState);
    procedure EnsureRowVisible(ARow: integer);
    function GetFullPath(ARow: integer; AbsolutePath: boolean = True): string;
    function UpdateSummary: TFolderInfo;
    procedure Clear;
    property Grid: TVarGrid read FGrid;
    property HasFolders: boolean read FHasFolders;
    property Checkboxes: boolean read FCheckboxes write SetCheckboxes;
    property IsPlain: boolean read FIsPlain write SetIsPlain;
    property DownloadDir: string read FDownloadDir write FDownloadDir;
    property Expanded[ARow: integer]: boolean read GetExpanded write SetExpanded;
    property Checked[ARow: integer]: TCheckBoxState read GetChecked write SetChecked;
    property RowLevel[ARow: integer]: integer read GetLevel;
    property OnStateChange: TNotifyEvent read FOnStateChange write FOnStateChange;
  end;

const
  // Files list columns
  idxFileName      = 0;
  idxFileSize      = 1;
  idxFileDone      = 2;
  idxFileProgress  = 3;
  idxFilePriority  = 4;
  idxFileId        = -1;
  idxFileFullPath  = -2;
  idxFileLevel     = -3;
  idxFileIndex     = -4;

  FilesExtraColumns = 4;

implementation

uses lclintf, lcltype, main, variants, Utils, lclproc,
  synacode, synautil, LazFileUtils, ResTranslator, download;

const
  roChecked   = $030000;
  roCollapsed = $040000;
  roHidden    = $080000;
  roTag       = $100000;

  roCheckedShift = 16;

  TR_PRI_MIXED = -1001;  // psedudo priority

{ TFilesTree }

constructor TFilesTree.Create(AGrid: TVarGrid);
begin
  inherited Create(AGrid);
  FGrid:=AGrid;
  FFiles:=FGrid.Items;
  FGrid.OnCheckBoxClick:=@DoCheckBoxClick;
  FGrid.OnTreeButtonClick:=@DoTreeButtonClick;
  FGrid.OnCellAttributes:=@DoCellAttributes;
  FGrid.OnAfterSort:=@DoAfterSort;
  FGrid.OnQuickSearch:=@DoQuickSearch;
  FGrid.OnDrawCell:=@DoDrawCell;
end;

destructor TFilesTree.Destroy;
begin
  inherited Destroy;
end;

function TFilesTree.IsFolder(ARow: integer): boolean;
begin
  Result:=VarIsEmpty(FGrid.Items[idxFileId, ARow]);
end;

procedure TFilesTree.CollapseAll;
var
  i: integer;
begin
  FGrid.BeginUpdate;
  try
    for i:=0 to FGrid.Items.Count - 1 do begin
      if IsFolder(i) then
        SetRowOption(i, roCollapsed, True);
      if integer(FGrid.Items[idxFileLevel, i]) > 0 then begin
        FGrid.RowVisible[i]:=False;
        FGrid.RowSelected[i]:=False;
        SetRowOption(i, roHidden, True);
      end;
    end;
    TreeChanged;
  finally
    FGrid.EndUpdate;
  end;
end;

procedure TFilesTree.FillTree(ATorrentId: integer; files, priorities, wanted: TJSONArray);

  procedure _AddFolders(list: TVarList; const path: string; var idx: integer; cnt, level: integer);
  var
    s, ss: string;
    j: integer;
    p: PChar;
    ww: widestring;
  begin
    while idx < cnt do begin

      ww := widestring(list[idxFileFullPath, idx]);

      s  := StringReplace(UTF8Encode(ww), ':', '_', [rfReplaceAll, rfIgnoreCase]);
      s  := ExtractFilePath(s); // fixed an incorrect search if there is a ":"

      if s = '' then begin
        Inc(idx);
        continue;
      end;
      if (path <> '') and (Pos(path, s) <> 1)  then
        break;
      if s = path then begin
        list[idxFileLevel, idx]:=level;
        Inc(idx);
      end
      else begin
        ss:=Copy(s, Length(path) + 1, MaxInt);
        p:=PChar(ss);
        while (p^ <> #0) and not (p^ in ['/','\']) do
          Inc(p);
        if p^ <> #0 then begin
          SetLength(ss, p - PChar(ss) + 1);
          j:=list.Count;
          list[idxFileLevel, j]:=level;
          list[idxFileFullPath, j]:=UTF8Decode(path + ss);
          _AddFolders(list, path + ss, idx, cnt, level + 1);
          ss:=ExcludeTrailingPathDelimiter(ss);
          list[idxFileName, j]:=UTF8Decode(ExtractFileName(ss));
        end;
      end;
    end;
  end;

var
  i, row: integer;
  FullRefresh: boolean;
  f: TJSONObject;
  s, ss, path: string;
  ff: double;
begin
  if files = nil then begin
    FGrid.Items.Clear;
    exit;
  end;
  FHasDone:=FGrid.Columns.Count > idxFileDone;
  FHasPriority:=FHasDone and (priorities <> nil) and (wanted <> nil);
  FullRefresh:=(FTorrentId <> ATorrentId) or (FLastFileCount <> files.Count);
  FLastFileCount:=files.Count;
  FTorrentId:=ATorrentId;
  FIsPlain:=FGrid.SortColumn <> idxFileName;
  FFiles.BeginUpdate;
  try
    FFiles.OnCompareVarRows:=nil;
    if FullRefresh then
      FFiles.Clear
    else begin
      for i:=0 to FFiles.Count - 1 do
        SetRowOption(i, roTag, False);
      FFiles.Sort(idxFileId);
    end;

    // Detecting top level folder to be removed
    FCommonPathLen:=0;
    path:='';
    if files.Count > 0 then begin
      s:=UTF8Encode(files.Objects[0].Strings['name']);
      s:=ExcludeInvalidChar(s); // petrov - Exclude prohibited characters
      FCommonPathLen:=Pos(RemotePathDelimiter, s);
      if FCommonPathLen > 0 then
        path:=Copy(s, 1, FCommonPathLen);
    end;

    FHasFolders:=False;
    for i:=0 to files.Count - 1 do begin
      f:=files.Objects[i];
      if FullRefresh then begin
        row:=i;
        FFiles[idxFileLevel, row]:=0;
      end
      else
        if not FFiles.Find(idxFileId, i, row) then begin
          FFiles.InsertRow(row);
          FFiles[idxFileLevel, row]:=0;
        end;
      SetRowOption(row, roTag, True);
      FFiles[idxFileId, row]:=i;

      s:=UTF8Encode(f.Strings['name']);
      s:=ExcludeInvalidChar(s); // petrov - Exclude prohibited characters

      FFiles[idxFileFullPath, row]:=UTF8Decode(ExtractFilePath(s));
      if FCommonPathLen > 0 then
        s:=Copy(s, FCommonPathLen + 1, MaxInt);
      ss:=ExtractFileName(s);
      if ss <> s then
        FHasFolders:=True;

      FFiles[idxFileName, row]:=UTF8Decode(ss);
      ff:=f.Floats['length'];
      FFiles[idxFileSize, row]:=ff;

      if FHasDone then begin
        FFiles[idxFileDone, row]:=f.Floats['bytesCompleted'];
        if ff = 0 then
          ff:=100.0
        else
          ff:=double(FFiles[idxFileDone, row])*100.0/ff;
        FFiles[idxFileProgress, row]:=Int(ff*10.0)/10.0;

        if FHasPriority then begin
          if wanted.Integers[i] = 0 then begin
            FFiles[idxFilePriority, row]:=TR_PRI_SKIP;
            IntSetChecked(row, cbUnchecked);
          end
          else begin
            FFiles[idxFilePriority, row]:=priorities.Integers[i];
            IntSetChecked(row, cbChecked);
          end;
        end;
      end;
    end;

    if not FullRefresh then begin
      i:=0;
      while i < FFiles.Count do
        if not IsFolder(i) and not LongBool(FFiles.RowOptions[i] and roTag) then
          FFiles.Delete(i)
        else
          Inc(i);
    end;

    if HasFolders and FullRefresh then begin
      FFiles.Sort(idxFileFullPath);
      i:=0;
      _AddFolders(FFiles, path, i, FFiles.Count, 0);
    end;

    FFiles.OnCompareVarRows:=@DoCompareVarRows;
    FGrid.Sort;
    if FullRefresh and (FFiles.Count > 0) then begin
      FGrid.Row:=0;
      if HasFolders then begin
        i:=FFiles.RowCnt + FGrid.FixedRows;
        if FGrid.RowCount <> i then
          FGrid.RowCount:=i;
        CollapseAll;
      end
      else
        TreeChanged;
    end
    else
      TreeChanged;
    if not IsPlain then
      UpdateSummary;
  finally
    FFiles.EndUpdate;
  end;
end;

procedure TFilesTree.SetStateAll(AState: TCheckBoxState);
var
  i: integer;
begin
  FFiles.BeginUpdate;
  try
    for i:=0 to FFiles.Count - 1 do
      IntSetChecked(i, AState);
  finally
    FFiles.EndUpdate;
  end;
  DoOnStateChange;
end;

procedure TFilesTree.EnsureRowVisible(ARow: integer);
var
  i, level: integer;
begin
  if not FGrid.RowVisible[ARow] then begin
    FGrid.BeginUpdate;
    try
      level:=FFiles[idxFileLevel, ARow] - 1;
      for i:=ARow downto 0 do begin
        if IsFolder(i) and (FFiles[idxFileLevel, i] = level) then begin
          ExpandFolder(i);
          if level = 0 then
            break;
          Dec(level);
        end;
      end;
    finally
      FGrid.EndUpdate;
    end;
  end;
  FGrid.EnsureRowVisible(ARow);
end;

function TFilesTree.GetFullPath(ARow: integer; AbsolutePath: boolean): string;
begin
  if AbsolutePath then begin
    Result:=FDownloadDir;
    if Copy(Result, Length(Result), 1) <> RemotePathDelimiter then
      Result:=Result + RemotePathDelimiter;
  end
  else
    Result:='';
    Result:=Result + UTF8Encode(widestring(FFiles[idxFileFullPath, ARow]));

  if IsFolder(ARow) then
      Result:=Copy(Result, 1, Length(Result) - 1)
  else
      Result:=Result + UTF8Encode(widestring(FFiles[idxFileName, ARow]));
end;

function TFilesTree.UpdateSummary: TFolderInfo;

  function _UpdateSummary(var idx: integer; cnt, level: integer): TFolderInfo;
  var
    i, j: integer;
    IsFirst: boolean;
  begin
    FillChar(Result, SizeOf(Result), 0);
    IsFirst:=True;
    while idx < cnt do begin
      if FFiles[idxFileLevel, idx] <> level then
        break;
      i:=idx;
      Inc(idx);

      if IsFolder(i) then begin
        with _UpdateSummary(idx, cnt, level + 1) do begin
          FFiles[idxFileSize, i]:=Size;
          if FHasDone then begin
            FFiles[idxFileDone, i]:=DoneSize;
            if Size = 0 then
              DoneSize:=100.0
            else
              DoneSize:=DoneSize*100.0/Size;
            FFiles[idxFileProgress, i]:=Int(DoneSize*10.0)/10.0;
          end;
          if FHasPriority then begin
            FFiles[idxFilePriority, i]:=Priority;
            IntSetChecked(i, chk);
          end;
        end;
      end;

      with Result do begin
        Size:=Size + FFiles[idxFileSize, i];
        if FHasDone then
          DoneSize:=DoneSize + FFiles[idxFileDone, i];
        if FHasPriority then begin
          j:=FFiles[idxFilePriority, i];
          if IsFirst then begin
            IsFirst:=False;
            Priority:=j;
            chk:=Checked[i];
          end
          else begin
            if Priority <> j then
              Priority:=TR_PRI_MIXED;
            if chk <> Checked[i] then
              chk:=cbGrayed;
          end;
        end;
      end;
    end;
  end;

var
  i: integer;
begin
  FFiles.BeginUpdate;
  try
    i:=0;
    Result:=_UpdateSummary(i, FFiles.Count, 0);
  finally
    FFiles.EndUpdate;
  end;
end;

procedure TFilesTree.Clear;
begin
  FLastFileCount:=0;
  FTorrentId:=0;
  FFiles.Clear;
end;

procedure TFilesTree.DoCheckBoxClick(Sender: TVarGrid; ACol, ARow, ADataCol: integer);
begin
  if Checked[ARow] = cbChecked then
    Checked[ARow]:=cbUnchecked
  else
    Checked[ARow]:=cbChecked;
end;

procedure TFilesTree.DoTreeButtonClick(Sender: TVarGrid; ACol, ARow, ADataCol: integer);
begin
  Expanded[ARow]:=not Expanded[ARow];
end;

procedure TFilesTree.DoAfterSort(Sender: TObject);
var
  p: boolean;
begin
  p:=FGrid.SortColumn <> idxFileName;
  if p <> IsPlain then
    IsPlain:=p
  else
    TreeChanged;
end;

procedure TFilesTree.CollapseFolder(ARow: integer);
var
  i, lev: integer;
begin
  AppBusy;
  FGrid.BeginUpdate;
  try
    lev:=FGrid.Items[idxFileLevel, ARow];
    SetRowOption(ARow, roCollapsed, True);
    for i:=ARow + 1 to FGrid.Items.Count - 1 do
      if integer(FGrid.Items[idxFileLevel, i]) > lev then begin
        FGrid.RowVisible[i]:=False;
        FGrid.RowSelected[i]:=False;
        SetRowOption(i, roHidden, True);
      end
      else
        break;
    TreeChanged;
  finally
    FGrid.EndUpdate;
  end;
  AppNormal;
end;

procedure TFilesTree.ExpandFolder(ARow: integer);
var
  i, j, lev: integer;
begin
  AppBusy;
  FGrid.BeginUpdate;
  try
    lev:=FGrid.Items[idxFileLevel, ARow] + 1;
    SetRowOption(ARow, roCollapsed, False);
    for i:=ARow + 1 to FGrid.Items.Count - 1 do begin
      j:=integer(FGrid.Items[idxFileLevel, i]);
      if j = lev then begin
        FGrid.RowVisible[i]:=True;
        SetRowOption(i, roHidden, False);
        if IsFolder(i) and Expanded[i] then
          ExpandFolder(i);
      end
      else
        if j <= lev then
          break;
    end;
    TreeChanged;
  finally
    FGrid.EndUpdate;
  end;
  AppNormal;
end;

function TFilesTree.GetChecked(ARow: integer): TCheckBoxState;
begin
  Result:=TCheckBoxState((FFiles.RowOptions[ARow] and roChecked) shr roCheckedShift);
end;

function TFilesTree.GetExpanded(ARow: integer): boolean;
begin
  Result:=not LongBool(FFiles.RowOptions[ARow] and roCollapsed);
end;

function TFilesTree.GetLevel(ARow: integer): integer;
begin
  Result:=FFiles[idxFileLevel, ARow];
end;

procedure TFilesTree.SetCheckboxes(const AValue: boolean);
begin
  if FCheckboxes = AValue then exit;
  FCheckboxes:=AValue;
end;

procedure TFilesTree.IntSetChecked(ARow: integer; const AValue: TCheckBoxState);
begin
  FFiles.RowOptions[ARow]:=(FFiles.RowOptions[ARow] and not roChecked) or (integer(AValue) shl roCheckedShift);
end;

procedure TFilesTree.SetChecked(ARow: integer; const AValue: TCheckBoxState);
var
  i, lev: integer;
  st: TCheckBoxState;
begin
  st:=AValue;
  if st = cbGrayed then
    st:=cbUnchecked;
  if Checked[ARow] = st then
    exit;
  IntSetChecked(ARow, st);
  FGrid.InvalidateRow(ARow + FGrid.FixedRows);

  if not IsPlain then begin
    lev:=integer(FFiles[idxFileLevel, ARow]);

    if IsFolder(ARow) then begin
      FFiles.BeginUpdate;
      for i:=ARow + 1 to FFiles.Count - 1 do
        if integer(FFiles[idxFileLevel, i]) <= lev then
          break
        else
          IntSetChecked(i, st);
      FFiles.EndUpdate;
    end;

    if lev > 0 then begin
      i:=ARow + 1;
      while (i < FFiles.Count) and (integer(FFiles[idxFileLevel, i]) >= lev) do
        Inc(i);

      for i:=i - 1 downto 0 do begin
        if IsFolder(i) and (integer(FFiles[idxFileLevel, i]) < lev) then begin
          IntSetChecked(i, st);
          FGrid.InvalidateRow(i + FGrid.FixedRows);
          Dec(lev);
          if lev = 0 then
            break;
        end
        else
          if Checked[i] <> st then
            st:=cbGrayed;
      end;
    end;
  end;
  DoOnStateChange;
end;

procedure TFilesTree.SetExpanded(ARow: integer; const AValue: boolean);
begin
  if GetExpanded(ARow) <> AValue then
    if AValue then
      ExpandFolder(ARow)
    else
      CollapseFolder(ARow);
end;

procedure TFilesTree.SetIsPlain(const AValue: boolean);
begin
  if FIsPlain = AValue then exit;
  FIsPlain:=AValue;
  FFiles.BeginUpdate;
  try
    TreeChanged;
    if not FIsPlain then
      UpdateSummary;
  finally
    FFiles.EndUpdate;
  end;
  if FFiles.Count > 0 then
    FGrid.Row:=0;
end;

procedure TFilesTree.TreeChanged;
var
  i, j: integer;
  f: boolean;
begin
  FGrid.Items.BeginUpdate;
  try
    FGrid.RowCount:=FFiles.RowCnt + FGrid.FixedRows;
    j:=0;
    for i:=0 to FGrid.Items.Count - 1 do begin
      if IsPlain then
        f:=not IsFolder(i)
      else
        f:=not LongBool(FFiles.RowOptions[i] and roHidden);
      FGrid.RowVisible[i]:=f;
      if f then begin
        FGrid.Items[idxFileIndex, i]:=j;
        Inc(j);
      end;
    end;
  finally
    FGrid.Items.EndUpdate;
  end;
end;

procedure TFilesTree.DoOnStateChange;
begin
  if Assigned(FOnStateChange) then
    FOnStateChange(Self);
end;

function TFilesTree.DoCompareVarRows(Sender: TVarList; Row1, Row2: PVariant; DescendingSort: boolean): integer;
begin
  if FGrid.SortColumn <> idxFileName then begin
    Result:=(integer(VarIsEmpty(Sender.GetRowItem(Row1, idxFileId))) and 1) - (integer(VarIsEmpty(Sender.GetRowItem(Row2, idxFileId))) and 1);
    exit;
  end;

  Result:=CompareVariants(Sender.GetRowItem(Row1, idxFileFullPath), Sender.GetRowItem(Row2, idxFileFullPath));
  if Result <> 0 then
    exit;
  Result:=(integer(VarIsEmpty(Sender.GetRowItem(Row2, idxFileId))) and 1) - (integer(VarIsEmpty(Sender.GetRowItem(Row1, idxFileId))) and 1);
  if Result <> 0 then
    exit;
  Result:=CompareVariants(Sender.GetRowItem(Row1, idxFileName), Sender.GetRowItem(Row2, idxFileName));
  if DescendingSort then
    Result:=-Result;
end;

procedure TFilesTree.SetRowOption(ARow, AOption: integer; DoSet: boolean);
var
  i: integer;
begin
  i:=FFiles.RowOptions[ARow];
  if DoSet then
    FFiles.RowOptions[ARow]:=i or AOption
  else
    FFiles.RowOptions[ARow]:=i and not AOption;
end;

procedure TFilesTree.DoCellAttributes(Sender: TVarGrid; ACol, ARow, ADataCol: integer; AState: TGridDrawState; var CellAttribs: TCellAttributes);
var
  i: integer;
begin
  if ARow < 0 then exit;
  with CellAttribs do begin
    if not (gdSelected in AState) and (integer(Sender.Items[idxFileIndex, ARow]) and 1 = 1) then
      Sender.Canvas.Brush.Color:=FAlterColor;
    if Text = '' then exit;
    case ADataCol of
      0:
        begin
//        Text:=(Sender.Items[idxFileFullPath, ARow]) + ' (' + Text + ')';// Lazarus 1.4.4

          if Checkboxes then begin
            Options:=[coDrawCheckBox];
            State:=Checked[ARow];
          end;
          if IsPlain then begin
            Text:=Copy(UTF8Encode(widestring(Sender.Items[idxFileFullPath, ARow])), FCommonPathLen + 1, MaxInt) + Text;
          end
          else begin
            Indent:=integer(Sender.Items[idxFileLevel, ARow])*16;
            if IsFolder(ARow) then begin
              Include(Options, coDrawTreeButton);
              Expanded:=Self.Expanded[ARow];
              ImageIndex:=22;
            end
            else
              if HasFolders then
                Inc(Indent, Sender.RowHeights[ARow + Sender.FixedRows]);
          end;
        end;
      idxFileSize, idxFileDone:
        Text:=(GetHumanSize(double(Sender.Items[ADataCol, ARow])));
      idxFileProgress:
        Text:=(Format('%.1f%%', [double(Sender.Items[ADataCol, ARow])]));
      idxFilePriority:
        begin
          i:=Sender.Items[idxFilePriority, ARow];
          if i = TR_PRI_MIXED then
            Text:=''
          else
            Text:= (PriorityToStr(i, ImageIndex));
        end;
    end;
  end;
end;

procedure TFilesTree.DoDrawCell(Sender: TVarGrid; ACol, ARow, ADataCol: integer; AState: TGridDrawState; const R: TRect;
  var ADefaultDrawing: boolean);
begin
  if ARow < 0 then exit;
  if ADataCol = idxFileProgress then begin
    ADefaultDrawing:=False;
    DrawProgressCell(Sender, ACol, ARow, ADataCol, AState, R);
  end;
end;

procedure TFilesTree.DoQuickSearch(Sender: TVarGrid; var SearchText: string; var ARow: integer);
var
  i: integer;
  s: string;
  v: variant;
begin
  s:= LazUTF8.UTF8UpperCase(SearchText);
  for i:=ARow to Sender.Items.Count - 1 do begin
    v:=Sender.Items[idxFileName, i];
    if VarIsEmpty(v) or VarIsNull(v) or (IsPlain and IsFolder(i)) then
      continue;
    if Pos(s, Trim(LazUTF8.UTF8UpperCase((widestring(v))))) > 0 then begin
      ARow:=i;
      EnsureRowVisible(ARow);
      break;
    end;
  end;
end;

{ TAddTorrentForm }

procedure TAddTorrentForm.FormShow(Sender: TObject);
begin
  if FInitialized then exit;
  FInitialized:=True;

  // 初始化失败，直接关闭
  if FInitError <> '' then begin
    MessageDlg(FInitError, mtError, [mbOK], 0);
    ModalResult:=mrCancel;
    exit;
  end;

  // 启动异步流程：第一步 session-get
  EnableControls(False);
  StepSessionGet;
end;

procedure TAddTorrentForm.EnableControls(AEnabled: Boolean);
var
  i: integer;
begin
  for i:=0 to ComponentCount - 1 do
    if Components[i] is TWinControl then
      TWinControl(Components[i]).Enabled:=AEnabled;
  Buttons.CancelButton.Enabled:=True; // Cancel 始终可用
  Buttons.OKButton.Enabled:=AEnabled;
  if AEnabled then
    AppNormal
  else
    AppBusy;
end;

function TAddTorrentForm.CorrectPath (path: string): string;
var
  l_old: integer;
begin
  path  := StringReplace(path, '//', '/', [rfReplaceAll, rfIgnoreCase]);
  Result:= path;
  l_old := length(path);
  if l_old >= 1 then begin
    if path[l_old]='/' then
        path := MidStr(path,1,l_old-1);
    Result:= path;
  end;
end;

procedure TAddTorrentForm.DeleteDirs(maxdel : Integer);
var
  i,min,max,indx, fldr: integer;
  pFD : FolderData;
begin
    max:=Ini.ReadInteger('Interface', 'MaxFoldersHistory',  50);
    Ini.WriteInteger    ('Interface', 'MaxFoldersHistory', max); // PETROV

    try
      while (cbDestFolder.Items.Count+maxdel) > max do begin
        min := 9999999;
        indx:=-1;
        for i:=0 to cbDestFolder.Items.Count - 1 do begin
          pFD := cbDestFolder.Items.Objects[i] as FolderData;

          fldr := DaysBetween(SysUtils.Date,pFD.Lst);
          if SysUtils.Date > pFD.Lst then
            fldr := 0- fldr;

          fldr := fldr + pFD.Hit;
          if fldr < min then begin
            min := fldr;
            indx:= i;
          end;
        end;

        if indx > -1 then
          cbDestFolder.Items.Delete(indx);
      end;
    except
      MessageDlg('Error: LS-001. Please contact the developer', mtError, [mbOK], 0);
    end;
end;

procedure TAddTorrentForm.OKButtonClick(Sender: TObject);
var
  s,e : string;
  i : integer;
  pFD : FolderData;
begin

  s := CorrectPath(cbDestFolder.Text);
  e := edExtension.Text;
  i := cbDestFolder.Items.IndexOf(s);
  try
    if i < 0 then begin
      DeleteDirs (1);               // prepare for new item
      cbDestFolder.Items.Add (s);
      i:=cbDestFolder.Items.IndexOf(s);
      pFD    := FolderData.create;
      pFD.Hit:= 1;
      pFD.Ext:= e;
      pFD.Txt:= s;
      pFD.Lst:= SysUtils.Date;
      cbDestFolder.Items.Objects[i]:= pFD;
    end else begin
      pFD    := cbDestFolder.Items.Objects[i] as FolderData;
      pFD.Hit:= pFD.Hit + 1;
      pFD.Ext:= e;
      pFD.Txt:= s;
      pFD.Lst:= SysUtils.Date;
      cbDestFolder.Items.Objects[i]:= pFD;
      DeleteDirs (0);               // check count items
    end;
  except
    MessageDlg('Error: LS-002. Please contact the developer', mtError, [mbOK], 0);
  end;

  // petrov - Exclude prohibited characters
  edSaveAs.Text := ExcludeInvalidChar(edSaveAs.Text);

  if edSaveAs.Enabled then begin
    edSaveAs.Text:=Trim(edSaveAs.Text);

    if edSaveAs.Text = '' then begin
      edSaveAs.SetFocus;
      MessageDlg(SInvalidName, mtError, [mbOK], 0);
      exit;
    end;
  end;

  // 异步化：不再直接关闭，而是启动后续 RPC 流程
  Buttons.OKButton.Enabled:=False;
  StepOKAfterModal;
end;

procedure TAddTorrentForm.UpdateSize;
var
  i: integer;
  d, sz, tsz: double;
  s: string;
begin
  sz:=0;
  tsz:=0;
  for i:=0 to lvFiles.Items.Count - 1 do
    if not FTree.IsFolder(i) then begin
      d:=double(lvFiles.Items[idxFileSize, i]);
      tsz:=tsz + d;
      if FTree.Checked[i] = cbChecked then
        sz:=sz + d;
    end;

  s:=GetHumanSize(sz);
  if s <> GetHumanSize(tsz) then
    s:=s + ' / ' + GetHumanSize(tsz);
  txSize.Caption:=Format('%s: %s', [SSize, s]);
end;

procedure TAddTorrentForm.btSelectAllClick(Sender: TObject);
begin
  FTree.SetStateAll(cbChecked);
end;

procedure TAddTorrentForm.btBrowseClick(Sender: TObject);
var
  s: string;
begin
  s:=MainForm.SelectRemoteFolder(cbDestFolder.Text, SSelectDownloadFolder);
  if s <> '' then begin
    cbDestFolder.Text:=s;
    cbDestFolderChange (nil);
  end;
end;

procedure TAddTorrentForm.btSelectNoneClick(Sender: TObject);
begin
  FTree.SetStateAll(cbUnchecked);
end;

procedure TAddTorrentForm.cbDestFolderChange(Sender: TObject);
var
  s : string;
  i : integer;
  pFD : FolderData;
begin
  s := cbDestFolder.Text;
  i := cbDestFolder.Items.IndexOf(s);
  if i < 0 then begin
    edExtension.Text := '';
  end else begin
    pFD             := cbDestFolder.Items.Objects[i] as FolderData;
    edExtension.Text:= pFD.Ext;
  end;
  DiskSpaceTimer.Enabled:=True;
end;

procedure TAddTorrentForm.cbStartTorrentChange(Sender: TObject);
begin
    Ini.WriteBool('Interface', 'StartTorrentOnAdd', cbStartTorrent.Checked);
    if (cbStartTorrent.Checked = false) then begin
      cbStartTorrent.Font.Style:= [fsbold];
      Buttons.OKButton.Font.Style:= [fsbold]
    end
    else begin
      cbStartTorrent.Font.Style:= [];
      Buttons.OKButton.Font.Style:= []
    end;
end;

procedure TAddTorrentForm.DelButtonClick(Sender: TObject);
var
  i: integer;
  s : string;
begin
    if cbDestFolder.Items.Count > 1 then begin
        s := CorrectPath(cbDestFolder.Text);
        i := cbDestFolder.Items.IndexOf(s);
        if i > -1 then begin
              cbDestFolder.Items.Delete(i);
              cbDestFolder.ItemIndex:=0;
        end;
    end;
end;

procedure TAddTorrentForm.DiskSpaceTimerTimer(Sender: TObject);
var
  req, args: TJSONObject;
  request: TRpcUserRequest;
begin
  DiskSpaceTimer.Enabled:=False;
  if RpcObj.RPCVersion < 15 then
    exit;
  req:=TJSONObject.Create;
  try
    req.Add('method', 'free-space');
    args:=TJSONObject.Create;
    args.Add('path', UTF8Decode(cbDestFolder.Text));
    req.Add('arguments', args);

    FRequestLifetime.AddRef;
    request:=TRpcUserRequest.Create(req, True, -1, @FreeSpaceCompleted, FRequestLifetime);
    if not RpcObj.QueueUserRequest(request) then begin
      FRequestLifetime.Release;
      txDiskSpace.Caption:=FDiskSpaceCaption + ' ' + GetHumanSize(-1);
      exit;
    end;
    req:=nil;
  finally
    req.Free;
  end;
end;

procedure TAddTorrentForm.edSaveAsChange(Sender: TObject);
begin
  Caption:=OrigCaption + ' - ' + edSaveAs.Text;
end;

procedure TAddTorrentForm.TreeStateChanged(Sender: TObject);
begin
  UpdateSize;
end;

function  TAddTorrentForm.GetTempate (ext:string; var e: array of string):integer;
var
  tmp,exten : string;
  i,n : integer;
begin
  tmp   := ext;
  exten := ext;
  n     := 0;
  while tmp <> '' do begin
    i := Pos (' ', tmp);
    if (i <> 0) then begin
      exten:= Trim (Copy (tmp, 1, i-1));
      tmp  := Trim (Copy (tmp, i, 999));
      end
    else begin
      exten:= Trim (tmp);
      tmp  := '';
    end;
    e[n]:= exten;
    n   := n+1;
  end;
  GetTempate := n;
end;

function  TAddTorrentForm.IsFileTemplate(filename:string; cntE : integer; e: array of string):boolean;
var
  tmp, tmpExt, tmp_Name, sstr: string;
  i,n,lstr,j,k, total_sstr, total_templ : integer;
  ok : boolean;
  re : boolean;
begin
  IsFileTemplate := false;

  tmp := filename;
  lstr:= Length(tmp);
  for i:=1 to lstr-1 do begin
    if (tmp[lstr-i]= '/') or (tmp[lstr-i]= '\') then begin
      tmp := Copy (tmp, lstr-i+1, 999);
      Break;
    end;
  end;

  for i:=0 to cntE-1 do begin
      tmpExt     := e[i];
      tmp_Name   := tmp;
      total_sstr := 0;
      total_templ:= 0;
      while tmpExt <> '' do begin
        j := Pos ('*', tmpExt);
        if j <> 0 then begin
          sstr  := Copy (tmpExt, 1, j-1);
          tmpExt:= Copy (tmpExt, j+1, 999);
          re    := false;
          end
        else begin
          sstr  := Trim (tmpExt);
          tmpExt:= '';
          re    := true;
        end;
        if sstr = '' then continue;

        total_templ := total_templ +1;
        n           := Length(sstr);
        ok          := false;
        while 1 = 1 do begin
          if tmp_Name = '' then break;
          k := Pos (sstr, tmp_Name);
          if k <> 0 then begin
            tmp_Name    := Copy (tmp_Name, k+n, 999);
            if ((tmpExt ='') and (re=true)) and (tmp_Name <> '') then begin
              continue;
            end else begin
              total_sstr := total_sstr +1;
              ok         := true;
              Break;
            end;
          end else begin
            Break;
          end;
        end;
        if ok = true then break;
      end;

      if total_sstr = total_templ then begin
        IsFileTemplate := true;
        Break;
      end;
  end;
end;


procedure TAddTorrentForm.SearchGoodExtension ();
var
  i,j, jMax, torrMax : integer;
  s, filename : string;
  filesize, dTotal,dTotalMax : double;
  pFD : FolderData;
  e : array [0..50] of string;
  n : integer;
begin
    dTotalMax := 0;
    jMax      :=-1;

    try
      for j:=0 to cbDestFolder.Items.Count-1 do begin
        pFD  := cbDestFolder.Items.Objects[j] as FolderData;
        s    := Trim(pFD.Ext);
        if s = '' then continue;

        n      := GetTempate (AnsiLowerCase(s), e);
        dTotal := 0;
        torrMax:= lvFiles.Items.Count;
        if torrMax > 100 then torrMax := 100;

        for i:=0 to torrMax - 1 do begin
            if not FTree.IsFolder(i) then begin
              filename := lvFiles.Items[idxFileName, i];
              filesize := double(lvFiles.Items[idxFileSize, i]);
              if IsFileTemplate(filename, n,e) = true then
                dTotal := dTotal + filesize;
            end;
        end;

        if (dTotal > 0) and (dTotal > dTotalMax) then begin
          dTotalMax := dTotal;
          jMax      := j;
        end;
      end;
    except
      MessageDlg('Error: LS-003. Please contact the developer', mtError, [mbOK], 0);
    end;

    try
      if jMax <> -1 then begin
        pFD  := cbDestFolder.Items.Objects[jMax] as FolderData;
        cbDestFolder.ItemIndex := jMax;
        cbDestFolder.Text := pFD.Txt;
        cbDestFolderChange(nil);
      end else begin
        cbDestFolderChange(nil);
      end;
    except
      MessageDlg('Error: LS-004. Please contact the developer', mtError, [mbOK], 0);
    end;
end;

procedure TAddTorrentForm.FormCreate(Sender: TObject);
begin
  FRequestLifetime:=TRpcRequestLifetime.Create;
  OrigCaption:=Caption;
  FDiskSpaceCaption:=txDiskSpace.Caption;
  lvFiles.Items.ExtraColumns:=FilesExtraColumns;
  FTree:=TFilesTree.Create(lvFiles);
  FTree.Checkboxes:=True;
  FTree.OnStateChange:=@TreeStateChanged;
  Buttons.OKButton.ModalResult:=mrNone;
  bidiMode := GetBiDi();
  cbStartTorrent.Checked := Ini.ReadBool('Interface', 'StartTorrentOnAdd', true);
  if (cbStartTorrent.Checked = false) then begin
    cbStartTorrent.Font.Style:= [fsbold];
    Buttons.OKButton.Font.Style:= [fsbold]
  end
  else begin
    cbStartTorrent.Font.Style:= [];
    Buttons.OKButton.Font.Style:= []
  end;

{$ifdef windows}
  gbSaveAs.Caption:='';
{$endif windows}
{$ifdef darwin}
  Buttons.BorderSpacing.Right:=Buttons.BorderSpacing.Right + ScaleInt(12);
{$endif darwin}
end;

procedure TAddTorrentForm.FormDestroy(Sender: TObject);
begin
  FRequestLifetime.Active:=False;
  FRequestLifetime.Release;
  if FAddTrackersList <> nil then
    FAddTrackersList.Free;
  if FWaitForm <> nil then
    FWaitForm.Free;
end;

procedure TAddTorrentForm.FreeSpaceCompleted(ARequest: TObject);
var
  f: double;
  res: TJSONObject;
begin
  if TRpcUserRequest(ARequest).Cancelled then
    exit;
  res:=TRpcUserRequest(ARequest).Result;
  if res <> nil then
    f:=res.Floats['size-bytes']
  else
    f:=-1;
  txDiskSpace.Caption:=FDiskSpaceCaption + ' ' + GetHumanSize(f);
end;

{ ============================================================================
  异步添加种子流程
  ============================================================================ }

procedure TAddTorrentForm.ShowWaitMsg(const AText: string);
begin
  if FWaitForm = nil then begin
    FWaitForm:=TBaseForm.CreateNew(Self);
    with FWaitForm do begin
{$ifndef windows}
      if FIsAppHidden then
        ShowInTaskBar:=stAlways;
{$endif windows}
      Caption:=AppName;
      BorderStyle:=bsToolWindow;
      BorderIcons:=[];
      Position:=poScreenCenter;
      Constraints.MinWidth:=400;
      AutoSize:=True;
      BorderWidth:=ScaleInt(16);
      with TLabel.Create(FWaitForm) do begin
        Alignment:=taCenter;
        Align:=alClient;
        Parent:=FWaitForm;
      end;
    end;
  end;
  with FWaitForm do begin
    TLabel(Controls[0]).Caption:=AText + '...';
    Show;
    BringToFront;
{$ifdef lclgtk2}
    Application.ProcessMessages;
{$endif lclgtk2}
    Update;
{$ifdef lclgtk2}
    sleep(100);
    Application.ProcessMessages;
{$endif lclgtk2}
  end;
end;

procedure TAddTorrentForm.HideWaitMsg;
begin
  if FWaitForm <> nil then
    FreeAndNil(FWaitForm);
end;

procedure TAddTorrentForm.AsyncFinish(ASuccess: boolean);
begin
  HideWaitMsg;
  AppNormal;
  FRequestLifetime.Active:=False;

  // 如果失败，把 FTorrentId 保留（MainForm 用来清理）
  // 如果成功，FTorrentId 也保留（MainForm 用来 post-add filter）
  // 都通过 public 属性 ResultTorrentId / ResultFilterKind 暴露

  // 关闭模态对话框
  if ASuccess then
    ModalResult:=mrOk
  else
    ModalResult:=mrCancel;
end;

procedure TAddTorrentForm.Execute(const AFileName: Utf8String);
var
  fs: TFileStreamUTF8;
  i: integer;
begin
  FFileName:=AFileName;
  FTorrentId:=0;
  FStep:=0;
  FPostAddFilterKind:=pafNone;
  FOKClicked:=False;
  FAddTrackersList:=nil;
  FIsAppHidden:=not MainForm.Visible or (MainForm.WindowState = wsMinimized);

  if FIsAppHidden then begin
    ShowWaitMsg(Caption);
{$ifndef windows}
    ShowInTaskBar:=stAlways;
{$endif windows}
  end;

  // 读取 torrent 文件或标记为 URL
  if IsProtocolSupported(FFileName) then
    FTorrentData:='-'
  else begin
    try
      fs:=TFileStreamUTF8.Create(FFileName, fmOpenRead or fmShareDenyNone);
    except
      on E: Exception do begin
        HideWaitMsg;
        FInitError:=E.Message;
        ModalResult:=mrCancel;
        exit;
      end;
    end;
    try
      SetLength(FTorrentData, fs.Size);
      fs.ReadBuffer(PChar(FTorrentData)^, Length(FTorrentData));
    finally
      fs.Free;
    end;
    FTorrentData:=EncodeBase64(FTorrentData);
  end;

  // 准备 Ini section 和目录列表
  FIniSec:='AddTorrent.' + MainForm.CurConn;
  MainForm.FillDownloadDirs(cbDestFolder, 'LastDownloadDir');
  if MainForm.WatchDownloading and (MainForm.WatchDestinationFolder <> '') then
    cbDestFolder.Text:=MainForm.WatchDestinationFolder;

  // 记录 post-add filter 信息
  if MainForm.lvFilter.Row >= StatusFiltersCount then begin
    i:=MainForm.lvFilter.Row;
    if VarIsNull(MainForm.lvFilter.Items[0, i]) then
      Dec(i);
    if i >= StatusFiltersCount then
      if not VarIsNull(MainForm.lvFilter.Items[-1, i]) then
        FPostAddFilterKind:=pafPath
      else
        FPostAddFilterKind:=pafTracker;
  end;
  MainForm.lvFilter.Row:=0;
  MainForm.edSearch.Text:='';

  // 显示模态对话框，FormShow 里启动异步流程
  ShowModal;
end;

procedure TAddTorrentForm.StepSessionGet;
var
  req, args: TJSONObject;
  request: TRpcUserRequest;
begin
  FStep:=1;
  req:=TJSONObject.Create;
  try
    req.Add('method', 'session-get');
    FRequestLifetime.AddRef;
    request:=TRpcUserRequest.Create(req, True, -1, @SessionGetCompleted, FRequestLifetime);
    if not RpcObj.QueueUserRequest(request) then begin
      FRequestLifetime.Release;
      MessageDlg('Unable to queue RPC request.', mtError, [mbOK], 0);
      AsyncFinish(False);
      exit;
    end;
    req:=nil;
  finally
    req.Free;
  end;
end;

procedure TAddTorrentForm.SessionGetCompleted(ARequest: TObject);
var
  res: TJSONObject;
  s: string;
  i: integer;
  pFD: FolderData;
begin
  FRequestLifetime.Release;
  if TRpcUserRequest(ARequest).Cancelled then begin
    AsyncFinish(False);
    exit;
  end;
  res:=TRpcUserRequest(ARequest).Result;
  if res = nil then begin
    MainForm.CheckStatus(False);
    AsyncFinish(False);
    exit;
  end;

  // 填默认目录到下拉框
  s:=CorrectPath(UTF8Encode(res.Strings['download-dir']));
  try
    if cbDestFolder.Items.IndexOf(s) < 0 then begin
      pFD:=FolderData.Create;
      pFD.Hit:=1;
      pFD.Ext:='';
      pFD.Txt:=s;
      pFD.Lst:=SysUtils.Date;
      cbDestFolder.Items.Add(s);
      i:=cbDestFolder.Items.IndexOf(s);
      cbDestFolder.Items.Objects[i]:=pFD;
    end;
  except
    MessageDlg('Error: LS-005. Please contact the developer', mtError, [mbOK], 0);
  end;

  // 旧版本显示磁盘空间
  if RpcObj.RPCVersion < 15 then
    if res.IndexOfName('download-dir-free-space') >= 0 then
      txDiskSpace.Caption:=txDiskSpace.Caption + ' ' + GetHumanSize(res.Floats['download-dir-free-space'])
    else begin
      txDiskSpace.Hide;
      txSize.Top:=(txSize.Top + txDiskSpace.Top) div 2;
    end;

  // 下一步：torrent-add
  StepTorrentAdd;
end;

procedure TAddTorrentForm.StepTorrentAdd;
var
  req, args: TJSONObject;
  request: TRpcUserRequest;
  i: integer;
  ss: string;
begin
  FStep:=2;
  req:=TJSONObject.Create;
  try
    req.Add('method', 'torrent-add');
    args:=TJSONObject.Create;
    args.Add('paused', TJSONIntegerNumber.Create(1));
    i:=Ini.ReadInteger(FIniSec, 'PeerLimit', 0);
    if i <> 0 then
      args.Add('peer-limit', TJSONIntegerNumber.Create(i));

    // 处理空目录
    try
      ss:=cbDestFolder.Text;
      if ss = '' then begin
        if cbDestFolder.Items.Count = 0 then
          ss:='' // 后面会有 session-get 给默认值，但这里先空着
        else begin
          cbDestFolder.ItemIndex:=0;
          ss:=cbDestFolder.Text;
        end;
      end;
    except
      MessageDlg('Error: LS-006. Please contact the developer', mtError, [mbOK], 0);
      ss:='';
    end;
    args.Add('download-dir', TJSONString.Create(UTF8Decode(ss)));

    if FTorrentData = '-' then
      args.Add('filename', TJSONString.Create(FFileName))
    else
      args.Add('metainfo', TJSONString.Create(FTorrentData));
    req.Add('arguments', args);

    FRequestLifetime.AddRef;
    request:=TRpcUserRequest.Create(req, True, -1, @TorrentAddCompleted, FRequestLifetime);
    if not RpcObj.QueueUserRequest(request) then begin
      FRequestLifetime.Release;
      MessageDlg('Unable to queue RPC request.', mtError, [mbOK], 0);
      AsyncFinish(False);
      exit;
    end;
    req:=nil;
  finally
    req.Free;
  end;
end;

procedure TAddTorrentForm.TorrentAddCompleted(ARequest: TObject);
var
  res: TJSONObject;
begin
  FRequestLifetime.Release;
  if TRpcUserRequest(ARequest).Cancelled then begin
    AsyncFinish(False);
    exit;
  end;
  res:=TRpcUserRequest(ARequest).Result;

  // 处理重复种子
  if res <> nil then begin
    if res.IndexOfName('torrent-duplicate') >= 0 then begin
      BeginAddTrackers(res.Objects['torrent-duplicate'].Integers['id']);
      exit;
    end;
    FTorrentId:=res.Objects['torrent-added'].Integers['id'];
  end
  else begin
    if RpcObj.Status = 'duplicate torrent' then begin
      BeginAddTrackers(0);
      exit;
    end;
    MainForm.CheckStatus(False);
    AsyncFinish(False);
    exit;
  end;

  if FTorrentId = 0 then begin
    MainForm.CheckStatus(False);
    AsyncFinish(False);
    exit;
  end;

  // 如果是"目录变更后重新添加"的分支（FOldDownloadDir 有值且已经过一轮 ShowModal），
  // 直接跳转到 StepTorrentSet
  if FOKClicked then begin
    MainForm.DoRefresh(True);
    StepTorrentSet;
    exit;
  end;

  // 正常流程：刷新 + 获取文件信息
  MainForm.DoRefresh(True);
  StepTorrentGetInfo;
end;

procedure TAddTorrentForm.StepTorrentGetInfo;
var
  req, args: TJSONObject;
  _fields: TJSONArray;
  request: TRpcUserRequest;
begin
  FStep:=3;
  req:=TJSONObject.Create;
  try
    req.Add('method', 'torrent-get');
    args:=TJSONObject.Create;
    args.Add('ids', TJSONArray.Create([FTorrentId]));
    _fields:=TJSONArray.Create(['files','maxConnectedPeers','name','metadataPercentComplete']);
    args.Add('fields', _fields);
    req.Add('arguments', args);

    FRequestLifetime.AddRef;
    request:=TRpcUserRequest.Create(req, True, -1, @TorrentGetInfoCompleted, FRequestLifetime);
    if not RpcObj.QueueUserRequest(request) then begin
      FRequestLifetime.Release;
      MessageDlg('Unable to queue RPC request.', mtError, [mbOK], 0);
      AsyncFinish(False);
      exit;
    end;
    req:=nil;
  finally
    req.Free;
  end;
end;

procedure TAddTorrentForm.TorrentGetInfoCompleted(ARequest: TObject);
var
  res: TJSONObject;
  t: TJSONArray;
  ShowWindow: boolean;
begin
  FRequestLifetime.Release;
  if TRpcUserRequest(ARequest).Cancelled then begin
    AsyncFinish(False);
    exit;
  end;
  res:=TRpcUserRequest(ARequest).Result;
  if res = nil then begin
    MainForm.CheckStatus(False);
    AsyncFinish(False);
    exit;
  end;

  t:=res.Arrays['torrents'];
  if t.Count = 0 then begin
    MessageDlg(sUnableGetFilesList, mtError, [mbOK], 0);
    AsyncFinish(False);
    exit;
  end;

  // 填充 UI
  FOldName:=UTF8Encode(t.Objects[0].Strings['name']);
  edSaveAs.Text:=FOldName;
  edSaveAs.Text:=ExcludeInvalidChar(edSaveAs.Text);

  if RpcObj.RPCVersion < 15 then begin
    edSaveAs.Enabled:=False;
    edSaveAs.ParentColor:=True;
  end;
  edPeerLimit.Value:=t.Objects[0].Integers['maxConnectedPeers'];
  FilesTree.FillTree(FTorrentId, t.Objects[0].Arrays['files'], nil, nil);

  Width:=Ini.ReadInteger('AddTorrent', 'Width', Width);
  if (RpcObj.RPCVersion >= 7) and (lvFiles.Items.Count = 0) and (t.Objects[0].Floats['metadataPercentComplete'] <> 1.0) then begin
    // Magnet link
    gbContents.Hide;
    gbSaveAs.BorderSpacing.Bottom:=gbSaveAs.BorderSpacing.Top;
    BorderStyle:=bsDialog;
    AutoSizeForm(TCustomForm(gbContents.Parent));
    edSaveAs.Enabled:=False;
    edSaveAs.ParentColor:=True;
  end
  else
    // Torrent file
    Height:=Ini.ReadInteger('AddTorrent', 'Height', Height);

  FOldDownloadDir:=cbDestFolder.Text;

  // 全选文件 + 搜索扩展名 + 启动磁盘空间查询
  btSelectAllClick(nil);
  SearchGoodExtension;
  DiskSpaceTimerTimer(nil);

  EnableControls(True);
  HideWaitMsg;

  // 判断是否自动跳过对话框直接添加
  ShowWindow:=Ini.ReadBool('Interface', 'ShowAddTorrentWindow', True);
  if MainForm.WatchDownloading then
    ShowWindow:=False;
  if not ShowWindow then begin
    // 不显示对话框，直接走 OK 流程
    FOKClicked:=True;
    StepOKAfterModal;
  end;
end;

{ ---- OK 后的后半段流程 ---- }

procedure TAddTorrentForm.StepOKAfterModal;
begin
  FStep:=4;
  FOKClicked:=True;

  if FIsAppHidden then
    ShowWaitMsg(Caption);
  EnableControls(False);

  // 如果目录变了：先删旧的，再重新添加
  // 两个请求在 RPC 队列中按顺序执行，不需要等 remove 回调
  if FOldDownloadDir <> cbDestFolder.Text then begin
    MainForm.QueueTorrentAction(FTorrentId, 'torrent-remove', nil, False);
    FTorrentId:=0;
    StepTorrentAdd; // 重新添加，新目录
    exit;
  end;

  StepTorrentSet;
end;

procedure TAddTorrentForm.StepTorrentSet;
var
  req, args: TJSONObject;
  files: TJSONArray;
  request: TRpcUserRequest;
  i: integer;
begin
  FStep:=5;
  req:=TJSONObject.Create;
  try
    req.Add('method', 'torrent-set');
    args:=TJSONObject.Create;
    args.Add('ids', TJSONArray.Create([FTorrentId]));
    args.Add('peer-limit', TJSONIntegerNumber.Create(edPeerLimit.Value));

    files:=TJSONArray.Create;
    for i:=0 to lvFiles.Items.Count - 1 do
      if not FilesTree.IsFolder(i) and (FilesTree.Checked[i] = cbChecked) then
        files.Add(integer(lvFiles.Items[idxFileId, i]));
    if files.Count > 0 then
      args.Add('files-wanted', files)
    else
      files.Free;

    files:=TJSONArray.Create;
    for i:=0 to lvFiles.Items.Count - 1 do
      if not FilesTree.IsFolder(i) and (FilesTree.Checked[i] <> cbChecked) then
        files.Add(integer(lvFiles.Items[idxFileId, i]));
    if files.Count > 0 then
      args.Add('files-unwanted', files)
    else
      files.Free;

    req.Add('arguments', args);

    FRequestLifetime.AddRef;
    request:=TRpcUserRequest.Create(req, False, -1, @TorrentSetCompleted, FRequestLifetime);
    if not RpcObj.QueueUserRequest(request) then begin
      FRequestLifetime.Release;
      MessageDlg('Unable to queue RPC request.', mtError, [mbOK], 0);
      AsyncFinish(False);
      exit;
    end;
    req:=nil;
  finally
    req.Free;
  end;
end;

procedure TAddTorrentForm.TorrentSetCompleted(ARequest: TObject);
begin
  FRequestLifetime.Release;
  if TRpcUserRequest(ARequest).Cancelled then begin
    AsyncFinish(False);
    exit;
  end;
  if TRpcUserRequest(ARequest).Result = nil then begin
    MainForm.CheckStatus(False);
    AsyncFinish(False);
    exit;
  end;

  // 检查是否需要重命名
  edSaveAs.Text:=ExcludeInvalidChar(edSaveAs.Text);
  if FOldName <> edSaveAs.Text then begin
    StepTorrentRename;
    exit;
  end;

  StepTorrentStart;
end;

procedure TAddTorrentForm.StepTorrentRename;
var
  req, args: TJSONObject;
  request: TRpcUserRequest;
begin
  FStep:=6;
  req:=TJSONObject.Create;
  try
    req.Add('method', 'torrent-rename-path');
    args:=TJSONObject.Create;
    args.Add('ids', TJSONArray.Create([FTorrentId]));
    args.Add('path', UTF8Decode(FOldName));
    args.Add('name', UTF8Decode(edSaveAs.Text));
    req.Add('arguments', args);

    FRequestLifetime.AddRef;
    request:=TRpcUserRequest.Create(req, False, -1, @TorrentRenameCompleted, FRequestLifetime);
    if not RpcObj.QueueUserRequest(request) then begin
      FRequestLifetime.Release;
      // 重命名失败不终止，继续
      StepTorrentStart;
      exit;
    end;
    req:=nil;
  finally
    req.Free;
  end;
end;

procedure TAddTorrentForm.TorrentRenameCompleted(ARequest: TObject);
begin
  FRequestLifetime.Release;
  if TRpcUserRequest(ARequest).Cancelled then begin
    AsyncFinish(False);
    exit;
  end;
  // 重命名失败不终止，继续
  StepTorrentStart;
end;

procedure TAddTorrentForm.StepTorrentStart;
begin
  FStep:=7;
  if cbStartTorrent.Checked then
    MainForm.QueueTorrentAction(FTorrentId, 'torrent-start', nil, True);

  // post-add filter + 选中 torrent（用 PostAddTorrentId 机制异步选中）
  if FPostAddFilterKind <> pafNone then begin
    MainForm.PostAddTorrentId:=FTorrentId;
    MainForm.PostAddFilterKind:=FPostAddFilterKind;
  end
  else begin
    MainForm.PostAddTorrentId:=FTorrentId;
    MainForm.PostAddFilterKind:=pafNone;
  end;
  MainForm.DoRefresh(True);

  // 清理文件 + 保存配置
  if (Ini.ReadBool('Interface', 'DeleteTorrentFile', False) and not IsProtocolSupported(FFileName)) or MainForm.WatchDownloading then
    DeleteFileUTF8(FFileName);

  Ini.WriteInteger(FIniSec, 'PeerLimit', edPeerLimit.Value);
  MainForm.SaveDownloadDirs(cbDestFolder, 'LastDownloadDir');

  // 完成
  AsyncFinish(True);
end;

procedure TAddTorrentForm.TorrentStartCompleted(ARequest: TObject);
begin
  // 预留：如果以后需要等启动完成再结束，可以在这里调用 AsyncFinish
  // 目前不等启动完成，发完请求就结束
end;

{ ============================================================================
  _AddTrackers 子流程（重复种子时合并 tracker）
  ============================================================================ }

procedure TAddTorrentForm.BeginAddTrackers(TorrentId: integer);
var
  s: string;
  i: integer;
begin
  FStep:=10;
  FAddTrackersTorrentId:=TorrentId;
  FAddTrackersHash:='';

  RpcObj.Status:='';
  s:='';
  if TorrentId <> 0 then begin
    i:=MainForm.gTorrents.Items.IndexOf(idxTorrentId, TorrentId);
    if i >= 0 then
      s:=Format(': %s', [UTF8Encode(widestring(MainForm.gTorrents.Items[idxName, i]))]);
  end;
  ForceAppNormal;
  s:=TranslateString(SDuplicateTorrent + s + '.', True);
  if RpcObj.RPCVersion < 10 then begin
    MessageDlg(s, mtError, [mbOK], 0);
    AsyncFinish(False);
    exit;
  end;
  if MessageDlg(s + LineEnding + LineEnding + SUpdateTrackers, mtConfirmation, [mbYes, mbNo], 0) <> mrYes then begin
    AsyncFinish(False);
    exit;
  end;

  AddTrackersConfirmYes;
end;

procedure TAddTorrentForm.AddTrackersConfirmYes;
var
  TrackersList: TStringList;
  fs: TFileStreamUTF8;
  TorData, AnnData, LData, LLData: TBEncoded;
  i, j: Integer;
  s, tfn, TorrentHash: string;
  req, args: TJSONObject;
  _fields: TJSONArray;
  request: TRpcUserRequest;
begin
  TrackersList:=TStringList.Create;
  AppBusy;
  try
    TorrentHash:='';
    if AnsiCompareText('magnet:?', Copy(FFileName, 1, 8)) = 0 then begin
      // 从 magnet 链接解析 trackers
      TrackersList.Delimiter:='&';
      TrackersList.DelimitedText:=Copy(FFileName, 9, MaxInt);
      i:=0;
      while i < TrackersList.Count do begin
        s:=TrackersList.Names[i];
        if (FAddTrackersTorrentId = 0) and (CompareText(s, 'xt') = 0) then begin
          s:=LowerCase(TrackersList.ValueFromIndex[i]);
          if (TorrentHash = '') and (Pos('urn:btih:', s) = 1) then begin
            s:=Copy(s, 10, MaxInt);
            if Length(s) = 32 then
              TorrentHash:=StrToHex(Base32Decode(UpperCase(s)))
            else
              TorrentHash:=s;
          end;
        end
        else
          if CompareText(s, 'tr') = 0 then begin
            TrackersList[i]:=DecodeURL(TrackersList.ValueFromIndex[i]);
            Inc(i);
            continue;
          end;
        TrackersList.Delete(i);
      end;
    end
    else
      try
        if IsProtocolSupported(FFileName) then begin
          tfn:=SysToUTF8(GetTempDir(True)) + 'remote-torrent.torrent';
          if not DownloadFile(FFileName, ExtractFilePath(tfn), ExtractFileName(tfn), SDownloadingTorrent) then begin
            AppNormal;
            AsyncFinish(False);
            exit;
          end;
        end
        else
          tfn:=FFileName;

        TorData:=nil;
        fs:=TFileStreamUTF8.Create(tfn, fmOpenRead or fmShareDenyNone);
        try
          TorData:=TBEncoded.Create(fs);
          if FAddTrackersTorrentId = 0 then begin
            LData:=(TorData.ListData.FindElement('info') as TBEncoded);
            s:='';
            LData.Encode(LData, s);
            TorrentHash:=StrToHex(SHA1(s));
          end;
          AnnData:=(TorData.ListData.FindElement('announce-list', False) as TBEncoded);
          if AnnData <> nil then
            for i:=0 to AnnData.ListData.Count - 1 do begin
              LData:=AnnData.ListData.Items[i].Data as TBEncoded;
              for j:=0 to LData.ListData.Count - 1 do begin
                LLData:=LData.ListData.Items[j].Data as TBEncoded;
                TrackersList.Add(LLData.StringData);
              end;
            end
          else begin
            AnnData:=(TorData.ListData.FindElement('announce', False) as TBEncoded);
            if AnnData <> nil then
              TrackersList.Add(AnnData.StringData);
          end;
        finally
          TorData.Free;
          fs.Free;
        end;
      finally
        if (tfn <> '') and (tfn <> FFileName) then
          DeleteFileUTF8(tfn);
      end;

    FAddTrackersHash:=TorrentHash;
    FAddTrackersList:=TrackersList; // 移交所有权
    TrackersList:=nil;

    // 发 torrent-get 获取已有 trackers
    req:=TJSONObject.Create;
    try
      req.Add('method', 'torrent-get');
      args:=TJSONObject.Create;
      if FAddTrackersTorrentId = 0 then
        args.Add('ids', TJSONArray.Create([FAddTrackersHash]))
      else
        args.Add('ids', TJSONArray.Create([FAddTrackersTorrentId]));
      _fields:=TJSONArray.Create(['id', 'trackers']);
      args.Add('fields', _fields);
      req.Add('arguments', args);

      FRequestLifetime.AddRef;
      request:=TRpcUserRequest.Create(req, True, -1, @AddTrackersGetCompleted, FRequestLifetime);
      if not RpcObj.QueueUserRequest(request) then begin
        FRequestLifetime.Release;
        MessageDlg('Unable to queue RPC request.', mtError, [mbOK], 0);
        AddTrackersFinish;
        exit;
      end;
      req:=nil;
    finally
      req.Free;
    end;
  finally
    TrackersList.Free;
  end;
end;

procedure TAddTorrentForm.AddTrackersGetCompleted(ARequest: TObject);
var
  res: TJSONObject;
  t: TJSONArray;
  tt: TJSONObject;
  trackers: TJSONArray;
  i, j: integer;
  s: string;
  addTrackers: TJSONArray;
  req, args: TJSONObject;
  request: TRpcUserRequest;
begin
  FRequestLifetime.Release;
  if TRpcUserRequest(ARequest).Cancelled then begin
    AddTrackersFinish;
    exit;
  end;
  res:=TRpcUserRequest(ARequest).Result;
  if res = nil then begin
    MainForm.CheckStatus(False);
    AddTrackersFinish;
    exit;
  end;

  try
    t:=res.Arrays['torrents'];
    if t.Count = 0 then
      raise Exception.Create('Torrent not found.');
    tt:=t.Objects[0] as TJSONObject;
    i:=tt.Integers['id'];
    if FAddTrackersTorrentId = 0 then begin
      FAddTrackersTorrentId:=i;
      // 异步选中：设到 PostAddTorrentId，下次刷新时自动选中
      MainForm.PostAddTorrentId:=i;
      MainForm.PostAddFilterKind:=pafNone;
    end;
    FTorrentId:=i;

    trackers:=tt.Arrays['trackers'];
    // 删除已存在的 trackers
    for i:=0 to trackers.Count - 1 do begin
      s:=UTF8Encode(trackers.Objects[i].Strings['announce']);
      j:=FAddTrackersList.IndexOf(s);
      if j >= 0 then
        FAddTrackersList.Delete(j);
    end;

    if FAddTrackersList.Count = 0 then begin
      // 没有新 tracker 需要添加
      MainForm.DoRefresh;
      AddTrackersFinish;
      exit;
    end;

    // 发 torrent-set(trackerAdd)
    addTrackers:=TJSONArray.Create;
    for i:=0 to FAddTrackersList.Count - 1 do
      addTrackers.Add(FAddTrackersList[i]);
    req:=TJSONObject.Create;
    try
      req.Add('method', 'torrent-set');
      args:=TJSONObject.Create;
      args.Add('ids', TJSONArray.Create([FAddTrackersTorrentId]));
      args.Add('trackerAdd', addTrackers);
      addTrackers:=nil;
      req.Add('arguments', args);

      FRequestLifetime.AddRef;
      request:=TRpcUserRequest.Create(req, False, -1, @AddTrackersSetCompleted, FRequestLifetime);
      if not RpcObj.QueueUserRequest(request) then begin
        FRequestLifetime.Release;
        MessageDlg('Unable to queue RPC request.', mtError, [mbOK], 0);
        AddTrackersFinish;
        exit;
      end;
      req:=nil;
    finally
      req.Free;
      addTrackers.Free;
    end;
  except
    on E: Exception do begin
      MessageDlg(E.Message, mtError, [mbOK], 0);
      AddTrackersFinish;
    end;
  end;
end;

procedure TAddTorrentForm.AddTrackersSetCompleted(ARequest: TObject);
begin
  FRequestLifetime.Release;
  if TRpcUserRequest(ARequest).Cancelled then begin
    AddTrackersFinish;
    exit;
  end;
  if TRpcUserRequest(ARequest).Result = nil then begin
    MainForm.CheckStatus(False);
  end
  else begin
    MainForm.DoRefresh;
  end;
  AddTrackersFinish;
end;

procedure TAddTorrentForm.AddTrackersFinish;
begin
  if FAddTrackersList <> nil then
    FreeAndNil(FAddTrackersList);
  AppNormal;
  FTorrentId:=0; // 重复种子，id 是已有的，不应该由 MainForm 清理
  AsyncFinish(False); // 重复种子不算"成功添加"
end;

initialization
  {$I addtorrent.lrs}

end.

