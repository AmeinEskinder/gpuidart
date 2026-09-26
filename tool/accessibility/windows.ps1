param(
    [Parameter(Mandatory)][int]$AppProcessId,
    [ValidateSet('query','invoke','toggle','set-value','set-range','focus')][string]$Operation = 'query',
    [string]$Name = '',
    [string]$Value = ''
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
    $matches = @($elements | Where-Object { $_.Current.Name -ceq $Name })
    if ($matches.Count -ne 1) { throw "Expected one UIA element named '$Name', got $($matches.Count)" }
    $element = $matches[0]
    switch ($Operation) {
        invoke { $element.GetCurrentPattern([System.Windows.Automation.InvokePattern]::Pattern).Invoke() }
        toggle { $element.GetCurrentPattern([System.Windows.Automation.TogglePattern]::Pattern).Toggle() }
        set-value { $element.GetCurrentPattern([System.Windows.Automation.ValuePattern]::Pattern).SetValue($Value) }
        set-range { $element.GetCurrentPattern([System.Windows.Automation.RangeValuePattern]::Pattern).SetValue([double]::Parse($Value, [Globalization.CultureInfo]::InvariantCulture)) }
        focus { $element.SetFocus() }
    }
    @{ api = 'UIAutomationClient'; operation = $Operation; accepted = $true } | ConvertTo-Json -Compress
    exit
}
$nodes = @()
foreach ($element in $elements) {
    $current = $element.Current
    $node = [ordered]@{
        name = $current.Name
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
    $nodes += $node
}
@{ api = 'UIAutomationClient'; process = $AppProcessId; nodes = $nodes } | ConvertTo-Json -Depth 8 -Compress
