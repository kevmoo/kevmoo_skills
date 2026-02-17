---
name: gob-curl
description: |-
  Use gob-curl to inspect the status of a changelist (CL) on Gerrit.
---

## When to use this skill

When the user gives you a link to a Gerrit CL or asks you to inspect the
status, review comments, or CI results of a CL on Gerrit (e.g.,
`https://dart-review.googlesource.com/c/sdk/+/478860` or `sdk~478860`).

## How to use this skill

Use the `run_command` tool to execute `gob-curl` against the Gerrit REST API
endpoints.

**CRITICAL RULE:**
*   You MUST ONLY do `GET` requests. 
*   Do NOT attempt to `POST`, `PUT`, or `DELETE` anything.

### Forming the URL

Gerrit CL URLs usually look like
`https://dart-review.googlesource.com/c/sdk/+/478860`.
The `<change-id>` for the API can be the project and CL number: `sdk~478860`.
Always strictly quote the URL in the shell command to avoid globbing issues
with `~` and `?`.

### Useful Endpoints for Inspecting CL Status

**1. Get Comprehensive Change Details**
This is the most useful endpoint to get an overall picture of the CL. It
includes labels (e.g., Code-Review, Commit-Queue), messages, current revision
info, and the files modified in the current patchset.
```bash
gob-curl 'https://dart-review.googlesource.com/changes/<change-id>/detail?o=LABELS&o=MESSAGES&o=CURRENT_REVISION&o=CURRENT_COMMIT&o=CURRENT_FILES'
# Example: gob-curl 'https://dart-review.googlesource.com/changes/sdk~478860/detail?o=LABELS&o=MESSAGES&o=CURRENT_REVISION&o=CURRENT_COMMIT&o=CURRENT_FILES'
```

**2. Get Inline Review Comments**
Retrieve inline comments left by reviewers on specific files in the CL.
```bash
gob-curl 'https://dart-review.googlesource.com/changes/<change-id>/comments'
```

**3. Get Reviewers and their Votes Detailed**
If you need specific details on who has reviewed the CL and what their votes are.
```bash
gob-curl 'https://dart-review.googlesource.com/changes/<change-id>/reviewers'
```

**4. Get the Commit Message of the Current Revision**
```bash
gob-curl 'https://dart-review.googlesource.com/changes/<change-id>/revisions/current/commit'
```

### Constraints and Best Practices
*   Always use single quotes (`'`) around the URL when calling `gob-curl` to
    avoid zsh issues with query parameters and special characters.
*   The output format starts with a magic string `)]}'\n`. Be prepared to handle
    or strip this when parsing the JSON output if you are scripting it (though
    `gob-curl` often prints it as is, and you can just read past it). 
*   Review the `messages` array in the change detail or the output of `comments`
    to identify specific feedback you need to address in the code.
