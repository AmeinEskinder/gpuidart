param([Parameter(Mandatory)][int]$AppProcessId, [ValidateSet('select','search','type-clear','pin','tick','shortlist','capture','close','down','scroll','focus-input','unicode','backspace','clear-unicode','small','normal','screen-scroll','capture-small','capture-footer','burst')][string]$Step)
$ErrorActionPreference = 'Stop'
$root = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
Add-Type -Path (Join-Path $root 'benchmarks/windows.cs') -ReferencedAssemblies System.Drawing
Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
public static class WatchlistInput {
    [DllImport("user32.dll", EntryPoint = "PostMessageW", ExactSpelling = true, SetLastError = true)] static extern bool PostMessageNative(IntPtr window, uint msg, IntPtr wp, IntPtr lp);
    static void PostMessage(IntPtr window, uint msg, IntPtr wp, IntPtr lp) {
        if (!PostMessageNative(window, msg, wp, lp)) throw new System.ComponentModel.Win32Exception(Marshal.GetLastWin32Error());
    }
    [StructLayout(LayoutKind.Sequential)] struct Rect { public int Left, Top, Right, Bottom; }
    [StructLayout(LayoutKind.Sequential)] struct Point { public int X, Y; }
    [DllImport("user32.dll")] static extern bool GetWindowRect(IntPtr window, out Rect rect);
    [DllImport("user32.dll")] static extern bool GetClientRect(IntPtr window, out Rect rect);
    [DllImport("user32.dll")] static extern bool MoveWindow(IntPtr window, int x, int y, int width, int height, bool repaint);
    [DllImport("user32.dll")] static extern bool ClientToScreen(IntPtr window, ref Point point);
    public static void Resize(IntPtr window, int width, int height, double scale) {
        Rect outer, inner; GetWindowRect(window, out outer); GetClientRect(window, out inner);
        if (!MoveWindow(window, outer.Left, outer.Top, (int)(width * scale) + outer.Right - outer.Left - inner.Right,
            (int)(height * scale) + outer.Bottom - outer.Top - inner.Bottom, true)) throw new InvalidOperationException("Resize failed");
    }
    public static void ScreenWheel(IntPtr window, double scale) {
        var point = new Point { X = (int)(25 * scale), Y = (int)(30 * scale) };
        ClientToScreen(window, ref point);
        PostMessage(window, 0x20A, new IntPtr(unchecked(-1200 << 16)), new IntPtr((point.Y << 16) | (point.X & 0xffff)));
    }
    public static void Click(IntPtr window, int x, int y, double scale) {
        var position = new IntPtr(((int)(y * scale) << 16) | (int)(x * scale));
        PostMessage(window, 0x200, IntPtr.Zero, position);
        PostMessage(window, 0x201, new IntPtr(1), position);
        PostMessage(window, 0x202, IntPtr.Zero, position);
    }
    public static void Text(IntPtr window, string text) {
        foreach (char ch in text) PostMessage(window, 0x102, new IntPtr(ch), IntPtr.Zero);
    }
    public static void Backspace(IntPtr window) {
        Key(window, 8);
    }
    public static void Key(IntPtr window, int key) {
        PostMessage(window, 0x100, new IntPtr(key), IntPtr.Zero);
        PostMessage(window, 0x101, new IntPtr(key), IntPtr.Zero);
    }
    public static void Unicode(IntPtr window) {
        Text(window, "\u65e5\u672c\u8a9e\ud83d\ude00");
    }
}
'@
[BenchmarkWindow]::Initialize()
try {
    $window = [BenchmarkWindow]::Find($AppProcessId)
    if ($window -eq [IntPtr]::Zero) { throw 'Watchlist process has no window' }
    $scale = [BenchmarkWindow]::Scale($window)
    switch ($Step) {
        select { [WatchlistInput]::Click($window, 40, 270, $scale) }
        search { [WatchlistInput]::Click($window, 40, 110, $scale); [WatchlistInput]::Text($window, 'ALP0000') }
        type-clear { [WatchlistInput]::Click($window, 40, 110, $scale); [WatchlistInput]::Text($window, 'X'); [WatchlistInput]::Backspace($window) }
        pin { [WatchlistInput]::Click($window, 200, 154, $scale) }
        tick { [WatchlistInput]::Click($window, 370, 154, $scale) }
        shortlist { [WatchlistInput]::Click($window, 50, 154, $scale) }
        capture { [BenchmarkWindow]::CaptureOffscreen($window, (Join-Path $root 'reports/sdk/visual/watchlist-edited.png')) }
        close { [BenchmarkWindow]::Close($window) }
        down { [WatchlistInput]::Key($window, 0x28) }
        scroll { [BenchmarkWindow]::MessageWheel($window, -1200) }
        focus-input { [WatchlistInput]::Click($window, 40, 110, $scale) }
        unicode { [WatchlistInput]::Unicode($window) }
        backspace { [WatchlistInput]::Backspace($window) }
        clear-unicode { 1..3 | ForEach-Object { [WatchlistInput]::Backspace($window) } }
        small { [WatchlistInput]::Resize($window, 400, 360, $scale) }
        normal { [WatchlistInput]::Resize($window, 960, 720, $scale) }
        screen-scroll { [WatchlistInput]::ScreenWheel($window, $scale) }
        capture-small { [BenchmarkWindow]::CaptureOffscreen($window, (Join-Path $root 'reports/sdk/visual/watchlist-small.png')) }
        capture-footer { [BenchmarkWindow]::CaptureOffscreen($window, (Join-Path $root 'reports/sdk/visual/watchlist-footer.png')) }
        burst { 1..100 | ForEach-Object { [WatchlistInput]::Click($window, 370, 154, $scale); Start-Sleep -Milliseconds 10 } }
    }
} finally { [BenchmarkWindow]::Finish() }
