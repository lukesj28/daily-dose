from unittest.mock import Mock

import defusedxml.ElementTree as ET
import pytest
from xml.etree.ElementTree import Element

import fetch_article as fa
from conftest import CDN_URL

def x(xml: str) -> Element:
    return ET.fromstring(xml)

@pytest.mark.parametrize("raw,expected", [
    ("$$x$$", ("x", True)),
    (r"\[x\]", ("x", True)),
    ("$x$", ("x", False)),
    (r"\(x\)", ("x", False)),
    (r"\documentclass{a}\begin{document}$y$\end{document}", ("y", False)),
    ("z", ("z", True)),
    ("   ", None),
])
def test_extract_tex_expression(raw, expected):
    assert fa._extract_tex_expression(raw) == expected

def test_tex_to_mathml_display_and_inline():
    block = fa._tex_to_mathml("x^2", True)
    inline = fa._tex_to_mathml("x^2", False)
    assert block.startswith("<math") and 'display="block"' in block
    assert inline.startswith("<math") and 'display="inline"' in inline

def test_tex_to_mathml_failure_returns_none(monkeypatch):
    monkeypatch.setattr(fa.latex2mathml.converter, "convert", Mock(side_effect=ValueError("bad")))
    assert fa._tex_to_mathml("x", True) is None

@pytest.mark.parametrize("xml,expected", [
    ("<p><italic>t</italic></p>", "*t*"),
    ("<p><i>t</i></p>", "*t*"),
    ("<p><bold>t</bold></p>", "**t**"),
    ("<p><b>t</b></p>", "**t**"),
    ("<p><italic><bold>t</bold></italic></p>", "***t***"),
    ("<p>10<sup>5</sup></p>", "10^(5)"),
    ("<p>CO<sub>2</sub></p>", "CO_(2)"),
    ("<p>a<xref>1</xref>.</p>", "a."),
    ("<p>a<sup><xref>1</xref></sup>.</p>", "a."),
    ("<p>a<sub> </sub>.</p>", "a."),
    ("<p>a<bold/>.</p>", "a."),
    ("<p>a<inline-formula><tex-math>$x$</tex-math></inline-formula>b</p>", "a x b"),
    ("<p>a<inline-formula><tex-math>$x$</tex-math></inline-formula></p>", "a x "),
    ("<p>a<inline-formula><tex-math>   </tex-math></inline-formula>b</p>", "ab"),
    ("<p>a<inline-formula><alternatives/></inline-formula>b</p>", "ab"),
    ("<p>a<ext-link>link</ext-link>b</p>", "alinkb"),
    ('<p xmlns:x="urn:x"><x:italic>t</x:italic></p>', "*t*"),
])
def test_element_to_markdown(xml, expected):
    assert fa._element_to_markdown(x(xml)) == expected

def test_sanitize_removes_blocked_tags_nested_and_uppercase():
    el = x("<table><tr><td>a<script>1</script></td></tr><SCRIPT>2</SCRIPT>"
           "<div><style>p{}</style><iframe/></div></table>")
    fa._sanitize_element(el)
    tags = {e.tag.lower() for e in el.iter()}
    assert tags.isdisjoint({"script", "style", "iframe"})
    assert "td" in tags

def test_sanitize_removes_event_handlers_including_namespaced():
    el = x('<td xmlns:n="urn:n" onclick="a()" n:onload="b()" colspan="2"/>')
    fa._sanitize_element(el)
    assert el.attrib == {"colspan": "2"}

@pytest.mark.parametrize("attr,value", [
    ("href", "javascript:alert(1)"),
    ("src", " JaVaScRiPt:alert(1)"),
    ("href", "data:text/html,<b>x</b>"),
    ("href", "java\x00script:alert(1)"),
])
def test_sanitize_removes_dangerous_urls(attr, value):
    el = Element("a")
    el.set(attr, value)
    fa._sanitize_element(el)
    assert attr not in el.attrib

def test_sanitize_keeps_safe_url():
    el = x('<a href="https://example.org">x</a>')
    fa._sanitize_element(el)
    assert el.get("href") == "https://example.org"

def test_extract_authors_excludes_editors_and_nameless():
    meta = x("""<article-meta><contrib-group>
      <contrib contrib-type="author"><name><surname>Smith</surname><given-names>Jane</given-names></name></contrib>
      <contrib contrib-type="author"><name><surname>Doe</surname></name></contrib>
      <contrib contrib-type="author"><name><given-names>Nobody</given-names></name></contrib>
      <contrib contrib-type="editor"><name><surname>Editor</surname><given-names>Ed</given-names></name></contrib>
    </contrib-group></article-meta>""")
    assert fa._extract_authors(meta) == ["Jane Smith", "Doe"]

def test_extract_publish_date_pads_and_defaults():
    assert fa._extract_publish_date(x(
        "<m><pub-date><day>5</day><month>3</month><year>2024</year></pub-date></m>")) == "2024-03-05"
    assert fa._extract_publish_date(x("<m><pub-date><year>2024</year></pub-date></m>")) == "2024-01-01"

