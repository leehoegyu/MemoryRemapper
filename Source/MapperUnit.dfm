object MapperForm: TMapperForm
  Left = 0
  Top = 0
  ClientHeight = 343
  ClientWidth = 469
  Color = clBtnFace
  Font.Charset = DEFAULT_CHARSET
  Font.Color = clWindowText
  Font.Height = -12
  Font.Name = 'Segoe UI'
  Font.Style = []
  Position = poScreenCenter
  TextHeight = 15
  object ListView1: TListView
    Left = 0
    Top = 0
    Width = 469
    Height = 343
    Align = alClient
    Columns = <
      item
        Caption = 'Address'
        Width = 140
      end
      item
        Caption = 'Size'
        Width = 80
      end
      item
        Caption = 'Protect'
        Width = 140
      end
      item
        Caption = 'FileName'
        Width = 400
      end>
    ReadOnly = True
    RowSelect = True
    PopupMenu = PopupMenu1
    TabOrder = 0
    ViewStyle = vsReport
    OnContextPopup = ListView1ContextPopup
    OnKeyDown = ListView1KeyDown
  end
  object PopupMenu1: TPopupMenu
    AutoHotkeys = maManual
    Left = 240
    Top = 232
    object RemapMemoryRegion1: TMenuItem
      Caption = 'Remap Memory Region'
      Default = True
      OnClick = RemapMemoryRegion1Click
    end
    object N1: TMenuItem
      Caption = '-'
    end
    object Openfilelocation1: TMenuItem
      Caption = 'Open file location'
      ShortCut = 16397
      OnClick = Openfilelocation1Click
    end
    object Copy1: TMenuItem
      Caption = 'Copy'
      ShortCut = 16451
      OnClick = Copy1Click
    end
    object CopyAddress1: TMenuItem
      Caption = 'Copy "Address"'
      Visible = False
      OnClick = CopyAddress1Click
    end
    object CopySize1: TMenuItem
      Caption = 'Copy "Size"'
      Visible = False
      OnClick = CopySize1Click
    end
    object CopyProtect1: TMenuItem
      Caption = 'Copy "Protect"'
      Visible = False
      OnClick = CopyProtect1Click
    end
    object CopyFileName1: TMenuItem
      Caption = 'Copy "FileName"'
      Visible = False
      OnClick = CopyFileName1Click
    end
  end
end
