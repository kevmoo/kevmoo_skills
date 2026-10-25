"""Unit tests for the lit-review skill script.

Run directly (`python3 tool/test/lit_review_test.py`) or through the Python CI
job. Network calls are replaced by canned OpenAlex responses.
"""

import contextlib
import importlib.util
import io
import json
import sys
import tempfile
import unittest
from pathlib import Path
from unittest import mock

SCRIPT = Path(__file__).resolve().parents[2] / "skills" / "lit-review" / "scripts" / "lit_review.py"
spec = importlib.util.spec_from_file_location("lit_review", SCRIPT)
lit = importlib.util.module_from_spec(spec)
sys.modules["lit_review"] = lit
spec.loader.exec_module(lit)


def work(
    wid, title, year=2020, cites=10, subfield="3320", kind="article", refs=(), authors=("A B",)
):
    """Return a minimal OpenAlex work."""
    return {
        "id": f"https://openalex.org/{wid}",
        "doi": f"https://doi.org/10.1/{wid.lower()}",
        "display_name": title,
        "publication_year": year,
        "cited_by_count": cites,
        "type": kind,
        "authorships": [{"author": {"display_name": a}} for a in authors],
        "primary_topic": {"subfield": {"id": f"https://openalex.org/subfields/{subfield}"}},
        "referenced_works": [f"https://openalex.org/{r}" for r in refs],
        "abstract_inverted_index": {"Elites": [0], "shape": [1], "democracy": [2]},
        "best_oa_location": {"pdf_url": f"https://example.org/{wid}.pdf"},
    }


def responder(routes):
    """Return a fake fetch that answers by URL substring, first match wins."""

    def fake(url, binary=False):
        decoded = lit.urllib.parse.unquote_plus(url)
        for fragment, body in routes:
            if fragment in decoded:
                return body
        return None

    return fake


class ReviewTestCase(unittest.TestCase):
    def setUp(self):
        tmp = tempfile.TemporaryDirectory()
        self.addCleanup(tmp.cleanup)
        self.dir = Path(tmp.name) / "review"
        self.dir.mkdir()

    def run_cli(self, argv, routes=()):
        """Run main() with --dir and canned routes; return (exit code, parsed stdout)."""
        out = io.StringIO()
        fake = mock.patch.object(lit, "fetch", side_effect=responder(routes))
        with fake, contextlib.redirect_stdout(out):
            code = lit.main([argv[0], "--dir", str(self.dir), *argv[1:]])
        return code, json.loads(out.getvalue())

    def write(self, name, data):
        (self.dir / name).write_text(json.dumps(data), encoding="utf-8")

    def read(self, name):
        return json.loads((self.dir / name).read_text(encoding="utf-8"))


class ParseAndMatchTest(unittest.TestCase):
    def test_parse_source_forms(self):
        self.assertEqual(lit.parse_source("https://doi.org/10.1017/X"), {"doi": "10.1017/X"})
        self.assertEqual(lit.parse_source("W2942478274"), {"openalex_id": "W2942478274"})
        self.assertEqual(
            lit.parse_source("The Great Leveler | Scheidel | 2017"),
            {"title": "The Great Leveler", "surname": "Scheidel", "year": 2017},
        )

    def test_empty_title_is_rejected(self):
        with self.assertRaises(ValueError):
            lit.parse_source(" | Scheidel | 2017")

    def test_missing_subtitle_still_matches(self):
        sim = lit.title_similarity(
            "Electoral Institutions and the Politics of Coalitions",
            "Electoral Institutions and the Politics of Coalitions: Why Some Democracies",
        )
        self.assertEqual(sim, 0.95)

    def test_year_mismatch_makes_a_match_uncertain(self):
        source = {"title": "How Democracies Die", "surname": "Levitsky", "year": 2018}
        chapter = work("W1", "How Democracies Die", year=2024, kind="book-chapter")
        self.assertEqual(lit.match_confidence(source, chapter), "uncertain")
        self.assertEqual(
            lit.match_confidence(source, work("W2", "How Democracies Die", 2018)), "exact"
        )

    def test_book_review_is_never_exact(self):
        source = {"title": "Social Dominance", "surname": "Sidanius", "year": 1999}
        review = work("W3", "Social Dominance", 1999, kind="book-review")
        self.assertEqual(lit.match_confidence(source, review), "uncertain")


