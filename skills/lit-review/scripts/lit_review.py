#!/usr/bin/env python3
"""Run the deterministic steps of a literature review against OpenAlex.

All state lives in one review directory as JSON, so a review can be paused,
resumed and extended. The agent makes every judgment (which candidates to
keep, what a work says, whether it supports a claim); this script only
fetches, counts and records. Subcommands:

  seed           Resolve sources ("title | surname | year", a DOI, or an
                 OpenAlex id) to OpenAlex works; writes seeds.json.
  fanout         Works the seeds cite and the most-cited works citing them,
                 ranked by seed links; title mentions stand in for seeds
                 OpenAlex lacks; writes candidates.json.
  pick           Keep candidates, fetching abstract and open-access link;
                 optionally set a theme and the agent's summary.
  claim-add      Record a claim and the work cited for it; fetches its abstract.
  claim-verdict  Record the agent's verdict, quote and page for a claim.
  fulltext       Download a work's open-access copy into the review directory.
  render         Write reading_list.md, fanout.md and claims.md from the JSON.

Output is always one JSON object on stdout. Exit codes: 0 success, 1 invalid
input or nothing found, 2 network or HTTP failure (retryable).
"""

import argparse
import datetime
import difflib
import json
import os
import re
import sys
import time
import urllib.error
import urllib.parse
import urllib.request
from pathlib import Path

API = "https://api.openalex.org"
USER_AGENT = "lit-review-skill/0.1 (+https://github.com/kevmoo/kevmoo_skills)"
CONTACT_ENV = "SKILLS_CONTACT_EMAIL"
KEY_ENV = "OPENALEX_API_KEY"
WORK_FIELDS = (
    "id,doi,display_name,publication_year,cited_by_count,fwci,type,authorships,"
    "primary_location,primary_topic,referenced_works,best_oa_location"
)
DROP_TYPES = {"paratext", "erratum", "editorial", "letter", "peer-review", "other", "retraction"}
VERDICTS = ("supported", "partly", "contradicted", "misattributed", "cant-tell")
ABSTRACT_LIMIT = 4000
# A safety valve only: a short-title check catches generic titles first.
MENTION_MAX_HITS = 10000
# Records about a work rather than the work itself (reviews, recorded talks, front matter).
NOT_THE_WORK_TYPES = {"book-review", "paratext", "other", "peer-review", "editorial", "erratum"}
# Reprints and fragments that should lose to the original record of the same title.
DEMOTED_TYPES = {"book-review", "book-chapter", "paratext", "erratum", "editorial"}


class FetchError(Exception):
    """A network or HTTP failure that should end the run with exit code 2."""


def user_agent():
    """Return the User-Agent, with a mailto contact when SKILLS_CONTACT_EMAIL is set."""
    email = os.environ.get(CONTACT_ENV, "").strip()
    if not email or "@" not in email or any(c in email for c in "()\r\n "):
        return USER_AGENT
    return f"{USER_AGENT[:-1]}; mailto:{email})"


def api_url(path, params=None):
    """Return an OpenAlex URL, adding the API key from OPENALEX_API_KEY when set."""
    params = dict(params or {})
    key = os.environ.get(KEY_ENV, "").strip()
    if key:
        params["api_key"] = key
    query = f"?{urllib.parse.urlencode(params)}" if params else ""
    return f"{API}{path}{query}"


def fetch(url, binary=False):
    """Return parsed JSON (or bytes) at url, None on 404; retries twice on 429, 5xx, resets."""
    request = urllib.request.Request(url, headers={"User-Agent": user_agent()})
    for attempt in range(3):
        try:
            with urllib.request.urlopen(request, timeout=60) as response:
                return response.read() if binary else json.load(response)
        except urllib.error.HTTPError as error:
            if error.code == 404:
                return None
            if attempt < 2 and (error.code == 429 or error.code >= 500):
                time.sleep(2 * (attempt + 1))
                continue
            raise FetchError(f"HTTP {error.code} from {redact(url)}") from error
        except (urllib.error.URLError, OSError) as error:
            if attempt < 2:
                time.sleep(2 * (attempt + 1))
                continue
            raise FetchError(f"{error} fetching {redact(url)}") from error
    raise FetchError(f"no response from {redact(url)}")


