unit MapperUnit;

interface

uses
  Winapi.Windows, Winapi.Messages, System.SysUtils, System.Variants, System.Classes, Vcl.Graphics,
  Vcl.Controls, Vcl.Forms, Vcl.Dialogs, Vcl.ComCtrls, Vcl.Clipbrd, Vcl.Menus, Winapi.ShellAPI,
  Winapi.ShlObj, Winapi.ActiveX;

type
  TMapperForm = class(TForm)
    ListView1: TListView;
    PopupMenu1: TPopupMenu;
    Copy1: TMenuItem;
    CopyAddress1: TMenuItem;
    CopySize1: TMenuItem;
    CopyProtect1: TMenuItem;
    CopyFileName1: TMenuItem;
    RemapMemoryRegion1: TMenuItem;
    N1: TMenuItem;
    Openfilelocation1: TMenuItem;
    procedure Copy1Click(Sender: TObject);
    procedure CopyAddress1Click(Sender: TObject);
    procedure CopySize1Click(Sender: TObject);
    procedure CopyProtect1Click(Sender: TObject);
    procedure CopyFileName1Click(Sender: TObject);
    procedure ListView1ContextPopup(Sender: TObject; MousePos: TPoint;
      var Handled: Boolean);
    procedure RemapMemoryRegion1Click(Sender: TObject);
    procedure Openfilelocation1Click(Sender: TObject);
    procedure ListView1KeyDown(Sender: TObject; var Key: Word;
      Shift: TShiftState);
  private
    { Private declarations }
  public
    procedure Refresh;
  end;

var
  MapperForm: TMapperForm;

implementation

uses
  cepluginsdk;

{$R *.dfm}

{$MINENUMSIZE 4}

type
  MEMORY_INFORMATION_CLASS = (
    MemoryBasicInformation, // q: MEMORY_BASIC_INFORMATION
    MemoryWorkingSetInformation, // q: MEMORY_WORKING_SET_INFORMATION
    MemoryMappedFilenameInformation, // q: UNICODE_STRING
    MemoryRegionInformation, // q: MEMORY_REGION_INFORMATION
    MemoryWorkingSetExInformation, // q: MEMORY_WORKING_SET_EX_INFORMATION // since VISTA
    MemorySharedCommitInformation, // q: MEMORY_SHARED_COMMIT_INFORMATION // since WIN8
    MemoryImageInformation, // q: MEMORY_IMAGE_INFORMATION
    MemoryRegionInformationEx, // MEMORY_REGION_INFORMATION
    MemoryPrivilegedBasicInformation, // MEMORY_BASIC_INFORMATION
    MemoryEnclaveImageInformation, // MEMORY_ENCLAVE_IMAGE_INFORMATION // since REDSTONE3
    MemoryBasicInformationCapped, // 10
    MemoryPhysicalContiguityInformation, // MEMORY_PHYSICAL_CONTIGUITY_INFORMATION // since 20H1
    MemoryBadInformation, // since WIN11
    MemoryBadInformationAllProcesses, // since 22H1
    MemoryImageExtensionInformation, // MEMORY_IMAGE_EXTENSION_INFORMATION // since 24H2
    MaxMemoryInfoClass
  );

  PUNICODE_STRING = ^UNICODE_STRING;
  UNICODE_STRING = record
    Length: USHORT;
    MaximumLength: USHORT;
    Buffer: PChar;
  end;

function NtClose(Handle: THandle): ULONG; stdcall; external 'ntdll.dll';
function NtCreateSection(
    var SectionHandle: THandle;
    DesiredAccess: ACCESS_MASK;
    ObjectAttributes: Pointer;
    SectionSize: PLargeInteger;
    Protect: ULONG;
    Attributes: ULONG;
    FileHandle: THandle
  ): ULONG; stdcall; external 'ntdll.dll';

function NtMapViewOfSection(
    SectionHandle: THandle;
    ProcessHandle: THandle;
    var BaseAddress: PVOID;
    ZeroBits: ULONG;
    CommitSize: SIZE_T;
    var SectionOffset: LARGE_INTEGER;
    var ViewSize: SIZE_T;
    InheritDisposition: ULONG;
    AllocationType: ULONG;
    Protect: ULONG
  ): ULONG; stdcall; external 'ntdll.dll';