class SeedTest(ReviewTestCase):
    def test_seed_prefers_the_confident_cited_record(self):
        (self.dir / "sources.txt").write_text("The Great Leveler | Scheidel | 2017\n10.1/x\n")
        results = {
            "results": [
                work("W1", "The Great Leveler", 2017, cites=194),
                work("W2", "The Great Leveler", 2017, cites=895, kind="book"),
                work("W3", "The Great Leveler", 2025, cites=2000),
            ]
        }
        routes = [("title.search", results), ("doi.org/10.1/x", work("W9", "Other"))]
        code, out = self.run_cli(["seed", str(self.dir / "sources.txt")], routes)
        self.assertEqual(code, 0)
        seeds = self.read("seeds.json")
        self.assertEqual(seeds[0]["work"]["id"], "W2")
        self.assertEqual(seeds[1]["confidence"], "exact")
        self.assertEqual(out["result"]["by_confidence"], {"exact": 2})


class FanoutTest(ReviewTestCase):
    def seeds(self):
        return [
            {
                "input": "Seed A | Alpha | 2014",
                "source": {"title": "Seed A", "surname": "Alpha", "year": 2014},
                "confidence": "exact",
                "work": lit.shape_work(work("W100", "Seed A", 2014, subfield="3320")),
            },
            {
                "input": "How Democracies Die | Levitsky | 2018",
                "source": {"title": "How Democracies Die", "surname": "Levitsky", "year": 2018},
                "confidence": "uncertain",
                "work": None,
            },
            {
                "input": "The Authoritarians | Altemeyer | 2006",
                "source": {"title": "The Authoritarians", "surname": "Altemeyer", "year": 2006},
                "confidence": "none",
                "work": None,
            },
        ]

    def test_links_filters_and_ranking(self):
        self.write("seeds.json", self.seeds())
        citers = {
            "results": [
                work("W1", "On topic, also mentions", cites=50),
                work("W2", "Off topic", cites=900, subfield="2725"),
                work("W3", "Front matter", kind="paratext"),
                work("W4", "Old and uncited", year=2001, cites=0),
                work("W100", "Seed A", 2014),
            ]
        }
        routes = [
            ("cites:W100", citers),
            ("works/W100", {"referenced_works": ["https://openalex.org/W5"]}),
            ("openalex:W5", {"results": [work("W5", "Foundation", 1957, cites=2000)]}),
            ("fulltext.search", {"meta": {"count": 3}, "results": [work("W1", "On topic")]}),
        ]
        code, out = self.run_cli(["fanout"], routes)
        self.assertEqual(code, 0)
        result = out["result"]
        self.assertEqual(
            result["dropped"],
            {
                "off-topic subfield": 1,
                "type paratext": 1,
                "uncited after two years": 1,
                "is a seed": 1,
            },
        )
        candidates = self.read("candidates.json")
        self.assertEqual([c["id"] for c in candidates], ["W1", "W5"])
        self.assertEqual(
            candidates[0]["links"], {"cites": ["Alpha 2014"], "mentions": ["Levitsky 2018"]}
        )
        self.assertEqual(candidates[0]["link_count"], 2)
        self.assertIn("too generic", result["seed_notes"]["Altemeyer 2006"])

    def test_rerun_keeps_agent_annotations(self):
        self.write("seeds.json", self.seeds()[:1])
        self.write(
            "candidates.json", [{"id": "W1", "picked": True, "summary": "Mine", "theme": "T"}]
        )
        routes = [("cites:W100", {"results": [work("W1", "On topic")]}), ("works/W100", {})]
        self.run_cli(["fanout"], routes)
        kept = self.read("candidates.json")[0]
        self.assertEqual((kept["picked"], kept["summary"], kept["theme"]), (True, "Mine", "T"))

    def test_fanout_without_seeds_exits_1(self):
        code, out = self.run_cli(["fanout"])
        self.assertEqual(code, 1)
        self.assertIn("run seed first", out["error"])