def redact(url):
    """Return url with any api_key value hidden, for error messages."""
    return re.sub(r"api_key=[^&]+", "api_key=REDACTED", url)


def short_id(value):
    """Return the bare OpenAlex id (W123) from an id or URL."""
    return (value or "").rsplit("/", 1)[-1]


def load(path, default):
    """Return parsed JSON from path, or default when the file does not exist."""
    return json.loads(path.read_text(encoding="utf-8")) if path.exists() else default


def save(path, data):
    """Write data to path as indented JSON."""
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(data, indent=1, ensure_ascii=False) + "\n", encoding="utf-8")


def abstract_text(work, limit=ABSTRACT_LIMIT):
    """Return the abstract rebuilt from OpenAlex's inverted index, marking any truncation."""
    index = work.get("abstract_inverted_index") or {}
    words = sorted((pos, word) for word, places in index.items() for pos in places)
    text = " ".join(word for _, word in words)
    return text if len(text) <= limit else text[:limit] + " [truncated]"


def shape_work(work):
    """Reduce an OpenAlex work to the fields a review records."""
    topic = work.get("primary_topic") or {}
    source = (work.get("primary_location") or {}).get("source") or {}
    oa = work.get("best_oa_location") or {}
    return {
        "id": short_id(work.get("id")),
        "doi": work.get("doi"),
        "title": work.get("display_name"),
        "year": work.get("publication_year"),
        "type": work.get("type"),
        "authors": [a["author"]["display_name"] for a in (work.get("authorships") or [])[:6]],
        "venue": source.get("display_name"),
        "cites": work.get("cited_by_count") or 0,
        "fwci": work.get("fwci"),
        "subfield": short_id((topic.get("subfield") or {}).get("id")) or None,
        "subfield_name": (topic.get("subfield") or {}).get("display_name"),
        "oa_url": oa.get("pdf_url") or oa.get("landing_page_url"),
    }


def parse_source(line):
    """Parse a seed line: a DOI or OpenAlex id, or a title, each optionally '| surname | year'."""
    parts = [p.strip() for p in line.strip().split("|")]
    head = parts[0]
    extra = {}
    if len(parts) > 1 and parts[1]:
        extra["surname"] = parts[1]
    if len(parts) > 2 and parts[2].isdigit():
        extra["year"] = int(parts[2])
    doi = re.match(r"^(?:https?://(?:dx\.)?doi\.org/|doi:)?(10\.\S+)$", head, re.IGNORECASE)
    if doi:
        return {"doi": doi.group(1), **extra}
    if re.fullmatch(r"(?:https://openalex\.org/)?W\d+", head):
        return {"openalex_id": short_id(head), **extra}
    if not head:
        raise ValueError(f"empty title in seed line: {line!r}")
    return {"title": head, "surname": extra.get("surname", ""), "year": extra.get("year")}


def norm_title(text):
    """Return a title lowercased with punctuation removed."""
    return re.sub(r"\s+", " ", re.sub(r"[^a-z0-9 ]", " ", (text or "").lower())).strip()


def title_similarity(a, b):
    """Return a 0-1 similarity between two titles; a title missing only its subtitle scores 0.95."""
    na, nb = norm_title(a), norm_title(b)
    if min(len(na), len(nb)) >= 8 and (nb.startswith(na + " ") or na.startswith(nb + " ")):
        return 0.95
    return difflib.SequenceMatcher(None, na, nb).ratio()


def match_confidence(source, work):
    """Return exact, likely, uncertain or none for a searched source vs a work."""
    similarity = title_similarity(source["title"], work["display_name"])
    year = work.get("publication_year") or 0
    year_ok = not source.get("year") or abs(year - source["year"]) <= 1
    if similarity < 0.5:
        return "none"
    # A review, or a record from another year (a reprint chapter, a different book), is not
    # the cited work even when the title matches.
    if not year_ok or work.get("type") in NOT_THE_WORK_TYPES:
        return "uncertain"
    if similarity >= 0.9:
        return "exact"
    return "likely" if similarity >= 0.75 else "uncertain"


