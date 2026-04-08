#!/usr/bin/env python3

import json
import logging
import os
import random
import re
import sys
import time
from datetime import datetime, timedelta, timezone
from pathlib import Path
import defusedxml.ElementTree as ET

import requests

TOOL_NAME = "DailyDose"
NCBI_EMAIL = os.environ.get("NCBI_EMAIL", "")
BASE_URL = "https://eutils.ncbi.nlm.nih.gov/entrez/eutils"
MAX_RETRIES = 5
MAX_CHAR_COUNT = 50_000
PMC_ARTICLE_BASE = "https://pmc.ncbi.nlm.nih.gov/articles"
OUTPUT_PATH = Path(__file__).resolve().parent.parent / "public" / "today.json"

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s [%(levelname)s] %(message)s",
)
log = logging.getLogger(__name__)


# --- XML → Markdown ---

INLINE_TAG_MAP = {
    "italic": "*",
    "i": "*",
    "bold": "**",
    "b": "**",
}


def _element_to_markdown(element: ET.Element) -> str:
    parts: list[str] = []

    if element.text:
        parts.append(element.text)

    for child in element:
        tag = _local_tag(child.tag)

        if tag == "xref":
            if child.tail:
                parts.append(child.tail)
            continue

        if tag in INLINE_TAG_MAP:
            marker = INLINE_TAG_MAP[tag]
            inner = _element_to_markdown(child).strip()
            if inner:
                parts.append(f"{marker}{inner}{marker}")
        elif tag == "sup":
            inner = _element_to_markdown(child).strip()
            if inner:
                parts.append(f"^({inner})")
        elif tag == "sub":
            inner = _element_to_markdown(child).strip()
            if inner:
                parts.append(f"_({inner})")
        else:
            parts.append(_element_to_markdown(child))

        if child.tail:
            parts.append(child.tail)

    return "".join(parts)


def _local_tag(tag: str) -> str:
    if "}" in tag:
        return tag.split("}", 1)[1]
    return tag


# --- PubMed API ---


def _api_params() -> dict:
    params = {"tool": TOOL_NAME}
    if NCBI_EMAIL:
        params["email"] = NCBI_EMAIL
    return params


def _search_term() -> str:
    five_years_ago = (datetime.now(timezone.utc) - timedelta(days=5 * 365)).strftime(
        "%Y/%m/%d"
    )
    return (
        '"open access"[filter] '
        f'AND ("{five_years_ago}"[PDAT] : "3000/12/31"[PDAT])'
    )


def _search_count() -> int:
    term = _search_term()
    params = {
        **_api_params(),
        "db": "pmc",
        "term": term,
        "rettype": "count",
    }
    log.info("ESearch (count) term=%s", term)
    resp = requests.get(f"{BASE_URL}/esearch.fcgi", params=params, timeout=30)
    resp.raise_for_status()

    root = ET.fromstring(resp.text)
    count_el = root.find("Count")
    if count_el is None or not count_el.text:
        raise ValueError("ESearch returned no Count element")
    count = int(count_el.text)
    log.info("Total PMC articles matching: %d", count)
    return count


def _search_random_id(count: int) -> str:
    offset = random.randint(0, min(count - 1, 9999))  # PMC's retstart hard limit is 9999
    term = _search_term()
    params = {
        **_api_params(),
        "db": "pmc",
        "term": term,
        "retstart": offset,
        "retmax": 1,
    }
    log.info("ESearch (fetch ID) offset=%d", offset)
    resp = requests.get(f"{BASE_URL}/esearch.fcgi", params=params, timeout=30)
    resp.raise_for_status()

    root = ET.fromstring(resp.text)
    id_list = root.find("IdList")
    if id_list is None:
        raise ValueError("ESearch returned no IdList")
    id_el = id_list.find("Id")
    if id_el is None or not id_el.text:
        raise ValueError("ESearch returned empty IdList")

    pmcid = f"PMC{id_el.text}"
    log.info("Selected article: %s", pmcid)
    return pmcid


