#ifndef AWS_CONFIG_H
#define AWS_CONFIG_H

// Copy this file to the standalone Arduino sketch directory and fill locally.
#define AWS_WASTE_API_URL "https://5s5v65nhf4kbtqygqktzc5u7rm0fxnmf.lambda-url.us-east-1.on.aws/api/waste"
#define AWS_WASTE_API_KEY "REPLACE_WITH_INGEST_SECRET"
#define WIFI_SSID "REPLACE_WITH_WIFI_SSID"
#define WIFI_PASSWORD "REPLACE_WITH_WIFI_PASSWORD"

#define MOTION_PIXEL_DIFFERENCE 22
#define MOTION_CHANGED_PERCENT 10
#define MOTION_CONFIRMATION_FRAMES 3
#define MOTION_CHECK_INTERVAL_MS 750UL
#define MOTION_WARMUP_MS 15000UL
#define MOTION_COOLDOWN_MS 20000UL

#endif
