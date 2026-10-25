"""Unit tests for the book-lookup skill script.

Run directly (`python3 tool/test/book_lookup_test.py`) or through the Python CI
job. Network calls are replaced by canned Open Library and Crossref responses.
"""

import contextlib
import importlib.util
import io
import json
import sys
import unittest
from pathlib import Path
from unittest import mock

SCRIPT = (
    Path(__file__).resolve().parents[2] / "skills" / "book-lookup" / "scripts" / "book_lookup.py"
)
spec = importlib.util.spec_from_file_location("book_lookup", SCRIPT)
book = importlib.util.module_from_spec(spec)
sys.modules["book_lookup"] = book
spec.loader.exec_module(book)

FEDERALIST_DOC = {
    "key": "/works/OL284420W",
    "title": "The Federalist",
    "author_name": ["Alexander Hamilton", "James Madison"],
    "first_publish_year": 1788,
    "edition_count": 350,
    "isbn": ["0451528816", "9781975921279"],
    "id_project_gutenberg": ["1404"],
    "ia": ["federalist1817", "federalist1817", "federalistb"],
    "ebook_access": "public",
}
EDITION = {
    "title": "The Narrow Corridor",
    "publishers": ["Penguin Press"],
    "publish_date": "2019",
    "key": "/books/OL27410795M",
    "works": [{"key": "/works/OL20220421W"}],
}
WORK = {"authors": [{"author": {"key": "/authors/OL1A"}}, {"author": {"key": "/authors/OL2A"}}]}


def crossref_item(doi, kind, year, family, given=None):
    """Return a minimal Crossref work."""
    person = {"family": family, "given": given} if given else {"family": family}
    return {
        "DOI": doi,
        "type": kind,
        "title": ["The Great Leveler"],
        "author": [person],
        "publisher": "Press",
        "issued": {"date-parts": [[year, 1, 1]]},
        "ISBN": ["9781400884605"],
    }


def responder(routes):
    """Return a fake fetch_json that answers by URL substring."""

    def fake(url):
        for fragment, body in routes.items():
            if fragment in url:
                return body
        return None

    return fake


def run_cli(argv, routes):
    """Run main() against canned routes and return (exit code, parsed stdout or None)."""
    out = io.StringIO()
    fake = mock.patch.object(book, "fetch_json", side_effect=responder(routes))
    with fake, contextlib.redirect_stdout(out), contextlib.redirect_stderr(io.StringIO()):
        code = book.main(argv)
    text = out.getvalue()
    return code, json.loads(text) if text else None


class IsbnTest(unittest.TestCase):
    def test_isbn13_passes_through(self):
        self.assertEqual(book.normalize_isbn("978-0-7352-2438-4"), "9780735224384")

    def test_isbn10_converts_to_isbn13(self):
        self.assertEqual(book.normalize_isbn("0735224382"), "9780735224384")

    def test_isbn10_with_x_check_digit(self):
        self.assertEqual(book.normalize_isbn("080442957X"), "9780804429573")

    def test_bad_isbn13_check_digit_names_the_expected_digit(self):
        with self.assertRaisesRegex(ValueError, r"expected 4 \(9780735224384\)"):
            book.normalize_isbn("9780735224385")

    def test_bad_isbn10_check_digit_names_the_expected_digit(self):
        with self.assertRaisesRegex(ValueError, r"expected 1 \(0465031331\)"):
            book.normalize_isbn("0-465-03133-6")

    def test_garbage_is_rejected(self):
        with self.assertRaises(ValueError):
            book.normalize_isbn("not-an-isbn")


class SearchTest(unittest.TestCase):
    def test_full_text_links_and_isbn13_filter(self):
        code, data = run_cli(
            ["search", "The Federalist"], {"search.json": {"docs": [FEDERALIST_DOC]}}
        )
        self.assertEqual(code, 0)
        work = data["result"][0]
        self.assertEqual(work["isbn13_sample"], ["9781975921279"])
        self.assertEqual(work["work_url"], "https://openlibrary.org/works/OL284420W")
        self.assertEqual(
            work["full_text"],
            [
                "https://www.gutenberg.org/ebooks/1404",
                "https://archive.org/details/federalist1817",
                "https://archive.org/details/federalistb",
            ],
        )

    def test_borrowable_scans_are_not_full_text(self):
        doc = dict(FEDERALIST_DOC, ebook_access="borrowable", id_project_gutenberg=None)
        self.assertEqual(book.full_text_links(doc), [])

    def test_no_results_exits_1(self):
        code, data = run_cli(["search", "zzz"], {"search.json": {"docs": []}})
        self.assertEqual(code, 1)
        self.assertFalse(data["found"])


