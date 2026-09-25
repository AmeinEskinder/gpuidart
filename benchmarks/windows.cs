using System;
using System.Diagnostics;
using System.Drawing;
using System.Drawing.Imaging;
using System.Runtime.InteropServices;

public static class BenchmarkWindow {
    public static Process Start(string executable, string arguments, string folder, bool isolatedPath) {
        var process = new Process { StartInfo = new ProcessStartInfo {
            FileName = executable, Arguments = arguments, WorkingDirectory = folder,
            UseShellExecute = false, CreateNoWindow = true, RedirectStandardOutput = true, RedirectStandardError = true
        }};
        if (isolatedPath) process.StartInfo.EnvironmentVariables["PATH"] = Environment.ExpandEnvironmentVariables("%SystemRoot%;%SystemRoot%\\System32");
        string stdout = System.IO.Path.Combine(folder, "stdout.log");
        string stderr = System.IO.Path.Combine(folder, "stderr.log");
        System.IO.File.WriteAllText(stdout, ""); System.IO.File.WriteAllText(stderr, "");
        process.OutputDataReceived += (_, e) => { if (e.Data != null) System.IO.File.AppendAllText(stdout, e.Data + Environment.NewLine); };
        process.ErrorDataReceived += (_, e) => { if (e.Data != null) System.IO.File.AppendAllText(stderr, e.Data + Environment.NewLine); };
        process.Start(); process.BeginOutputReadLine(); process.BeginErrorReadLine();
        return process;
    }
    [StructLayout(LayoutKind.Sequential)] public struct Rect { public int Left, Top, Right, Bottom; }
    [StructLayout(LayoutKind.Sequential)] public struct Point { public int X, Y; }
    [StructLayout(LayoutKind.Sequential)] struct MouseInput { public int X, Y; public uint Data, Flags, Time; public UIntPtr Extra; }
    [StructLayout(LayoutKind.Explicit)] struct InputUnion { [FieldOffset(0)] public MouseInput Mouse; }
    [StructLayout(LayoutKind.Sequential)] struct Input { public uint Type; public InputUnion Union; }
    delegate bool EnumProc(IntPtr window, IntPtr parameter);
    [DllImport("user32.dll")] static extern bool EnumWindows(EnumProc callback, IntPtr parameter);
    [DllImport("user32.dll")] static extern uint GetWindowThreadProcessId(IntPtr window, out uint process);
    [DllImport("user32.dll")] static extern bool IsWindowVisible(IntPtr window);
    [DllImport("user32.dll", CharSet = CharSet.Unicode)] static extern int GetWindowText(IntPtr window, System.Text.StringBuilder title, int maximum);
    [DllImport("user32.dll")] static extern bool GetClientRect(IntPtr window, out Rect rect);
    [DllImport("user32.dll")] static extern bool GetWindowRect(IntPtr window, out Rect rect);
    [DllImport("user32.dll")] static extern bool ClientToScreen(IntPtr window, ref Point point);
    [DllImport("user32.dll")] public static extern uint GetDpiForWindow(IntPtr window);
    [DllImport("user32.dll")] static extern IntPtr MonitorFromWindow(IntPtr window, uint flags);
    [DllImport("shcore.dll")] static extern int GetDpiForMonitor(IntPtr monitor, int type, out uint x, out uint y);
    [DllImport("user32.dll")] static extern bool SetForegroundWindow(IntPtr window);
    [DllImport("user32.dll")] static extern bool ShowWindow(IntPtr window, int command);
    [DllImport("user32.dll")] static extern IntPtr GetForegroundWindow();
    [DllImport("user32.dll")] static extern bool MoveWindow(IntPtr window, int x, int y, int width, int height, bool repaint);
    [DllImport("user32.dll")] static extern bool SetCursorPos(int x, int y);
    [DllImport("user32.dll", SetLastError = true)] static extern uint SendInput(uint count, Input[] inputs, int size);
    [DllImport("user32.dll")] static extern bool PostMessage(IntPtr window, uint message, IntPtr wParam, IntPtr lParam);
    [DllImport("user32.dll")] static extern bool SetProcessDPIAware();
    [DllImport("user32.dll")] static extern bool PrintWindow(IntPtr window, IntPtr device, uint flags);
    [DllImport("winmm.dll")] static extern uint timeBeginPeriod(uint period);
    [DllImport("winmm.dll")] static extern uint timeEndPeriod(uint period);