def test_extract_publish_date_skips_dates_without_year():
    meta = x("<m><pub-date><month>3</month></pub-date><pub-date><year>2020</year></pub-date></m>")
    assert fa._extract_publish_date(meta) == "2020-01-01"

def test_extract_publish_date_none():
    assert fa._extract_publish_date(x("<m/>")) == ""

def test_extract_journal():
    assert fa._extract_journal(x(
        "<front><journal-meta><journal-title>Journal of Testing</journal-title></journal-meta></front>"
    )) == "Journal of Testing"
    assert fa._extract_journal(x("<front><journal-meta/></front>")) == ""
    assert fa._extract_journal(x("<front/>")) == ""

@pytest.mark.parametrize("href", [
    "https://creativecommons.org/licenses/by/4.0/",
    "http://creativecommons.org/licenses/by/4.0",
    "https://creativecommons.org/licenses/by/4.0",
])
def test_extract_license_known_cc(href):
    meta = x(f'<m xmlns:xlink="http://www.w3.org/1999/xlink"><permissions>'
             f'<license xlink:href="{href}"><license-p>ignored</license-p></license></permissions></m>')
    assert fa._extract_license(meta) == \
        "Creative Commons Attribution 4.0 International License (CC BY 4.0)"

def test_extract_license_skips_non_href_attributes():
    meta = x('<m xmlns:xlink="urn:x"><permissions><license license-type="open" '
             'xlink:href="https://creativecommons.org/publicdomain/zero/1.0/"/></permissions></m>')
    assert fa._extract_license(meta) == "Public Domain (CC0 1.0)"

def test_extract_license_unknown_href_uses_license_p():
    meta = x('<m xmlns:xlink="urn:x"><permissions><license xlink:href="https://example.org/l">'
             '<license-p>Custom terms</license-p></license></permissions></m>')
    assert fa._extract_license(meta) == "Custom terms"

@pytest.mark.parametrize("xml", [
    '<m xmlns:xlink="urn:x"><permissions><license xlink:href="https://example.org/l"><license-p> </license-p></license></permissions></m>',
    "<m><permissions><license/></permissions></m>",
    "<m><permissions/></m>",
    "<m/>",
])
def test_extract_license_fallback_open_access(xml):
    assert fa._extract_license(x(xml)) == "Open Access"

FIG = ('<sec xmlns:xlink="http://www.w3.org/1999/xlink"><fig><label>Figure 1</label>'
       '<caption><title>Cells</title><p>Under <bold>40x</bold>.</p></caption>'
       '<graphic xlink:href="{href}"/></fig></sec>')

def _fig(href="fig1"):
    return fa._find_deep(x(FIG.format(href=href)), "fig")

def test_parse_figure():
    assert fa._parse_figure(_fig(), {"fig1": CDN_URL}) == {
        "type": "image", "url": CDN_URL, "caption": "Figure 1 Cells Under **40x**."}

def test_parse_figure_resolves_stem_from_path_with_extension():
    assert fa._parse_figure(_fig("images/fig1.tif"), {"fig1": CDN_URL})["url"] == CDN_URL

def test_parse_figure_excludes_nested_caption_paragraphs():
    fig = x('<fig xmlns:xlink="urn:x"><caption><p>Direct</p><list><p>Deep</p></list></caption>'
            '<graphic xlink:href="fig1"/></fig>')
    assert fa._parse_figure(fig, {"fig1": CDN_URL})["caption"] == "Direct"

def test_parse_figure_without_label_or_caption_has_empty_caption():
    fig = x('<fig xmlns:xlink="urn:x"><graphic xlink:href="fig1"/></fig>')
    assert fa._parse_figure(fig, {"fig1": CDN_URL})["caption"] == ""
    fig = x('<fig xmlns:xlink="urn:x"><caption><p>Only p</p></caption><graphic xlink:href="fig1"/></fig>')
    assert fa._parse_figure(fig, {"fig1": CDN_URL})["caption"] == "Only p"

def test_parse_figure_href_found_after_other_attributes():
    fig = x('<fig xmlns:xlink="urn:x"><graphic id="g1" xlink:href="fig1"/></fig>')
    assert fa._parse_figure(fig, {"fig1": CDN_URL})["url"] == CDN_URL

@pytest.mark.parametrize("xml,image_map", [
    ("<fig/>", {"fig1": CDN_URL}),
    ('<fig xmlns:xlink="urn:x"><graphic xlink:href=""/></fig>', {"fig1": CDN_URL}),
    ('<fig xmlns:xlink="urn:x"><graphic xlink:href="other"/></fig>', {"fig1": CDN_URL}),
    ("<fig><graphic/></fig>", {"fig1": CDN_URL}),
])
def test_parse_figure_unresolvable_returns_none(xml, image_map):
    assert fa._parse_figure(x(xml), image_map) is None

