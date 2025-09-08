unit MainUnit;

interface

uses
  Winapi.Windows, System.SysUtils, cepluginsdk;

function GetVersion(var PluginVersion: TpluginVersion; sizeofpluginversion: Integer): BOOL; stdcall;
function InitializePlugin(ExportedFunctions: PExportedFunctions; pluginid: DWORD): BOOL; stdcall;
function DisablePlugin: BOOL; stdcall;

implementation

uses
  MapperUnit;

function ViewMappedMemoryRegions(disassembleraddress: pptruint; selected_disassembler_address: pptruint; hexviewaddress: pptruint): BOOL; stdcall;
begin
  Result := True;

  if not Assigned(MapperForm) then
    MapperForm := TMapperForm.Create(nil);

  MapperForm.Refresh;
  MapperForm.Show;
end;

function GetVersion(var PluginVersion: TpluginVersion; sizeofpluginversion: Integer): BOOL; stdcall;
begin
  Result := False;
  if sizeofpluginversion <> SizeOf(TPluginVersion) then
    Exit;

  PluginVersion.version := 1;
  PluginVersion.pluginname := 'Memory Remapper';
  Result := True;
end;

function InitializePlugin(ExportedFunctions: PExportedFunctions; pluginid: DWORD): BOOL; stdcall;
var
  func: TFunction1;
begin
  Exported := ExportedFunctions^;
  func.name := 'View Mapped Memory Regions';
  func.callbackroutine := ViewMappedMemoryRegions;
  func.shortcut := nil;
  Exported.registerfunction(pluginid, ptMemoryView, @func);
  Result := True;
end;

function DisablePlugin: BOOL; stdcall;
begin
  if Assigned(MapperForm) then
    FreeAndNil(MapperForm);
  Result := True;
end;

end.
