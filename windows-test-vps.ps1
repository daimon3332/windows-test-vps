Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$script:WorkspaceRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$script:ResultsDirectory = Join-Path $script:WorkspaceRoot 'Results'
$script:CommandCache = @{}
$script:ToolDefinitions = @{
    tcping = @{
        DisplayName = 'tcping'
        Candidates  = @('tcping.exe', 'tcping')
    }
    ping = @{
        DisplayName = 'ping'
        Candidates  = @('ping.exe', 'ping')
    }
    iperf3 = @{
        DisplayName = 'iperf3'
        Candidates  = @('iperf3.exe', 'iperf3')
    }
    nexttrace = @{
        DisplayName = 'nexttrace'
        Candidates  = @('nexttrace.exe', 'nexttrace')
    }
}
$script:OneClickItems = [ordered]@{
    '1' = 'TCP延迟'
    '2' = 'Ping延迟'
    '3' = 'iperf3测速'
    '4' = '出国路由'
}

function Initialize-Console {
    try {
        $utf8 = [System.Text.UTF8Encoding]::new($false)
        [Console]::InputEncoding = $utf8
        [Console]::OutputEncoding = $utf8
        $global:OutputEncoding = $utf8
    }
    catch {
    }
}

function Test-InteractiveConsole {
    return -not [Console]::IsInputRedirected -and -not [Console]::IsOutputRedirected
}

function Write-Line {
    param(
        [string]$Text = '',
        [ConsoleColor]$Color = [ConsoleColor]::Gray
    )

    Write-Host $Text -ForegroundColor $Color
}

function Write-Separator {
    param(
        [int]$Length = 30,
        [ConsoleColor]$Color = [ConsoleColor]::DarkCyan
    )

    Write-Line ('-' * $Length) $Color
}

function Show-Banner {
    Clear-Host
    Write-Line 'Windows VPS 测试工具箱' Yellow
    Write-Separator 30
}

function Show-MainMenu {
    Write-Line '1.  一键测试' Cyan
    Write-Line '2.  TCP测试' Cyan
    Write-Line '3.  Ping测试' Cyan
    Write-Line '4.  iperf3速度测试' Cyan
    Write-Line '5.  出国路由查看' Cyan
    Write-Line '0.  退出脚本' Cyan
    Write-Separator 30
}

function Update-EditableLine {
    param(
        [string]$Prompt,
        [System.Collections.Generic.List[char]]$Buffer,
        [int]$CursorIndex,
        [int]$StartLeft,
        [int]$StartTop,
        [ref]$RenderedLength
    )

    $text = -join $Buffer.ToArray()
    $fullText = $Prompt + $text
    $bufferWidth = [Math]::Max([Console]::BufferWidth, 1)

    [Console]::SetCursorPosition($StartLeft, $StartTop)

    if ($RenderedLength.Value -gt 0) {
        [Console]::Write(' ' * $RenderedLength.Value)
        [Console]::SetCursorPosition($StartLeft, $StartTop)
    }

    [Console]::Write($fullText)
    $RenderedLength.Value = $fullText.Length

    $absoluteIndex = $StartLeft + $Prompt.Length + $CursorIndex
    $cursorLeft = $absoluteIndex % $bufferWidth
    $cursorTop = $StartTop + [Math]::Floor($absoluteIndex / $bufferWidth)
    [Console]::SetCursorPosition($cursorLeft, $cursorTop)
}

function Read-EditableInput {
    param(
        [string]$Prompt,
        [string]$DefaultValue = ''
    )

    if (-not (Test-InteractiveConsole)) {
        $response = Read-Host $Prompt.Trim()
        if ([string]::IsNullOrWhiteSpace($response)) {
            return $DefaultValue
        }

        return $response.Trim()
    }

    $buffer = [System.Collections.Generic.List[char]]::new()
    foreach ($char in $DefaultValue.ToCharArray()) {
        [void]$buffer.Add($char)
    }

    $cursorIndex = $buffer.Count
    $startLeft = [Console]::CursorLeft
    $startTop = [Console]::CursorTop
    $renderedLength = 0

    Update-EditableLine -Prompt $Prompt -Buffer $buffer -CursorIndex $cursorIndex -StartLeft $startLeft -StartTop $startTop -RenderedLength ([ref]$renderedLength)

    while ($true) {
        $key = [Console]::ReadKey($true)

        switch ($key.Key) {
            'Enter' {
                $absoluteEnd = $startLeft + $Prompt.Length + $buffer.Count
                $bufferWidth = [Math]::Max([Console]::BufferWidth, 1)
                $endLeft = $absoluteEnd % $bufferWidth
                $endTop = $startTop + [Math]::Floor($absoluteEnd / $bufferWidth)
                [Console]::SetCursorPosition($endLeft, $endTop)
                [Console]::WriteLine()
                return (-join $buffer.ToArray()).Trim()
            }
            'LeftArrow' {
                if ($cursorIndex -gt 0) {
                    $cursorIndex--
                    Update-EditableLine -Prompt $Prompt -Buffer $buffer -CursorIndex $cursorIndex -StartLeft $startLeft -StartTop $startTop -RenderedLength ([ref]$renderedLength)
                }
            }
            'RightArrow' {
                if ($cursorIndex -lt $buffer.Count) {
                    $cursorIndex++
                    Update-EditableLine -Prompt $Prompt -Buffer $buffer -CursorIndex $cursorIndex -StartLeft $startLeft -StartTop $startTop -RenderedLength ([ref]$renderedLength)
                }
            }
            'Home' {
                $cursorIndex = 0
                Update-EditableLine -Prompt $Prompt -Buffer $buffer -CursorIndex $cursorIndex -StartLeft $startLeft -StartTop $startTop -RenderedLength ([ref]$renderedLength)
            }
            'End' {
                $cursorIndex = $buffer.Count
                Update-EditableLine -Prompt $Prompt -Buffer $buffer -CursorIndex $cursorIndex -StartLeft $startLeft -StartTop $startTop -RenderedLength ([ref]$renderedLength)
            }
            'Backspace' {
                if ($cursorIndex -gt 0) {
                    $buffer.RemoveAt($cursorIndex - 1)
                    $cursorIndex--
                    Update-EditableLine -Prompt $Prompt -Buffer $buffer -CursorIndex $cursorIndex -StartLeft $startLeft -StartTop $startTop -RenderedLength ([ref]$renderedLength)
                }
            }
            'Delete' {
                if ($cursorIndex -lt $buffer.Count) {
                    $buffer.RemoveAt($cursorIndex)
                    Update-EditableLine -Prompt $Prompt -Buffer $buffer -CursorIndex $cursorIndex -StartLeft $startLeft -StartTop $startTop -RenderedLength ([ref]$renderedLength)
                }
            }
            default {
                if (-not [char]::IsControl($key.KeyChar)) {
                    $buffer.Insert($cursorIndex, $key.KeyChar)
                    $cursorIndex++
                    Update-EditableLine -Prompt $Prompt -Buffer $buffer -CursorIndex $cursorIndex -StartLeft $startLeft -StartTop $startTop -RenderedLength ([ref]$renderedLength)
                }
            }
        }
    }
}