class PickAndClaimTest(ReviewTestCase):
    def setUp(self):
        super().setUp()
        candidate = {**lit.shape_work(work("W1", "Elite Origins")), "links": {}, "link_count": 1}
        self.write("candidates.json", [candidate])

    def test_pick_fetches_abstract_and_records_summary(self):
        routes = [("openalex:W1", {"results": [work("W1", "Elite Origins")]})]
        code, out = self.run_cli(["pick", "W1", "--theme", "Elites", "--summary", "S"], routes)
        self.assertEqual(code, 0)
        self.assertEqual(out["result"]["picked"][0]["abstract"], "Elites shape democracy")
        stored = self.read("candidates.json")[0]
        self.assertEqual(
            (stored["picked"], stored["theme"], stored["summary"]), (True, "Elites", "S")
        )

    def test_pick_unknown_id_exits_1(self):
        code, out = self.run_cli(["pick", "W404"])
        self.assertEqual(code, 1)
        self.assertIn("W404", out["error"])

    def test_claim_needs_quote_to_be_supported(self):
        routes = [("works/W1", work("W1", "Elite Origins"))]
        self.run_cli(["claim-add", "--work", "W1", "--text", "Elites design institutions"], routes)
        code, out = self.run_cli(["claim-verdict", "C1", "--verdict", "supported"])
        self.assertEqual(code, 1)
        self.assertIn("--quote", out["error"])
        code, _ = self.run_cli(
            ["claim-verdict", "C1", "--verdict", "supported", "--quote", "q", "--page", "4"]
        )
        self.assertEqual(code, 0)
        claim = self.read("claims.json")[0]
        self.assertEqual(claim["abstract"], "Elites shape democracy")
        self.assertEqual(claim["verdict"]["page"], "4")


class RenderTest(ReviewTestCase):
    def test_render_marks_unresolved_and_groups_themes(self):
        resolved = lit.shape_work(work("W100", "Seed A | B", 2014))
        self.write(
            "seeds.json",
            [
                {"input": "Seed A", "confidence": "exact", "work": resolved},
                {"input": "Lost | X | 2018", "confidence": "uncertain", "work": resolved},
            ],
        )
        picked = {**lit.shape_work(work("W1", "Elite Origins")), "links": {"cites": ["Alpha 2014"]}}
        self.write(
            "candidates.json", [{**picked, "picked": True, "theme": "Elites", "summary": "S"}]
        )
        code, _ = self.run_cli(["render"])
        self.assertEqual(code, 0)
        reading = (self.dir / "reading_list.md").read_text()
        self.assertIn("[Seed A \\| B](https://doi.org/10.1/w100)", reading)
        self.assertIn("unresolved (closest record:", reading)
        fanout = (self.dir / "fanout.md").read_text()
        self.assertIn("## Elites", fanout)
        self.assertIn("cites: Alpha 2014", fanout)
        self.assertFalse((self.dir / "claims.md").exists())


class ConfigTest(unittest.TestCase):
    def test_api_key_is_added_and_redacted(self):
        with mock.patch.dict("os.environ", {"OPENALEX_API_KEY": "sekrit"}):
            url = lit.api_url("/works", {"filter": "x"})
        self.assertIn("api_key=sekrit", url)
        self.assertNotIn("sekrit", lit.redact(url))

    def test_contact_email_is_opt_in(self):
        with mock.patch.dict("os.environ", {}, clear=True):
            self.assertEqual(lit.user_agent(), lit.USER_AGENT)
        with mock.patch.dict("os.environ", {"SKILLS_CONTACT_EMAIL": "me@example.com"}):
            self.assertTrue(lit.user_agent().endswith("; mailto:me@example.com)"))

    def test_network_failure_exits_2(self):
        out = io.StringIO()
        fail = mock.patch.object(lit, "fetch", side_effect=lit.FetchError("boom"))
        with tempfile.TemporaryDirectory() as tmp, fail, contextlib.redirect_stdout(out):
            Path(tmp, "seeds.json").write_text(
                json.dumps([{"input": "x", "confidence": "exact", "work": {"id": "W1"}}])
            )
            code = lit.main(["fanout", "--dir", tmp])
        self.assertEqual(code, 2)
        self.assertEqual(json.loads(out.getvalue()), {"ok": False, "error": "boom"})


if __name__ == "__main__":
    unittest.main()
