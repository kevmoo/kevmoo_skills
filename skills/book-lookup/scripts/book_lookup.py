#!/usr/bin/env python3
"""Look up books in Open Library and Crossref and print verified records as JSON.

Every field printed comes from a record fetched in this run, so an agent can
cite it without trusting its own memory. Subcommands:

  search    Open Library works matching a title (and author), with ISBN-13s
            and any public full text (Project Gutenberg, Internet Archive).
  isbn      One Open Library edition by ISBN-10 or ISBN-13.
  editions  The editions of one Open Library work, oldest first, for pre-ISBN
            and translated books.
  doi       One Crossref record, flagging whether it is a whole book.
  book-doi  Crossref book DOIs matching a title (and author), oldest first.

Output is always one JSON object on stdout: {"found", "result"} or
{"found": false, "error"}. Exit codes: 0 found, 1 nothing found or invalid
input, 2 network or HTTP failure (retryable).
"""

import argparse
import json
import os
import re
import sys
import time
import urllib.error
import urllib.parse
import urllib.request

USER_AGENT = "book-lookup-skill/0.1 (+https://github.com/kevmoo/kevmoo_skills)"
# Opt-in contact address: Crossref serves identified clients from its faster "polite pool".
CONTACT_ENV = "SKILLS_CONTACT_EMAIL"
OPEN_LIBRARY = "https://openlibrary.org"
CROSSREF = "https://api.crossref.org"
BOOK_TYPES = ("book", "monograph", "edited-book", "reference-book")
# Oxford registers chapters (.003.NNNN) and handbook entries (.013.NN) with type "book".
CHAPTER_DOI = re.compile(r"^10\.1093/.+\.(003|013)\.\d+$", re.IGNORECASE)
YEAR = re.compile(r"\b(1[4-9]\d\d|20\d\d)\b")
SEARCH_FIELDS = (
    "key,title,author_name,first_publish_year,edition_count,isbn,"
    "id_project_gutenberg,ia,ebook_access"
)


class FetchError(Exception):
    """A network or HTTP failure that should end the run with exit code 2."""


def user_agent():
    """Return the User-Agent, with a mailto contact when SKILLS_CONTACT_EMAIL is set."""
    email = os.environ.get(CONTACT_ENV, "").strip()
    if not email or "@" not in email or any(c in email for c in "()\r\n "):
        return USER_AGENT
    return f"{USER_AGENT[:-1]}; mailto:{email})"


def fetch_json(url):
    """Return the parsed JSON at url, or None on 404. Retries twice on 429, 5xx and resets."""
    request = urllib.request.Request(url, headers={"User-Agent": user_agent()})
    for attempt in range(3):
        try:
            with urllib.request.urlopen(request, timeout=30) as response:
                return json.load(response)
        except urllib.error.HTTPError as error:
            if error.code == 404:
                return None
            if attempt < 2 and (error.code == 429 or error.code >= 500):
                time.sleep(2 * (attempt + 1))
                continue
            raise FetchError(f"HTTP {error.code} from {url}") from error
        except (urllib.error.URLError, OSError) as error:
            if attempt < 2:
                time.sleep(2 * (attempt + 1))
                continue
            raise FetchError(f"{error} fetching {url}") from error
    raise FetchError(f"no response from {url}")


def isbn13_check_digit(first12):
    """Return the ISBN-13 check digit for a 12-digit prefix."""
    total = sum(int(d) * (1 if i % 2 == 0 else 3) for i, d in enumerate(first12))
    return str((10 - total % 10) % 10)


def isbn10_check_digit(first9):
    """Return the ISBN-10 check character for a 9-digit prefix."""
    remainder = (11 - sum((10 - i) * int(d) for i, d in enumerate(first9)) % 11) % 11
    return "X" if remainder == 10 else str(remainder)


def normalize_isbn(raw):
    """Return a validated ISBN-13 for an ISBN-10 or ISBN-13, or raise ValueError.

    A wrong check digit names the expected one, since a typo in the last
    digit is the most common way a copied ISBN goes wrong.
    """
    isbn = raw.replace("-", "").replace(" ", "").upper()
    if len(isbn) == 13 and isbn.isdigit():
        expected = isbn13_check_digit(isbn[:12])
        if expected != isbn[12]:
            raise ValueError(
                f"ISBN-13 check digit mismatch in {raw}: expected {expected} "
                f"({isbn[:12]}{expected}); confirm the corrected ISBN before using it"
            )
        return isbn
    if len(isbn) == 10 and isbn[:9].isdigit() and (isbn[9].isdigit() or isbn[9] == "X"):
        expected = isbn10_check_digit(isbn[:9])
        if expected != isbn[9]:
            raise ValueError(
                f"ISBN-10 check digit mismatch in {raw}: expected {expected} "
                f"({isbn[:9]}{expected}); confirm the corrected ISBN before using it"
            )
        prefix = "978" + isbn[:9]
        return prefix + isbn13_check_digit(prefix)
    raise ValueError(f"not an ISBN-10 or ISBN-13 (wrong length or characters): {raw}")


