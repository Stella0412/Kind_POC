# 用法（PowerShell）：
#   . D:\docker_project\env\env.ps1
# 作用：把 kubeconfig 固定在 D 盘。kind/helm 已由 winget 写入用户 PATH。

$env:DOCKER_PROJECT_ROOT = "D:\docker_project"
$env:KUBECONFIG = "D:\docker_project\work\kubeconfig"

Write-Host "DOCKER_PROJECT_ROOT=$env:DOCKER_PROJECT_ROOT"
Write-Host "KUBECONFIG=$env:KUBECONFIG"
Write-Host ("kind: " + (Get-Command kind -ErrorAction SilentlyContinue).Source)
Write-Host ("helm: " + (Get-Command helm -ErrorAction SilentlyContinue).Source)