function Read-TargetIp {
    while ($true) {
        $target = (Read-Host '请输入目标 IP 地址（支持 IPv4 / IPv6）').Trim()

        if ([string]::IsNullOrWhiteSpace($target)) {
            Write-Line 'IP 不能为空。' Red
            continue
        }

        $parsed = $null
        if ([System.Net.IPAddress]::TryParse($target, [ref]$parsed)) {
            return $target
        }

        Write-Line 'IP 格式无效，请重新输入。' Red
    }
}

function Get-IpVersionSwitch {
    param([string]$TargetIp)

    $parsed = [System.Net.IPAddress]::Parse($TargetIp)
    if ($parsed.AddressFamily -eq [System.Net.Sockets.AddressFamily]::InterNetworkV6) {
        return '-6'
    }

    return '-4'
}

function Read-TcpPort {
    while ($true) {
        Write-Line '请输入 TCP 端口，直接回车使用默认值 22。' DarkYellow
        $portText = Read-EditableInput -Prompt '> ' -DefaultValue '22'

        if ([string]::IsNullOrWhiteSpace($portText)) {
            Write-Line '端口不能为空。' Red
            continue
        }

        $port = 0
        if ([int]::TryParse($portText, [ref]$port) -and $port -ge 1 -and $port -le 65535) {
            return $port
        }

        Write-Line '端口必须是 1-65535 的整数。' Red
    }
}

function Parse-SelectionInput {
    param([string]$RawInput)

    $validKeys = $script:OneClickItems.Keys
    $ordered = [System.Collections.Generic.List[string]]::new()

    foreach ($item in ($RawInput -split '[,\s，]+' | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })) {
        $value = $item.Trim()
        if ($validKeys -contains $value -and -not $ordered.Contains($value)) {
            $ordered.Add($value)
        }
    }

    return $ordered.ToArray()
}

function Read-OneClickSelections {
    while ($true) {
        Write-Line '默认测试项目：' DarkYellow
        foreach ($item in $script:OneClickItems.GetEnumerator()) {
            Write-Line ("{0}.  {1}" -f $item.Key, $item.Value) Cyan
        }

        Write-Line '请确认/修改要执行的测试编号（默认全选，可直接删除或改写）。' DarkYellow
        $selectionText = Read-EditableInput -Prompt '> ' -DefaultValue '1 2 3 4'
        $selections = Parse-SelectionInput -RawInput $selectionText

        if ($selections.Count -gt 0) {
            return $selections
        }

        Write-Line '至少需要保留一个测试编号。' Red
    }
}

function Get-ToolPath {
    param([string]$ToolName)

    if ($script:CommandCache.ContainsKey($ToolName)) {
        return $script:CommandCache[$ToolName]
    }

    $definition = $script:ToolDefinitions[$ToolName]
    foreach ($candidate in $definition.Candidates) {
        $command = Get-Command $candidate -ErrorAction SilentlyContinue | Where-Object { $_.CommandType -eq 'Application' } | Select-Object -First 1
        if ($null -ne $command) {
            $script:CommandCache[$ToolName] = $command.Source
            return $command.Source
        }
    }

    $script:CommandCache[$ToolName] = $null
    return $null
}

function Write-SectionHeader {
    param([string]$Title)

    $line = ('=' * 10) + " $Title " + ('=' * 10)
    Write-Line ''
    Write-Line $line Cyan
}

function Format-CommandText {
    param(
        [string]$CommandPath,
        [string[]]$Arguments
    )

    $parts = @($CommandPath) + $Arguments
    return ($parts | ForEach-Object {
        if ($_ -match '\s') { '"{0}"' -f $_ } else { $_ }
    }) -join ' '
}

