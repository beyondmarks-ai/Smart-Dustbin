# Azure waste verifier

Active Python 3.11 Azure Functions backend for the ESP32-CAM and Flutter app. The camera uploads five JPEGs to private Blob Storage, then submits an authenticated `POST /api/process`. Azure OpenAI classifies the images. Flutter reads `GET /api/waste` and `GET /api/waste/{event_id}/image`; `/api/health` reports service status.

## Configuration

The repository does not provision Azure infrastructure automatically. Use an existing Python 3.11 Function App with managed identity, Storage account and Azure OpenAI vision-capable deployment. Create private containers `waste-raw`, `waste-analysis` and `verified-waste`. Grant the Function managed identity the required Blob data access (read raw images, read/write analysis and verified images) and Cognitive Services OpenAI User access to the model resource.

Use `local.settings.example.json` as a list of required app settings. Configure the real values in Azure; do not commit them. `DEVICE_INGEST_KEY` must match the firmware. Issue a container-scoped create/write-only SAS for raw image uploads, with an appropriate expiry, and place it only in the ignored firmware config. Keep the containers private.

The REST adapter authenticates using App Service managed-identity environment variables (`IDENTITY_ENDPOINT`, `IDENTITY_HEADER`). Running the complete backend on a laptop therefore requires an alternate development credential adapter; copying local settings alone is not sufficient. Offline unit tests do not require Azure credentials:

```powershell
cd cloud/waste_verifier
py -3.11 -m unittest discover -s tests -v
```

## Deployment to your existing Function App

Install Azure CLI and authenticate with your own account. From the repository root, package only application files:

```powershell
New-Item -ItemType Directory -Force build | Out-Null
Compress-Archive -LiteralPath cloud/waste_verifier/function_app.py,cloud/waste_verifier/waste_ai.py,cloud/waste_verifier/azure_rest.py,cloud/waste_verifier/host.json,cloud/waste_verifier/requirements.txt,cloud/waste_verifier/dashboard.html -DestinationPath build/waste-verifier.zip -Force
az functionapp deployment source config-zip --resource-group YOUR_RESOURCE_GROUP --name YOUR_FUNCTION_APP --src build/waste-verifier.zip --build-remote true
```

Verify `/api/health`, configure the camera's process URL and storage SAS, then build Flutter with `--dart-define=AZURE_WASTE_API_BASE=https://YOUR_FUNCTION_APP.azurewebsites.net`.

## Limitations

This is a prototype: read/image/dashboard endpoints and the optional Event Grid webhook are anonymous. The device process endpoint requires the ingest key. Protect read access and validate/secure webhook delivery before a production deployment. Do not send private images to a publicly readable installation. Model classifications and recycling guidance can be wrong; review uncertain results and local disposal rules. Location is a fixed installation coordinate calibrated from a phone, not GPS tracking on the ESP32.