    public static void Initialize() { SetProcessDPIAware(); timeBeginPeriod(1); }
    public static void Finish() { timeEndPeriod(1); }
    public static IntPtr Find(int process) {
        IntPtr found = IntPtr.Zero;
        EnumWindows((window, _) => {
            uint owner;
            GetWindowThreadProcessId(window, out owner);
            Rect rect;
            GetClientRect(window, out rect);
            if (owner == process && rect.Right > 100 && rect.Bottom > 100) { found = window; return false; }
            return true;
        }, IntPtr.Zero);
        return found;
    }
    public static double Scale(IntPtr window) {
        uint x, y;
        if (GetDpiForMonitor(MonitorFromWindow(window, 2), 0, out x, out y) != 0)
            throw new InvalidOperationException("Cannot determine monitor DPI");
        return x / 96.0;
    }
    public static Rect Client(IntPtr window) { Rect rect; GetClientRect(window, out rect); return rect; }
    public static void Prepare(IntPtr window, bool activate) {
        ShowWindow(window, activate ? 5 : 4);
        Rect outer; GetWindowRect(window, out outer);
        Rect inner = Client(window);
        double scale = Scale(window);
        MoveWindow(window, 80, 80, (int)(860 * scale) + outer.Right - outer.Left - inner.Right,
            (int)(650 * scale) + outer.Bottom - outer.Top - inner.Bottom, true);
        if (activate) SetForegroundWindow(window);
    }
    public static void RequireFocus(IntPtr window) {
        if (GetForegroundWindow() != window) throw new InvalidOperationException("Benchmark window lost focus; input stopped. Target: " + Describe(window) + "; foreground: " + Describe(GetForegroundWindow()));
    }
    public static string Describe(IntPtr window) {
        uint owner; GetWindowThreadProcessId(window, out owner);
        var title = new System.Text.StringBuilder(1024); GetWindowText(window, title, title.Capacity);
        return window + " pid=" + owner + " visible=" + IsWindowVisible(window) + " title=" + title;
    }
    public static void Pointer(IntPtr window, double x, double y) {
        RequireFocus(window);
        Point point = new Point { X = (int)(x * Scale(window)), Y = (int)(y * Scale(window)) };
        ClientToScreen(window, ref point);
        if (!SetCursorPos(point.X, point.Y)) throw new InvalidOperationException("SetCursorPos failed");
    }
    static void Mouse(params Input[] inputs) {
        if (SendInput((uint)inputs.Length, inputs, Marshal.SizeOf(typeof(Input))) != inputs.Length)
            throw new InvalidOperationException("SendInput failed: " + Marshal.GetLastWin32Error());
    }
    static Input Packet(uint flags, uint data) { return new Input { Union = new InputUnion { Mouse = new MouseInput { Flags = flags, Data = data } } }; }
    public static void Click(IntPtr window, double y) {
        Pointer(window, 140, y);
        RequireFocus(window);
        Mouse(Packet(2, 0), Packet(4, 0));
    }
    public static void MessageClick(IntPtr window, double y) {
        int x = (int)(140 * Scale(window));
        int pointY = (int)(y * Scale(window));
        IntPtr position = new IntPtr((pointY << 16) | x);
        PostMessage(window, 0x200, IntPtr.Zero, position);
        PostMessage(window, 0x201, new IntPtr(1), position);
        PostMessage(window, 0x202, IntPtr.Zero, position);
    }
    public static void MessageWheel(IntPtr window, int delta) {
        Point point = new Point { X = (int)(400 * Scale(window)), Y = (int)(270 * Scale(window)) };
        ClientToScreen(window, ref point);
        PostMessage(window, 0x20A, new IntPtr(unchecked(delta << 16)), new IntPtr((point.Y << 16) | (point.X & 0xffff)));
    }
    public static void Wheel(IntPtr window, int delta) {
        RequireFocus(window);
        Mouse(Packet(0x800, unchecked((uint)delta)));
    }
    public static void Close(IntPtr window) { PostMessage(window, 0x10, IntPtr.Zero, IntPtr.Zero); }
    public static void Capture(IntPtr window, string path) {
        RequireFocus(window);
        Rect rect = Client(window);
        Point point = new Point(); ClientToScreen(window, ref point);
        using (Bitmap bitmap = new Bitmap(rect.Right, rect.Bottom)) {
            using (Graphics graphics = Graphics.FromImage(bitmap))
                graphics.CopyFromScreen(point.X, point.Y, 0, 0, bitmap.Size);
            bitmap.Save(path, ImageFormat.Png);
        }
    }
    public static void CaptureOffscreen(IntPtr window, string path) {
        Rect rect = Client(window);
        using (Bitmap bitmap = new Bitmap(rect.Right, rect.Bottom)) {
            using (Graphics graphics = Graphics.FromImage(bitmap)) {
                IntPtr device = graphics.GetHdc();
                try { if (!PrintWindow(window, device, 3)) throw new InvalidOperationException("PrintWindow failed"); }
                finally { graphics.ReleaseHdc(device); }
            }
            bitmap.Save(path, ImageFormat.Png);
        }
    }
}