function Remove-AnsiEscape {
    param([string]$Text)

    if ($null -eq $Text) {
        return ''
    }

    $escape = [char]27
    $cleanText = $Text -replace "$escape\[[0-?]*[ -/]*[@-~]", ''
    $cleanText = $cleanText -replace "$escape\][^\a]*($escape\\|\a)", ''
    return $cleanText
}

function Invoke-ExternalCommand {
    param(
        [string]$CommandPath,
        [string[]]$Arguments,
        [string]$SectionTitle
    )

    Write-SectionHeader -Title $SectionTitle

    $commandText = Format-CommandText -CommandPath $CommandPath -Arguments $Arguments
    Write-Line ("Command: {0}" -f $commandText) DarkYellow

    $outputLines = [System.Collections.Generic.List[string]]::new()

    & $CommandPath @Arguments 2>&1 | ForEach-Object {
        $line = $_.ToString()
        $outputLines.Add((Remove-AnsiEscape -Text $line))
        Write-Host $line
    }

    $exitCode = 0
    if ($null -ne $LASTEXITCODE) {
        $exitCode = $LASTEXITCODE
    }

    return [pscustomobject]@{
        Title     = $SectionTitle
        Command   = $commandText
        ExitCode  = $exitCode
        Output    = $outputLines.ToArray()
    }
}

function Write-MissingTool {
    param([string]$ToolName)

    $message = "未找到 $ToolName，请先安装并确保已加入 PATH。"
    Write-Line $message Red
    return $message
}

function New-ResultRecord {
    param(
        [string]$Kind,
        [string]$Name,
        [string]$Command = '',
        [string[]]$Output = @(),
        [int]$ExitCode = 0,
        [string]$Status = 'success',
        [object]$Summary = $null,
        [hashtable]$Meta = @{}
    )

    if ($null -eq $Meta) {
        $Meta = @{}
    }

    return [pscustomobject]@{
        Kind    = $Kind
        Name    = $Name
        Command = $Command
        Output  = @($Output)
        ExitCode = $ExitCode
        Status  = $Status
        Summary = $Summary
        Meta    = $Meta
    }
}

function Format-SuccessRate {
    param(
        [int]$Sent,
        [int]$Successful
    )

    if ($Sent -le 0) {
        return '-'
    }

    return ('{0:0.00}%' -f (($Successful / $Sent) * 100))
}

function Get-SectionStatusFromSummary {
    param([object]$Summary)

    if ($null -eq $Summary) {
        return 'failed'
    }

    if ($Summary.Success -gt 0 -and $Summary.Failed -eq 0) {
        return 'success'
    }

    if ($Summary.Success -gt 0) {
        return 'partial'
    }

    return 'failed'
}

function Parse-TcpingSummary {
    param([string[]]$Output)

    $sent = $null
    $successful = $null
    $failed = $null
    $minimum = $null
    $maximum = $null
    $average = $null

    foreach ($line in $Output) {
        if ($line -match '^\s*(\d+)\s+probes sent\.') {
            $sent = [int]$matches[1]
            continue
        }

        if ($line -match '^\s*(\d+)\s+successful,\s+(\d+)\s+failed\.\s+\(([\d.]+)%\s+fail\)') {
            $successful = [int]$matches[1]
            $failed = [int]$matches[2]
            continue
        }

        if ($line -match '^\s*Minimum\s*=\s*([0-9.]+ms),\s*Maximum\s*=\s*([0-9.]+ms),\s*Average\s*=\s*([0-9.]+ms)') {
            $minimum = $matches[1]
            $maximum = $matches[2]
            $average = $matches[3]
        }
    }

    if ($null -eq $sent -and $null -eq $successful -and $null -eq $minimum) {
        return $null
    }

    return [pscustomobject]@{
        Sent        = if ($null -ne $sent) { $sent } else { 0 }
        Success     = if ($null -ne $successful) { $successful } else { 0 }
        Failed      = if ($null -ne $failed) { $failed } else { 0 }
        SuccessRate = if ($null -ne $sent -and $null -ne $successful) { Format-SuccessRate -Sent $sent -Successful $successful } else { '-' }
        Minimum     = if ($minimum) { $minimum } else { '-' }
        Maximum     = if ($maximum) { $maximum } else { '-' }
        Average     = if ($average) { $average } else { '-' }
    }
}

function Parse-PingSummary {
    param([string[]]$Output)

    $sent = $null
    $received = $null
    $lost = $null
    $minimum = $null
    $maximum = $null
    $average = $null

    foreach ($line in $Output) {
        if ($line -match '^\s*Packets:\s*Sent\s*=\s*(\d+),\s*Received\s*=\s*(\d+),\s*Lost\s*=\s*(\d+)\s+\(([\d.]+)%\s*loss\),?') {
            $sent = [int]$matches[1]
            $received = [int]$matches[2]
            $lost = [int]$matches[3]
            continue
        }

        if ($line -match '^\s*Minimum\s*=\s*([0-9.]+ms),\s*Maximum\s*=\s*([0-9.]+ms),\s*Average\s*=\s*([0-9.]+ms)') {
            $minimum = $matches[1]
            $maximum = $matches[2]
            $average = $matches[3]
        }
    }

    if ($null -eq $sent -and $null -eq $received -and $null -eq $minimum) {
        return $null
    }

    return [pscustomobject]@{
        Sent        = if ($null -ne $sent) { $sent } else { 0 }
        Success     = if ($null -ne $received) { $received } else { 0 }
        Failed      = if ($null -ne $lost) { $lost } else { 0 }
        SuccessRate = if ($null -ne $sent -and $null -ne $received) { Format-SuccessRate -Sent $sent -Successful $received } else { '-' }
        Minimum     = if ($minimum) { $minimum } else { '-' }
        Maximum     = if ($maximum) { $maximum } else { '-' }
        Average     = if ($average) { $average } else { '-' }
    }
}

