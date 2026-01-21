#!/usr/bin/env python3
from __future__ import annotations

import sys
from pathlib import Path
from typing import Dict, List

import yaml


REPO_ROOT = Path(__file__).resolve().parent.parent
SKILLS_DIR = REPO_ROOT / "wf" / "skills"


class ValidationError(Exception):
    pass


def load_frontmatter(path: Path) -> Dict[str, str]:
    content = path.read_text(encoding="utf-8")
    lines = content.splitlines()
    if not lines or lines[0].strip() != "---":
        raise ValidationError("missing opening frontmatter delimiter '---'")

    closing_index = None
    for idx, line in enumerate(lines[1:], start=1):
        if line.strip() == "---":
            closing_index = idx
            break
    if closing_index is None:
        raise ValidationError("missing closing frontmatter delimiter '---'")

    raw_frontmatter = "\n".join(lines[1:closing_index])
    try:
        data = yaml.safe_load(raw_frontmatter) or {}
    except yaml.YAMLError as exc:
        raise ValidationError(f"invalid YAML: {exc}") from exc

    if not isinstance(data, dict):
        raise ValidationError("frontmatter must be a YAML mapping")

    return data


def validate_skill(skill_dir: Path) -> List[str]:
    errors: List[str] = []
    skill_file = skill_dir / "SKILL.md"

    if not skill_file.exists():
        return [f"{skill_dir.name}: missing SKILL.md"]

    try:
        frontmatter = load_frontmatter(skill_file)
    except ValidationError as exc:
        return [f"{skill_dir.name}: {exc}"]

    name = frontmatter.get("name")
    if not isinstance(name, str) or not name.strip():
        errors.append(f"{skill_dir.name}: 'name' is required and must be a non-empty string")
    elif name != skill_dir.name:
        errors.append(f"{skill_dir.name}: 'name' must match directory name '{skill_dir.name}'")

    description = frontmatter.get("description")
    if not isinstance(description, str) or not description.strip():
        errors.append(f"{skill_dir.name}: 'description' is required and must be a non-empty string")

    model = frontmatter.get("model")
    if model is not None and (not isinstance(model, str) or not model.strip()):
        errors.append(f"{skill_dir.name}: 'model' must be a non-empty string when provided")

    return errors


def main() -> int:
    if not SKILLS_DIR.exists():
        print(f"skills directory not found: {SKILLS_DIR}", file=sys.stderr)
        return 1

    all_errors: List[str] = []
    seen_names = set()
    for skill_dir in sorted(p for p in SKILLS_DIR.iterdir() if p.is_dir()):
        errors = validate_skill(skill_dir)
        name_path = skill_dir.name
        if name_path in seen_names:
            errors.append(f"{skill_dir.name}: duplicate skill directory name")
        seen_names.add(name_path)
        all_errors.extend(errors)

    if all_errors:
        print("Skill validation failed:")
        for error in all_errors:
            print(f"- {error}")
        return 1

    print("All skills validated successfully.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