function NtUnmapViewOfSection(ProcessHandle: THandle; BaseAddress: Pointer): ULONG; stdcall; external 'ntdll.dll';
function NtQueryVirtualMemory(ProcessHandle: THandle; BaseAddress: Pointer; MemoryInformationClass: MEMORY_INFORMATION_CLASS;
  MemoryInformation: Pointer; MemoryInformationLength: SIZE_T; var ReturnLength: SIZE_T): NTSTATUS; stdcall; external 'ntdll.dll';

type
  TVirtualQueryEx = function(hProcess: THandle; lpAddress: Pointer;
    var lpBuffer: TMemoryBasicInformation; dwLength: SIZE_T): SIZE_T; stdcall;
  TReadProcessMemory = function(hProcess: THandle; const lpBaseAddress: Pointer; lpBuffer: Pointer;
    nSize: SIZE_T; var lpNumberOfBytesRead: SIZE_T): BOOL; stdcall;
  TWriteProcessMemory = function (hProcess: THandle; const lpBaseAddress: Pointer; lpBuffer: Pointer;
    nSize: SIZE_T; var lpNumberOfBytesWritten: SIZE_T): BOOL; stdcall;

const
  STATUS_BUFFER_OVERFLOW: NTSTATUS = NTSTATUS($80000005);

var
  VirtualQueryEx: TVirtualQueryEx;
  ReadProcessMemory: TReadProcessMemory;
  WriteProcessMemory: TWriteProcessMemory;

procedure OpenExplorerAndSelectFile(const FilePath: string);
var
  pidl: PItemIDList;
  parentPidl: PItemIDList;
  item: PItemIDList;
  hr: HRESULT;
  WideFilePath: array[0..MAX_PATH] of WideChar;
begin
  CoInitialize(nil);
  try
    StringToWideChar(FilePath, WideFilePath, MAX_PATH);
    pidl := nil;

    hr := SHParseDisplayName(WideFilePath, nil, pidl, 0, PDWORD(nil)^);
    if Succeeded(hr) and Assigned(pidl) then
    begin
      parentPidl := ILClone(pidl);
      ILRemoveLastID(parentPidl);
      item := ILFindLastID(pidl);

      hr := SHOpenFolderAndSelectItems(parentPidl, 1, @item, 0);
      if not Succeeded(hr) then
        raise Exception.CreateFmt('SHOpenFolderAndSelectItems failed: 0x%x', [hr]);

      CoTaskMemFree(pidl);
      CoTaskMemFree(parentPidl);
    end
    else
      raise Exception.CreateFmt('SHParseDisplayName failed: 0x%x', [hr]);
  finally
    CoUninitialize;
  end;
end;

procedure SetClipboard(S: string);
var
  Clipboard: TClipboard;
begin
  Clipboard := TClipboard.Create;
  try
    Clipboard.SetTextBuf(PChar(S));
  finally
    Clipboard.Free;
  end;
end;

function NT_SUCCESS(Status: NTSTATUS): Boolean;
begin
  Result := Status >= 0;
end;

function ConvertDevicePathToDrivePath(const DevicePath: string): string;
var
  Drives: string;
  Drive: string;
  DeviceName: array[0..1023] of Char;
  I: Integer;
  DevicePrefix: string;
begin
  Result := '';
  SetLength(Drives, GetLogicalDriveStrings(0, nil));
  SetLength(Drives, GetLogicalDriveStrings(Length(Drives), PChar(Drives)));

  I := 1;
  while I <= Length(Drives) do
  begin
    Drive := PChar(@Drives[I]);

    FillChar(DeviceName, SizeOf(DeviceName), 0);
    if QueryDosDevice(PChar(Copy(Drive, 1, 2)), DeviceName, 1024) <> 0 then
    begin
      DevicePrefix := StrPas(DeviceName) + '\';
      if Pos(DevicePrefix, DevicePath) = 1 then
      begin
        Result := Drive + Copy(DevicePath, Length(DevicePrefix) + 1, MaxInt);
        Exit;
      end;
    end;

    Inc(I, Length(Drive) + 1);
  end;