def resolve_source(source):
    """Return (work or None, confidence, alternates) for a parsed seed source.

    Alternates are other records with the same title (journal reprints such as
    ACM SIGPLAN Notices copies of conference papers), so the choice is visible.
    """
    select = WORK_FIELDS.replace(",referenced_works", "")
    if "doi" in source or "openalex_id" in source:
        path = f"https://doi.org/{source['doi']}" if "doi" in source else source["openalex_id"]
        work = fetch(api_url(f"/works/{path}", {"select": select}))
        return work, "exact" if work else "none", []
    title = re.sub(r"[,:?!|]", " ", source["title"])
    filters = f"title.search:{title}"
    if source.get("surname"):
        filters += f",raw_author_name.search:{source['surname']}"
    data = fetch(api_url("/works", {"filter": filters, "per-page": 10, "select": select})) or {}
    candidates = data.get("results") or []
    if not candidates:
        return None, "none", []

    def rank(work):
        """Prefer confident matches, then title similarity, originals over reprints, citations."""
        similarity = round(title_similarity(source["title"], work["display_name"]), 2)
        confident = match_confidence(source, work) in ("exact", "likely")
        original = work.get("type") not in DEMOTED_TYPES
        return (confident, similarity, original, work.get("cited_by_count") or 0)

    ranked = sorted(candidates, key=rank, reverse=True)
    best = ranked[0]
    alternates = [
        {k: shape_work(w)[k] for k in ("id", "doi", "year", "type", "venue", "cites")}
        for w in ranked[1:]
        if title_similarity(best["display_name"], w["display_name"]) >= 0.9
    ]
    return best, match_confidence(source, best), alternates


def seed_record(line, previous):
    """Resolve one seed line into a seeds.json record, keeping any earlier annotations."""
    source = parse_source(line)
    work, confidence, alternates = resolve_source(source)
    record = {**previous, "input": line, "source": source, "confidence": confidence}
    record.update({"work": None, "alternates": alternates, "notes": []})
    if work and confidence != "none":
        record["work"] = shape_work(work)
        if not record["work"]["doi"]:
            record["notes"].append("no DOI; if this is a book, anchor it with book-lookup")
    if alternates:
        record["notes"].append(
            f"{len(alternates)} other record(s) share this title; see alternates"
        )
    return record


def cmd_seed(args):
    """Resolve every line of the sources file; seeds.json mirrors the file afterward."""
    text = Path(args.file).read_text(encoding="utf-8")
    lines = list(dict.fromkeys(line.strip() for line in text.splitlines() if line.strip()))
    path = Path(args.dir) / "seeds.json"
    previous = {s["input"]: s for s in load(path, [])}
    seeds = [seed_record(line, previous.get(line, {})) for line in lines]
    save(path, seeds)
    counts = {}
    for record in seeds:
        counts[record["confidence"]] = counts.get(record["confidence"], 0) + 1
    removed = [i for i in previous if i not in lines]
    flagged = {seed_label(s): s["notes"] for s in seeds if s["notes"]}
    return {
        "seeds": len(seeds),
        "by_confidence": counts,
        "removed": removed,
        "notes": flagged,
    }, True


def seed_label(seed):
    """Return a short 'Surname Year' label, preferring the user's citation over the record."""
    work = seed.get("work") or {}
    source = seed.get("source") or {}
    surname = source.get("surname") or ((work.get("authors") or ["?"])[0].split() or ["?"])[-1]
    return f"{surname} {source.get('year') or work.get('year') or ''}".strip()


def citing_works(work_id, per_seed):
    """Return the most-cited works that cite work_id."""
    params = {
        "filter": f"cites:{work_id}",
        "sort": "cited_by_count:desc",
        "per-page": min(per_seed, 200),
        "select": WORK_FIELDS,
    }
    return (fetch(api_url("/works", params)) or {}).get("results", [])


