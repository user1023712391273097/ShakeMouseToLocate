#include <TrayConstants.au3>
#include <WindowsConstants.au3>
#Include <WinAPI.au3>
#include <GDIPlus.au3>
#include <Misc.au3>

#Region Globals

Global Const $SHAKE_DIST = 20
Global Const $SHAKE_SLICE_TIMEOUT = 75 ; milliseconds
Global Const $SHAKE_TIMEOUT = 500 ; milliseconds
Global Const $SHOWING_TIMEOUT = 750 ; milliseconds
Global $needed_shake_count = 4 ; set from configuration

Global Const $VERSION  = "1.0"
Global Const $APP_NAME = "ShakeMouseToLocate"
Global Const $EXE_NAME = @AutoItExe
Global Const $TRAY_TOOLTIP = $APP_NAME & " V" & $VERSION & " -- Quickly move the mouse pointer left and right to make it temporarily bigger"
Global Const $ABOUT_TEXT = $APP_NAME & " V" & $VERSION & @CRLF & @CRLF & _
    "Shake or circle the mouse quickly and a big mouse" & @CRLF & _
    "will show for a short while. This will help you find" & @CRLF & _
    "back the mouse cursor." & @CRLF & @CRLF & _
    "Forked by Nicolas de Jong (nicolas@rutilo.nl)" & @CRLF & _
    "Original by Spinal Cord (http://spinalcode.co.uk/)" & @CRLF & @CRLF & _
    "Altered because the original showed the big mouse" & @CRLF & _
    "too often. Now it shows only after moving the mouse" & @CRLF & _
    "pointer left and right quickly a few times." & @CRLF & @CRLF & _
    "Also added flags for autostart, enabled, ctrl and" & @CRLF & _
    "sensitivity."

Global Const $REGKEY_AUTORUN = "HKCU\Software\Microsoft\Windows\CurrentVersion\Run"
Global Const $REGKEY_CONFIG  = "HKCU\Software\" & $APP_NAME
Global Const $REGKEY_ENABLED = "Enabled"
Global Const $REGKEY_TCTRL   = "CtrlNeeded"
Global Const $REGKEY_SENSIT  = "Sensitivity"

Global Const $SENSITIVITY_HIGH   = 2
Global Const $SENSITIVITY_MEDIUM = 4
Global Const $SENSITIVITY_LOW    = 7

Global Const $AC_SRC_ALPHA = 1

Global $idAbout, $idExit, $idAutoStart, $idEnabled, $idUseCtrl, $idSensit, $idSensit0, $idSensit1, $idSensit2
Global $hBmp, $hIcon
Global $oldMX, $oldMY, $curMx, $curMY, $distX, $distY, $distPix
Global $showing = 0
Global $running = 1

#EndRegion ### Globals ###

#Region Init

$avMousePos = MouseGetPos()
$win_mouse = GUICreate($APP_NAME, 64, 64, $avMousePos[0], $avMousePos[1], $WS_POPUP, BitOR($WS_EX_LAYERED, $WS_EX_TOOLWINDOW))
	@@ -86,382 +81,300 @@ GUISetState(@SW_SHOW)
_setEnabled()  ; 'enabled' is persistent so this statement can be removed if required
_createTray()

; Timer for mouse tracking
$showingTimer = TimerInit()
$shakeSliceTimer = TimerInit()
$shakeTimeoutTimer = TimerInit()
$shakeCount = 0

Global $nowX = 0, $oldX = 0, $minX = 0, $maxX = 0, $hasMin = 0, $hasMax = 0

#EndRegion Init

_getSensitivity()

While $running = 1
    $avMousePos = MouseGetPos()

    _detectMouseMoves()
    _updateMouse()
    _handleTrayEvents()
WEnd

Func _detectMouseMoves()
    $nowX = $avMousePos[0]
    If $nowX < $oldX Then
        If $hasMin = 0 Then
            $hasMin = 1
            $minX = $nowX
        Else
            $minX = _min($minX, $nowX)
        EndIf
    ElseIf $nowX > $oldX Then
        If $hasMax = 0 Then
            $hasMax = 1
            $maxX = $nowX
        Else
            $maxX = _max($maxX, $nowX)
        EndIf
    EndIf
    $oldX = $nowX
EndFunc

Func _isShaking()
    If _needsCtrl() And Not _isCtrlPressed() Then
        Return 0
    EndIf
    $isShaking = 0
    If TimerDiff($shakeSliceTimer) >= $SHAKE_SLICE_TIMEOUT Then
        $shakeSliceTimer = TimerInit()

        If $hasMin = 1 And $hasMax = 1 And $maxX - $minX > $SHAKE_DIST Then
            $shakeCount += 1
            $shakeTimeoutTimer = TimerInit()
        EndIf

        If $shakeCount >= $needed_shake_count AND _isEnabled() Then
            $showingTimer = TimerInit()
            $shakeCount = 0
            $isShaking = 1
            _showBig()
        EndIf

        $hasMin = 0
        $hasMax = 0
        $minX = 0
        $maxX = 0
    EndIf
    Return $isShaking
