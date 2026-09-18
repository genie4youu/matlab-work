<#
    start-session.ps1 — 「MATLAB 업무 시작」 = 내 데스크톱 MATLAB 을 Claude/Codex 에게 여는 스위치

    하는 일: 환경 점검 → 죽은 공유 기록 정리 → MATLAB 실행(MATLAB_SHARE=1) → 다음 단계 안내.

    🔄 2026-09-16 개편 — 「인스턴스는 하나, 공유는 자동」에서 「공유는 이 스위치를 눌렀을 때만」으로.
      · 이 스크립트로 켠 MATLAB  → MATLAB_SHARE=1 → startup.m 이 satk 로 공유 → Claude/Codex 세션이 전부 여기 붙는다
                                    (한 데스크톱을 여럿이 쓰므로 실행 담당 한 명, -Resource matlab 잠금)
      · 이 스크립트를 안 눌렀다     → Claude/Codex 세션마다 자기 MATLAB 을 창 없이 띄운다(MCP auto 모드) → 병렬
      · 시작 메뉴 · VS Code 확장 · matlab -batch 로 뜬 MATLAB → 공유 안 됨
      근거·실측: 볼트 work/knowledge/결정이력 2026-09-16 절, work/knowledge/AI도구_작업환경_시작순서 §A

    실행:  더블클릭 start-session.cmd  또는  & C:\Users\leeyj\matlab-work\start-session.ps1
    옵션:  -NoLaunch   점검만 하고 MATLAB 은 띄우지 않는다

    ⚠️ 이 파일은 UTF-8 BOM 포함으로 저장해야 한다.
       PowerShell 5.1 은 BOM 이 없으면 ANSI 로 읽어서 한글 주석이 깨지고
       바로 다음 줄을 통째로 삼킨다 (구문 오류도 안 난다).
#>

param(
    [switch]$NoLaunch
)

$ErrorActionPreference = 'Stop'

$WorkRoot    = 'C:\Users\leeyj\matlab-work'
$MatlabHome  = 'C:\Program Files\MATLAB'
$ClaudeJson  = Join-Path $env:USERPROFILE '.claude.json'
$CodexToml   = Join-Path $env:USERPROFILE '.codex\config.toml'
$StartupM    = Join-Path $env:USERPROFILE 'Documents\MATLAB\startup.m'
$FinishM     = Join-Path $env:USERPROFILE 'Documents\MATLAB\finish.m'
$ShareRecord = Join-Path $env:APPDATA 'MathWorks\MATLAB MCP Server\v1\sessionDetails.json'

$fail = 0

function Show-Check {
    param([string]$Name, [bool]$Ok, [string]$Detail)
    if ($Ok) {
        Write-Host ('  [OK]   ' + $Name) -ForegroundColor Green
    } else {
        Write-Host ('  [FAIL] ' + $Name) -ForegroundColor Red
        $script:fail++
    }
    if ($Detail) { Write-Host ('         ' + $Detail) -ForegroundColor DarkGray }
}

# 공유 기록(sessionDetails.json)을 읽어 pid 가 살아 있는지 본다.
# 반환: $null(기록 없음) / @{Pid=..; Alive=$true|$false}
function Get-ShareRecord {
    if (-not (Test-Path $ShareRecord)) { return $null }
    try {
        $rec = Get-Content $ShareRecord -Raw -Encoding UTF8 | ConvertFrom-Json
        $alive = $null -ne (Get-Process -Id $rec.pid -ErrorAction SilentlyContinue)
        return @{ Pid = [int]$rec.pid; Alive = $alive }
    } catch {
        return @{ Pid = -1; Alive = $false }
    }
}

Write-Host ''
Write-Host '=== MATLAB 업무 시작 — 점검 ===' -ForegroundColor Cyan
Write-Host ''

# 1. 작업 폴더
$hasWork = Test-Path $WorkRoot
Show-Check '작업 폴더' $hasWork $WorkRoot

# 2. 경로에 위험 문자가 없는지
#    코드 생성 툴체인은 공백·비ASCII 경로에서 깨진다. 볼트에 모델을 두지 않는 이유.
$pathClean = ($WorkRoot -match '^[\x20-\x7E]+$') -and ($WorkRoot -notmatch '[ ]')
Show-Check '경로가 코드 생성에 안전 (공백·비ASCII 없음)' $pathClean