end;

function GetProcessMappedFileName(ProcessHandle: THandle; BaseAddress: PVOID): string;
var
  Status: NTSTATUS;
  BufferSize: SIZE_T;
  ReturnLength: SIZE_T;
  Buffer: PUNICODE_STRING;
begin
  Result := '';
  ReturnLength := 0;
  BufferSize := $200;
  GetMem(Buffer, BufferSize);
  Status := NtQueryVirtualMemory(ProcessHandle, BaseAddress, MemoryMappedFilenameInformation, Buffer, BufferSize, ReturnLength);
  if (Status = STATUS_BUFFER_OVERFLOW) and (ReturnLength > 0) then
  begin
    FreeMem(Buffer);
    BufferSize := ReturnLength;
    GetMem(Buffer, BufferSize);
    Status := NtQueryVirtualMemory(ProcessHandle, BaseAddress, MemoryMappedFilenameInformation, Buffer, BufferSize, ReturnLength);
  end;
  if NT_SUCCESS(Status) then
    Result := string(Buffer.Buffer);
  FreeMem(Buffer);
end;

procedure Remap(Address: Pointer; Size: SIZE_T);
var
  Buffer: Pointer;
  hSection: THandle;
  SectionSize: LARGE_INTEGER;
  ViewSize: SIZE_T;
  BaseAddress: Pointer;
begin
  ReadProcessMemory := Exported.ReadProcessMemory^;
  WriteProcessMemory := Exported.WriteProcessMemory^;

  Buffer := VirtualAlloc(nil, Size, MEM_COMMIT or MEM_RESERVE, PAGE_READWRITE);
  ReadProcessMemory(Exported.OpenedProcessHandle^, Address, Buffer, Size, PSIZE_T(nil)^);

  SectionSize.QuadPart := Size;
  NtCreateSection(hSection, SECTION_ALL_ACCESS, nil, @SectionSize, PAGE_EXECUTE_READWRITE, SEC_COMMIT, 0);
  NtUnmapViewOfSection(Exported.OpenedProcessHandle^, Address);
  SectionSize.QuadPart := 0;
  ViewSize := 0;
  BaseAddress := Address;
  NtMapViewOfSection(hSection, Exported.OpenedProcessHandle^, BaseAddress, 0, Size, SectionSize, ViewSize, 2, 0, PAGE_EXECUTE_READWRITE);
  WriteProcessMemory(Exported.OpenedProcessHandle^, Address, Buffer, Size, PSIZE_T(nil)^);
  VirtualFree(Buffer, 0, MEM_RELEASE);
  NtClose(hSection);
end;

procedure TMapperForm.Copy1Click(Sender: TObject);
var
  Item: TListItem;
begin
  Item := ListView1.Selected;
  if not Assigned(Item) then
    Exit;

  SetClipboard(Format('%s, %s, %s, %s', [Item.Caption, Item.SubItems[0], Item.SubItems[1], Item.SubItems[2]]));
end;

procedure TMapperForm.CopyAddress1Click(Sender: TObject);
var
  Item: TListItem;
begin
  Item := ListView1.Selected;
  if not Assigned(Item) then
    Exit;

  SetClipboard(Item.Caption);
end;

procedure TMapperForm.CopyFileName1Click(Sender: TObject);
var
  Item: TListItem;
begin
  Item := ListView1.Selected;
  if not Assigned(Item) then
    Exit;

  SetClipboard(Item.SubItems[2]);
end;

procedure TMapperForm.CopyProtect1Click(Sender: TObject);
var
  Item: TListItem;
begin
  Item := ListView1.Selected;
  if not Assigned(Item) then
    Exit;

  SetClipboard(Item.SubItems[1]);
end;

procedure TMapperForm.CopySize1Click(Sender: TObject);
var
  Item: TListItem;
begin
  Item := ListView1.Selected;
  if not Assigned(Item) then
    Exit;

  SetClipboard(Item.SubItems[0]);
end;

procedure TMapperForm.ListView1ContextPopup(Sender: TObject; MousePos: TPoint;
  var Handled: Boolean);