def referenced_works(work_id):
    """Return the works that work_id cites, hydrated in batches of 50."""
    work = fetch(api_url(f"/works/{work_id}", {"select": "id,referenced_works"})) or {}
    ids = [short_id(r) for r in work.get("referenced_works") or []]
    results = []
    for start in range(0, len(ids), 50):
        params = {"filter": "openalex:" + "|".join(ids[start : start + 50]), "per-page": 50}
        params["select"] = WORK_FIELDS
        results += (fetch(api_url("/works", params)) or {}).get("results", [])
    return results


def mention_search(seed):
    """Return (works mentioning a seed's title, skip reason or None) for seeds OpenAlex lacks."""
    source = seed.get("source") or {}
    title, surname = source.get("title"), source.get("surname")
    if not title or not surname:
        return [], "needs a title and surname"
    if len(re.findall(r"[A-Za-z]{3,}", title)) < 3:
        return [], "title too generic for a full-text search"
    params = {
        "filter": f'fulltext.search:"{title}" {surname}',
        "sort": "cited_by_count:desc",
        "per-page": 100,
        "select": WORK_FIELDS,
    }
    data = fetch(api_url("/works", params)) or {}
    if (data.get("meta") or {}).get("count", 0) > MENTION_MAX_HITS:
        return [], f"over {MENTION_MAX_HITS} full-text hits; title too common"
    return data.get("results", []), None


def add_links(pool, works, label, relation):
    """Record that each work in works has relation to the seed called label."""
    for work in works:
        entry = pool.setdefault(short_id(work["id"]), {**shape_work(work), "links": {}})
        entry["links"].setdefault(relation, [])
        if label not in entry["links"][relation]:
            entry["links"][relation].append(label)


def quality_reason(entry, subfields, this_year):
    """Return why a candidate is filtered out, or None to keep it."""
    if entry["type"] in DROP_TYPES:
        return f"type {entry['type']}"
    if subfields and entry["subfield"] and entry["subfield"] not in subfields:
        return "off-topic subfield"
    if entry["cites"] == 0 and (entry["year"] or this_year) <= this_year - 2:
        return "uncited after two years"
    return None


def collect(seeds, per_seed):
    """Return (candidate pool, per-seed notes) from seed citations, references and mentions."""
    pool, notes = {}, {}
    for seed in seeds:
        label, work = seed_label(seed), seed.get("work")
        if work and seed["confidence"] in ("exact", "likely"):
            add_links(pool, citing_works(work["id"], per_seed), label, "cites")
            add_links(pool, referenced_works(work["id"]), label, "cited_by")
            continue
        found, skipped = mention_search(seed)
        add_links(pool, found, label, "mentions")
        notes[label] = skipped or f"no OpenAlex record; {len(found)} full-text mentions"
    return pool, notes


def merge_duplicates(pool):
    """Merge candidates with the same title and first author, keeping the most-cited record."""
    merged = {}
    for entry in sorted(pool.values(), key=lambda e: -e["cites"]):
        first = (entry["authors"] or [""])[0].split()
        key = (norm_title(entry["title"]), first[-1].lower() if first else "")
        if key not in merged:
            merged[key] = {**entry, "duplicates": []}
            continue
        kept = merged[key]
        kept["duplicates"].append(entry["id"])
        for relation, labels in entry["links"].items():
            target = kept["links"].setdefault(relation, [])
            target.extend(label for label in labels if label not in target)
    return {entry["id"]: entry for entry in merged.values()}