def _fetch_article_xml(pmcid: str) -> ET.Element:
    numeric_id = pmcid.replace("PMC", "")
    params = {
        **_api_params(),
        "db": "pmc",
        "id": numeric_id,
        "rettype": "full",
        "retmode": "xml",
    }
    log.info("EFetch id=%s", numeric_id)
    resp = requests.get(f"{BASE_URL}/efetch.fcgi", params=params, timeout=60)
    resp.raise_for_status()
    return ET.fromstring(resp.text)


# --- HTML Sanitization ---

_BLOCKED_TAGS = {"script", "style", "object", "embed", "iframe", "frame", "link", "meta", "base"}
_URL_ATTRS = {"href", "src", "action", "formaction", "data"}


def _sanitize_element(element: ET.Element) -> None:
    for child in list(element):
        tag = _local_tag(child.tag).lower()
        if tag in _BLOCKED_TAGS:
            element.remove(child)
        else:
            _sanitize_element(child)

    for attr in list(element.attrib):
        attr_local = attr.split("}")[-1].lower() if "}" in attr else attr.lower()
        if attr_local.startswith("on"):
            del element.attrib[attr]
        elif attr_local in _URL_ATTRS:
            val = element.attrib[attr].strip().lower().replace("\x00", "")
            if val.startswith("javascript:") or val.startswith("data:"):
                del element.attrib[attr]


# --- XML Parsing ---


def _extract_text(element: ET.Element | None) -> str:
    if element is None:
        return ""
    return "".join(element.itertext()).strip()


def _find_deep(root: ET.Element, tag: str) -> ET.Element | None:
    for el in root.iter():
        if _local_tag(el.tag) == tag:
            return el
    return None


def _find_all_deep(root: ET.Element, tag: str) -> list[ET.Element]:
    return [el for el in root.iter() if _local_tag(el.tag) == tag]


def _extract_authors(article_meta: ET.Element) -> list[str]:
    authors: list[str] = []
    for contrib in _find_all_deep(article_meta, "contrib"):
        if contrib.get("contrib-type") != "author":
            continue
        surname = _extract_text(_find_deep(contrib, "surname"))
        given = _extract_text(_find_deep(contrib, "given-names"))
        if surname:
            name = f"{given} {surname}".strip() if given else surname
            authors.append(name)
    return authors


def _extract_publish_date(article_meta: ET.Element) -> str:
    for pub_date in _find_all_deep(article_meta, "pub-date"):
        year = _extract_text(_find_deep(pub_date, "year"))
        month = _extract_text(_find_deep(pub_date, "month")) or "01"
        day = _extract_text(_find_deep(pub_date, "day")) or "01"
        if year:
            return f"{year}-{month.zfill(2)}-{day.zfill(2)}"
    return ""


def _extract_journal(root: ET.Element) -> str:
    journal_title = _find_deep(root, "journal-title")
    if journal_title is not None:
        return _extract_text(journal_title)
    journal_meta = _find_deep(root, "journal-meta")
    if journal_meta is not None:
        jt = _find_deep(journal_meta, "journal-title")
        return _extract_text(jt) if jt is not None else ""
    return ""


def _fetch_image_map(pmcid: str) -> dict[str, str]:
    """Scrape the PMC article page to map image filename stems → CDN blob URLs.

    The NLM JATS XML only gives us a short graphic id (e.g. "ao5c13251_0001"),
    but PMC now serves images from cdn.ncbi.nlm.nih.gov/pmc/blobs/<hash>/... with
    an opaque path we can't construct. The rendered HTML has the real src.
    """
    url = f"{PMC_ARTICLE_BASE}/{pmcid}/"
    try:
        resp = requests.get(
            url,
            timeout=30,
            headers={"User-Agent": f"{TOOL_NAME}/1.0"},
        )
        resp.raise_for_status()
    except requests.RequestException as exc:
        log.warning("Failed to fetch PMC article page for image URLs: %s", exc)
        return {}

    mapping: dict[str, str] = {}
    for match in re.finditer(
        r'src="(https://cdn\.ncbi\.nlm\.nih\.gov/pmc/blobs/[^"]+)"', resp.text
    ):
        full_url = match.group(1)
        filename = full_url.rsplit("/", 1)[-1]
        stem = filename.rsplit(".", 1)[0]
        mapping[stem] = full_url
    log.info("Resolved %d image URLs from PMC page", len(mapping))
    return mapping


