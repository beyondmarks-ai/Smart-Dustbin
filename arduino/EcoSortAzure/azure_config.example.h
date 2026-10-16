#pragma once
// Copy to azure_config.h and fill locally. Never commit azure_config.h.
#define AZURE_BLOB_CONTAINER_URL "https://YOUR_STORAGE.blob.core.windows.net/waste-raw"
// Container-scoped create/write-only SAS, without a leading question mark.
#define AZURE_BLOB_SAS_TOKEN "REPLACE_WITH_WRITE_ONLY_CONTAINER_SAS"
#define AZURE_PROCESS_URL "https://YOUR_FUNCTION.azurewebsites.net/api/process"
#define AZURE_DEVICE_INGEST_KEY "REPLACE_WITH_DEVICE_INGEST_KEY"
#define DEVICE_ID "esp32-camera-01"

#define MOTION_PIXEL_DIFFERENCE 22
#define MOTION_CHANGED_PERCENT 10
#define MOTION_CONFIRMATION_FRAMES 2
#define MOTION_CHECK_INTERVAL_MS 500UL
#define MOTION_WARMUP_MS 10000UL
#define MOTION_COOLDOWN_MS 15000UL