# 3. MATLAB 설치
$release = $null
if (Test-Path $MatlabHome) {
    $release = Get-ChildItem $MatlabHome -Directory | Sort-Object Name -Descending | Select-Object -First 1
}
$hasMatlab = $null -ne $release
if ($hasMatlab) {
    $MatlabExe = Join-Path $release.FullName 'bin\matlab.exe'
    $hasMatlab = Test-Path $MatlabExe
}
if ($hasMatlab) {
    Show-Check 'MATLAB 설치' $true $release.Name
} else {
    Show-Check 'MATLAB 설치' $false '찾지 못했습니다'
}

# 4. startup.m 이 공유 스위치(MATLAB_SHARE)를 보고, finish.m 이 종료 때 기록을 지우는지
$hasStartup = $false
if (Test-Path $StartupM) {
    $startupText = Get-Content $StartupM -Raw -Encoding UTF8
    $hasStartup = ($startupText -match 'matlab-work') -and ($startupText -match 'MATLAB_SHARE')
}
if ($hasStartup) {
    Show-Check 'startup.m — 경로 등록 + MATLAB_SHARE 스위치' $true $StartupM
} else {
    Show-Check 'startup.m — 경로 등록 + MATLAB_SHARE 스위치' $false '2026-09-16 판이 아닙니다. 볼트 결정이력 09-16 절을 보세요'
}
Show-Check 'finish.m — 종료 때 공유 기록 정리' (Test-Path $FinishM) $FinishM

# 5. Claude · Codex 의 MATLAB MCP 가 auto 모드인지 (existing 이면 공유가 없을 때 붙을 데가 없어 실패한다)
$claudeAuto = $false
if (Test-Path $ClaudeJson) {
    try {
        $cfg = Get-Content $ClaudeJson -Raw -Encoding UTF8 | ConvertFrom-Json
        if ($cfg.mcpServers -and $cfg.mcpServers.matlab) {
            $claudeAuto = (@($cfg.mcpServers.matlab.args) -contains '--matlab-session-mode=auto')
        }
    } catch { $claudeAuto = $false }
}
if ($claudeAuto) {
    Show-Check 'Claude Code MATLAB MCP — auto 모드 (user scope)' $true
} else {
    Show-Check 'Claude Code MATLAB MCP — auto 모드 (user scope)' $false 'claude mcp get matlab 으로 확인. 등록 명령은 볼트 MATLAB_MCP_연결_구축기록'
}
$codexAuto = $false
if (Test-Path $CodexToml) {
    $codexAuto = (Get-Content $CodexToml -Raw -Encoding UTF8) -match '--matlab-session-mode=auto'
}
if ($codexAuto) {
    Show-Check 'Codex MATLAB MCP — auto 모드' $true
} else {
    Show-Check 'Codex MATLAB MCP — auto 모드' $false ($CodexToml + ' 의 [mcp_servers.matlab] args')
}

# 6. 죽은 공유 기록 정리 — 비정상 종료로 finish.m 이 못 돌면 남는다.
#    auto 모드는 이게 있어도 결국 자기 MATLAB 을 띄우지만(09-16 실측) 붙기를 시도하느라 10초쯤 잃는다.
$rec = Get-ShareRecord
if ($null -ne $rec -and -not $rec.Alive) {
    Remove-Item $ShareRecord -Force
    Show-Check '죽은 공유 기록 정리' $true ('pid ' + $rec.Pid + ' 은 없음 → sessionDetails.json 삭제')
    $rec = $null
} else {
    Show-Check '죽은 공유 기록 없음' $true
}

Write-Host ''