def full_text_links(doc):
    """Return public full-text URLs for an Open Library search doc."""
    links = [f"https://www.gutenberg.org/ebooks/{g}" for g in doc.get("id_project_gutenberg") or []]
    # "borrowable" and "printdisabled" scans need a human login, so they are not full text.
    if doc.get("ebook_access") == "public":
        unique = list(dict.fromkeys(doc.get("ia") or []))
        links += [f"https://archive.org/details/{ia}" for ia in unique[:3]]
    return links


def shape_search_doc(doc):
    """Reduce an Open Library search doc to the fields worth citing."""
    isbn13s = [i for i in doc.get("isbn") or [] if len(i) == 13 and i.isdigit()]
    return {
        "title": doc.get("title"),
        "authors": doc.get("author_name") or [],
        "first_publish_year": doc.get("first_publish_year"),
        "edition_count": doc.get("edition_count"),
        "work_url": OPEN_LIBRARY + doc["key"],
        "isbn13_sample": isbn13s[:5],
        "ebook_access": doc.get("ebook_access"),
        "full_text": full_text_links(doc),
    }


def search(title, author=None, limit=5):
    """Return Open Library works matching title and optional author."""
    params = {"title": title, "limit": limit, "fields": SEARCH_FIELDS}
    if author:
        params["author"] = author
    data = fetch_json(f"{OPEN_LIBRARY}/search.json?{urllib.parse.urlencode(params)}") or {}
    return [shape_search_doc(doc) for doc in data.get("docs", [])]


def author_names(work_key):
    """Return author names for an Open Library work, at most five lookups."""
    work = fetch_json(OPEN_LIBRARY + work_key + ".json") or {}
    names = []
    for entry in (work.get("authors") or [])[:5]:
        key = (entry.get("author") or {}).get("key")
        author = fetch_json(OPEN_LIBRARY + key + ".json") if key else None
        if author and author.get("name"):
            names.append(author["name"])
    return names


def isbn_record(raw):
    """Return the Open Library edition for an ISBN, or None when it has no record."""
    isbn = normalize_isbn(raw)
    edition = fetch_json(f"{OPEN_LIBRARY}/isbn/{isbn}.json")
    if edition is None:
        return None
    works = edition.get("works") or []
    work_key = works[0]["key"] if works else None
    return {
        "isbn13": isbn,
        "title": edition.get("title"),
        "subtitle": edition.get("subtitle"),
        "authors": author_names(work_key) if work_key else [],
        "publishers": edition.get("publishers") or [],
        "publish_date": edition.get("publish_date"),
        "edition_url": OPEN_LIBRARY + edition["key"],
        "work_url": OPEN_LIBRARY + work_key if work_key else None,
        "canonical_url": f"{OPEN_LIBRARY}/isbn/{isbn}",
    }


def full_name(person):
    """Return a Crossref contributor's display name."""
    parts = [person.get("given"), person.get("family")]
    return " ".join(p for p in parts if p) or person.get("name") or ""


def shape_crossref(item):
    """Reduce a Crossref work to the fields worth citing."""
    parts = ((item.get("issued") or {}).get("date-parts") or [[None]])[0]
    doi = item.get("DOI") or ""
    return {
        "doi": doi,
        "type": item.get("type"),
        "is_whole_book": item.get("type") in BOOK_TYPES and not CHAPTER_DOI.match(doi),
        "title": (item.get("title") or [None])[0],
        "authors": [full_name(a) for a in item.get("author") or []],
        "publisher": item.get("publisher"),
        "issued_year": parts[0] if parts else None,
        "isbns": item.get("ISBN") or [],
        "canonical_url": f"https://doi.org/{item.get('DOI')}",
    }


def doi_record(doi):
    """Return the Crossref record for a DOI, or None when Crossref has no record."""
    doi = doi.strip()
    for prefix in ("https://doi.org/", "http://doi.org/", "https://dx.doi.org/", "doi:"):
        doi = doi.removeprefix(prefix)
    data = fetch_json(f"{CROSSREF}/works/{urllib.parse.quote(doi, safe='/:')}")
    return shape_crossref(data["message"]) if data else None