EndFunc

Func _moveBigMouse()
    WinMove($win_mouse, "", $avMousePos[0], $avMousePos[1])
    WinSetOnTop($win_mouse, '', 1)
EndFunc

Func _hideBigMouseOnTimeout()
    If TimerDiff($showingTimer) >= $SHOWING_TIMEOUT Then
        _hideBig()
        _resetCursorTheme() ; Reset cursor theme when hiding the big cursor
        $shakeCount = 0
    EndIf
EndFunc

Func _updateMouse()
    If $showing = 1 Then
        _moveBigMouse()
        _hideBigMouseOnTimeout()
    Else
        If _isShaking() Then
            _showBig()
            _moveBigMouse()
        EndIf
    EndIf

    If TimerDiff($shakeTimeoutTimer) >= $SHAKE_TIMEOUT Then
        $shakeCount = 0
    EndIf
EndFunc

Func _createTray()
    Opt("TrayMenuMode", 3) ; The default tray menu items will not be shown and items are not checked when selected. These are options 1 and 2 for TrayMenuMode.

    $idAbout = TrayCreateItem("About")
    _TrayAddLine()
    $idAutoStart = TrayCreateItem("Start with Windows")
    $idEnabled = TrayCreateItem("Enabled")
    $idUseCtrl = TrayCreateItem("Also press ctrl to trigger")
    _TrayAddLine()
    $idSensit0 = TrayCreateItem("Sensitivity high")
    $idSensit1 = TrayCreateItem("Sensitivity medium")
    $idSensit2 = TrayCreateItem("Sensitivity low")
    _TrayAddLine()
    $idExit = TrayCreateItem("Exit")

    If RegRead($REGKEY_AUTORUN, $APP_NAME) <> '' Then
        TrayItemSetState($idAutoStart, $TRAY_CHECKED)
    EndIf

    If _isEnabled() Then
        TrayItemSetState($idEnabled, $TRAY_CHECKED)
    EndIf

    If _needsCtrl() Then
        TrayItemSetState($idUseCtrl, $TRAY_CHECKED)
    EndIf

    _setSensitivity(0) ; Initialize

    TraySetState($TRAY_ICONSTATE_SHOW) ; Show the tray menu.
    TraySetToolTip($TRAY_TOOLTIP)

    TrayItemSetOnEvent($idAbout, "_showAbout")
    TrayItemSetOnEvent($idAutoStart, "_toggleAutoStart")
    TrayItemSetOnEvent($idEnabled, "_toggleEnabled")
    TrayItemSetOnEvent($idUseCtrl, "_toggleCtrl")
    TrayItemSetOnEvent($idSensit0, "_setSensitivity")
    TrayItemSetOnEvent($idSensit1, "_setSensitivity")
    TrayItemSetOnEvent($idSensit2, "_setSensitivity")
    TrayItemSetOnEvent($idExit, "_exit")
EndFunc

Func _TrayAddLine()
    TrayCreateItem("")
EndFunc

Func _showAbout()
    MsgBox(64, "About " & $APP_NAME, $ABOUT_TEXT)
EndFunc

Func _toggleAutoStart()
    If TrayItemGetState($idAutoStart) = $TRAY_UNCHECKED Then
        TrayItemSetState($idAutoStart, $TRAY_CHECKED)
        RegWrite($REGKEY_AUTORUN, $APP_NAME, "REG_SZ", $EXE_NAME)
    Else
        TrayItemSetState($idAutoStart, $TRAY_UNCHECKED)
        RegDelete($REGKEY_AUTORUN, $APP_NAME)
    EndIf
EndFunc

Func _toggleEnabled()
    If TrayItemGetState($idEnabled) = $TRAY_UNCHECKED Then
        TrayItemSetState($idEnabled, $TRAY_CHECKED)
        _setEnabled()
    Else
        TrayItemSetState($idEnabled, $TRAY_UNCHECKED)
        _setDisabled()
    EndIf
EndFunc

Func _toggleCtrl()
    If TrayItemGetState($idUseCtrl) = $TRAY_UNCHECKED Then
        TrayItemSetState($idUseCtrl, $TRAY_CHECKED)
        _setCtrlNeeded()
    Else
        TrayItemSetState($idUseCtrl, $TRAY_UNCHECKED)
        _unsetCtrlNeeded()
    EndIf
EndFunc

Func _showBig()
    _setCursorTheme() ; Set cursor theme when showing the big cursor
    GUISetState(@SW_SHOW, $win_mouse)
    $showing = 1
EndFunc

Func _hideBig()
    GUISetState(@SW_HIDE, $win_mouse)
    $showing = 0
EndFunc

Func _isCtrlPressed()
    If _IsPressed("11") Then Return 1
    Return 0
EndFunc

Func _isEnabled()
    If RegRead($REGKEY_CONFIG, $REGKEY_ENABLED) = "1" Then Return 1
    Return 0
EndFunc

Func _setEnabled()
    RegWrite($REGKEY_CONFIG, $REGKEY_ENABLED, "REG_SZ", "1")
