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
    [DllImport("user32.dll")] static extern bool SetWindowPos(IntPtr window, IntPtr after, int x, int y, int width, int height, uint flags);
    [DllImport("user32.dll")] static extern IntPtr WindowFromPoint(Point point);
    [DllImport("user32.dll")] static extern IntPtr RealChildWindowFromPoint(IntPtr parent, Point point);
    [DllImport("user32.dll")] static extern bool ScreenToClient(IntPtr window, ref Point point);
    [DllImport("user32.dll")] static extern IntPtr GetAncestor(IntPtr window, uint flags);
    [DllImport("user32.dll")] static extern bool SetCursorPos(int x, int y);
    [DllImport("user32.dll")] static extern bool GetCursorPos(out Point point);
    [DllImport("user32.dll")] static extern int GetSystemMetrics(int index);
    [DllImport("user32.dll", SetLastError = true)] static extern uint SendInput(uint count, Input[] inputs, int size);
    [DllImport("user32.dll")] static extern bool PostMessage(IntPtr window, uint message, IntPtr wParam, IntPtr lParam);
    [DllImport("user32.dll")] static extern bool SetProcessDPIAware();
    [DllImport("user32.dll")] static extern bool PrintWindow(IntPtr window, IntPtr device, uint flags);
    [DllImport("winmm.dll")] static extern uint timeBeginPeriod(uint period);
    [DllImport("winmm.dll")] static extern uint timeEndPeriod(uint period);
    [DllImport("kernel32.dll", CharSet = CharSet.Unicode, SetLastError = true)] static extern IntPtr CreateWaitableTimerExW(IntPtr attributes, string name, uint flags, uint access);
    [DllImport("kernel32.dll", SetLastError = true)] static extern bool SetWaitableTimer(IntPtr timer, ref long dueTime, int period, IntPtr callback, IntPtr argument, bool resume);
    [DllImport("kernel32.dll")] static extern uint WaitForSingleObject(IntPtr handle, uint milliseconds);
    [DllImport("kernel32.dll")] static extern bool CloseHandle(IntPtr handle);
    [DllImport("kernel32.dll")] static extern IntPtr GetCurrentProcess();
    [DllImport("kernel32.dll")] static extern IntPtr GetCurrentThread();
    [DllImport("kernel32.dll")] static extern bool SetPriorityClass(IntPtr process, uint priorityClass);
    [DllImport("kernel32.dll")] static extern uint SetThreadExecutionState(uint flags);
    [DllImport("kernel32.dll")] static extern bool SetThreadPriority(IntPtr thread, int priority);
    [DllImport("ntdll.dll")] static extern int NtQueryTimerResolution(out uint maximum, out uint minimum, out uint current);
    static IntPtr driverTimer;
    public static int ActivationClicks { get; private set; }

    /// The system timer resolution in place while the driver runs, in 100 ns units.
    public static uint TimerResolution { get; private set; }
    public static bool ElevatedPriority { get; private set; }

    public static void Initialize() {
        SetProcessDPIAware();
        ActivationClicks = 0;
        driverTimer = CreateWaitableTimerExW(IntPtr.Zero, null, 2, 0x00100002);
        if (driverTimer == IntPtr.Zero) throw new InvalidOperationException("Cannot create high resolution driver timer: " + Marshal.GetLastWin32Error());
        timeBeginPeriod(1);
        uint maximum, minimum, current;
        TimerResolution = NtQueryTimerResolution(out maximum, out minimum, out current) == 0 ? current : 0;
        // The driver competes with the fixture for the CPU; a higher class keeps
        // its one-millisecond wakeups from landing behind the fixture's frames.
        ElevatedPriority = SetPriorityClass(GetCurrentProcess(), 0x80) && SetThreadPriority(GetCurrentThread(), 2);
        // A foreground run needs the display: injected input does not count as
        // user presence, so an unattended machine would turn its display off
        // and lock mid-run. Held for the run, released in Finish.
        SetThreadExecutionState(0x80000003);
    }
    public static void Finish() {
        SetThreadExecutionState(0x80000000);
        SetThreadPriority(GetCurrentThread(), 0);
        SetPriorityClass(GetCurrentProcess(), 0x20);
        timeEndPeriod(1);
        if (driverTimer != IntPtr.Zero) CloseHandle(driverTimer);
        driverTimer = IntPtr.Zero;
    }
    /// Pays the first-call costs of the input path before the measured window:
    /// a zero-length pointer move through SendInput and one timer wait.
    public static void Warm() {
        Mouse(Packet(0x0001, 0));
        Pause();
    }
    public static void Pause() {
        long dueTime = -10000; // Relative time in 100 ns units: one millisecond.
        if (!SetWaitableTimer(driverTimer, ref dueTime, 0, IntPtr.Zero, IntPtr.Zero, false) || WaitForSingleObject(driverTimer, 2000) != 0)
            throw new InvalidOperationException("Driver timer wait failed");
    }
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
        if (activate && GetForegroundWindow() != window) {
            SetForegroundWindow(window);
            if (GetForegroundWindow() != window) {
                // Temporarily expose only our own window so activation cannot click another app.
                if (!SetWindowPos(window, new IntPtr(-1), 0, 0, 0, 0, 0x13)) throw new InvalidOperationException("Cannot expose benchmark window for activation");
                try {
                    Point point = new Point { X = (int)(800 * scale), Y = (int)(600 * scale) };
                    ClientToScreen(window, ref point);
                    IntPtr covering = GetAncestor(WindowFromPoint(point), 2);
                    if (covering != window) throw new InvalidOperationException("Benchmark activation point is occluded; no click sent. Covering: " + Describe(covering));
                    if (!SetCursorPos(point.X, point.Y)) throw new InvalidOperationException("Cannot position benchmark activation click");
                    Mouse(Packet(2, 0), Packet(4, 0));
                    ActivationClicks++;
                } finally {
                    SetWindowPos(window, new IntPtr(-2), 0, 0, 0, 0, 0x13);
                }
            }
        }
    }
    public static void RequireFocus(IntPtr window) {
        if (GetForegroundWindow() != window) throw new InvalidOperationException("Benchmark window lost focus; input stopped. Target: " + Describe(window) + "; foreground: " + Describe(GetForegroundWindow()));
    }
    public static string Describe(IntPtr window) {
        uint owner; GetWindowThreadProcessId(window, out owner);
        var title = new System.Text.StringBuilder(1024); GetWindowText(window, title, title.Capacity);
        return window + " pid=" + owner + " visible=" + IsWindowVisible(window) + " title=" + title;
    }
    static Point placed;
    public static void Pointer(IntPtr window, double x, double y) {
        RequireFocus(window);
        Point point = new Point { X = (int)(x * Scale(window)), Y = (int)(y * Scale(window)) };
        ClientToScreen(window, ref point);
        // A cursor already at the point stays: moving it again costs up to
        // 17 ms on this machine in one click of twenty, which the input
        // timestamp taken before it would charge to the fixture.
        Point now;
        if (GetCursorPos(out now) && now.X == point.X && now.Y == point.Y) { placed = point; return; }
        if (!SetCursorPos(point.X, point.Y)) throw new InvalidOperationException("SetCursorPos failed");
        placed = point;
    }
    /// Windows routes wheel input to the window under the cursor, so a pointer
    /// moved by someone at the machine sends the injected events elsewhere or
    /// off the table while the focus check still passes. A traced run showed
    /// exactly that: stop the run rather than record the drift as the fixture's.
    public static void RequirePointer() {
        Point now;
        if (!GetCursorPos(out now)) throw new InvalidOperationException("GetCursorPos failed");
        if (Math.Abs(now.X - placed.X) > 2 || Math.Abs(now.Y - placed.Y) > 2)
            throw new InvalidOperationException("Benchmark pointer moved; input stopped. Placed at " + placed.X + "," + placed.Y + "; now at " + now.X + "," + now.Y);
    }
    static uint Mouse(params Input[] inputs) {
        uint accepted = SendInput((uint)inputs.Length, inputs, Marshal.SizeOf(typeof(Input)));
        if (accepted != inputs.Length)
            throw new InvalidOperationException("SendInput failed: " + Marshal.GetLastWin32Error());
        return accepted;
    }
    static Input Packet(uint flags, uint data, uint sequence = 0) {
        return new Input { Union = new InputUnion { Mouse = new MouseInput {
            Flags = flags, Data = data, Extra = sequence == 0 ? UIntPtr.Zero : new UIntPtr(0x47500000UL | sequence)
        } } };
    }
    public static uint Click(IntPtr window, double y, uint sequence = 0) {
        Pointer(window, 140, y);
        RequireFocus(window);
        return Mouse(Packet(2, 0, sequence), Packet(4, 0, sequence));
    }
    /// An injected pointer move to a client point, through the input queue
    /// like a user's, so the fixture sees a hover it may repaint for.
    public static void Hover(IntPtr window, double x, double y) {
        RequireFocus(window);
        Point point = new Point { X = (int)(x * Scale(window)), Y = (int)(y * Scale(window)) };
        ClientToScreen(window, ref point);
        int width = GetSystemMetrics(0), height = GetSystemMetrics(1);
        Input move = Packet(0x8001, 0);
        move.Union.Mouse.X = (int)Math.Round(point.X * 65535.0 / (width - 1));
        move.Union.Mouse.Y = (int)Math.Round(point.Y * 65535.0 / (height - 1));
        Mouse(move);
    }
    // Posted messages go to the window that owns the pixels: Flutter hosts its
    // content in a child view, GPUI windows have no children. The point is
    // rewritten into the target's client coordinates.
    static IntPtr MessageTarget(IntPtr window, ref Point client) {
        IntPtr child = RealChildWindowFromPoint(window, client);
        if (child == IntPtr.Zero || child == window) return window;
        Point screen = client;
        ClientToScreen(window, ref screen);
        ScreenToClient(child, ref screen);
        client = screen;
        return child;
    }
    public static void MessageClick(IntPtr window, double y) {
        Point point = new Point { X = (int)(140 * Scale(window)), Y = (int)(y * Scale(window)) };
        IntPtr target = MessageTarget(window, ref point);
        IntPtr position = new IntPtr((point.Y << 16) | (point.X & 0xffff));
        PostMessage(target, 0x200, IntPtr.Zero, position);
        PostMessage(target, 0x201, new IntPtr(1), position);
        PostMessage(target, 0x202, IntPtr.Zero, position);
    }
    public static void MessageWheel(IntPtr window, int delta) {
        Point point = new Point { X = (int)(400 * Scale(window)), Y = (int)(270 * Scale(window)) };
        IntPtr target = MessageTarget(window, ref point);
        ClientToScreen(target, ref point);
        PostMessage(target, 0x20A, new IntPtr(unchecked(delta << 16)), new IntPtr((point.Y << 16) | (point.X & 0xffff)));
    }
    public static uint Wheel(IntPtr window, int delta, uint sequence = 0) {
        RequireFocus(window);
        RequirePointer();
        return Mouse(Packet(0x800, unchecked((uint)delta), sequence));
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
    /// Milliseconds on [since] when the window's client area first shows more
    /// than one color through PrintWindow, polled every five milliseconds; -1
    /// on timeout. A proxy for the first presented frame that needs no ETW
    /// access: it observes the composited content, not the swap chain.
    public static double FirstContent(IntPtr window, Stopwatch since, int timeoutMs) {
        while (since.ElapsedMilliseconds < timeoutMs) {
            Rect rect = Client(window);
            if (rect.Right > 0 && rect.Bottom > 0) {
                using (Bitmap bitmap = new Bitmap(rect.Right, rect.Bottom)) {
                    bool printed;
                    using (Graphics graphics = Graphics.FromImage(bitmap)) {
                        IntPtr device = graphics.GetHdc();
                        try { printed = PrintWindow(window, device, 3); }
                        finally { graphics.ReleaseHdc(device); }
                    }
                    if (printed && HasContent(bitmap)) return since.Elapsed.TotalMilliseconds;
                }
            }
            System.Threading.Thread.Sleep(5);
        }
        return -1;
    }
    static bool HasContent(Bitmap bitmap) {
        int step = Math.Max(1, Math.Min(bitmap.Width, bitmap.Height) / 64);
        Color first = bitmap.GetPixel(0, 0);
        int differing = 0, sampled = 0;
        for (int y = 0; y < bitmap.Height; y += step)
            for (int x = 0; x < bitmap.Width; x += step) {
                sampled++;
                Color pixel = bitmap.GetPixel(x, y);
                if (Math.Abs(pixel.R - first.R) + Math.Abs(pixel.G - first.G) + Math.Abs(pixel.B - first.B) > 24) differing++;
            }
        return sampled > 0 && differing * 100 > sampled;
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
