# Security and deployment notes

- Never commit `wifi_config.h`, `azure_config.h`, `aws_config.h`, real `.env` or `local.settings.json` files, signing keys, SAS URLs, device ingest keys or camera setup codes. Use the committed example files and keep real values local/Azure-side.
- The camera's local setup API uses HTTP, a device-specific setup code and a failed-code rate limit. Use only a trusted private hotspot; do not forward its port to the internet. Recovery Wi-Fi uses a device-specific password derived from that setup code. Physical USB access can retrieve the setup code by design.
- Firmware credentials and the saved network profile are not protected against physical flash extraction. The Android app stores the setup code in local preferences; it does not persist the entered hotspot password.
- The Azure prototype exposes anonymous history, image and dashboard endpoints. Its optional Event Grid webhook is also anonymous. Add appropriate authentication, authorization and webhook validation before production or private-data use. A local app session is not cloud authentication.
- The app defaults to the existing demo API. Set `AZURE_WASTE_API_BASE` to your own backend when deploying a separate installation. The app contains no device ingest credential.
- Rotate/revoke any accidentally published secret immediately; deleting it in a later commit does not remove it from history. Avoid including images, GPS coordinates or logs in public issues when they reveal private information.
- Android release builds currently use development signing. Set up private release signing before distributing through an app store.

Report vulnerabilities privately to the repository owner. Do not publish working credentials or private capture data in an issue.
