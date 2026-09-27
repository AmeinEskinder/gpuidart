param(
    [Parameter(Mandatory)][int]$AppProcessId,
    [ValidateSet('query','invoke','toggle','set-value','set-range','focus','select','hover','invoke-menu')][string]$Operation = 'query',
    [string]$Name = '',
    [string]$Value = '',
    [string]$Id = ''
)
$ErrorActionPreference = 'Stop'
[Console]::OutputEncoding = New-Object System.Text.UTF8Encoding($false)
Add-Type -AssemblyName UIAutomationClient, UIAutomationTypes
$condition = New-Object System.Windows.Automation.PropertyCondition([System.Windows.Automation.AutomationElement]::ProcessIdProperty, $AppProcessId)
$window = [System.Windows.Automation.AutomationElement]::RootElement.FindFirst([System.Windows.Automation.TreeScope]::Children, $condition)
if ($null -eq $window) { throw "No UIA window for process $AppProcessId" }
$elements = $window.FindAll([System.Windows.Automation.TreeScope]::Subtree, [System.Windows.Automation.Condition]::TrueCondition)
if ($elements.Count -gt 4096) { throw "UIA tree exceeds probe bound: $($elements.Count)" }
if ($Operation -ne 'query') {
    $matches = @($elements | Where-Object { if ($Id) { $_.Current.AutomationId -ceq $Id } else { $_.Current.Name -ceq $Name } })
    if ($Operation -eq 'invoke-menu') { $matches = @($matches | Where-Object { $_.Current.ControlType -eq [System.Windows.Automation.ControlType]::MenuItem }) }
    if ($matches.Count -ne 1) { throw "Expected one UIA element named '$Name', got $($matches.Count)" }
    $element = $matches[0]
    $details = @{}
    switch ($Operation) {
        invoke-menu { $element.GetCurrentPattern([System.Windows.Automation.InvokePattern]::Pattern).Invoke() }
        hover {
            Add-Type -TypeDefinition 'using System; using System.Runtime.InteropServices; public static class TerminalPointer { [DllImport("user32.dll")] public static extern bool SetPhysicalCursorPos(int x, int y); [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr h); }'
            $bounds = $element.Current.BoundingRectangle
            $details.bounds = @($bounds.X, $bounds.Y, $bounds.Width, $bounds.Height)
            if ($bounds.IsEmpty -or $bounds.Width -le 0 -or $bounds.Height -le 0) { throw 'Hover target has no bounds' }
            [void][TerminalPointer]::SetForegroundWindow([IntPtr]$window.Current.NativeWindowHandle)
            if (-not [TerminalPointer]::SetPhysicalCursorPos([int]($bounds.X + $bounds.Width / 2), [int]($bounds.Y + $bounds.Height / 2))) { throw 'Pointer move failed' }
        }
        invoke { $element.GetCurrentPattern([System.Windows.Automation.InvokePattern]::Pattern).Invoke() }
        toggle { $element.GetCurrentPattern([System.Windows.Automation.TogglePattern]::Pattern).Toggle() }
        set-value { $element.GetCurrentPattern([System.Windows.Automation.ValuePattern]::Pattern).SetValue($Value) }
        set-range { $element.GetCurrentPattern([System.Windows.Automation.RangeValuePattern]::Pattern).SetValue([double]::Parse($Value, [Globalization.CultureInfo]::InvariantCulture)) }
        focus { $element.SetFocus() }
        select { $element.GetCurrentPattern([System.Windows.Automation.SelectionItemPattern]::Pattern).Select() }
    }
    @{ api = 'UIAutomationClient'; operation = $Operation; accepted = $true; details = $details } | ConvertTo-Json -Compress
    exit
}
Add-Type -Path (Join-Path $PSScriptRoot 'windows_description.cs')
$descriptions = [NativeUiaDescriptions]::Read([IntPtr]$window.Current.NativeWindowHandle)
$nodes = @()
foreach ($element in $elements) {
    $current = $element.Current
    $node = [ordered]@{
        name = $current.Name
        description = $(if ($current.AutomationId) { $descriptions[$current.AutomationId] } else { '' })
        help = $current.HelpText
        role = $current.ControlType.ProgrammaticName
        id = $current.AutomationId
        enabled = $current.IsEnabled
        focused = $current.HasKeyboardFocus
        focusable = $current.IsKeyboardFocusable
        offscreen = $current.IsOffscreen
        patterns = @($element.GetSupportedPatterns() | ForEach-Object ProgrammaticName)
    }
    $pattern = $null
    if ($element.TryGetCurrentPattern([System.Windows.Automation.TogglePattern]::Pattern, [ref]$pattern)) { $node.checked = $pattern.Current.ToggleState.ToString() }
    $pattern = $null
    if ($element.TryGetCurrentPattern([System.Windows.Automation.ValuePattern]::Pattern, [ref]$pattern)) { $node.value = $pattern.Current.Value; $node.read_only = $pattern.Current.IsReadOnly }
    $pattern = $null
    if ($element.TryGetCurrentPattern([System.Windows.Automation.RangeValuePattern]::Pattern, [ref]$pattern)) {
        $node.number = $pattern.Current.Value
        $node.min = $pattern.Current.Minimum
        $node.max = $pattern.Current.Maximum
        $node.step = $pattern.Current.SmallChange
        $node.read_only = $pattern.Current.IsReadOnly
    }
    $pattern = $null
    if ($element.TryGetCurrentPattern([System.Windows.Automation.ExpandCollapsePattern]::Pattern, [ref]$pattern)) { $node.expanded = $pattern.Current.ExpandCollapseState.ToString() }
    $pattern = $null
    if ($element.TryGetCurrentPattern([System.Windows.Automation.WindowPattern]::Pattern, [ref]$pattern)) { $node.modal = $pattern.Current.IsModal }
    $pattern = $null
    if ($element.TryGetCurrentPattern([System.Windows.Automation.SelectionItemPattern]::Pattern, [ref]$pattern)) { $node.selected = $pattern.Current.IsSelected }
    $pattern = $null
    if ($element.TryGetCurrentPattern([System.Windows.Automation.GridPattern]::Pattern, [ref]$pattern)) { $node.rows = $pattern.Current.RowCount; $node.columns = $pattern.Current.ColumnCount }
    $pattern = $null
    if ($element.TryGetCurrentPattern([System.Windows.Automation.GridItemPattern]::Pattern, [ref]$pattern)) { $node.row = $pattern.Current.Row; $node.column = $pattern.Current.Column }
    $nodes += $node
}
@{ api = 'UIAutomationClient'; process = $AppProcessId; nodes = $nodes } | ConvertTo-Json -Depth 8 -Compress
