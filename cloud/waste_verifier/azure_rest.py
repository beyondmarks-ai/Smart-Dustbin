from __future__ import annotations

import json
import os
import threading
import time
import xml.etree.ElementTree as ET
from datetime import datetime, timezone
from email.utils import format_datetime, parsedate_to_datetime
from types import SimpleNamespace
from urllib.error import HTTPError
from urllib.parse import quote, urlencode
from urllib.request import Request, urlopen


class ManagedIdentityCredential:
    def __init__(self) -> None:
        self._cache = {}
        self._lock = threading.Lock()

    def get_token(self, scope: str):
        # App Service's managed-identity endpoint accepts an Azure AD resource,
        # not an SDK scope. Remove only ".default" so the required trailing
        # slash remains (for example, https://storage.azure.com/).
        resource = scope[:-8] if scope.endswith(".default") else scope
        with self._lock:
            cached = self._cache.get(resource)
            if cached and cached.expires_on > time.time() + 300:
                return cached

            url = os.environ["IDENTITY_ENDPOINT"] + "?" + urlencode({
                "api-version": "2019-08-01", "resource": resource
            })
            request = Request(
                url,
                headers={"X-IDENTITY-HEADER": os.environ["IDENTITY_HEADER"]},
                method="GET",
            )
            try:
                with urlopen(request, timeout=15) as response:
                    payload = json.loads(response.read())
            except HTTPError as error:
                detail = error.read().decode("utf-8", errors="replace")
                raise RuntimeError(
                    f"Managed identity HTTP {error.code}: {detail[:300]}"
                ) from error
            try:
                expires_on = int(payload.get("expires_on", time.time() + 3600))
            except (TypeError, ValueError):
                expires_on = int(time.time() + 3600)
            token = SimpleNamespace(token=payload["access_token"], expires_on=expires_on)
            self._cache[resource] = token
            return token


class ContentSettings:
    def __init__(self, content_type: str = "application/octet-stream") -> None:
        self.content_type = content_type


class HttpResponse:
    def __init__(self, status_code: int, content: bytes, headers) -> None:
        self.status_code = status_code
        self.content = content
        self.headers = headers


class BlobDownload:
    def __init__(self, content: bytes) -> None:
        self._content = content

    def readall(self) -> bytes:
        return self._content


class BlobProperties:
    def __init__(self, last_modified: str) -> None:
        self.last_modified = (
            parsedate_to_datetime(last_modified)
            if last_modified
            else datetime.now(timezone.utc)
        )


class BlobClient:
    def __init__(self, service, container: str, blob: str) -> None:
        self.service = service
        self.container = container
        self.blob = blob

    @property
    def url(self) -> str:
        return (
            f"{self.service.account_url}/{quote(self.container, safe='')}/"
            f"{quote(self.blob, safe='/')}"
        )

    def exists(self) -> bool:
        return self.service.request(
            "HEAD", self.url, allow_not_found=True
        ).status_code != 404

    def download_blob(self) -> BlobDownload:
        return BlobDownload(self.service.request("GET", self.url).content)

    def get_blob_properties(self) -> BlobProperties:
        response = self.service.request("HEAD", self.url)
        return BlobProperties(response.headers.get("Last-Modified", ""))

    def upload_blob(
        self, data: bytes | str, overwrite: bool = False, content_settings=None
    ) -> None:
        if isinstance(data, str):
            data = data.encode("utf-8")
        headers = {
            "x-ms-blob-type": "BlockBlob",
            "Content-Type": (
                content_settings.content_type
                if content_settings
                else "application/octet-stream"
            ),
        }
        if not overwrite:
            headers["If-None-Match"] = "*"
        self.service.request("PUT", self.url, headers=headers, data=data)


class ContainerClient:
    def __init__(self, service, container: str) -> None:
        self.service = service
        self.container = container

    def get_blob_client(self, blob: str) -> BlobClient:
        return BlobClient(self.service, self.container, blob)

    def download_blob(self, blob: str) -> BlobDownload:
        return self.get_blob_client(blob).download_blob()

    def list_blobs(self):
        marker = ""
        while True:
            params = {"restype": "container", "comp": "list"}
            if marker:
                params["marker"] = marker
            url = f"{self.service.account_url}/{quote(self.container, safe='')}"
            response = self.service.request("GET", url, params=params)
            root = ET.fromstring(response.content)
            for node in root.findall("./Blobs/Blob"):
                name = node.findtext("Name")
                if name:
                    yield SimpleNamespace(name=name)
            marker = root.findtext("NextMarker") or ""
            if not marker:
                return


class AzureBlobService:
    def __init__(self, account_url: str, credential: ManagedIdentityCredential) -> None:
        self.account_url = account_url.rstrip("/")
        self.credential = credential

    def request(
        self,
        method: str,
        url: str,
        *,
        params=None,
        headers=None,
        data=None,
        allow_not_found: bool = False,
    ) -> HttpResponse:
        if params:
            url += ("&" if "?" in url else "?") + urlencode(params)
        request_headers = {
            "Authorization": (
                "Bearer "
                + self.credential.get_token(
                    "https://storage.azure.com/.default"
                ).token
            ),
            "x-ms-version": "2023-11-03",
            "x-ms-date": format_datetime(datetime.now(timezone.utc), usegmt=True),
        }
        request_headers.update(headers or {})
        request = Request(
            url, data=data, headers=request_headers, method=method
        )
        try:
            with urlopen(request, timeout=45) as response:
                return HttpResponse(
                    response.status, response.read(), response.headers
                )
        except HTTPError as error:
            content = error.read()
            if allow_not_found and error.code == 404:
                return HttpResponse(error.code, content, error.headers)
            detail = content.decode("utf-8", errors="replace")
            raise RuntimeError(
                f"Azure Blob HTTP {error.code}: {detail[:500]}"
            ) from error

    def get_blob_client(self, container: str, blob: str) -> BlobClient:
        return BlobClient(self, container, blob)

    def get_container_client(self, container: str) -> ContainerClient:
        return ContainerClient(self, container)
