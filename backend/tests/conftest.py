from datetime import datetime, timezone
from pathlib import Path
from unittest.mock import Mock

import pytest
import requests

import fetch_article

CDN_URL = "https://cdn.ncbi.nlm.nih.gov/pmc/blobs/abc/123/fig1.jpg"


class FakeResponse:
    def __init__(self, text="", status_code=200):
        self.text = text
        self.status_code = status_code

    def raise_for_status(self):
        if self.status_code >= 400:
            raise requests.HTTPError(f"{self.status_code}")


class _FrozenDatetime(datetime):
    @classmethod
    def now(cls, tz=None):
        return datetime(2026, 11, 17, 12, 0, tzinfo=timezone.utc)


@pytest.fixture
def frozen_now(monkeypatch):
    monkeypatch.setattr(fetch_article, "datetime", _FrozenDatetime)


@pytest.fixture
def article_xml():
    return (Path(__file__).parent / "fixtures" / "article.xml").read_text(encoding="utf-8")


@pytest.fixture
def fake_ncbi(monkeypatch, article_xml):
    """Route all NCBI/PMC GETs to canned responses. Returns (get, head, sleep) mocks."""

    def route(url, params=None, **kwargs):
        if url.endswith("esearch.fcgi"):
            if params.get("rettype") == "count":
                return FakeResponse("<eSearchResult><Count>42</Count></eSearchResult>")
            return FakeResponse("<eSearchResult><IdList><Id>123</Id></IdList></eSearchResult>")
        if url.endswith("efetch.fcgi"):
            return FakeResponse(article_xml)
        if url.startswith("https://pmc.ncbi.nlm.nih.gov/articles/"):
            return FakeResponse(f'<img src="{CDN_URL}">')
        raise AssertionError(f"unexpected GET {url}")

    get = Mock(side_effect=route)
    head = Mock(return_value=FakeResponse(status_code=200))
    sleep = Mock()
    monkeypatch.setattr(fetch_article.requests, "get", get)
    monkeypatch.setattr(fetch_article.requests, "head", head)
    monkeypatch.setattr(fetch_article.time, "sleep", sleep)
    return get, head, sleep
