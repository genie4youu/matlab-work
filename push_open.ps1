<#
    push_open.ps1 — matlab-work 의 「내가 만든 것」만 GitHub genie4youu/matlab-work(공개 거울)에 올린다.
    2026-09-18 사용자 결정: 로컬 matlab-work 는 회사 모델(20260804/ 등)을 포함한 채 그대로 두고,
    open_allow.txt 에 적힌 경로만 별도 거울 저장소(C:\Users\leeyj\matlab-work-open)에 복사해 커밋·push 한다.
    과거 커밋 이력은 가져가지 않으므로 회사 모델이 이력에 새지 않는다.

    실행:  & C:\Users\leeyj\matlab-work\push_open.ps1 -Message "layout_chart 추가"
           -DryRun  : 복사·목록만 보여주고 커밋·push 는 안 한다
    규칙:  ① open_allow.txt 에 없는 경로는 안 올라간다(기본 거부)
           ② 아래 $HardDeny 에 걸리는 경로는 목록에 있어도 안 올라간다(회사 모델 폴더·백업·분석출력)
           ③ 텍스트 파일 안의 회사 모델 이름($Scrub)은 예시 이름으로 치환하고, 남으면 push 를 막는다(공개 저장소)
           ④ 복사 뒤 git status 를 먼저 보여준다 — 마지막 판단은 사람
    ⚠️ UTF-8 BOM 으로 저장한다(PS 5.1 한글).
#>
param(
    [string]$Message = '',
    [switch]$DryRun
)
$ErrorActionPreference = 'Continue'   # PS 5.1 은 git 의 정상 stderr("Cloning into…")를 Stop 에서 오류로 잡는다 → 종료 코드로 판단
$Src    = 'C:\Users\leeyj\matlab-work'
$Mirror = 'C:\Users\leeyj\matlab-work-open'
$Remote = 'https://github.com/genie4youu/matlab-work.git'
$Allow  = Join-Path $Src 'open_allow.txt'
$HardDeny = @('20260804', 'results\ecapp_master_lifecycle', '_백업', '_분석출력', '_폐기', 'slprj', '_덤프', '*.slx.original', '*.zip', '*.sldd')
# 회사 모델 고유명사 → 예시 이름 (공개 저장소에 회사 고유명사를 남기지 않는다 — AGENTS 「공개 글은 공개 출처로」)
$Scrub = [ordered]@{
    'Example_Fault' = 'Example_Fault'
    'Example_Main_SF'          = 'Example_Main_SF'
    'ExampleModel'          = 'ExampleModel'
    'ModelDictionary'     = 'ModelDictionary'
    'ExampleLib' = 'ExampleLib'
}
$TextExt = @('.m', '.md', '.txt', '.ps1', '.cmd', '.json', '.gitignore', '.gitattributes')