def test_parse_table(article_xml):
    wrap = fa._find_deep(x(article_xml), "table-wrap")
    block = fa._parse_table(wrap)
    assert block["type"] == "table"
    assert block["caption"] == "Table 1 Results"
    assert "<table" in block["html"]
    for kept in ("Variable", ">A<"):
        assert kept in block["html"]
    for banned in ("onclick", "<script", "xmlns"):
        assert banned not in block["html"]

def test_parse_table_without_label_or_caption_and_without_table():
    wrap = x("<table-wrap><table><tr><td>a</td></tr></table></table-wrap>")
    assert fa._parse_table(wrap)["caption"] == ""
    wrap = x("<table-wrap><caption><p>no title</p></caption><table><tr><td>a</td></tr></table></table-wrap>")
    assert fa._parse_table(wrap)["caption"] == ""
    assert fa._parse_table(x("<table-wrap><label>Table 1</label></table-wrap>")) is None

def test_parse_body_fixture_sequence(article_xml):
    body = fa._find_deep(x(article_xml), "body")
    blocks = fa._parse_body(body, {"fig1": CDN_URL})
    assert [(b["type"], b.get("text")) for b in blocks] == [
        ("heading", "Introduction"),
        ("paragraph", "Paragraph one with *E. coli*."),
        ("paragraph", "Paragraph two with CO_(2) and 10^(5) cells."),
        ("heading", "Background"),
        ("paragraph", "Paragraph three."),
        ("heading", "Results"),
        ("paragraph", "Paragraph four."),
        ("image", None),
        ("table", None),
        ("math", None),
    ]
    assert blocks[7]["url"] == CDN_URL
    assert blocks[9]["mathml"].startswith("<math")

def test_parse_body_skips_empty_and_unresolvable_elements():
    body = x("""<body><sec><title/><p/><list><p>ignored</p></list>
      <fig><label>F</label></fig><table-wrap><label>T</label></table-wrap>
      <disp-formula/><disp-formula><tex-math>  </tex-math></disp-formula>
      <p>kept</p></sec></body>""")
    assert fa._parse_body(body, {}) == [{"type": "paragraph", "text": "kept"}]

def test_parse_body_skips_formula_when_conversion_fails(monkeypatch):
    monkeypatch.setattr(fa.latex2mathml.converter, "convert", Mock(side_effect=ValueError))
    body = x("<body><disp-formula><tex-math>$$x$$</tex-math></disp-formula></body>")
    assert fa._parse_body(body, {}) == []

def test_parse_article_fixture(frozen_now, fake_ncbi, article_xml):
    payload = fa._parse_article(x(article_xml), "PMC123")
    assert set(payload) == {"id", "title", "journal", "fetch_date", "publish_date", "authors",
                            "license", "source_url", "abstract", "content"}
    assert payload["id"] == "PMC123"
    assert payload["title"] == "A Novel Approach"
    assert payload["journal"] == "Journal of Testing"
    assert payload["fetch_date"] == "2026-11-17"
    assert payload["publish_date"] == "2024-03-05"
    assert payload["authors"] == ["Jane Smith", "Doe"]
    assert payload["license"].startswith("Creative Commons Attribution 4.0")
    assert payload["source_url"] == "https://www.ncbi.nlm.nih.gov/pmc/articles/PMC123/"
    assert payload["abstract"] == "First **finding**. Second finding."
    assert [b["type"] for b in payload["content"]].count("image") == 1

def test_parse_article_without_figures_skips_pmc_page(fake_ncbi):
    get = fake_ncbi[0]
    root = x("<article><front><article-meta/></front><body><p>text</p></body></article>")
    payload = fa._parse_article(root, "PMC1")
    assert payload["content"] == [{"type": "paragraph", "text": "text"}]
    assert payload["abstract"] == ""
    assert payload["license"] == "Open Access"
    get.assert_not_called()

def test_parse_article_accepts_bare_article_and_wrapperless_root(article_xml, fake_ncbi):
    bare = fa._find_deep(x(article_xml), "article")
    assert fa._parse_article(bare, "PMC1")["title"] == "A Novel Approach"
    wrapped = x("<doc><front><article-meta/></front><body><p>t</p></body></doc>")
    assert fa._parse_article(wrapped, "PMC1")["content"][0]["text"] == "t"

@pytest.mark.parametrize("xml", [
    "<article><body><p>t</p></body></article>",
    "<article><front/><body><p>t</p></body></article>",
    "<article><front><article-meta/></front></article>",
])
def test_parse_article_missing_required_sections_returns_none(xml):
    assert fa._parse_article(x(xml), "PMC1") is None

def test_parse_article_missing_title_group_gives_empty_title():
    payload = fa._parse_article(
        x("<article><front><article-meta/></front><body/></article>"), "PMC1")
    assert payload["title"] == ""
