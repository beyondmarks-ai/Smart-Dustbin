param(
    [string]$Region = $(if ($env:AWS_REGION) { $env:AWS_REGION } else { 'us-east-1' }),
    [string]$StackName = 'smart-dustbin-backend'
)

$ErrorActionPreference = 'Stop'
$workspaceRoot = Split-Path -Parent $PSScriptRoot
$buildDirectory = Join-Path $workspaceRoot '.aws-build'
$archivePath = Join-Path $buildDirectory 'waste-function.zip'
$packagedTemplate = Join-Path $buildDirectory 'packaged-template.yaml'

$identityJson = aws sts get-caller-identity --output json
if ($LASTEXITCODE -ne 0) {
    throw 'AWS authentication failed. Run aws login, then retry this script.'
}
$identity = $identityJson | ConvertFrom-Json
$artifactBucket = "$($identity.Account)-smart-dustbin-artifacts-$Region".ToLowerInvariant()

New-Item -ItemType Directory -Force -Path $buildDirectory | Out-Null
if (Test-Path -LiteralPath $archivePath) {
    Remove-Item -LiteralPath $archivePath -Force
}
Compress-Archive -Path (Join-Path $PSScriptRoot 'function\*') -DestinationPath $archivePath

$previousErrorPreference = $ErrorActionPreference
$ErrorActionPreference = 'SilentlyContinue'
aws s3api head-bucket --bucket $artifactBucket 2>&1 | Out-Null
$bucketExists = $LASTEXITCODE -eq 0
$ErrorActionPreference = $previousErrorPreference
if (-not $bucketExists) {
    if ($Region -eq 'us-east-1') {
        aws s3api create-bucket --bucket $artifactBucket --region $Region | Out-Null
    } else {
        aws s3api create-bucket --bucket $artifactBucket --region $Region --create-bucket-configuration "LocationConstraint=$Region" | Out-Null
    }
}

$artifactKey = "lambda/waste-function-$([DateTimeOffset]::UtcNow.ToUnixTimeSeconds()).zip"
aws s3 cp $archivePath "s3://$artifactBucket/$artifactKey" --region $Region | Out-Null
if ($LASTEXITCODE -ne 0) { throw 'Failed to upload the Lambda package.' }

$template = Get-Content -Raw (Join-Path $PSScriptRoot 'template.yaml')
$template = $template.Replace('__CODE_S3_BUCKET__', $artifactBucket)
$template = $template.Replace('__CODE_S3_KEY__', $artifactKey)
[IO.File]::WriteAllText($packagedTemplate, $template, [Text.UTF8Encoding]::new($false))

aws cloudformation deploy `
    --template-file $packagedTemplate `
    --stack-name $StackName `
    --region $Region `
    --capabilities CAPABILITY_NAMED_IAM `
    --no-fail-on-empty-changeset
if ($LASTEXITCODE -ne 0) { throw 'CloudFormation deployment failed.' }

$outputsJson = aws cloudformation describe-stacks --stack-name $StackName --region $Region --query 'Stacks[0].Outputs' --output json
$outputs = $outputsJson | ConvertFrom-Json
$apiUrl = ($outputs | Where-Object OutputKey -eq 'ApiBaseUrl').OutputValue
$secretArn = ($outputs | Where-Object OutputKey -eq 'IngestSecretArn').OutputValue

Write-Host "AWS backend deployed successfully." -ForegroundColor Green
Write-Host "Flutter API URL: $apiUrl"
Write-Host "Run: flutter run --dart-define=AWS_WASTE_API_BASE=$apiUrl"
Write-Host "Ingest secret ARN: $secretArn"
