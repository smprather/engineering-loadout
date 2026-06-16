#Requires AutoHotkey v2.0
#SingleInstance Force
SetTitleMatchMode("Slow")
InstallMouseHook()
InstallKeybdHook()

; Installer-managed feature flags. engineering-loadout.ps1 patches these values from
; %USERPROFILE%\loadout_keys.toml after copying this file into place.
cfg_feature_corp_logins := false
cfg_feature_mouse_wiggle := false
cfg_feature_cisco_secure_client_vpn := false
cfg_feature_password_manager := false
cfg_feature_tmux_hotkeys := false
cfg_feature_f1f2f3_as_mouse_buttons := false
cfg_feature_thinlinc_reconnect := true

StrJoin(arr, sep) {
    out := ""
    for i, v in arr
        out .= (i > 1 ? sep : "") . v
    return out
}

g_corp_mode := (EnvGet("CORP_UID") != "")
g_uid := ""
g_password := ""
if (g_corp_mode) {
    g_uid := EnvGet("CORP_UID")
    g_password := EnvGet("CORP_PASSWORD")
    if ((cfg_feature_corp_logins || cfg_feature_cisco_secure_client_vpn) && g_password = "")
        MsgBox "CORP_PASSWORD environment variable is not set."
}

g_idle := false
g_autologin := true
g_autologin_saved := true
g_mouse_wiggle_allowed := (EnvGet("AHK_ENABLE_MOUSE_WIGGLE") != "false")
g_thinlinc_ticks := 0
g_thinlinc_last_seen := "(handle_thinlinc not yet called)"
g_thinlinc_relaunch_pending := false

; Don't flood windows with gui events too fast.
SetMouseDelay(10)
SetTimer(do_loop, 1000)
Return  ; End of auto-execute section

check_idle()
{
    global g_idle
    g_idle := (A_TimeIdlePhysical > 7200000)
}

do_loop()
{
    global cfg_feature_cisco_secure_client_vpn, cfg_feature_mouse_wiggle, cfg_feature_thinlinc_reconnect, g_mouse_wiggle_allowed

    check_idle()

    if (cfg_feature_mouse_wiggle && g_mouse_wiggle_allowed)
        mouse_nudge()

    if (cfg_feature_cisco_secure_client_vpn)
        log_into_corp_vpn()

    if (cfg_feature_thinlinc_reconnect)
        handle_thinlinc()
}

;g_vpn_log := A_ScriptDir . "\vpn_debug.log"
;VpnLog(msg) {
;    global g_vpn_log
;    FileAppend(A_Now " " . msg . "`n", g_vpn_log)
;}

log_into_corp_vpn()
{
    global g_autologin, g_corp_mode, g_idle, g_password, g_uid

    if (!g_corp_mode || g_idle || !g_autologin)
        return

    ; Don't try to reconnect while the workstation is locked -- there's
    ; likely no network, and we'd just pile up error dialogs.
    if (ProcessExist("LogonUI.exe"))
        return

    if (g_password = "")
        return

    ; Start with a cooldown so Cisco's own auto-connect (e.g. after a
    ; reboot) has time to finish before we try clicking Connect.
    static last_action_ms := A_TickCount
    ; Exponential backoff when server is unreachable -- starts at 30 s,
    ; doubles each consecutive failure, caps at ~16 min.
    static fail_backoff_ms := 0
    static last_fail_ms := 0

    try {
        SetTitleMatchMode(3)
        if (WinExist("Cisco Secure Client", "The secure gateway has terminated the VPN")) {
            WinActivate()
            ControlClick("Button1")
            SetTitleMatchMode(2)
            return
        }

        ; Auto-dismiss "connect already in progress" dialog and reset the
        ; cooldown so we don't immediately re-attempt.
        if (WinExist("Cisco Secure Client", "already in progress")) {
            WinActivate()
            ControlClick("Button1")
            last_action_ms := A_TickCount
            SetTitleMatchMode(2)
            return
        }

        ; Auto-dismiss "Could not connect to server" dialog and start
        ; exponential backoff so we don't flood the screen with errors.
        if (WinExist("Cisco Secure Client", "Could not connect to server")) {
            WinActivate()
            ControlClick("Button1")
            last_fail_ms := A_TickCount
            fail_backoff_ms := fail_backoff_ms ? Min(fail_backoff_ms * 2, 1000000) : 30000
            SetTitleMatchMode(2)
            return
        }

        ; Cooldown after any Connect click -- prevents clicking Connect again
        ; while a connection attempt is still being processed.
        if (A_TickCount - last_action_ms < 5000) {
            SetTitleMatchMode(2)
            return
        }

        ; Back off after server-unreachable failures.
        if (fail_backoff_ms && A_TickCount - last_fail_ms < fail_backoff_ms) {
            SetTitleMatchMode(2)
            return
        }

        SetTitleMatchMode(1)
        if (WinExist("Cisco Secure Client | ")) {
            WinActivate()
            ControlSetText(g_uid, "Edit1")
            ControlSetText(g_password, "Edit2")
            ControlClick("Button1")
            last_action_ms := A_TickCount
            fail_backoff_ms := 0
            SetTitleMatchMode(2)
            return
        }

        SetTitleMatchMode(3)
        DetectHiddenWindows(true)
        if (WinExist("Cisco Secure Client", "AnyConnect VPN:")) {
            windowText := WinGetText("Cisco Secure Client", "AnyConnect VPN:")
            DetectHiddenWindows(false)
            if (InStr(windowText, "Connected to")) {
                fail_backoff_ms := 0
                SetTitleMatchMode(2)
                return
            }
        } else {
            DetectHiddenWindows(false)
        }

        SetTitleMatchMode(2)
        Run("C:\Program Files (x86)\Cisco\Cisco Secure Client\UI\csc_ui.exe")
        Sleep(1500)
        SetTitleMatchMode(3)
        if (WinExist("Cisco Secure Client", "AnyConnect VPN:")) {
            WinActivate("Cisco Secure Client", "AnyConnect VPN:")
            ControlClick("Button1", "Cisco Secure Client", "AnyConnect VPN:")
        }
        last_action_ms := A_TickCount
        SetTitleMatchMode(2)
    } catch as e {
        DetectHiddenWindows(false)
        SetTitleMatchMode(2)
        last_action_ms := A_TickCount
        ;VpnLog("ERROR: " e.Message " (line " e.Line ")")
    }
}