var
  Left: Integer;
  i: Integer;
  CopyMenu: array[0..3]of TMenuItem;
begin
  if not Assigned(ListView1.Selected) then
  begin
    Handled := True;
    Exit;
  end;

  CopyMenu[0] := CopyAddress1;
  CopyMenu[1] := CopySize1;
  CopyMenu[2] := CopyProtect1;
  CopyMenu[3] := CopyFileName1;

  Left := 0;
  for i := 0 to 3 do
  begin
    CopyMenu[i].Visible := (Left <= MousePos.X) and (Left + ListView1.Columns[i].Width > MousePos.X);
    Left := Left + ListView1.Columns[i].Width;
  end;
end;

procedure TMapperForm.ListView1KeyDown(Sender: TObject; var Key: Word;
  Shift: TShiftState);
var
  i: Integer;
begin
  for i := 0 to PopupMenu1.Items.Count - 1 do
  begin
    if ShortCut(Key, Shift) = PopupMenu1.Items[i].Shortcut then
    begin
      PopupMenu1.Items[i].Click;
      Break;
    end;
  end;
end;

procedure TMapperForm.Openfilelocation1Click(Sender: TObject);
var
  Item: TListItem;
  FileName: string;
begin
  Item := ListView1.Selected;
  if not Assigned(Item) then
    Exit;

  FileName := Item.SubItems[2];
  if FileName = '' then
    Exit;

  OpenExplorerAndSelectFile(FileName);
end;

procedure TMapperForm.Refresh;
var
  mbi: TMemoryBasicInformation;
  Protect: string;
  Name: array[0..255]of AnsiChar;
begin
  VirtualQueryEx := Exported.VirtualQueryEx^;

  ListView1.Clear;
  mbi.BaseAddress := nil;
  while VirtualQueryEx(Exported.OpenedProcessHandle^, mbi.BaseAddress, mbi, SizeOf(mbi)) <> 0 do
  begin
    if (mbi.Type_9 = MEM_MAPPED) and (mbi.State and MEM_COMMIT <> 0) then
    begin
      case mbi.Protect of
        PAGE_NOACCESS:
          Protect := 'PAGE_NOACCESS';
        PAGE_READONLY:
          Protect := 'PAGE_READONLY';
        PAGE_READWRITE:
          Protect := 'PAGE_READWRITE';
        PAGE_WRITECOPY:
          Protect := 'PAGE_WRITECOPY';
        PAGE_EXECUTE:
          Protect := 'PAGE_EXECUTE';
        PAGE_EXECUTE_READ:
          Protect := 'PAGE_EXECUTE_READ';
        PAGE_EXECUTE_READWRITE:
          Protect := 'PAGE_EXECUTE_READWRITE';
        PAGE_EXECUTE_WRITECOPY:
          Protect := 'PAGE_EXECUTE_WRITECOPY';
        PAGE_GUARD:
          Protect := 'PAGE_GUARD';
        PAGE_NOCACHE:
          Protect := 'PAGE_NOCACHE'
        else
          Protect := IntToHex(mbi.Protect, 0);
      end;

      Exported.sym_addressToName(SIZE_T(mbi.BaseAddress), @Name, SizeOf(Name));

      var Item := ListView1.Items.Add;
      Item.Caption := string(Name);
      Item.SubItems.Add(IntToHex(mbi.RegionSize, 0));
      Item.SubItems.Add(Protect);
      Item.SubItems.Add(ConvertDevicePathToDrivePath(GetProcessMappedFileName(Exported.OpenedProcessHandle^, mbi.BaseAddress)));
    end;
    mbi.BaseAddress := PByte(mbi.BaseAddress) + mbi.RegionSize;
  end;
end;

procedure TMapperForm.RemapMemoryRegion1Click(Sender: TObject);
var
  Address: SIZE_T;
begin
  if not Assigned(ListView1.Selected) then
    Exit;

  if Exported.sym_nameToAddress(PAnsiChar(AnsiString(ListView1.Selected.Caption)), @Address) then
  begin
    Exported.pause();
    Remap(Pointer(Address), StrToInt('$' + ListView1.Selected.SubItems[0]));
    Exported.unpause();
    Refresh;
  end;
end;

end.