def author_matches(wanted, contributors):
    """Return True when any contributor has the wanted surname and, if known, first initial."""
    names = wanted.lower().split()
    surname, initial = names[-1], names[0][0] if len(names) > 1 else None
    for person in contributors:
        family = (person.get("family") or person.get("name") or "").lower()
        given = (person.get("given") or "").lower()
        if surname in family and (not initial or not given or given.startswith(initial)):
            return True
    return False


def book_dois(title, author=None, rows=10):
    """Return Crossref book records matching title and optional author, oldest first."""
    query = f"{title} {author}" if author else title
    params = {
        "query.bibliographic": query,
        "filter": ",".join(f"type:{t}" for t in BOOK_TYPES),
        "rows": rows,
        "select": "DOI,type,title,author,publisher,issued,ISBN",
    }
    data = fetch_json(f"{CROSSREF}/works?{urllib.parse.urlencode(params)}") or {}
    raw_items = (data.get("message") or {}).get("items", [])
    items = [shape_crossref(i) for i in raw_items]
    if author:
        # Crossref matches titles loosely: a same-titled book by someone else is common.
        for item, raw in zip(items, raw_items):
            item["author_match"] = author_matches(author, raw.get("author") or [])
    return sorted(
        items,
        key=lambda r: (
            not r.get("author_match", True),
            r["issued_year"] is None,
            r["issued_year"] or 0,
        ),
    )


def work_key(raw):
    """Return the bare Open Library work id (OL123W) from an id, key, or URL."""
    match = re.search(r"(OL\d+W)", raw)
    if not match:
        raise ValueError(f"not an Open Library work id: {raw}")
    return match.group(1)


def shape_edition(edition):
    """Reduce an Open Library edition to the fields worth citing."""
    ocaid = edition.get("ocaid")
    year = YEAR.search(edition.get("publish_date") or "")
    return {
        "title": edition.get("title"),
        "publish_date": edition.get("publish_date"),
        "year": int(year.group(1)) if year else None,
        "publishers": edition.get("publishers") or [],
        "languages": [lang["key"].rsplit("/", 1)[-1] for lang in edition.get("languages") or []],
        "isbn13": edition.get("isbn_13") or [],
        "edition_url": OPEN_LIBRARY + edition["key"],
        "scan_url": f"https://archive.org/details/{ocaid}" if ocaid else None,
    }


def editions(raw_work, limit=50):
    """Return a work's editions, oldest first, with any Internet Archive scan."""
    key = work_key(raw_work)
    data = fetch_json(f"{OPEN_LIBRARY}/works/{key}/editions.json?limit={limit}") or {}
    shaped = [shape_edition(e) for e in data.get("entries", [])]
    return sorted(shaped, key=lambda e: (e["year"] is None, e["year"] or 0))


def run(args):
    """Dispatch a parsed command and return (result, found)."""
    if args.command == "search":
        result = search(args.title, args.author, args.limit)
        return result, bool(result)
    if args.command == "isbn":
        result = isbn_record(args.isbn)
        return result, result is not None
    if args.command == "doi":
        result = doi_record(args.doi)
        return result, result is not None
    if args.command == "editions":
        result = editions(args.work, args.limit)
        return result, bool(result)
    result = book_dois(args.title, args.author, args.rows)
    # With an author, only a matching row counts: other rows are different books.
    found = any(r["author_match"] for r in result) if args.author else bool(result)
    return result, found


def build_parser():
    """Return the argument parser for the five subcommands."""
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    sub = parser.add_subparsers(dest="command", required=True)
    p_search = sub.add_parser("search", help="Open Library works by title")
    p_search.add_argument("title")
    p_search.add_argument("--author")
    p_search.add_argument("--limit", type=int, default=5)
    sub.add_parser("isbn", help="one edition by ISBN").add_argument("isbn")
    p_editions = sub.add_parser("editions", help="editions of one Open Library work")
    p_editions.add_argument("work", help="work id, key, or URL, e.g. OL1914748W")
    p_editions.add_argument("--limit", type=int, default=50)
    sub.add_parser("doi", help="one Crossref record by DOI").add_argument("doi")
    p_doi = sub.add_parser("book-doi", help="Crossref book DOIs by title")
    p_doi.add_argument("title")
    p_doi.add_argument("--author")
    p_doi.add_argument("--rows", type=int, default=10)
    return parser


def main(argv=None):
    """Run the CLI and return its exit code."""
    args = build_parser().parse_args(argv)
    try:
        result, found = run(args)
    except (ValueError, FetchError) as error:
        print(json.dumps({"found": False, "error": str(error)}, indent=2))
        return 2 if isinstance(error, FetchError) else 1
    print(json.dumps({"found": found, "result": result}, indent=2, ensure_ascii=False))
    return 0 if found else 1


if __name__ == "__main__":
    sys.exit(main())
