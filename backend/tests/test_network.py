from datetime import datetime, timezone
from unittest.mock import Mock

import defusedxml.ElementTree as ET
import pytest
import requests

import fetch_article as fa
from conftest import FakeResponse


def stub_get(monkeypatch, text="", status=200, **kw):
    get = Mock(return_value=FakeResponse(text, status), **kw)
    monkeypatch.setattr(fa.requests, "get", get)
    return get


def test_api_params_email(monkeypatch):
    monkeypatch.setattr(fa, "NCBI_EMAIL", "me@example.org")
    assert fa._api_params() == {"tool": "DailyDose", "email": "me@example.org"}
    monkeypatch.setattr(fa, "NCBI_EMAIL", "")
    assert fa._api_params() == {"tool": "DailyDose"}


def test_search_term_filters(frozen_now):
    term = fa._search_term()
    assert '"open access"[filter]' in term
    assert '"3000/12/31"[PDAT]' in term


def test_search_term_five_calendar_years(frozen_now):
    assert '"2021/11/17"[PDAT]' in fa._search_term()


def test_search_term_leap_day_maps_to_feb_28(monkeypatch):
    class LeapDay(datetime):
        @classmethod
        def now(cls, tz=None):
            return datetime(2028, 2, 29, 12, 0, tzinfo=timezone.utc)

    monkeypatch.setattr(fa, "datetime", LeapDay)
    assert '"2023/02/28"[PDAT]' in fa._search_term()


def test_search_count_parses_and_sends_params(monkeypatch):
    get = stub_get(monkeypatch, "<eSearchResult><Count>42</Count></eSearchResult>")
    assert fa._search_count() == 42
    assert get.call_args.args[0].endswith("/esearch.fcgi")
    params = get.call_args.kwargs["params"]
    assert (params["db"], params["rettype"], params["tool"]) == ("pmc", "count", "DailyDose")


@pytest.mark.parametrize("xml", ["<eSearchResult/>", "<eSearchResult><Count/></eSearchResult>"])
def test_search_count_missing_count(monkeypatch, xml):
    stub_get(monkeypatch, xml)
    with pytest.raises(ValueError):
        fa._search_count()


def test_search_count_http_error(monkeypatch):
    stub_get(monkeypatch, "", 500)
    with pytest.raises(requests.HTTPError):
        fa._search_count()


def test_search_random_id(monkeypatch):
    get = stub_get(monkeypatch, "<eSearchResult><IdList><Id>123</Id></IdList></eSearchResult>")
    assert fa._search_random_id(5) == "PMC123"
    assert get.call_args.kwargs["params"]["retmax"] == 1


@pytest.mark.parametrize("count,expected", [(5, (0, 4)), (50_000, (0, 9999))])
def test_search_random_id_offset_range(monkeypatch, count, expected):
    stub_get(monkeypatch, "<eSearchResult><IdList><Id>1</Id></IdList></eSearchResult>")
    spy = Mock(return_value=0)
    monkeypatch.setattr(fa.random, "randint", spy)
    fa._search_random_id(count)
    spy.assert_called_once_with(*expected)


@pytest.mark.parametrize("xml", [
    "<eSearchResult/>",
    "<eSearchResult><IdList/></eSearchResult>",
    "<eSearchResult><IdList><Id/></IdList></eSearchResult>",
])
def test_search_random_id_empty(monkeypatch, xml):
    stub_get(monkeypatch, xml)
    with pytest.raises(ValueError):
        fa._search_random_id(5)


def test_fetch_article_xml(monkeypatch):
    get = stub_get(monkeypatch, "<pmc-articleset><article/></pmc-articleset>")
    root = fa._fetch_article_xml("PMC123")
    assert root.tag == "pmc-articleset"
    assert get.call_args.args[0].endswith("/efetch.fcgi")
    assert get.call_args.kwargs["params"]["id"] == "123"


def test_fetch_article_xml_malformed(monkeypatch):
    stub_get(monkeypatch, "<bad")
    with pytest.raises(ET.ParseError):
        fa._fetch_article_xml("PMC1")


def test_fetch_image_map(monkeypatch):
    html = ('<img src="https://cdn.ncbi.nlm.nih.gov/pmc/blobs/a/1/f1.jpg">'
            '<img src="https://cdn.ncbi.nlm.nih.gov/pmc/blobs/b/2/f2.png">'
            '<img src="https://example.com/pmc/blobs/x/f3.jpg">')
    get = stub_get(monkeypatch, html)
    assert fa._fetch_image_map("PMC9") == {
        "f1": "https://cdn.ncbi.nlm.nih.gov/pmc/blobs/a/1/f1.jpg",
        "f2": "https://cdn.ncbi.nlm.nih.gov/pmc/blobs/b/2/f2.png",
    }
    assert get.call_args.args[0] == "https://pmc.ncbi.nlm.nih.gov/articles/PMC9/"
    assert get.call_args.kwargs["headers"]["User-Agent"].startswith("DailyDose/")


def test_fetch_image_map_failures_return_empty(monkeypatch):
    monkeypatch.setattr(fa.requests, "get", Mock(side_effect=requests.ConnectionError))
    assert fa._fetch_image_map("PMC1") == {}
    stub_get(monkeypatch, "", 404)
    assert fa._fetch_image_map("PMC1") == {}


def test_validate_image_urls(monkeypatch):
    def head(url, **kw):
        if "bad404" in url:
            return FakeResponse(status_code=404)
        if "slow" in url:
            raise requests.Timeout
        return FakeResponse(status_code=200)

    mock = Mock(side_effect=head)
    monkeypatch.setattr(fa.requests, "head", mock)
    p = {"content": [
        {"type": "paragraph", "text": "a"},
        {"type": "image", "url": "https://ok/1.jpg"},
        {"type": "image", "url": "https://bad404/2.jpg"},
        {"type": "heading", "text": "h"},
        {"type": "image", "url": "https://slow/3.jpg"},
        {"type": "table", "html": "<table/>"},
    ]}
    out = fa._validate_image_urls(p)
    assert [b["type"] for b in out["content"]] == ["paragraph", "image", "heading", "table"]
    assert out["content"][1]["url"] == "https://ok/1.jpg"
    assert all(c.kwargs["allow_redirects"] is True for c in mock.call_args_list)