function Parse-Iperf3EndpointLine {
    param([string]$Line)

    if ($Line -match '^\[(?<stream>[^\]]+)\]\s+(?<interval>\S+\s+sec)\s+(?<transfer>[0-9.]+\s+[KMGT]?Bytes)\s+(?<bitrate>[0-9.]+\s+[KMGT]?bits/sec)(?:\s+\d+)?\s+(?<role>sender|receiver)\s*$') {
        return [pscustomobject]@{
            Stream   = $matches.stream.Trim()
            Interval = $matches.interval
            Transfer = $matches.transfer
            Bitrate  = $matches.bitrate
            Role     = $matches.role
        }
    }

    return $null
}

function Parse-Iperf3Summary {
    param(
        [string[]]$Output,
        [switch]$UseSum
    )

    $summaryLines = $Output | Where-Object { $_ -match '\b(sender|receiver)\s*$' }
    if ($UseSum) {
        $summaryLines = $summaryLines | Where-Object { $_ -match '^\[SUM\]' }
    }
    else {
        $summaryLines = $summaryLines | Where-Object { $_ -notmatch '^\[SUM\]' }
    }

    $senderLine = $summaryLines | Where-Object { $_ -match '\bsender\s*$' } | Select-Object -Last 1
    $receiverLine = $summaryLines | Where-Object { $_ -match '\breceiver\s*$' } | Select-Object -Last 1

    if (-not $senderLine -and -not $receiverLine) {
        return $null
    }

    $sender = $null
    $receiver = $null

    if ($senderLine) {
        $sender = Parse-Iperf3EndpointLine -Line $senderLine
    }

    if ($receiverLine) {
        $receiver = Parse-Iperf3EndpointLine -Line $receiverLine
    }

    return [pscustomobject]@{
        SenderTransfer   = if ($sender) { $sender.Transfer } else { '-' }
        SenderBitrate    = if ($sender) { $sender.Bitrate } else { '-' }
        ReceiverTransfer = if ($receiver) { $receiver.Transfer } else { '-' }
        ReceiverBitrate  = if ($receiver) { $receiver.Bitrate } else { '-' }
    }
}

function Escape-MarkdownCell {
    param([string]$Text)

    if ($null -eq $Text) {
        return ''
    }

    return ($Text -replace '\|', '\|')
}

function Add-MarkdownLine {
    param(
        [System.Collections.Generic.List[string]]$Lines,
        [string]$Text = ''
    )

    [void]$Lines.Add($Text)
}

function Add-MarkdownDetailsBlock {
    param(
        [System.Collections.Generic.List[string]]$Lines,
        [string]$Summary,
        [string[]]$Output
    )

    Add-MarkdownLine -Lines $Lines -Text '<details>'
    Add-MarkdownLine -Lines $Lines -Text ("<summary>{0}</summary>" -f $Summary)
    Add-MarkdownLine -Lines $Lines
    Add-MarkdownLine -Lines $Lines -Text '```text'

    foreach ($line in $Output) {
        Add-MarkdownLine -Lines $Lines -Text $line
    }

    Add-MarkdownLine -Lines $Lines -Text '```'
    Add-MarkdownLine -Lines $Lines
    Add-MarkdownLine -Lines $Lines -Text '</details>'
    Add-MarkdownLine -Lines $Lines
}

function Get-SectionStatusLabel {
    param([string]$Status)

    switch ($Status) {
        'success' { return '成功' }
        'partial' { return '部分成功' }
        'terminated' { return '已终止' }
        default { return '失败' }
    }
}

function Get-OverviewText {
    param([object]$Section)

    if ($null -eq $Section.Summary) {
        if ($Section.Output.Count -gt 0) {
            return ($Section.Output[0])
        }

        return '-'
    }

    switch ($Section.Kind) {
        'tcp' { return ("平均 {0}，成功率 {1}" -f $Section.Summary.Average, $Section.Summary.SuccessRate) }
        'ping' { return ("平均 {0}，成功率 {1}" -f $Section.Summary.Average, $Section.Summary.SuccessRate) }
        'iperf3' { return ("Sender {0} / Receiver {1}" -f $Section.Summary.SenderBitrate, $Section.Summary.ReceiverBitrate) }
        'route' { return '完整路由见下方明细' }
        'portcheck' { return ("成功率 {0}，平均 {1}" -f $Section.Summary.SuccessRate, $Section.Summary.Average) }
        default { return '-' }
    }
}