def _parse_figure(fig_el: ET.Element, image_map: dict[str, str]) -> dict | None:
    graphic = _find_deep(fig_el, "graphic")
    if graphic is None:
        return None

    # xlink:href is namespace-qualified; match any attr containing "href"
    href = None
    for attr_key, attr_val in graphic.attrib.items():
        if "href" in attr_key:
            href = attr_val
            break

    if not href:
        return None

    stem = href.rsplit("/", 1)[-1].rsplit(".", 1)[0]
    url = image_map.get(stem)
    if not url:
        log.warning("No CDN URL found for figure %s", stem)
        return None

    caption_parts: list[str] = []
    label = _find_deep(fig_el, "label")
    if label is not None:
        caption_parts.append(_extract_text(label))

    caption_el = _find_deep(fig_el, "caption")
    if caption_el is not None:
        title = _find_deep(caption_el, "title")
        if title is not None:
            caption_parts.append(_element_to_markdown(title).strip())
        for p in _find_all_deep(caption_el, "p"):
            if p in list(caption_el):
                caption_parts.append(_element_to_markdown(p).strip())

    caption = " ".join(caption_parts).strip()
    return {"type": "image", "url": url, "caption": caption}


def _parse_table(table_wrap: ET.Element) -> dict | None:
    table_el = _find_deep(table_wrap, "table")
    if table_el is None:
        return None

    _sanitize_element(table_el)
    html = ET.tostring(table_el, encoding="unicode", method="html")
    html = re.sub(r'\s+xmlns[^"]*"[^"]*"', "", html)

    caption_parts: list[str] = []
    label = _find_deep(table_wrap, "label")
    if label is not None:
        caption_parts.append(_extract_text(label))
    caption_el = _find_deep(table_wrap, "caption")
    if caption_el is not None:
        title = _find_deep(caption_el, "title")
        if title is not None:
            caption_parts.append(_extract_text(title))

    caption = " ".join(caption_parts).strip()
    return {"type": "table", "html": html, "caption": caption}


def _parse_body(body: ET.Element, image_map: dict[str, str]) -> list[dict]:
    content: list[dict] = []

    def _walk_section(section: ET.Element):
        for child in section:
            tag = _local_tag(child.tag)

            if tag == "title":
                text = _element_to_markdown(child).strip()
                if text:
                    content.append({"type": "heading", "text": text})
            elif tag == "p":
                text = _element_to_markdown(child).strip()
                if text:
                    content.append({"type": "paragraph", "text": text})
            elif tag == "sec":
                _walk_section(child)
            elif tag == "fig":
                fig_block = _parse_figure(child, image_map)
                if fig_block:
                    content.append(fig_block)
            elif tag == "table-wrap":
                table_block = _parse_table(child)
                if table_block:
                    content.append(table_block)

    _walk_section(body)
    return content


def _parse_article(root: ET.Element, pmcid: str) -> dict | None:
    article = _find_deep(root, "article")
    if article is None:
        article = root

    front = _find_deep(article, "front")
    if front is None:
        log.warning("No <front> element found")
        return None

    article_meta = _find_deep(front, "article-meta")
    if article_meta is None:
        log.warning("No <article-meta> element found")
        return None

    title_group = _find_deep(article_meta, "title-group")
    title = _extract_text(_find_deep(title_group, "article-title")) if title_group is not None else ""
    authors = _extract_authors(article_meta)
    publish_date = _extract_publish_date(article_meta)
    journal = _extract_journal(front)

    abstract_el = _find_deep(article_meta, "abstract")
    abstract = ""
    if abstract_el is not None:
        abstract_paragraphs = _find_all_deep(abstract_el, "p")
        abstract = " ".join(_element_to_markdown(p).strip() for p in abstract_paragraphs)

    body = _find_deep(article, "body")
    if body is None:
        log.warning("No <body> element found")
        return None

    image_map = _fetch_image_map(pmcid) if _find_deep(body, "fig") is not None else {}
    content = _parse_body(body, image_map)

    return {
        "id": pmcid,
        "title": title,
        "journal": journal,
        "fetch_date": datetime.now(timezone.utc).strftime("%Y-%m-%d"),
        "publish_date": publish_date,
        "authors": authors,
        "abstract": abstract,
        "content": content,
    }


