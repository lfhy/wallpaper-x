import json
import re
import shutil
from pathlib import Path
from typing import Optional, Tuple


ROOT = Path.home() / "Movies" / "MyWallpaperX" / "创意工坊"
OLD_EXPORT_DIR = ROOT / "已整理视频"
INDEX_DIR = ROOT / ".mywallpaperx-steam-metadata"
META_NAME = ".mywallpaperx-steam-metadata.json"
VIDEO_EXTS = {".mp4", ".webm", ".mov", ".m4v"}
INVALID_CHARS = re.compile(r'[\\/:?%*|"<>\n\r\t]')
WHITESPACE = re.compile(r"\s+")


def sanitize(title: str, fallback: str) -> str:
    cleaned = INVALID_CHARS.sub(" ", title or "")
    cleaned = WHITESPACE.sub(" ", cleaned).strip()
    cleaned = cleaned[:120].strip()
    return cleaned or fallback


def unique_destination(base_name: str, extension: str, preferred: Optional[Path]) -> Path:
    if preferred and preferred.parent == ROOT:
        return preferred

    index = 0
    while True:
        candidate_name = (
            f"{base_name}{extension}"
            if index == 0
            else f"{base_name} ({index}){extension}"
        )
        candidate = ROOT / candidate_name
        if not candidate.exists():
            return candidate
        index += 1


def load_json(path: Path) -> dict:
    if not path.exists():
        return {}
    try:
        return json.loads(path.read_text(encoding="utf-8"))
    except Exception:
        return {}


def resolve_source_video(workshop_dir: Path, metadata: dict, project: dict) -> Tuple[Optional[Path], Optional[str]]:
    relative_path = metadata.get("sourceVideoRelativePath")
    if relative_path:
        candidate = workshop_dir / relative_path
        if candidate.exists():
            return candidate, relative_path

    preferred = project.get("file")
    if preferred:
        candidate = workshop_dir / preferred
        if candidate.exists():
            return candidate, preferred

    for child in sorted(workshop_dir.iterdir()):
        if child.is_file() and child.suffix.lower() in VIDEO_EXTS:
            return child, child.name
    return None, None


def migrate() -> dict:
    migrated: list[tuple[str, str]] = []
    skipped: list[str] = []
    INDEX_DIR.mkdir(parents=True, exist_ok=True)

    for child in sorted(ROOT.iterdir()):
        if not child.is_dir() or child.name == OLD_EXPORT_DIR.name:
            continue

        metadata_path = child / META_NAME
        project_path = child / "project.json"
        if not metadata_path.exists() and not project_path.exists():
            continue

        metadata = load_json(metadata_path)
        project = load_json(project_path)
        source_video, source_relative_path = resolve_source_video(child, metadata, project)
        if source_video is None or source_relative_path is None:
            skipped.append(child.name)
            continue

        item = metadata.get("item") or {}
        workshop_id = item.get("id") or project.get("workshopid") or child.name
        title = item.get("title") or project.get("title") or f"Workshop-{workshop_id}"
        destination = unique_destination(
            sanitize(title, f"Workshop-{workshop_id}"),
            source_video.suffix or ".mp4",
            Path(metadata["exportedVideoURL"]) if metadata.get("exportedVideoURL") else None,
        )

        if OLD_EXPORT_DIR.exists():
            old_candidate = OLD_EXPORT_DIR / destination.name
            if old_candidate.exists() and not destination.exists():
                shutil.move(str(old_candidate), str(destination))

        if not destination.exists():
            shutil.copy2(str(source_video), str(destination))

        metadata["sourceVideoRelativePath"] = source_relative_path
        preview_relative_path = None
        for candidate_name in ("preview.jpg", "preview.jpeg", "preview.png", "preview.gif"):
            if (child / candidate_name).exists():
                preview_relative_path = candidate_name
                break
        metadata["previewRelativePath"] = preview_relative_path
        metadata["exportedVideoURL"] = str(destination)
        metadata["legacyFolderURL"] = str(child)
        metadata.setdefault("fetchedAt", 0)
        metadata_path.write_text(
            json.dumps(metadata, ensure_ascii=False, separators=(",", ":")),
            encoding="utf-8",
        )
        (INDEX_DIR / f"{workshop_id}.json").write_text(
            json.dumps(metadata, ensure_ascii=False, separators=(",", ":")),
            encoding="utf-8",
        )
        migrated.append((str(workshop_id), destination.name))

    if OLD_EXPORT_DIR.exists():
        remaining = [entry for entry in OLD_EXPORT_DIR.iterdir() if entry.name != ".DS_Store"]
        if not remaining:
            shutil.rmtree(OLD_EXPORT_DIR, ignore_errors=True)

    return {
        "migrated_count": len(migrated),
        "migrated": migrated,
        "skipped": skipped,
    }


if __name__ == "__main__":
    print(json.dumps(migrate(), ensure_ascii=False))
