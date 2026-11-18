import json
import logging
from pathlib import Path
import re

import pytest
import requests

import fetch_article as fa
from conftest import CDN_URL, FakeResponse

def payload(paragraph_lengths=(10, 10, 10, 10), title="T", authors=("A",), extra=()):
    content = [{"type": "paragraph", "text": "x" * n} for n in paragraph_lengths]
    return {"title": title, "authors": list(authors), "content": content + list(extra)}

def test_validate_payload_valid():
    assert fa._validate_payload(payload()) is True

@pytest.mark.parametrize("p", [payload(title=""), payload(title=None), payload(authors=())])
def test_validate_payload_missing_metadata(p):
    assert fa._validate_payload(p) is False

def test_validate_payload_needs_more_than_three_paragraphs_headings_dont_count():
    p = payload((10, 10, 10), extra=[{"type": "heading", "text": "h"}])
    assert fa._validate_payload(p) is False

def test_validate_payload_char_limit_boundaries():
    assert fa._validate_payload(payload((12000, 12000, 12000, 13999))) is True
    assert fa._validate_payload(payload((12000, 12000, 12000, 14001))) is False

def test_validate_payload_exactly_limit_rejected():
    assert fa._validate_payload(payload((12000, 12000, 12000, 14000))) is False

@pytest.mark.parametrize("block", [
    {"type": "table", "html": "h" * 50_000, "caption": ""},
    {"type": "image", "url": "u", "caption": "c" * 50_000},
])
def test_validate_payload_counts_html_and_caption(block):
    assert fa._validate_payload(payload(extra=[block])) is False

@pytest.fixture
def out(monkeypatch, tmp_path):
    path = tmp_path / "public" / "today.json"
    monkeypatch.setattr(fa, "OUTPUT_PATH", path)
    return path

def test_main_success_writes_data_contract(out, fake_ncbi, frozen_now, monkeypatch):
    monkeypatch.setattr(fa, "NCBI_EMAIL", "me@example.org")
    assert fa.main() is None
    assert fake_ncbi[0].call_args_list[0].kwargs["params"]["email"] == "me@example.org"
    data = json.loads(out.read_text(encoding="utf-8"))
    assert data["id"] == "PMC123"
    assert data["title"] == "A Novel Approach"
    assert data["fetch_date"] == "2026-11-17"
    assert data["publish_date"] == "2024-03-05"
    assert data["authors"] == ["Jane Smith", "Doe"]
    assert data["journal"] == "Journal of Testing"
    assert data["source_url"] == "https://www.ncbi.nlm.nih.gov/pmc/articles/PMC123/"
    assert data["license"].startswith("Creative Commons Attribution 4.0")
    assert [b["url"] for b in data["content"] if b["type"] == "image"] == [CDN_URL]

def test_main_all_retries_fail_keeps_yesterdays_file(out, fake_ncbi, monkeypatch, caplog):
    out.parent.mkdir(parents=True)
    out.write_text('{"id":"yesterday"}')
    get, _, _ = fake_ncbi
    get.side_effect = requests.ConnectionError("down")
    monkeypatch.setattr(fa, "NCBI_EMAIL", "")
    with caplog.at_level(logging.WARNING), pytest.raises(SystemExit) as exc:
        fa.main()
    assert exc.value.code == 0
    assert out.read_text() == '{"id":"yesterday"}'
    assert get.call_count == 5
    assert "NCBI_EMAIL not set" in caplog.text

def _fail_first_attempt(fake_ncbi, article_xml, kind):
    """Wrap the router so attempt 1 fails in the given way; attempt 2 is normal."""
    get = fake_ncbi[0]
    ok = get.side_effect
    state = {"attempt": 0}
    no_body = re.sub(r"<body>.*</body>", "", article_xml, flags=re.DOTALL)
    one_paragraph = re.sub(r"<p>Paragraph (?:two|three|four).*?</p>", "", article_xml)

    def route(url, params=None, **kw):
        is_count = url.endswith("esearch.fcgi") and params.get("rettype") == "count"
        if is_count:
            state["attempt"] += 1
            if state["attempt"] == 1 and kind == "zero":
                return FakeResponse("<eSearchResult><Count>0</Count></eSearchResult>")
            if state["attempt"] == 1 and kind == "no_count":
                return FakeResponse("<eSearchResult/>")
        if url.endswith("efetch.fcgi") and state["attempt"] == 1:
            return FakeResponse({"bad_xml": "<bad", "no_body": no_body,
                                 "invalid": one_paragraph}[kind])
        return ok(url, params=params, **kw)

    get.side_effect = route

@pytest.mark.parametrize("kind", ["zero", "bad_xml", "no_body", "no_count", "invalid"])
def test_main_retries_after_failure_then_succeeds(out, fake_ncbi, frozen_now, article_xml, kind):
    _fail_first_attempt(fake_ncbi, article_xml, kind)
    fa.main()
    assert json.loads(out.read_text(encoding="utf-8"))["id"] == "PMC123"

def test_main_output_matches_ios_contract_fixture(out, fake_ncbi, frozen_now):
    fa.main()
    produced = json.loads(out.read_text(encoding="utf-8"))
    fixture = json.loads((Path(__file__).parents[2] / "ios-app/DailyDoseTests/Fixtures/today.json").read_text(encoding="utf-8"))
    assert produced.keys() == fixture.keys()
    assert [b["type"] for b in produced["content"]] == [b["type"] for b in fixture["content"]]
    for got, want in zip(produced["content"], fixture["content"]):
        assert got.keys() == want.keys()
