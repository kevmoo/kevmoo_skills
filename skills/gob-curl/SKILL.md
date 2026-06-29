---
name: gob-curl
description: |-
  Use gob-curl and Buildbucket tools to inspect the status, tryjobs, and CI results of a Gerrit CL.
key_features:
  - Gerrit CL inspection
  - Buildbucket tryjob inspection
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

### Finding the CL from a local branch

If you need to inspect a local branch in the `sdk` repository and find its
corresponding CL:
1. Run `git log -1` to locate the `Change-Id` in the most recent commit message.
2. Query Gerrit using the Change-Id to find the CL number:
   ```bash
   gob-curl 'https://dart-review.googlesource.com/changes/?q=<Change-Id>'
   ```
   Extract the `project` and `_number` from the response to form the
   `<change-id>` (e.g., `sdk~478860`).

### Useful Endpoints for Inspecting CL Status

**1. Get Comprehensive Change Details**
This is the most useful endpoint to get an overall picture of the CL. It
includes labels (e.g., Code-Review, Commit-Queue), messages, current revision
info, and the files modified in the current patchset.
```bash
gob-curl 'https://dart-review.googlesource.com/changes/<change-id>/detail?o=LABELS&o=MESSAGES&o=CURRENT_REVISION&o=CURRENT_COMMIT&o=CURRENT_FILES'
# Example: gob-curl 'https://dart-review.googlesource.com/changes/sdk~478860/detail?o=LABELS&o=MESSAGES&o=CURRENT_REVISION&o=CURRENT_COMMIT&o=CURRENT_FILES'
```

### 2. Digging into Tryjob Failures (Buildbucket)

When a tryjob fails (e.g., `dart/try/dart2wasm-linux-optimized-jsc-try`), the
Gerrit message will often include a link to the Buildbucket build, for example:
`https://cr-buildbucket.appspot.com/build/8689486480122051441`.

You can use the Buildbucket CLI (`bb`) to quickly fetch the failure details:

**NOTE:** Some `bb` commands may require you to be authenticated. If you see
"Login required", ask the user to run `bb auth-login` in their terminal.


1. **Find the failed steps**:
   Extract the Build ID from the URL (`8689486480122051441`) and use `bb get`
   with the `-steps` flag to see which step failed:
   ```bash
   bb get -steps <BUILD_ID>
   ```
   Look for the step marked `FAILURE` (e.g., `Step "build dart" FAILURE`).

2. **Fetch the raw execution logs**:
   Use `bb log` passing the build ID and the exact name of the failed step to
   print the logs directly to your terminal:
   ```bash
   bb log <BUILD_ID> "<STEP_NAME>"
   ```
   *Example:* `bb log 8689486480122051441 "build dart"`

**Alternative method using curl:**
If you do not have the `bb` CLI installed, you can extract the Build ID and use the BuildBucket API:

```bash
# Get the failing step and log URLs inside the BuildBucket API
curl -s -X POST 'https://cr-buildbucket.appspot.com/prpc/buildbucket.v2.Builds/GetBuild' \
     -H 'Accept: application/json' -H 'Content-Type: application/json' \
     -d '{"id": "<build-id>", "mask": {"fields": "steps"}}' \
     | tail -n +2 | jq -r 'if .steps then .steps[] | select(.status == "FAILURE") | .name, (.logs[]?.viewUrl) else empty end'

# The previous command provides a viewUrl for browsers. To get the raw log,
# construct a URL like the one below using the build ID and failed step name:
curl -s 'https://logs.chromium.org/logs/dart/buildbucket/cr-buildbucket/<build-id>/+/u/<failed_step_name>/stdout?format=raw'
```

**3. Get Inline Review Comments**
Retrieve inline comments left by reviewers on specific files in the CL.
```bash
gob-curl 'https://dart-review.googlesource.com/changes/<change-id>/comments'
```

**4. Get Reviewers and their Votes Detailed**
If you need specific details on who has reviewed the CL and what their votes are.
```bash
gob-curl 'https://dart-review.googlesource.com/changes/<change-id>/reviewers'
```

**5. Get the Commit Message of the Current Revision**
```bash
gob-curl 'https://dart-review.googlesource.com/changes/<change-id>/revisions/current/commit'
```

**6. Check Tryjob and Test Results**
Tryjob and CI test results are typically recorded as messages on the CL. To see
if tests passed or failed on the latest patchset:
```bash
gob-curl 'https://dart-review.googlesource.com/changes/<change-id>/detail?o=MESSAGES&o=LABELS'
```
Check the `messages` array for the most recent status updates from CI bots
(e.g., "Tryjobs failed" or "Dry run: This CL passed all dry run builders"). The
`attention_set` object may also indicate a reason like `ps#8: Tryjobs failed`.


### Constraints and Best Practices
*   Always use single quotes (`'`) around the URL when calling `gob-curl` to
    avoid zsh issues with query parameters and special characters.
*   The output format starts with a magic string `)]}'\n`. Be prepared to handle
    or strip this when parsing the JSON output if you are scripting it (though
    `gob-curl` often prints it as is, and you can just read past it).
*   Review the `messages` array in the change detail or the output of `comments`
    to identify specific feedback you need to address in the code.
