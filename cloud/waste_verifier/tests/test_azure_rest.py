import unittest

from azure_rest import BlobClient, ContentSettings


class RecordingService:
    account_url = "https://example.blob.core.windows.net"

    def __init__(self):
        self.data = None

    def request(self, method, url, **kwargs):
        self.data = kwargs["data"]


class BlobUploadTests(unittest.TestCase):
    def test_encodes_text_as_utf8(self):
        service = RecordingService()
        client = BlobClient(service, "analysis", "event.json")

        client.upload_blob(
            '{"summary":"recyclable bottle"}',
            overwrite=True,
            content_settings=ContentSettings("application/json"),
        )

        self.assertIsInstance(service.data, bytes)
        self.assertEqual(service.data, b'{"summary":"recyclable bottle"}')


if __name__ == "__main__":
    unittest.main()