function Render-LatencySection {
    param(
        [System.Collections.Generic.List[string]]$Lines,
        [object]$Section
    )

    Add-MarkdownLine -Lines $Lines -Text ("## {0}" -f $Section.Name)
    Add-MarkdownLine -Lines $Lines

    if ($null -eq $Section.Summary) {
        Add-MarkdownLine -Lines $Lines -Text ("> 状态：{0}" -f (Get-SectionStatusLabel -Status $Section.Status))
        Add-MarkdownLine -Lines $Lines
    }
    else {
        Add-MarkdownLine -Lines $Lines -Text '| 指标 | 数值 |'
        Add-MarkdownLine -Lines $Lines -Text '|---|---|'
        Add-MarkdownLine -Lines $Lines -Text ('| 探测次数 | {0} |' -f (Escape-MarkdownCell $Section.Summary.Sent))
        Add-MarkdownLine -Lines $Lines -Text ('| 成功次数 | {0} |' -f (Escape-MarkdownCell $Section.Summary.Success))
        Add-MarkdownLine -Lines $Lines -Text ('| 失败次数 | {0} |' -f (Escape-MarkdownCell $Section.Summary.Failed))
        Add-MarkdownLine -Lines $Lines -Text ('| 成功率 | {0} |' -f (Escape-MarkdownCell $Section.Summary.SuccessRate))
        Add-MarkdownLine -Lines $Lines -Text ('| 最小延迟 | {0} |' -f (Escape-MarkdownCell $Section.Summary.Minimum))
        Add-MarkdownLine -Lines $Lines -Text ('| 最大延迟 | {0} |' -f (Escape-MarkdownCell $Section.Summary.Maximum))
        Add-MarkdownLine -Lines $Lines -Text ('| 平均延迟 | {0} |' -f (Escape-MarkdownCell $Section.Summary.Average))
        Add-MarkdownLine -Lines $Lines
    }

    if ($Section.Command) {
        Add-MarkdownLine -Lines $Lines -Text ('- 测试命令：`{0}`' -f (Escape-MarkdownCell $Section.Command))
        Add-MarkdownLine -Lines $Lines
    }

    if ($Section.Output.Count -gt 0) {
        Add-MarkdownDetailsBlock -Lines $Lines -Summary '查看原始输出' -Output $Section.Output
    }
}

function Render-Iperf3Section {
    param(
        [System.Collections.Generic.List[string]]$Lines,
        [object]$Section
    )

    Add-MarkdownLine -Lines $Lines -Text ("### {0}" -f $Section.Name)
    Add-MarkdownLine -Lines $Lines

    if ($Section.Command) {
        Add-MarkdownLine -Lines $Lines -Text ('- 测试命令：`{0}`' -f (Escape-MarkdownCell $Section.Command))
    }

    if ($null -ne $Section.Summary) {
        Add-MarkdownLine -Lines $Lines -Text ('- Sender 速率：`{0}`' -f (Escape-MarkdownCell $Section.Summary.SenderBitrate))
        Add-MarkdownLine -Lines $Lines -Text ('- Receiver 速率：`{0}`' -f (Escape-MarkdownCell $Section.Summary.ReceiverBitrate))
    }
    else {
        Add-MarkdownLine -Lines $Lines -Text ("> 状态：{0}" -f (Get-SectionStatusLabel -Status $Section.Status))
    }

    Add-MarkdownLine -Lines $Lines

    if ($Section.Output.Count -gt 0) {
        Add-MarkdownDetailsBlock -Lines $Lines -Summary '查看原始输出' -Output $Section.Output
    }
}

