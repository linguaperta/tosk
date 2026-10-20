# Renders sheet.html to sheet.png with headless Edge (see BRIEF.md).
$p = Split-Path -Parent $MyInvocation.MyCommand.Path
$u = "file:///" + ($p -replace '\\', '/') + "/sheet.html"
Start-Process -FilePath "C:\Program Files (x86)\Microsoft\Edge\Application\msedge.exe" -ArgumentList @("--headless=new", "--disable-gpu", "--hide-scrollbars", "--user-data-dir=$p\edgeprof", "--window-size=1600,2340", "--screenshot=$p\sheet.png", $u) -Wait -WindowStyle Hidden