def cmd_fanout(args):
    """Fan out from the seeds, filter, rank and write candidates.json."""
    root = Path(args.dir)
    seeds = load(root / "seeds.json", [])
    if not seeds:
        raise ValueError(f"no seeds in {root / 'seeds.json'}; run seed first")
    pool, notes = collect(seeds, args.per_seed)
    pool = merge_duplicates(pool)
    seed_ids = {s["work"]["id"] for s in seeds if s.get("work")}
    seed_ids |= {a["id"] for s in seeds for a in s.get("alternates") or []}
    subfields = set()
    if not args.no_subfield_filter:
        subfields = {
            s["work"]["subfield"] for s in seeds if s.get("work") and s["work"]["subfield"]
        }
    this_year, kept, dropped = datetime.date.today().year, [], {}
    for wid, entry in pool.items():
        is_seed = wid in seed_ids or seed_ids & set(entry["duplicates"])
        reason = "is a seed" if is_seed else quality_reason(entry, subfields, this_year)
        if reason:
            dropped[reason] = dropped.get(reason, 0) + 1
            continue
        entry["link_count"] = len({s for labels in entry["links"].values() for s in labels})
        kept.append(entry)
    kept.sort(key=lambda e: (-e["link_count"], -e["cites"]))
    previous = {c["id"]: c for c in load(root / "candidates.json", [])}
    for entry in kept:
        for field in ("picked", "theme", "summary", "abstract"):
            if field in previous.get(entry["id"], {}):
                entry[field] = previous[entry["id"]][field]
    save(root / "candidates.json", kept)
    multi = sum(1 for e in kept if e["link_count"] >= 2)
    summary = {"candidates": len(kept), "linked_to_2_plus_seeds": multi, "dropped": dropped}
    return {**summary, "seed_notes": notes, "top": [brief(e) for e in kept[:15]]}, bool(kept)


def brief(entry):
    """Return a one-line view of a candidate for stdout."""
    return {
        "id": entry["id"],
        "title": entry["title"],
        "year": entry["year"],
        "cites": entry["cites"],
        "links": entry["links"],
    }


def cmd_pick(args):
    """Mark candidates as kept, fetch their abstracts, and record theme and summary."""
    path = Path(args.dir) / "candidates.json"
    candidates = {c["id"]: c for c in load(path, [])}
    missing = [i for i in args.ids if i not in candidates]
    if missing:
        raise ValueError(f"not in candidates.json: {', '.join(missing)}")
    if args.summary and len(args.ids) != 1:
        raise ValueError("--summary applies to one candidate at a time")
    need = [i for i in args.ids if "abstract" not in candidates[i]]
    if need:
        params = {"filter": "openalex:" + "|".join(need), "per-page": 50}
        params["select"] = "id,abstract_inverted_index,best_oa_location"
        for work in (fetch(api_url("/works", params)) or {}).get("results", []):
            candidates[short_id(work["id"])]["abstract"] = abstract_text(work)
    for wid in args.ids:
        candidates[wid]["picked"] = True
        if args.theme:
            candidates[wid]["theme"] = args.theme
        if args.summary:
            candidates[wid]["summary"] = args.summary
    save(path, list(candidates.values()))
    shown = [{"id": i, "abstract": candidates[i].get("abstract", "")} for i in args.ids]
    return {"picked": shown}, True


def work_for(ref, root):
    """Return a work record for a claim's cited work: a seed input, a candidate, or a W id."""
    for seed in load(root / "seeds.json", []):
        if ref == seed["input"] and seed.get("work"):
            return seed["work"]
    for candidate in load(root / "candidates.json", []):
        if ref == candidate["id"]:
            return candidate
    if re.fullmatch(r"W\d+", ref):
        work = fetch(api_url(f"/works/{ref}", {"select": WORK_FIELDS}))
        if work:
            return shape_work(work)
    raise ValueError(f"no work found for {ref!r}; use a seed input line or an OpenAlex W id")


def cmd_claim_add(args):
    """Record a claim with its cited work's abstract and open-access link."""
    root = Path(args.dir)
    work = work_for(args.work, root)
    detail = fetch(api_url(f"/works/{work['id']}", {"select": "id,abstract_inverted_index"})) or {}
    claims = load(root / "claims.json", [])
    claim = {
        "id": f"C{len(claims) + 1}",
        "text": args.text,
        "where": args.where,
        "work": {k: work.get(k) for k in ("id", "doi", "title", "year", "authors", "oa_url")},
        "abstract": abstract_text(detail),
        "verdict": None,
    }
    claims.append(claim)
    save(root / "claims.json", claims)
    return claim, True