function Test-Denied([string]$rel) {
    foreach ($d in $HardDeny) {
        if ($d.Contains('*')) { if ((Split-Path $rel -Leaf) -like $d) { return $true } }
        elseif ($rel -eq $d -or $rel.StartsWith("$d\") -or $rel.StartsWith("$d/")) { return $true }
    }
    return $false
}

# 0. 거울 저장소 준비
if (-not (Test-Path (Join-Path $Mirror '.git'))) {
    Write-Host "거울 저장소가 없다 → clone $Remote" -ForegroundColor Yellow
    cmd /c "git clone $Remote `"$Mirror`" 2>&1" | Out-Host
    if ($LASTEXITCODE -ne 0 -or -not (Test-Path (Join-Path $Mirror '.git'))) { Write-Host "STOP: clone 실패" -ForegroundColor Red; exit 2 }
    git -C $Mirror config core.autocrlf false     # LF 그대로 (CRLF 경고 소음 방지)
}

# 1. 허용 목록 읽기
$entries = Get-Content -Encoding UTF8 $Allow | ForEach-Object { $_.Trim() } | Where-Object { $_ -and -not $_.StartsWith('#') }
$copied = @(); $skipped = @()
foreach ($e in $entries) {
    $rel = $e -replace '/', '\'
    if (Test-Denied $rel) { $skipped += "$rel (HardDeny)"; continue }
    $from = Join-Path $Src $rel; $to = Join-Path $Mirror $rel
    if (-not (Test-Path $from)) { $skipped += "$rel (없음)"; continue }
    if ((Get-Item $from).PSIsContainer) {
        # 폴더: 거울로 동기화(삭제 반영), .git·빌드 산출물·덤프 제외
        $null = robocopy $from $to /MIR /XD .git slprj _slprj _덤프 _백업 /XF *.asv *.autosave *.slx.r* *.m~ build_diag_*.log update_diag_*.log /NFL /NDL /NJH /NJS /NP
        if ($LASTEXITCODE -ge 8) { throw "robocopy 실패($LASTEXITCODE): $rel" }
        $copied += "$rel\ (폴더)"
    } else {
        New-Item -ItemType Directory -Force (Split-Path $to -Parent) | Out-Null
        Copy-Item $from $to -Force
        $copied += $rel
    }
}
# 1a. 거울에서 허용 목록 밖의 최상위 폴더 제거 (옛 배치 잔재)
foreach ($d in Get-ChildItem $Mirror -Directory | Where-Object { $_.Name -ne '.git' }) {
    $top = $d.Name
    $inAllow = @($entries | ForEach-Object { $_ -replace '/', '\' } | Where-Object { $_ -eq $top -or $_.StartsWith($top + '\') }).Count -gt 0
    if (-not $inAllow) { Remove-Item -Recurse -Force $d.FullName; Write-Host "  - 거울에서 제거: $top\" -ForegroundColor Yellow }
}
# 1b. 거울에 남은 캐시·진단 로그 제거 (/MIR 은 /XD·/XF 로 제외한 것을 목적지에서 지우지 않는다)
Get-ChildItem $Mirror -Recurse -Force -Directory | Where-Object { $_.FullName -notlike "$Mirror\.git\*" -and $_.Name -match '^(slprj|_slprj|_덤프.*|_백업)$' } |
    ForEach-Object { Remove-Item -Recurse -Force $_.FullName -ErrorAction SilentlyContinue }
Get-ChildItem $Mirror -Recurse -Force -File | Where-Object { $_.FullName -notlike "$Mirror\.git\*" -and $_.Name -match '^(build|update)_diag.*\.log$' } |
    ForEach-Object { Remove-Item -Force $_.FullName -ErrorAction SilentlyContinue }

# 2. 거울 안내 파일
$note = @(
    '# matlab-work (open mirror)',
    '',
    '`matlab-work` 작업 폴더에서 **직접 만든 도구·노트만** 복사한 공개 거울이다 — 회사 모델·데이터 사전·분석 출력은 없고, 회사 모델 이름은 예시 이름으로 바꿨다.',
    '무엇을 올리는지는 `open_allow.txt`, 올리는 방법은 `push_open.ps1`. 원본 저장소의 커밋 이력은 가져오지 않는다.',
    "마지막 동기화: $(Get-Date -Format 'yyyy-MM-dd HH:mm')"
)
[IO.File]::WriteAllLines((Join-Path $Mirror '_OPEN_MIRROR.md'), $note, (New-Object System.Text.UTF8Encoding($false)))

# 3. 회사 고유명사 치환 (텍스트 파일만, BOM 보존)
$scrubbed = 0
foreach ($f in Get-ChildItem $Mirror -Recurse -Force -File | Where-Object { $_.FullName -notlike "$Mirror\.git\*" -and ($TextExt -contains $_.Extension -or $TextExt -contains $_.Name) }) {
    $bytes = [IO.File]::ReadAllBytes($f.FullName)
    $bom = ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF)
    $txt = [System.Text.Encoding]::UTF8.GetString($bytes); if ($bom) { $txt = $txt.Substring(1) }
    $new = $txt
    foreach ($k in $Scrub.Keys) { $new = $new.Replace($k, $Scrub[$k]) }
    if ($new -ne $txt) {
        [IO.File]::WriteAllText($f.FullName, $new, (New-Object System.Text.UTF8Encoding($bom)))
        $scrubbed++
    }
}
if ($scrubbed) { Write-Host "고유명사 치환: $scrubbed 파일" -ForegroundColor Yellow }
$left = Get-ChildItem $Mirror -Recurse -Force -File | Where-Object { $_.FullName -notlike "$Mirror\.git\*" } |
        Select-String -Pattern ($Scrub.Keys -join '|') -CaseSensitive -List | ForEach-Object { $_.Path.Substring($Mirror.Length + 1) }
if ($left) { Write-Host "STOP: 치환 뒤에도 회사 고유명사가 남았다 —" -ForegroundColor Red; $left | ForEach-Object { Write-Host "  $_" }; exit 4 }

# 4. 거울 안에 회사 폴더가 남아 있지 않은지 마지막 검사
$leak = Get-ChildItem $Mirror -Recurse -Force -File | Where-Object { $_.FullName -notlike "$Mirror\.git\*" } |
        ForEach-Object { $_.FullName.Substring($Mirror.Length + 1) } | Where-Object { Test-Denied $_ }
if ($leak) { Write-Host "STOP: 거울에 거부 경로가 있다 —" -ForegroundColor Red; $leak | ForEach-Object { Write-Host "  $_" }; exit 3 }

Write-Host "복사: $($copied.Count)" -ForegroundColor Green; $copied | ForEach-Object { Write-Host "  + $_" }
if ($skipped.Count) { Write-Host "건너뜀: $($skipped.Count)" -ForegroundColor Yellow; $skipped | ForEach-Object { Write-Host "  - $_" } }

# 5. 커밋·push
Push-Location $Mirror
try {
    git add -A | Out-Null
    $st = git status --porcelain
    Write-Host "`n거울 변경 $(@($st).Count)건:"; $st | ForEach-Object { Write-Host "  $_" }
    if ($DryRun) { Write-Host "`n[DryRun] 커밋·push 안 함"; git reset -q; exit 0 }
    if (-not $st) { Write-Host "변경 없음"; exit 0 }
    if (-not $Message) { $Message = "sync $(Get-Date -Format 'yyyy-MM-dd HH:mm')" }
    git commit -q -m $Message | Out-Null
    cmd /c "git push -u origin HEAD 2>&1" | Out-Host
    if ($LASTEXITCODE -ne 0) { Write-Host "STOP: push 실패($LASTEXITCODE)" -ForegroundColor Red; exit 5 }
    Write-Host "push 완료: $(git log -1 --format='%h %s')" -ForegroundColor Green
} finally { Pop-Location }