# --- Validation ---


def _validate_image_urls(payload: dict) -> dict:
    validated_content: list[dict] = []
    for block in payload["content"]:
        if block["type"] == "image":
            url = block.get("url", "")
            try:
                resp = requests.head(url, timeout=10, allow_redirects=True)
                if resp.status_code == 200:
                    validated_content.append(block)
                else:
                    log.warning("Image URL returned %d, removing: %s", resp.status_code, url)
            except requests.RequestException as exc:
                log.warning("Image URL unreachable (%s), removing: %s", exc, url)
        else:
            validated_content.append(block)

    payload["content"] = validated_content
    return payload


def _validate_payload(payload: dict) -> bool:
    if not payload.get("title"):
        log.warning("Validation failed: no title")
        return False

    if not payload.get("authors"):
        log.warning("Validation failed: no authors")
        return False

    paragraph_count = sum(
        1 for b in payload["content"] if b["type"] == "paragraph"
    )
    if paragraph_count <= 3:
        log.warning("Validation failed: only %d paragraphs (need >3)", paragraph_count)
        return False

    total_chars = sum(
        len(b.get("text", "") + b.get("html", "") + b.get("caption", ""))
        for b in payload["content"]
    )
    if total_chars > MAX_CHAR_COUNT:
        log.warning("Validation failed: %d chars exceeds %d limit", total_chars, MAX_CHAR_COUNT)
        return False

    log.info(
        "Validation passed: title=%r, authors=%d, paragraphs=%d, chars=%d",
        payload["title"][:60],
        len(payload["authors"]),
        paragraph_count,
        total_chars,
    )
    return True


# --- Main ---


def main():
    if not NCBI_EMAIL:
        log.warning("NCBI_EMAIL not set. Requests may be throttled.")

    for attempt in range(1, MAX_RETRIES + 1):
        log.info("=== Attempt %d/%d ===", attempt, MAX_RETRIES)
        try:
            count = _search_count()
            if count == 0:
                log.error("No articles found matching query")
                continue

            time.sleep(0.4)
            pmcid = _search_random_id(count)
            time.sleep(0.4)
            xml_root = _fetch_article_xml(pmcid)

            payload = _parse_article(xml_root, pmcid)
            if payload is None:
                log.warning("Parsing returned None, retrying...")
                continue

            payload = _validate_image_urls(payload)

            if not _validate_payload(payload):
                continue

            OUTPUT_PATH.parent.mkdir(parents=True, exist_ok=True)
            with open(OUTPUT_PATH, "w", encoding="utf-8") as f:
                json.dump(payload, f, indent=2, ensure_ascii=False)

            log.info("✅ Successfully wrote %s", OUTPUT_PATH)
            return

        except requests.RequestException as exc:
            log.error("Network error: %s", exc)
        except ET.ParseError as exc:
            log.error("XML parse error: %s", exc)
        except Exception as exc:
            log.error("Unexpected error: %s", exc, exc_info=True)

        if attempt < MAX_RETRIES:
            wait = 2**attempt
            log.info("Waiting %ds before retry...", wait)
            time.sleep(wait)

    log.error(
        "❌ All %d retries exhausted. Exiting without overwriting today.json.",
        MAX_RETRIES,
    )
    sys.exit(0)


if __name__ == "__main__":
    main()