def cmd_claim_verdict(args):
    """Record the agent's verdict on a claim, with the quote or note that settles it."""
    path = Path(args.dir) / "claims.json"
    claims = load(path, [])
    claim = next((c for c in claims if c["id"] == args.id), None)
    if claim is None:
        raise ValueError(f"no claim {args.id} in {path}")
    if args.verdict in ("supported", "contradicted") and not args.quote:
        raise ValueError(f"a {args.verdict} verdict needs --quote from the source")
    if args.verdict in ("misattributed", "cant-tell") and not args.note:
        raise ValueError(f"a {args.verdict} verdict needs --note saying why")
    claim["verdict"] = {
        "verdict": args.verdict,
        "depth": args.depth,
        "quote": args.quote,
        "page": args.page,
        "note": args.note,
    }
    save(path, claims)
    return claim, True


def oa_urls(work):
    """Return a work's open-access URLs to try: PDF links first, then landing pages."""
    best = work.get("best_oa_location") or {}
    others = [loc for loc in work.get("locations") or [] if loc and loc.get("is_oa")]
    locations = [best] + others
    pdfs = [loc.get("pdf_url") for loc in locations]
    landings = [loc.get("landing_page_url") for loc in locations]
    return [url for url in dict.fromkeys(pdfs + landings) if url]


def cmd_fulltext(args):
    """Download the first open-access copy that is really a PDF into fulltext/."""
    root = Path(args.dir)
    work = fetch(api_url(f"/works/{args.work}", {"select": "id,best_oa_location,locations"}))
    urls = oa_urls(work or {})
    if not urls:
        return {"work": args.work, "error": "no open-access copy in OpenAlex"}, False
    attempts = []
    for url in urls:
        try:
            body = fetch(url, binary=True)
        except FetchError as error:
            attempts.append({"url": url, "result": str(error)})
            continue
        if body and body[:5] == b"%PDF-":
            path = root / "fulltext" / f"{args.work}.pdf"
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_bytes(body)
            return {"work": args.work, "url": url, "path": str(path), "bytes": len(body)}, True
        found = "not found" if body is None else "HTML, not a PDF (landing page or bot check)"
        attempts.append({"url": url, "result": found})
    return {"work": args.work, "error": "no PDF retrievable", "attempts": attempts}, False


def md(text):
    """Return text safe for a Markdown table cell."""
    return str(text or "").replace("|", "\\|").replace("\n", " ")


def link(work):
    """Return a Markdown link to a work's DOI, or its OpenAlex page."""
    url = work.get("doi") or f"https://openalex.org/{work['id']}"
    return f"[{md(work['title'])}]({url})"


def openalex_cell(work):
    """Return a Markdown link to a work's OpenAlex record."""
    return f"[{work['id']}](https://openalex.org/{work['id']})" if work.get("id") else "-"


def render_seeds(seeds):
    """Return the reading list as Markdown; unconfirmed matches show as unresolved."""
    rows = ["| Work | Author(s), year | Match | OpenAlex |", "| --- | --- | --- | --- |"]
    for seed in seeds:
        work = seed.get("work")
        if work and seed["confidence"] in ("exact", "likely"):
            who = md(", ".join(work["authors"][:3]))
            cells = [link(work), f"{who}, {work['year']}", seed["confidence"], openalex_cell(work)]
        else:
            hint = f" (closest record: {link(work)}, {work['year']})" if work else ""
            cells = [md(seed["input"]), "-", f"unresolved{hint}", "-"]
        rows.append("| " + " | ".join(cells) + " |")
    return "# Reading list\n\n" + "\n".join(rows) + "\n"


