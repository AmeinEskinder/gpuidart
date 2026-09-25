param([Parameter(Mandatory)][int]$AppProcessId, [ValidateSet('select','search','type-clear','pin','tick','shortlist','capture','close')][string]$Step)
$ErrorActionPreference = 'Stop'
$root = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
Add-Type -Path (Join-Path $root 'benchmarks/windows.cs') -ReferencedAssemblies System.Drawing
Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
public static class WatchlistInput {
    [DllImport("user32.dll")] static extern bool PostMessage(IntPtr window, uint msg, IntPtr wp, IntPtr lp);
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
        PostMessage(window, 0x100, new IntPtr(8), IntPtr.Zero);
        PostMessage(window, 0x101, new IntPtr(8), IntPtr.Zero);
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
    }
} finally { [BenchmarkWindow]::Finish() }