# ── 지금 떠 있는 MATLAB ────────────────────────────────
$procs = @(Get-CimInstance Win32_Process -Filter "Name='MATLAB.exe'" -ErrorAction SilentlyContinue)
if ($procs.Count -gt 0) {
    Write-Host '지금 떠 있는 MATLAB:' -ForegroundColor Cyan
    foreach ($p in $procs) {
        $cmd = [string]$p.CommandLine
        $who = '데스크톱(창) 또는 보조'
        if ($cmd -match 'initmatlabls')      { $who = 'VS Code MATLAB 확장(언어서버, 공유 안 됨)' }
        elseif ($cmd -match '-batch')        { $who = 'matlab -batch(공유 안 됨)' }
        elseif ($cmd -match 'MW_MCP|mcp')    { $who = 'MCP 가 띄운 세션용(공유 안 됨)' }
        if ($null -ne $rec -and $rec.Alive -and $p.ProcessId -eq $rec.Pid) { $who = '🔗 공유 중 — Claude/Codex 가 여기 붙는다' }
        Write-Host ('  pid ' + $p.ProcessId + '  ' + $who) -ForegroundColor DarkGray
    }
    Write-Host ''
}

# ── MATLAB 실행 ────────────────────────────────────────
if ($null -ne $rec -and $rec.Alive) {
    Write-Host ('이미 공유 중인 MATLAB 이 있습니다 (pid ' + $rec.Pid + '). 새로 띄우지 않습니다.') -ForegroundColor Yellow
    Write-Host '  그 창을 그대로 쓰면 됩니다. 바꾸려면 그 MATLAB 을 닫고 다시 실행하세요.' -ForegroundColor DarkGray
} elseif ($NoLaunch) {
    Write-Host 'MATLAB 은 띄우지 않았습니다 (-NoLaunch).' -ForegroundColor Yellow
} elseif ($hasMatlab -and $fail -eq 0) {
    Write-Host 'MATLAB 을 공유 모드로 실행합니다 (MATLAB_SHARE=1)...' -ForegroundColor Cyan
    # 이 프로세스에만 주는 환경변수다(setx 아님). 자식 MATLAB 이 물려받고, 창을 닫으면 사라진다.
    $env:MATLAB_SHARE = '1'
    Start-Process -FilePath $MatlabExe -WorkingDirectory $WorkRoot
    Remove-Item Env:MATLAB_SHARE -ErrorAction SilentlyContinue
    Write-Host '  startup.m 이 경로 등록 + satk(공유)를 합니다. 명령창에 Result: PASS 가 나오면 준비 완료.' -ForegroundColor DarkGray
} else {
    Write-Host '점검에 실패한 항목이 있어 MATLAB 을 띄우지 않았습니다.' -ForegroundColor Red
}

# ── 다음 단계 ──────────────────────────────────────────
Write-Host ''
Write-Host '=== 다음 단계 ===' -ForegroundColor Cyan
Write-Host ''
Write-Host '  1. MATLAB 명령창에서 아래 두 줄이 보이는지 확인'
Write-Host '       작업 폴더: C:\Users\leeyj\matlab-work (경로 N개 등록)' -ForegroundColor DarkGray
Write-Host '       SATK 초기화를 시작합니다 ... Result: PASS' -ForegroundColor DarkGray
Write-Host ''
Write-Host '  2. Claude Code / Codex 를 연다 — 순서는 상관없다.'
Write-Host '       MCP 는 첫 MATLAB 도구를 부를 때 붙는다. 그 전에 위 창이 떠 있으면 된다.' -ForegroundColor DarkGray
Write-Host '       (이미 열어둔 세션이 그 전에 자기 MATLAB 을 띄웠다면 그 세션은 거기 그대로 있다)' -ForegroundColor DarkGray
Write-Host ''
Write-Host '  3. 이 창을 여럿이 쓴다 — 실행 담당 한 명, /model·/analyze 는 -Resource matlab 잠금.'
Write-Host '       병렬로 돌리고 싶으면 이 스크립트를 쓰지 않는다: 세션마다 자기 MATLAB 을 창 없이 띄운다.' -ForegroundColor DarkGray
Write-Host '       그 세션에 "모델 보여줘" 하면 Simulink 창을, "MATLAB 창 보여줘" 하면 데스크톱을 띄운다.' -ForegroundColor DarkGray
Write-Host ''

if ($fail -gt 0) {
    Write-Host ('점검 실패 ' + $fail + '건. 위 [FAIL] 항목을 먼저 해결하세요.') -ForegroundColor Red
    exit 1
}

Write-Host '점검 통과.' -ForegroundColor Green
exit 0