def render_candidates(candidates):
    """Return picked candidates as Markdown, one table per theme."""
    picked = [c for c in candidates if c.get("picked")]
    themes = sorted({c.get("theme") or "Unsorted" for c in picked})
    parts = ["# Fan-out\n"]
    for theme in themes:
        parts.append(f"## {theme}\n")
        parts.append("| Work | Author(s), year | Connects to | What it adds | Citations |")
        parts.append("| --- | --- | --- | --- | --- |")
        for c in [c for c in picked if (c.get("theme") or "Unsorted") == theme]:
            connects = "; ".join(
                f"{k.replace('_', ' ')}: {', '.join(v)}" for k, v in c["links"].items()
            )
            summary = c.get("summary") or "(no summary yet)"
            who = md(", ".join(c["authors"][:3]))
            parts.append(
                f"| {link(c)} | {who}, {c['year']} | {md(connects)} | {md(summary)} |"
                f" {c['cites']:,} |"
            )
        parts.append("")
    return "\n".join(parts)


def render_claims(claims):
    """Return the claim checks as Markdown."""
    rows = ["| Claim | Cited work | Verdict | Evidence |", "| --- | --- | --- | --- |"]
    for c in claims:
        v = c.get("verdict") or {}
        verdict = f"{v['verdict']} ({v['depth']})" if v else "unchecked"
        evidence = f'"{v["quote"]}"' if v.get("quote") else v.get("note") or ""
        if v.get("page"):
            evidence += f" (p. {v['page']})"
        rows.append(
            f"| {c['id']}: {md(c['text'])} | {link(c['work'])} | {verdict} | {md(evidence)} |"
        )
    return "# Claim checks\n\n" + "\n".join(rows) + "\n"


def cmd_render(args):
    """Write reading_list.md, fanout.md and claims.md from the review JSON."""
    root = Path(args.dir)
    outputs = {
        "reading_list.md": (load(root / "seeds.json", []), render_seeds),
        "fanout.md": (load(root / "candidates.json", []), render_candidates),
        "claims.md": (load(root / "claims.json", []), render_claims),
    }
    written = []
    for name, (data, renderer) in outputs.items():
        if data:
            (root / name).write_text(renderer(data), encoding="utf-8")
            written.append(str(root / name))
    return {"written": written}, bool(written)


def build_parser():
    """Return the argument parser for all subcommands."""
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    sub = parser.add_subparsers(dest="command", required=True)

    def add(name, func, help_text):
        """Register a subcommand that takes the shared --dir argument."""
        p = sub.add_parser(name, help=help_text)
        p.add_argument("--dir", required=True, help="review directory, e.g. lit-review/<slug>")
        p.set_defaults(func=func)
        return p

    add("seed", cmd_seed, "resolve sources to OpenAlex").add_argument("file")
    p = add("fanout", cmd_fanout, "fan out from seeds")
    p.add_argument("--per-seed", type=int, default=200)
    p.add_argument(
        "--no-subfield-filter",
        action="store_true",
        help="keep candidates outside the seeds' OpenAlex subfields",
    )
    p = add("pick", cmd_pick, "keep candidates and fetch abstracts")
    p.add_argument("ids", nargs="+")
    p.add_argument("--theme")
    p.add_argument("--summary")
    p = add("claim-add", cmd_claim_add, "record a claim and its cited work")
    p.add_argument("--work", required=True, help="seed input line or OpenAlex W id")
    p.add_argument("--text", required=True)
    p.add_argument("--where", default="", help="where the claim appears, e.g. a doc section")
    p = add("claim-verdict", cmd_claim_verdict, "record a verdict on a claim")
    p.add_argument("id")
    p.add_argument("--verdict", required=True, choices=VERDICTS)
    p.add_argument("--depth", choices=("abstract", "full-text"), default="abstract")
    p.add_argument("--quote", default="")
    p.add_argument("--page", default="")
    p.add_argument("--note", default="")
    add("fulltext", cmd_fulltext, "download an open-access copy").add_argument("work")
    add("render", cmd_render, "write Markdown tables")
    return parser


def main(argv=None):
    """Run the CLI and return its exit code."""
    args = build_parser().parse_args(argv)
    try:
        result, ok = args.func(args)
    except (ValueError, OSError, FetchError) as error:
        print(json.dumps({"ok": False, "error": str(error)}, indent=2))
        return 2 if isinstance(error, FetchError) else 1
    print(json.dumps({"ok": ok, "result": result}, indent=2, ensure_ascii=False))
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())