function Render-OneClickMarkdownReport {
    param(
        [string]$ResultFile,
        [string]$TargetIp,
        [datetime]$ReportTime,
        [string[]]$SelectedNames,
        [Nullable[int]]$TcpPort,
        [object[]]$Sections,
        [string]$TerminationMessage = ''
    )

    $lines = [System.Collections.Generic.List[string]]::new()
    $tcpSection = $Sections | Where-Object { $_.Kind -eq 'tcp' } | Select-Object -First 1
    $pingSection = $Sections | Where-Object { $_.Kind -eq 'ping' } | Select-Object -First 1
    $iperfSections = @($Sections | Where-Object { $_.Kind -eq 'iperf3' })
    $routeSection = $Sections | Where-Object { $_.Kind -eq 'route' } | Select-Object -First 1

    if ($TerminationMessage) {
        Add-MarkdownLine -Lines $lines -Text ("> {0}" -f $TerminationMessage)
        Add-MarkdownLine -Lines $lines
    }

    Add-MarkdownLine -Lines $lines -Text '| 项目 | 状态 | 平均延迟 | 最小延迟 | 最大延迟 | 成功次数 | 失败次数 | 成功率 | Sender 速率 | Receiver 速率 | 说明 |'
    Add-MarkdownLine -Lines $lines -Text '|---|---|---:|---:|---:|---:|---:|---:|---:|---:|---|'

    if ($tcpSection) {
        if ($null -ne $tcpSection.Summary) {
            Add-MarkdownLine -Lines $lines -Text ('| TCP延迟 | {0} | {1} | {2} | {3} | {4} | {5} | {6} | - | - | - |' -f `
                (Get-SectionStatusLabel -Status $tcpSection.Status),
                (Escape-MarkdownCell $tcpSection.Summary.Average),
                (Escape-MarkdownCell $tcpSection.Summary.Minimum),
                (Escape-MarkdownCell $tcpSection.Summary.Maximum),
                (Escape-MarkdownCell $tcpSection.Summary.Success),
                (Escape-MarkdownCell $tcpSection.Summary.Failed),
                (Escape-MarkdownCell $tcpSection.Summary.SuccessRate))
        }
        else {
            Add-MarkdownLine -Lines $lines -Text ('| TCP延迟 | {0} | - | - | - | - | - | - | - | - | {1} |' -f `
                (Get-SectionStatusLabel -Status $tcpSection.Status),
                (Escape-MarkdownCell (Get-OverviewText -Section $tcpSection)))
        }
    }

    if ($pingSection) {
        if ($null -ne $pingSection.Summary) {
            Add-MarkdownLine -Lines $lines -Text ('| Ping延迟 | {0} | {1} | {2} | {3} | {4} | {5} | {6} | - | - | - |' -f `
                (Get-SectionStatusLabel -Status $pingSection.Status),
                (Escape-MarkdownCell $pingSection.Summary.Average),
                (Escape-MarkdownCell $pingSection.Summary.Minimum),
                (Escape-MarkdownCell $pingSection.Summary.Maximum),
                (Escape-MarkdownCell $pingSection.Summary.Success),
                (Escape-MarkdownCell $pingSection.Summary.Failed),
                (Escape-MarkdownCell $pingSection.Summary.SuccessRate))
        }
        else {
            Add-MarkdownLine -Lines $lines -Text ('| Ping延迟 | {0} | - | - | - | - | - | - | - | - | {1} |' -f `
                (Get-SectionStatusLabel -Status $pingSection.Status),
                (Escape-MarkdownCell (Get-OverviewText -Section $pingSection)))
        }
    }

    if ($iperfSections.Count -gt 0) {
        foreach ($section in $iperfSections) {
            if ($null -ne $section.Summary) {
                Add-MarkdownLine -Lines $lines -Text ('| {0} | {1} | - | - | - | - | - | - | {2} | {3} | - |' -f `
                    (Escape-MarkdownCell $section.Name),
                    (Get-SectionStatusLabel -Status $section.Status),
                    (Escape-MarkdownCell $section.Summary.SenderBitrate),
                    (Escape-MarkdownCell $section.Summary.ReceiverBitrate))
            }
            else {
                Add-MarkdownLine -Lines $lines -Text ('| {0} | {1} | - | - | - | - | - | - | - | - | {2} |' -f `
                    (Escape-MarkdownCell $section.Name),
                    (Get-SectionStatusLabel -Status $section.Status),
                    (Escape-MarkdownCell (Get-OverviewText -Section $section)))
            }
        }
    }
    elseif ($SelectedNames -contains 'iperf3测速' -and $TerminationMessage) {
        Add-MarkdownLine -Lines $lines -Text ('| iperf3测速 | 已终止 | - | - | - | - | - | - | - | - | {0} |' -f (Escape-MarkdownCell $TerminationMessage))
    }

    if ($routeSection) {
        Add-MarkdownLine -Lines $lines -Text ('| 出国路由 | {0} | - | - | - | - | - | - | - | - | 完整路由见下方明细 |' -f (Get-SectionStatusLabel -Status $routeSection.Status))
    }

    Add-MarkdownLine -Lines $lines

    if ($routeSection) {
        Add-MarkdownLine -Lines $lines -Text '## 出国路由'
        Add-MarkdownLine -Lines $lines

        Add-MarkdownLine -Lines $lines -Text '```text'
        foreach ($line in $routeSection.Output) {
            Add-MarkdownLine -Lines $lines -Text $line
        }
        Add-MarkdownLine -Lines $lines -Text '```'
        Add-MarkdownLine -Lines $lines
    }

    Set-Content -LiteralPath $ResultFile -Value $lines -Encoding UTF8
}

function Invoke-TcpPortCheck {
    param(
        [string]$TargetIp,
        [int]$Port
    )

    $tcpingPath = Get-ToolPath -ToolName 'tcping'
    if (-not $tcpingPath) {
        $message = Write-MissingTool -ToolName 'tcping'
        return (New-ResultRecord -Kind 'portcheck' -Name 'iperf3 端口预检查' -Output @($message) -Status 'failed' -Meta @{
            IsOpen        = $false
            FailureReason = 'missing_tool'
            Port          = $Port
        })
    }

    $result = Invoke-ExternalCommand -CommandPath $tcpingPath -Arguments @($TargetIp, $Port.ToString()) -SectionTitle ("TCP 端口检测 {0}:{1}" -f $TargetIp, $Port)
    $summary = Parse-TcpingSummary -Output $result.Output
    $joined = ($result.Output -join "`n")
    $hasOpenLine = $joined -match '(?i)Port is open'
    $isOpen = $false

    if ($summary) {
        $isOpen = $hasOpenLine -and $summary.Sent -gt 0 -and $summary.Success -eq $summary.Sent -and $summary.Failed -eq 0
    }
    else {
        $isOpen = $hasOpenLine
    }

    $status = if ($isOpen) { 'success' } else { 'failed' }

    return (New-ResultRecord -Kind 'portcheck' -Name 'iperf3 端口预检查' -Command $result.Command -Output $result.Output -ExitCode $result.ExitCode -Status $status -Summary $summary -Meta @{
        IsOpen        = $isOpen
        FailureReason = if ($isOpen) { 'none' } else { 'port_closed' }
        Port          = $Port
    })
}