class IsbnRecordTest(unittest.TestCase):
    def test_edition_with_authors_from_work(self):
        routes = {
            "/isbn/9780735224384": EDITION,
            "/works/OL20220421W": WORK,
            "/authors/OL1A": {"name": "Daron Acemoglu"},
            "/authors/OL2A": {"name": "James A. Robinson"},
        }
        code, data = run_cli(["isbn", "0735224382"], routes)
        self.assertEqual(code, 0)
        record = data["result"]
        self.assertEqual(record["authors"], ["Daron Acemoglu", "James A. Robinson"])
        self.assertEqual(record["canonical_url"], "https://openlibrary.org/isbn/9780735224384")
        self.assertEqual(record["work_url"], "https://openlibrary.org/works/OL20220421W")

    def test_unknown_isbn_exits_1(self):
        code, data = run_cli(["isbn", "9780735224384"], {})
        self.assertEqual(code, 1)
        self.assertIsNone(data["result"])

    def test_invalid_isbn_exits_1_with_json_error(self):
        code, data = run_cli(["isbn", "9780735224385"], {})
        self.assertEqual(code, 1)
        self.assertFalse(data["found"])
        self.assertIn("check digit mismatch", data["error"])


class EditionsTest(unittest.TestCase):
    def test_editions_sort_oldest_first_with_scans(self):
        entries = [
            {"key": "/books/OL2M", "title": "Political Parties", "publish_date": "1962"},
            {
                "key": "/books/OL1M",
                "title": "Political parties",
                "publish_date": "1915",
                "languages": [{"key": "/languages/eng"}],
                "ocaid": "politicalparties00mich",
            },
            {"key": "/books/OL3M", "title": "Undated"},
        ]
        code, data = run_cli(
            ["editions", "https://openlibrary.org/works/OL1914748W"],
            {"/works/OL1914748W/editions.json": {"entries": entries}},
        )
        self.assertEqual(code, 0)
        self.assertEqual([e["year"] for e in data["result"]], [1915, 1962, None])
        first = data["result"][0]
        self.assertEqual(first["languages"], ["eng"])
        self.assertEqual(first["scan_url"], "https://archive.org/details/politicalparties00mich")

    def test_bad_work_id_exits_1(self):
        code, data = run_cli(["editions", "not-a-work"], {})
        self.assertEqual(code, 1)
        self.assertIn("work id", data["error"])


class CrossrefTest(unittest.TestCase):
    def test_doi_url_prefix_is_stripped_and_book_flagged(self):
        item = crossref_item("10.1515/9781400884605", "edited-book", 2017, "Scheidel")
        code, data = run_cli(
            ["doi", "https://doi.org/10.1515/9781400884605"],
            {"/works/10.1515/9781400884605": {"message": item}},
        )
        self.assertEqual(code, 0)
        self.assertTrue(data["result"]["is_whole_book"])
        self.assertEqual(data["result"]["canonical_url"], "https://doi.org/10.1515/9781400884605")

    def test_chapter_is_not_whole_book(self):
        item = crossref_item("10.4324/x-14", "book-chapter", 2024, "Levitsky")
        self.assertFalse(book.shape_crossref(item)["is_whole_book"])

    def test_oxford_chapter_typed_as_book_is_not_whole_book(self):
        for doi in ("10.1093/oso/9780190634889.003.0007", "10.1093/oxfordhb/9780198755609.013.22"):
            item = crossref_item(doi, "book", 2017, "Dorman")
            self.assertFalse(book.shape_crossref(item)["is_whole_book"], doi)
        whole = crossref_item("10.1093/acprof:oso/9780190626594.001.0001", "monograph", 2016, "G")
        self.assertTrue(book.shape_crossref(whole)["is_whole_book"])

    def test_author_match_checks_first_initial_when_known(self):
        people = [{"family": "Mann", "given": "Michael"}]
        self.assertFalse(book.author_matches("Thomas Mann", people))
        self.assertTrue(book.author_matches("Mann", people))
        self.assertTrue(book.author_matches("Thomas Mann", [{"family": "Mann"}]))

    def test_book_doi_without_author_match_exits_1(self):
        items = [crossref_item("10.1/x", "monograph", 2001, "Christophers")]
        code, data = run_cli(
            ["book-doi", "The Great Leveler", "--author", "Walter Scheidel"],
            {"query.bibliographic": {"message": {"items": items}}},
        )
        self.assertEqual(code, 1)
        self.assertFalse(data["found"])
        self.assertFalse(data["result"][0]["author_match"])

    def test_book_doi_puts_author_matches_first_then_oldest(self):
        items = [
            crossref_item("10.1/c", "monograph", 2018, "Scheidel"),
            crossref_item("10.1/a", "edited-book", 2016, "Christophers"),
            crossref_item("10.1/b", "edited-book", 2017, "Scheidel"),
        ]
        code, data = run_cli(
            ["book-doi", "The Great Leveler", "--author", "Walter Scheidel"],
            {"query.bibliographic": {"message": {"items": items}}},
        )
        self.assertEqual(code, 0)
        self.assertEqual([r["doi"] for r in data["result"]], ["10.1/b", "10.1/c", "10.1/a"])
        self.assertFalse(data["result"][2]["author_match"])


class FailureTest(unittest.TestCase):
    def test_network_failure_exits_2_with_json_error(self):
        out = io.StringIO()
        fail = mock.patch.object(book, "fetch_json", side_effect=book.FetchError("boom"))
        with fail, contextlib.redirect_stdout(out), contextlib.redirect_stderr(io.StringIO()):
            code = book.main(["search", "anything"])
        self.assertEqual(code, 2)
        self.assertEqual(json.loads(out.getvalue()), {"found": False, "error": "boom"})


if __name__ == "__main__":
    unittest.main()
