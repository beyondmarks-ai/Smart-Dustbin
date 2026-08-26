param(
    [Parameter(Mandatory = $true)][string]$ApiBaseUrl,
    [Parameter(Mandatory = $true)][string]$SecretArn,
    [string]$Region = $(if ($env:AWS_REGION) { $env:AWS_REGION } else { 'us-east-1' })
)

$apiKey = aws secretsmanager get-secret-value --secret-id $SecretArn --region $Region --query SecretString --output text
if ($LASTEXITCODE -ne 0) { throw 'Unable to retrieve the ingestion API key.' }
$body = @{
    waste_confidence = 0.96
    evidence_summary = 'Sample record created after AWS deployment'
    items = @(
        @{
            name = 'Plastic Bottle'
            material = 'PET plastic'
            category = 'plastic'
            recyclable = $true
            recycling_confidence = 0.94
            recycling_guidance = 'Rinse, dry, and place in the recycling bin.'
        }
    )
} | ConvertTo-Json -Depth 8

$base = $ApiBaseUrl.TrimEnd('/')
Invoke-RestMethod -Method Post -Uri "$base/api/waste" -Headers @{ 'x-api-key' = $apiKey } -ContentType 'application/json' -Body $body
