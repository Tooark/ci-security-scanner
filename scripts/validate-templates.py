#!/usr/bin/env python3
"""Structural validation of the GitLab CI/CD component templates.

GitLab only reports these problems when a pipeline is created, which is far too
late for a component that other projects include. The checks here are the ones
that catch real breakage:

  * the spec/config separator is present and both documents parse;
  * every ``$[[ inputs.x ]]`` reference resolves to a declared input;
  * every declared input is actually referenced (dead inputs are a doc lie);
  * a declared ``default`` is one of the declared ``options``;
  * the template defines exactly one job.

Usage: python3 scripts/validate-templates.py [templates/*.yml]
"""

from __future__ import annotations

import re
import sys
from pathlib import Path

try:
  import yaml
except ImportError:  # pragma: no cover - environment problem, not a template one
  sys.exit("PyYAML is required: python3 -m pip install pyyaml")

REPO_ROOT = Path(__file__).resolve().parent.parent
INPUT_REF = re.compile(r"\$\[\[\s*inputs\.([A-Za-z0-9_]+)\s*\]\]")
VALID_INPUT_KEYS = {"default", "description", "type", "options", "regex"}
VALID_INPUT_TYPES = {"string", "number", "boolean", "array"}


class TemplateError(Exception):
  """A template violates one of the structural rules."""


def split_documents(text: str) -> tuple[str, str]:
  """Splits a component template into its spec and config halves."""
  parts = re.split(r"^---\s*$", text, maxsplit=1, flags=re.MULTILINE)
  if len(parts) != 2:
    raise TemplateError("missing the '---' separator between spec and config")
  return parts[0], parts[1]


def check_inputs_declared(spec_text: str) -> dict[str, dict]:
  """Parses and sanity-checks the spec half, returning the input definitions."""
  spec_doc = yaml.safe_load(spec_text)
  if not isinstance(spec_doc, dict) or "spec" not in spec_doc:
    raise TemplateError("the first document must contain a 'spec' key")

  inputs = spec_doc["spec"].get("inputs")
  if not isinstance(inputs, dict) or not inputs:
    raise TemplateError("spec.inputs must be a non-empty mapping")

  for name, definition in inputs.items():
    # A bare `name:` with no body is a valid required input.
    if definition is None:
      continue
    if not isinstance(definition, dict):
      raise TemplateError(f"input '{name}' must be a mapping or null")

    unknown = set(definition) - VALID_INPUT_KEYS
    if unknown:
      raise TemplateError(f"input '{name}' has unknown keys: {sorted(unknown)}")

    declared_type = definition.get("type", "string")
    if declared_type not in VALID_INPUT_TYPES:
      raise TemplateError(f"input '{name}' has unsupported type '{declared_type}'")

    options = definition.get("options")
    if options is not None:
      if declared_type != "string":
        raise TemplateError(f"input '{name}' uses options with type '{declared_type}'")
      if "default" in definition and definition["default"] not in options:
        raise TemplateError(
            f"input '{name}' default {definition['default']!r} is not among its options"
        )

  return inputs


def check_config(config_text: str) -> None:
  """Parses the config half and asserts it defines a single job."""
  config_doc = yaml.safe_load(config_text)
  if not isinstance(config_doc, dict) or len(config_doc) != 1:
    raise TemplateError("the second document must define exactly one job")


def validate(path: Path) -> list[str]:
  """Validates one template, returning the problems found."""
  text = path.read_text(encoding="utf-8")
  problems: list[str] = []

  try:
    spec_text, config_text = split_documents(text)
    inputs = check_inputs_declared(spec_text)
    check_config(config_text)
  except (TemplateError, yaml.YAMLError) as exc:
    return [str(exc)]

  referenced = set(INPUT_REF.findall(config_text))
  declared = set(inputs)

  for name in sorted(referenced - declared):
    problems.append(f"references undeclared input '{name}'")
  for name in sorted(declared - referenced):
    problems.append(f"declares input '{name}' but never uses it")

  return problems


def main(argv: list[str]) -> int:
  targets = [Path(a) for a in argv[1:]] or sorted((REPO_ROOT / "templates").glob("*.yml"))
  if not targets:
    print("no templates found", file=sys.stderr)
    return 1

  failed = False
  for path in targets:
    problems = validate(path)
    label = path.relative_to(REPO_ROOT) if path.is_absolute() else path
    if problems:
      failed = True
      print(f"  FAIL {label}")
      for problem in problems:
        print(f"       {problem}")
    else:
      print(f"  ok   {label}")

  if failed:
    print("\ntemplate validation failed", file=sys.stderr)
    return 1

  print("\nall templates valid")
  return 0


if __name__ == "__main__":
  sys.exit(main(sys.argv))