mouse_nudge()
{
    global g_idle

    static mouse_delta_x := 5
    static expected_x := ""
    static expected_y := ""

    if (g_idle || A_TimeIdlePhysical <= 500000) {
        expected_x := ""
        return
    }

    CoordMode("Mouse", "Screen")
    MouseGetPos(&cur_x, &cur_y)

    if (expected_x != "" && (cur_x != expected_x || cur_y != expected_y)) {
        expected_x := ""
        return
    }

    new_x := cur_x + mouse_delta_x
    MouseMove(new_x, cur_y, 10)
    expected_x := new_x
    expected_y := cur_y
    mouse_delta_x *= -1
}

; Auto-dismiss ThinLinc "Connection error" dialogs and, when the main
; "ThinLinc client" window is up (or tlclient.exe is not running at all),
; auto-connect using THINLINC_SERVER / THINLINC_USERNAME / THINLINC_PASSWORD.
handle_thinlinc()
{
    global g_thinlinc_ticks, g_thinlinc_last_seen, g_thinlinc_relaunch_pending
    static last_fill_ms := 0

    g_thinlinc_ticks += 1

    try {
        ; --- Case 1: "Connection error" dialog -> dismiss so tlclient restarts ---
        SetTitleMatchMode(3)
        if (WinExist("Connection error ahk_exe tlclient.exe")) {
            g_thinlinc_last_seen := "case1: dismissing 'Connection error'"
            WinActivate()
            Sleep(100)
            Send("{Enter}")  ; "Close" is the default button
            g_thinlinc_relaunch_pending := true
            SetTitleMatchMode(2)
            return
        }

        server := EnvGet("THINLINC_SERVER")
        if (server = "") {
            g_thinlinc_last_seen := "THINLINC_SERVER env var is empty -- nothing to do"
            SetTitleMatchMode(2)
            return
        }

        ; --- Case 2: Main ThinLinc client window -> fill creds + Connect ---
        if (WinExist("ThinLinc client ahk_exe tlclient.exe")) {
            SetTitleMatchMode(2)

            ; Rate-limit only the fill/connect path -- guards against credential
            ; hammering if Connect keeps failing. Does not delay the initial
            ; reconnect cycle (dismiss -> relaunch -> first fill).
            if (A_TickCount - last_fill_ms < 10000) {
                g_thinlinc_last_seen := "case2: rate-limited (" . ((A_TickCount - last_fill_ms) // 1000) . "s since last fill)"
                return
            }

            if (!thinlinc_server_reachable(server)) {
                g_thinlinc_last_seen := "case2: main window present, server '" . server . "' unreachable"
                return
            }

            username := EnvGet("THINLINC_USERNAME")
            password := EnvGet("THINLINC_PASSWORD")
            if (username = "" || password = "") {
                g_thinlinc_last_seen := "case2: THINLINC_USERNAME or THINLINC_PASSWORD empty"
                return
            }

            g_thinlinc_last_seen := "case2: filling credentials + Connect"
            WinActivate("ThinLinc client ahk_exe tlclient.exe")
            WinWaitActive("ThinLinc client ahk_exe tlclient.exe", , 2)
            Sleep(200)

            ; Tab/Shift-Tab don't wrap in the ThinLinc client, so 10 Shift-Tab
            ; presses is a reliable way to anchor focus on the first field (Server).
            Loop 10
                Send("+{Tab}")
            Sleep(50)

            ; Server -> Username -> Password (Tab between them).
            Send("^a{Delete}")
            SendText(server)
            Send("{Tab}")
            Send("^a{Delete}")
            SendText(username)
            Send("{Tab}")
            Send("^a{Delete}")
            SendText(password)

            ; From Password, five Tabs reaches the Connect button; Enter activates it.
            Loop 5
                Send("{Tab}")
            Send("{Enter}")
            last_fill_ms := A_TickCount
            return
        }
        SetTitleMatchMode(2)

        ; --- Case 3: tlclient not running -> only relaunch if we just dismissed an error ---
        if (ProcessExist("tlclient.exe")) {
            g_thinlinc_last_seen := "case3: tlclient.exe running, no main window match (connecting?)"
            return
        }
        if (!g_thinlinc_relaunch_pending) {
            g_thinlinc_last_seen := "case3: tlclient closed, no relaunch pending (respecting user close)"
            return
        }
        if (!thinlinc_server_reachable(server)) {
            g_thinlinc_last_seen := "case3: relaunch pending, server '" . server . "' unreachable"
            return
        }
        g_thinlinc_last_seen := "case3: relaunching tlclient.exe after error dismiss"
        try Run('"C:\Program Files\ThinLinc client\tlclient.exe"')
        g_thinlinc_relaunch_pending := false
    } catch as e {
        g_thinlinc_last_seen := "ERROR: " . e.Message . " (line " . e.Line . ")"
        SetTitleMatchMode(2)
    }
}

; Quick reachability probe. Spawns ping with a 500 ms timeout, hidden.
; Blocks the 1 s timer briefly; swap for a raw TCP check if that becomes
; a concern.
thinlinc_server_reachable(host)
{
    if (host = "")
        return false
    try {
        exitCode := RunWait('cmd.exe /c ping -n 1 -w 500 "' . host . '" >nul 2>&1', , "Hide")
        return exitCode = 0
    } catch {
        return false
    }
}

; ^ = Ctrl
; + = Shift
; ! = Alt

/*
; Diagnostic hotkey: Ctrl+Alt+D -- scans visible top-level windows and shows any
; whose title or EXE matches a regex. Kept commented for future targeting work;
; uncomment (and tweak the `needles` pattern) when identifying a new app's dialogs.
^!d::
{
    SetTitleMatchMode(2)
    needles := "i)(thinlinc|tlclient|connection)"
    out := "=== Matching windows (thinlinc|tlclient|connection) ===`n"
    hits := 0
    for hwnd in WinGetList() {
        title := ""
        try title := WinGetTitle(hwnd)
        catch
            continue
        pid := 0
        exePath := ""
        try {
            pid := WinGetPID(hwnd)
            exePath := ProcessGetPath(pid)
        } catch {
        }
        exeName := ""
        if (exePath != "")
            SplitPath(exePath, &exeName)
        if (!RegExMatch(title . " " . exeName, needles))
            continue
        hits += 1
        out .= "`nTitle: [" title "]`n"
        out .= "PID: " pid "  EXE: " exePath "`n"
        try {
            controls := WinGetControls(hwnd)
            out .= "Controls: " . (controls.Length > 0 ? StrJoin(controls, ", ") : "(none)") . "`n"
        } catch {
            out .= "Controls: (error)`n"
        }
        try {
            text := WinGetText(hwnd)
            if (text != "")
                out .= "Text:`n" text "`n"
        } catch {
        }
        out .= "---`n"
    }
    if (hits = 0)
        out .= "`n(no matching windows found)`n"
    diagGui := Gui(, "AHK Window Diagnostic")
    editCtrl := diagGui.Add("Edit", "ReadOnly w700 h500 VScroll", out)
    diagGui.Add("Button", "Default w80", "OK").OnEvent("Click", (*) => diagGui.Destroy())
    diagGui.Show()
    editCtrl.Focus()
    SendMessage(0xB1, 0, -1, editCtrl)  ; EM_SETSEL: select all
}
*/

; If you make any edits to this file, do a ctrl-alt-r to reload the script.
^!r::
{
    Reload
}

; Toggle all hotkeys on/off -- exempt from suspension so it always works.
; Saves/restores g_autologin so VPN auto-login resumes its prior state on unpause.
#SuspendExempt
^!a::
{
    global g_autologin, g_autologin_saved

    Suspend(-1)
    if (A_IsSuspended) {
        g_autologin_saved := g_autologin
        g_autologin := false
        ToolTip("Hotkeys: PAUSED")
    } else {
        g_autologin := g_autologin_saved
        ToolTip("Hotkeys: ACTIVE")
    }
    SetTimer(() => ToolTip(), -1000)
}
#SuspendExempt False

#HotIf cfg_feature_cisco_secure_client_vpn && g_corp_mode
^!v::
{
    global g_autologin

    g_autologin := !g_autologin
    state := g_autologin ? "ON" : "OFF"
    ToolTip("VPN auto-login: " state)
    SetTimer(() => ToolTip(), -1000)
}
#HotIf

#HotIf cfg_feature_thinlinc_reconnect
; Ctrl+Alt+T -- dump handle_thinlinc() state, env vars, window matches, and a live ping.
^!t::
{
    global cfg_feature_thinlinc_reconnect, g_thinlinc_ticks, g_thinlinc_last_seen, g_thinlinc_relaunch_pending

    out := "=== ThinLinc reconnect diagnostic ===`n"
    out .= "cfg_feature_thinlinc_reconnect: " . (cfg_feature_thinlinc_reconnect ? "true" : "false") . "`n"
    out .= "handle_thinlinc ticks: " . g_thinlinc_ticks . "`n"
    out .= "relaunch pending: " . (g_thinlinc_relaunch_pending ? "true" : "false") . "`n"
    out .= "last seen: " . g_thinlinc_last_seen . "`n`n"

    pw := EnvGet("THINLINC_PASSWORD")
    out .= "THINLINC_SERVER:   [" . EnvGet("THINLINC_SERVER") . "]`n"
    out .= "THINLINC_USERNAME: [" . EnvGet("THINLINC_USERNAME") . "]`n"
    out .= "THINLINC_PASSWORD: " . (pw = "" ? "(unset)" : "(set, length " . StrLen(pw) . ")") . "`n"
    out .= "tlclient.exe PID:  " . ProcessExist("tlclient.exe") . "`n`n"

    SetTitleMatchMode(3)
    out .= "'Connection error' window: " . (WinExist("Connection error ahk_exe tlclient.exe") ? "EXISTS" : "not found") . "`n"
    out .= "'ThinLinc client' window:  " . (WinExist("ThinLinc client ahk_exe tlclient.exe") ? "EXISTS" : "not found") . "`n"
    SetTitleMatchMode(2)

    server := EnvGet("THINLINC_SERVER")
    if (server != "") {
        out .= "`nPinging [" . server . "]...`n"
        start := A_TickCount
        reachable := thinlinc_server_reachable(server)
        elapsed := A_TickCount - start
        out .= "Reachable: " . (reachable ? "YES" : "NO") . " (" . elapsed . " ms)`n"
    }

    diagGui := Gui(, "ThinLinc Diagnostic")
    editCtrl := diagGui.Add("Edit", "ReadOnly w600 h400 VScroll", out)
    diagGui.Add("Button", "Default w80", "OK").OnEvent("Click", (*) => diagGui.Destroy())
    diagGui.Show()
    editCtrl.Focus()
    SendMessage(0xB1, 0, -1, editCtrl)  ; EM_SETSEL: select all
}
#HotIf

#HotIf cfg_feature_corp_logins && g_corp_mode
^!i::
{
    SendText(g_password)
    Send("{Tab}")
}

^!o::
{
    SendText(g_uid)
    Send("{Tab}")
    SendText(g_password)
    Send("{Enter}")
}

^!p::
{
    SendText(g_password)
    Send("{Enter}")
}
#HotIf

#HotIf cfg_feature_tmux_hotkeys
$*RAlt::
$*RWin::
{
    Send("^\z")
    if (InStr(A_ThisHotkey, "RWin"))
        KeyWait("RWin")
}

^;::
{
    Send("{Ctrl up}^\;{Ctrl down}")
}
#HotIf

#HotIf cfg_feature_password_manager
^!b::
{
    password := EnvGet("PWMANAGER_PASSWORD")
    if (password = "") {
        MsgBox "PWMANAGER_PASSWORD environment variable is not set."
        return
    }
    SendText(password)
    Send("{Enter}")
}
#HotIf

#HotIf cfg_feature_f1f2f3_as_mouse_buttons && (WinActive("ahk_exe mspaint.exe") || WinActive("ahk_exe etxc.exe") || WinActive("ahk_exe wezterm-gui.exe"))
F1::
{
    Send("{LButton Down}")
    KeyWait("F1")
    Send("{LButton Up}")
}

F2::
{
    Send("{RButton Down}")
    KeyWait("F2")
    Send("{RButton Up}")
}

F3::
{
    Send("{LButton 2}")
    Sleep(500)
    Send("{RButton}")
}
#HotIf