function Invoke-TcpLatencyTest {
    param(
        [string]$TargetIp,
        [int]$Port
    )

    $tcpingPath = Get-ToolPath -ToolName 'tcping'
    if (-not $tcpingPath) {
        $message = Write-MissingTool -ToolName 'tcping'
        return (New-ResultRecord -Kind 'tcp' -Name 'TCP 延迟' -Output @($message) -Status 'failed')
    }

    $result = Invoke-ExternalCommand -CommandPath $tcpingPath -Arguments @($TargetIp, $Port.ToString()) -SectionTitle 'TCP 延迟'
    $summary = Parse-TcpingSummary -Output $result.Output
    $status = if ($summary) { Get-SectionStatusFromSummary -Summary $summary } elseif ($result.ExitCode -eq 0) { 'success' } else { 'failed' }
    return (New-ResultRecord -Kind 'tcp' -Name 'TCP 延迟' -Command $result.Command -Output $result.Output -ExitCode $result.ExitCode -Status $status -Summary $summary)
}

function Invoke-PingLatencyTest {
    param(
        [string]$TargetIp
    )

    $pingPath = Get-ToolPath -ToolName 'ping'
    if (-not $pingPath) {
        $message = Write-MissingTool -ToolName 'ping'
        return (New-ResultRecord -Kind 'ping' -Name 'Ping 延迟' -Output @($message) -Status 'failed')
    }

    $ipSwitch = Get-IpVersionSwitch -TargetIp $TargetIp
    $result = Invoke-ExternalCommand -CommandPath $pingPath -Arguments @($ipSwitch, $TargetIp, '-l', '1372') -SectionTitle 'Ping 延迟'
    $summary = Parse-PingSummary -Output $result.Output
    $status = if ($summary) { Get-SectionStatusFromSummary -Summary $summary } elseif ($result.ExitCode -eq 0) { 'success' } else { 'failed' }
    return (New-ResultRecord -Kind 'ping' -Name 'Ping 延迟' -Command $result.Command -Output $result.Output -ExitCode $result.ExitCode -Status $status -Summary $summary)
}

function Invoke-Iperf3Test {
    param(
        [string]$TargetIp,
        [switch]$SkipPortCheck
    )

    $sections = [System.Collections.Generic.List[object]]::new()
    $iperfPath = Get-ToolPath -ToolName 'iperf3'
    if (-not $iperfPath) {
        $message = Write-MissingTool -ToolName 'iperf3'
        $sections.Add((New-ResultRecord -Kind 'iperf3' -Name 'iperf3测速' -Output @($message) -Status 'failed'))
        return $sections.ToArray()
    }

    if (-not $SkipPortCheck) {
        $portCheck = Invoke-TcpPortCheck -TargetIp $TargetIp -Port 22001
        $sections.Add($portCheck)

        if (-not $portCheck.Meta.IsOpen) {
            $message = if ($portCheck.Meta.FailureReason -eq 'missing_tool') {
                '未找到 tcping，无法完成 iperf3 端口预检查，本次测试已终止。'
            }
            else {
                '22001 端口未开启，本次测试已终止，请先在服务端开启该端口。'
            }

            Write-Line $message Red
            $sections.Add((New-ResultRecord -Kind 'message' -Name 'iperf3 测试终止' -Output @($message) -Status 'terminated'))
            return $sections.ToArray()
        }
    }

    $ipSwitch = Get-IpVersionSwitch -TargetIp $TargetIp
    $tests = @(
        @{ Title = 'iperf3 单线程下载'; Args = @($ipSwitch, '-c', $TargetIp, '-p', '22001', '-t', '12', '-P', '1', '-R'); UseSum = $false }
        @{ Title = 'iperf3 多线程下载'; Args = @($ipSwitch, '-c', $TargetIp, '-p', '22001', '-t', '12', '-P', '4', '-R'); UseSum = $true }
        @{ Title = 'iperf3 单线程上传'; Args = @($ipSwitch, '-c', $TargetIp, '-p', '22001', '-t', '12', '-P', '1'); UseSum = $false }
        @{ Title = 'iperf3 多线程上传'; Args = @($ipSwitch, '-c', $TargetIp, '-p', '22001', '-t', '12', '-P', '4'); UseSum = $true }
    )

    foreach ($test in $tests) {
        $result = Invoke-ExternalCommand -CommandPath $iperfPath -Arguments $test.Args -SectionTitle $test.Title
        $summary = Parse-Iperf3Summary -Output $result.Output -UseSum:$test.UseSum
        $status = if ($summary) { 'success' } elseif ($result.ExitCode -eq 0) { 'success' } else { 'failed' }
        $sections.Add((New-ResultRecord -Kind 'iperf3' -Name $test.Title -Command $result.Command -Output $result.Output -ExitCode $result.ExitCode -Status $status -Summary $summary))
    }

    return $sections.ToArray()
}

function Invoke-RouteTraceTest {
    param([string]$TargetIp)

    $nexttracePath = Get-ToolPath -ToolName 'nexttrace'
    if (-not $nexttracePath) {
        $message = Write-MissingTool -ToolName 'nexttrace'
        return (New-ResultRecord -Kind 'route' -Name '出国路由' -Output @($message) -Status 'failed')
    }

    $result = Invoke-ExternalCommand -CommandPath $nexttracePath -Arguments @($TargetIp) -SectionTitle '出国路由'
    $status = if ($result.ExitCode -eq 0) { 'success' } else { 'failed' }
    return (New-ResultRecord -Kind 'route' -Name '出国路由' -Command $result.Command -Output $result.Output -ExitCode $result.ExitCode -Status $status)
}

