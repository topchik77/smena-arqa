param([switch]$SkipBuild)
$ErrorActionPreference = 'Stop'
$taskRoot = Split-Path -Parent $PSScriptRoot
Push-Location $taskRoot
try {
    if (-not (Test-Path 'backend/.venv/Scripts/python.exe')) {
        python -m venv backend/.venv
        if ($LASTEXITCODE) { throw 'Python 3.12+ is required.' }
    }
    $taskPython = Join-Path $taskRoot 'backend/.venv/Scripts/python.exe'
    & $taskPython -m pip install -r backend/requirements.txt
    if ($LASTEXITCODE) { throw 'Dependency installation failed.' }
    if (-not $SkipBuild) {
        $taskFlutter = if (Test-Path '.tools/flutter/bin/flutter.bat') {
            (Resolve-Path '.tools/flutter/bin/flutter.bat').Path
        } else { 'flutter' }
        Push-Location client
        try {
            & $taskFlutter pub get
            if ($LASTEXITCODE) { throw 'Flutter dependencies failed.' }
            & $taskFlutter build web --release --no-web-resources-cdn
            if ($LASTEXITCODE) { throw 'Flutter web build failed.' }
        } finally { Pop-Location }
    }
    if (-not (Test-Path 'client/build/web/index.html')) { throw 'Build the Flutter web client first.' }
    Push-Location backend
    try {
        & $taskPython -m app.import_data ../data/trips.json
        if ($LASTEXITCODE) { throw 'Example import failed.' }
        & $taskPython -m app.import_data ../data/demo-trips.json
        if ($LASTEXITCODE) { throw 'Demo import failed.' }
        Write-Host 'Смена: http://127.0.0.1:8000 · API: http://127.0.0.1:8000/docs'
        & $taskPython -m uvicorn app.main:app --host 127.0.0.1 --port 8000
    } finally { Pop-Location }
} finally { Pop-Location }
