using System;
using System.Collections.Generic;
using System.Runtime.InteropServices;

// .NET Framework's UIA property registry predates FullDescription (30159).
// Read it through the public native UIA interfaces. Unused methods preserve
// the SDK vtable order; only the signatures called below are projected.
public static class NativeUiaDescriptions
{
    [ComImport, Guid("30cbe57d-d9d0-452a-ab13-7ac5ac4825ee"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    interface Automation
    {
        void CompareElements(); void CompareRuntimeIds(); void GetRootElement();
        Element ElementFromHandle(IntPtr window);
        void ElementFromPoint(); void GetFocusedElement();
        void GetRootElementBuildCache(); void ElementFromHandleBuildCache();
        void ElementFromPointBuildCache(); void GetFocusedElementBuildCache();
        void CreateTreeWalker(); void ControlViewWalker(); void ContentViewWalker();
        void RawViewWalker(); void RawViewCondition(); void ControlViewCondition();
        void ContentViewCondition(); void CreateCacheRequest();
        Condition CreateTrueCondition();
    }
    [ComImport, Guid("352ffba8-0973-437c-a61f-f64cafd81df9"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    interface Condition {}
    [ComImport, Guid("d22108aa-8ac5-49a5-837b-37bbb3d7591e"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    interface Element
    {
        void SetFocus(); void GetRuntimeId(); void FindFirst();
        Elements FindAll(int scope, Condition condition);
        void FindFirstBuildCache(); void FindAllBuildCache(); void BuildUpdatedCache();
        [return: MarshalAs(UnmanagedType.Struct)] object GetCurrentPropertyValue(int property);
    }
    [ComImport, Guid("14314595-b4bc-4055-95f2-58f2e42c9855"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    interface Elements
    {
        int Length { get; }
        Element GetElement(int index);
    }

    public static Dictionary<string, string> Read(IntPtr window)
    {
        var automation = (Automation)Activator.CreateInstance(Type.GetTypeFromCLSID(
            new Guid("ff48dba4-60ef-4201-aa87-54103eef594e")));
        Element root = null;
        Condition condition = null;
        Elements elements = null;
        try
        {
            root = automation.ElementFromHandle(window);
            condition = automation.CreateTrueCondition();
            elements = root.FindAll(7, condition); // TreeScope_Subtree
            int count = elements.Length;
            if (count > 4096) throw new InvalidOperationException("UIA description tree exceeds bound");
            var result = new Dictionary<string, string>(StringComparer.Ordinal);
            for (int i = 0; i < count; i++)
            {
                var element = elements.GetElement(i);
                try
                {
                    var id = element.GetCurrentPropertyValue(30011) as string;
                    if (!String.IsNullOrEmpty(id))
                        result.Add(id, element.GetCurrentPropertyValue(30159) as string ?? "");
                }
                finally { Marshal.ReleaseComObject(element); }
            }
            return result;
        }
        finally
        {
            if (elements != null) Marshal.ReleaseComObject(elements);
            if (condition != null) Marshal.ReleaseComObject(condition);
            if (root != null) Marshal.ReleaseComObject(root);
            Marshal.ReleaseComObject(automation);
        }
    }
}