function Convert-ToSafeFileName {
    param([string]$TargetIp)

    return [Regex]::Replace($TargetIp, '[\\/:*?"<>|% ]', '_')
}

function New-OneClickResultFile {
    param([string]$TargetIp)

    if (-not (Test-Path -LiteralPath $script:ResultsDirectory)) {
        [void](New-Item -Path $script:ResultsDirectory -ItemType Directory)
    }

    $safeTarget = Convert-ToSafeFileName -TargetIp $TargetIp
    $timestamp = Get-Date -Format 'yyyy-M-d-H-mm'
    $fileName = '{0}----{1}.md' -f $safeTarget, $timestamp
    $resultFile = Join-Path $script:ResultsDirectory $fileName
    [void](New-Item -Path $resultFile -ItemType File -Force)
    return $resultFile
}

function Wait-ForReturn {
    if (-not (Test-InteractiveConsole)) {
        return
    }

    Read-Host '按回车返回主菜单' | Out-Null
}

function Start-OneClickTest {
    Show-Banner
    Write-Line '一键测试' Yellow
    Write-Separator 30

    $targetIp = Read-TargetIp
    $selections = Read-OneClickSelections

    $reportTime = Get-Date
    $resultFile = New-OneClickResultFile -TargetIp $targetIp
    $selectedNames = $selections | ForEach-Object { $script:OneClickItems[$_] }
    $sections = [System.Collections.Generic.List[object]]::new()
    $terminationMessage = ''

    $tcpPort = $null
    if ($selections -contains '1') {
        $tcpPort = Read-TcpPort
    }

    if ($selections -contains '3') {
        $portCheckSection = Invoke-TcpPortCheck -TargetIp $targetIp -Port 22001
        $sections.Add($portCheckSection)

        if (-not $portCheckSection.Meta.IsOpen) {
            $terminationMessage = if ($portCheckSection.Meta.FailureReason -eq 'missing_tool') {
                '检测到本次选择包含 iperf3，但当前未找到 tcping，无法完成 22001 端口预检查，本次测试已终止。'
            }
            else {
                '检测到本次选择包含 iperf3，22001 端口未开启，本次测试已终止，请先在服务端开启该端口。'
            }

            Write-Line $terminationMessage Red
            Render-OneClickMarkdownReport -ResultFile $resultFile -TargetIp $targetIp -ReportTime $reportTime -SelectedNames $selectedNames -TcpPort $null -Sections $sections.ToArray() -TerminationMessage $terminationMessage
            Write-Line ''
            Write-Line ("结果已保存到: {0}" -f $resultFile) Green
            Wait-ForReturn
            return
        }
    }

    foreach ($selection in $selections) {
        switch ($selection) {
            '1' { $sections.Add((Invoke-TcpLatencyTest -TargetIp $targetIp -Port $tcpPort)) }
            '2' { $sections.Add((Invoke-PingLatencyTest -TargetIp $targetIp)) }
            '3' {
                foreach ($section in (Invoke-Iperf3Test -TargetIp $targetIp -SkipPortCheck)) {
                    if ($section.Kind -ne 'message') {
                        $sections.Add($section)
                    }
                }
            }
            '4' { $sections.Add((Invoke-RouteTraceTest -TargetIp $targetIp)) }
        }
    }

    Render-OneClickMarkdownReport -ResultFile $resultFile -TargetIp $targetIp -ReportTime $reportTime -SelectedNames $selectedNames -TcpPort $tcpPort -Sections $sections.ToArray()
    Write-Line ''
    Write-Line ("结果已保存到: {0}" -f $resultFile) Green
    Wait-ForReturn
}

function Start-TcpTest {
    Show-Banner
    Write-Line 'TCP 测试' Yellow
    Write-Separator 30

    $targetIp = Read-TargetIp
    $port = Read-TcpPort
    [void](Invoke-TcpLatencyTest -TargetIp $targetIp -Port $port)
    Wait-ForReturn
}

function Start-PingTest {
    Show-Banner
    Write-Line 'Ping 测试' Yellow
    Write-Separator 30

    $targetIp = Read-TargetIp
    [void](Invoke-PingLatencyTest -TargetIp $targetIp)
    Wait-ForReturn
}

function Start-Iperf3Test {
    Show-Banner
    Write-Line 'iperf3 速度测试' Yellow
    Write-Separator 30

    $targetIp = Read-TargetIp
    [void](Invoke-Iperf3Test -TargetIp $targetIp)
    Wait-ForReturn
}

function Start-NexttraceTest {
    Show-Banner
    Write-Line '出国路由查看' Yellow
    Write-Separator 30

    $targetIp = Read-TargetIp
    [void](Invoke-RouteTraceTest -TargetIp $targetIp)
    Wait-ForReturn
}

function Start-Toolbox {
    Initialize-Console

    while ($true) {
        Show-Banner
        Show-MainMenu
        $choice = (Read-Host '请输入你的选择').Trim()

        switch ($choice) {
            '1' { Start-OneClickTest }
            '2' { Start-TcpTest }
            '3' { Start-PingTest }
            '4' { Start-Iperf3Test }
            '5' { Start-NexttraceTest }
            '0' { return }
            default {
                Write-Line '无效选择，请重新输入。' Red
                Start-Sleep -Seconds 1
            }
        }
    }
}

if ($MyInvocation.InvocationName -ne '.') {
    Start-Toolbox
}
