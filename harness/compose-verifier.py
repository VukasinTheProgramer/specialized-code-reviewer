#!/usr/bin/env python3
"""Compose one pr-verify-* agent from core/doctrine.md + a verify-*.body.md.

usage: compose-verifier.py <body.md> <doctrine.md> <banner> > OUT.md

body.md is a `key: value` header (one field per line) followed by a lone
`---` line, then the per-label "How to verify in this codebase" content
verbatim. doctrine.md is the two shared blocks with a `<<<BODY>>>` marker
between them, and `{{PLACEHOLDER}}` tokens filled from the header fields.
Plain string replacement, not sed — the prose has backticks, em-dashes and
quotes that make shell quoting a liability for no benefit here.
"""
import sys

body_path, doctrine_path, banner = sys.argv[1], sys.argv[2], sys.argv[3]

with open(body_path) as f:
    body_text = f.read()
header_text, sep, section_content = body_text.partition("\n---\n")
if not sep:
    sys.exit(f"error: {body_path} has no lone '---' line separating its header from its body content")

fields = {}
for line in header_text.splitlines():
    key, _, value = line.partition(": ")
    fields[key.strip()] = value

with open(doctrine_path) as f:
    doctrine = f.read()
pre, marker, post = doctrine.partition("<<<BODY>>>\n")
if not marker:
    sys.exit(f"error: {doctrine_path} has no <<<BODY>>> marker")

placeholders = {
    "{{SLICE_NAME}}": fields["slice_name"],
    "{{LABELS_TICKED}}": fields["labels_ticked"],
    "{{LABELS_JSON}}": fields["labels_json"],
    "{{EXAMPLE_LABEL}}": fields["example_label"],
    "{{QUESTION}}": fields["question"],
    "{{MULTI_LABEL_EG}}": fields["multi_label_eg"],
    "{{LABELS}}": fields["labels"],
}


def render(text):
    for k, v in placeholders.items():
        text = text.replace(k, v)
    return text


frontmatter = (
    "---\n"
    f"{banner}\n"
    f"name: {fields['name']}\n"
    f"description: {fields['description']}\n"
    "tools: Read, Grep, Glob, mcp__graphify__get_neighbors, mcp__graphify__shortest_path\n"
    "disallowedTools: Write, Edit, NotebookEdit, Bash\n"
    "model: sonnet\n"
    "effort: default\n"
    "---\n"
)

sys.stdout.write(
    frontmatter
    + render(pre)
    + "\n"
    + section_content.rstrip("\n")
    + "\n\n"
    + render(post)
)