EndFunc

Func _setDisabled()
    RegWrite($REGKEY_CONFIG, $REGKEY_ENABLED, "REG_SZ", "0")
EndFunc

Func _needsCtrl()
    If RegRead($REGKEY_CONFIG, $REGKEY_TCTRL) = "1" Then Return 1
    Return 0
EndFunc

Func _setCtrlNeeded()
    RegWrite($REGKEY_CONFIG, $REGKEY_TCTRL, "REG_SZ", "1")
EndFunc

Func _unsetCtrlNeeded()
    RegWrite($REGKEY_CONFIG, $REGKEY_TCTRL, "REG_SZ", "0")
EndFunc

Func _getSensitivity()
    $sens = RegRead($REGKEY_CONFIG, $REGKEY_SENSIT)
    Select
        Case $sens = $SENSITIVITY_HIGH
            TrayItemSetState($idSensit0, $TRAY_CHECKED)
        Case $sens = $SENSITIVITY_MEDIUM
            TrayItemSetState($idSensit1, $TRAY_CHECKED)
        Case $sens = $SENSITIVITY_LOW
            TrayItemSetState($idSensit2, $TRAY_CHECKED)
        Case Else
            TrayItemSetState($idSensit0, $TRAY_CHECKED)
            _setSensitivity($SENSITIVITY_HIGH)
    EndSelect
EndFunc

Func _setSensitivity($level)
    Select
        Case $level = $SENSITIVITY_HIGH
            RegWrite($REGKEY_CONFIG, $REGKEY_SENSIT, "REG_SZ", $SENSITIVITY_HIGH)
            TrayItemSetState($idSensit0, $TRAY_CHECKED)
            TrayItemSetState($idSensit1, $TRAY_UNCHECKED)
            TrayItemSetState($idSensit2, $TRAY_UNCHECKED)
            $needed_shake_count = $SENSITIVITY_HIGH
        Case $level = $SENSITIVITY_MEDIUM
            RegWrite($REGKEY_CONFIG, $REGKEY_SENSIT, "REG_SZ", $SENSITIVITY_MEDIUM)
            TrayItemSetState($idSensit0, $TRAY_UNCHECKED)
            TrayItemSetState($idSensit1, $TRAY_CHECKED)
            TrayItemSetState($idSensit2, $TRAY_UNCHECKED)
            $needed_shake_count = $SENSITIVITY_MEDIUM
        Case $level = $SENSITIVITY_LOW
            RegWrite($REGKEY_CONFIG, $REGKEY_SENSIT, "REG_SZ", $SENSITIVITY_LOW)
            TrayItemSetState($idSensit0, $TRAY_UNCHECKED)
            TrayItemSetState($idSensit1, $TRAY_UNCHECKED)
            TrayItemSetState($idSensit2, $TRAY_CHECKED)
            $needed_shake_count = $SENSITIVITY_LOW
    EndSelect
EndFunc

Func _exit()
    _GDIPlus_Shutdown()
    Exit
EndFunc

Func _Torus()
    Local $torus = "..."
    ; Your image data here
    Return BinaryToString($torus)
EndFunc

Func _min($a, $b)
    If $a < $b Then Return $a
    Return $b
EndFunc

Func _max($a, $b)
    If $a > $b Then Return $a
    Return $b
EndFunc

; Custom functions to set and reset cursor theme
Func _setCursorTheme()
    RunWait('rundll32.exe shell32.dll,Control_RunDLL main.cpl @0,1') ; Open Mouse Properties
    WinWaitActive("Mouse Properties")
    ControlClick("Mouse Properties", "", "[CLASS:SysTabControl32; INSTANCE:1]", "Left", 1, 50, 20) ; Click Pointers tab
    ControlClick("Mouse Properties", "", "[CLASS:Button; TEXT:B]") ; Click Browse button to select new scheme
    WinWaitActive("Browse")
    ControlCommand("Browse", "", "[CLASS:ComboBox; INSTANCE:1]", "SelectString", "macOS Cursors - No Shadows Newer") ; Select the desired theme
    ControlClick("Browse", "", "[CLASS:Button; TEXT:Open]") ; Click Open
    ControlClick("Mouse Properties", "", "[CLASS:Button; TEXT:OK]") ; Click OK to apply and close Mouse Properties
EndFunc

Func _resetCursorTheme()
    RunWait('rundll32.exe shell32.dll,Control_RunDLL main.cpl @0,1') ; Open Mouse Properties
    WinWaitActive("Mouse Properties")
    ControlClick("Mouse Properties", "", "[CLASS:SysTabControl32; INSTANCE:1]", "Left", 1, 50, 20) ; Click Pointers tab
    ControlCommand("Mouse Properties", "", "[CLASS:ComboBox; INSTANCE:1]", "SelectString", "Windows Default (system scheme)") ; Select default scheme
    ControlClick("Mouse Properties", "", "[CLASS:Button; TEXT:OK]") ; Click OK to apply and close Mouse Properties
EndFunc
