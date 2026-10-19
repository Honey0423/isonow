import json
import re
from pathlib import Path
from datetime import datetime


# =========================================================
# 현장별 도면 메타데이터 생성
#
# 폴더 구조:
#
#   assets/sites/{현장이름}/iso/        ISO PDF
#   assets/sites/{현장이름}/pkg/        PKG PDF
#   assets/sites/{현장이름}/plan_dwg/   Plan DWG / DXF
#
# 현장이름은 Firestore projects 문서의 name과 같아야 한다. (예: M17)
#
# 실행 (isonow 폴더에서):
#
#   python tools/generate_pdf_metadata.py
#
# 결과:
#   - 현장마다 iso_metadata.json / pkg_metadata.json / plan_metadata.json 생성
#   - pubspec.yaml의 SITE ASSETS 블록을 현장 폴더 목록으로 갱신
# =========================================================

SITES_DIR = Path("assets/sites")
PUBSPEC = Path("pubspec.yaml")

ASSETS_START = "# ===== SITE ASSETS START ====="
ASSETS_END = "# ===== SITE ASSETS END ====="


# =========================================================
# 공통 - 파일 최종 수정 날짜
# =========================================================

def get_modified_date(file):
    modified_time = datetime.fromtimestamp(
        file.stat().st_mtime
    )

    return modified_time.strftime("%Y-%m-%d")


def asset_path(file):
    # Flutter asset 경로는 항상 / 사용
    return file.as_posix()


# =========================================================
# ISO
# =========================================================

def build_iso(iso_dir):
    iso_files = []

    if not iso_dir.exists():
        return iso_files

    for file in iso_dir.iterdir():

        if not file.is_file():
            continue

        if file.suffix.lower() != ".pdf":
            continue

        # ■삭제가 들어간 파일은 제외
        if "■삭제" in file.name:
            continue

        file_name = file.name
        base_name = file.stem

        # -----------------------------------------
        # Revision 추출
        #
        # 예:
        # OD25-POW-E-0038-01_Rev00.pdf
        # OD25-POW-E-0038-01_Rev01.pdf
        # -----------------------------------------

        revision_match = re.search(
            r"_Rev(\d+)$",
            base_name,
            re.IGNORECASE
        )

        if revision_match:
            revision_number = int(revision_match.group(1))

            iso_name = re.sub(
                r"_Rev\d+$",
                "",
                base_name,
                flags=re.IGNORECASE
            )

            revision = f"Rev.{revision_number:02d}"

        else:
            revision_number = -1
            iso_name = base_name
            revision = "Rev.?"

        iso_files.append({
            "fileName": file_name,
            "isoName": iso_name,
            "revision": revision,
            "revisionNumber": revision_number,
            "modifiedDate": get_modified_date(file),
            "path": asset_path(file),
        })

    # ISO 이름 → Revision 순서
    iso_files.sort(
        key=lambda x: (
            x["isoName"],
            x["revisionNumber"]
        )
    )

    return iso_files


# =========================================================
# PKG
# =========================================================

def build_pkg(pkg_dir):
    pkg_files = []

    if not pkg_dir.exists():
        return pkg_files

    for file in pkg_dir.iterdir():

        if not file.is_file():
            continue

        if file.suffix.lower() != ".pdf":
            continue

        # ■삭제 파일 제외
        if "■삭제" in file.name:
            continue

        pkg_files.append({
            "fileName": file.name,
            "pkgName": file.stem,
            "modifiedDate": get_modified_date(file),
            "path": asset_path(file),
        })

    pkg_files.sort(
        key=lambda x: x["fileName"].lower()
    )

    return pkg_files


# =========================================================
# PLAN (DWG / DXF)
# =========================================================

def build_plan(plan_dir):
    plan_files = []

    if not plan_dir.exists():
        return plan_files

    for file in plan_dir.iterdir():

        if not file.is_file():
            continue

        if file.suffix.lower() not in [".dwg", ".dxf"]:
            continue

        # ■삭제 파일 제외
        if "■삭제" in file.name:
            continue

        plan_files.append({
            "fileName": file.name,
            "planName": file.stem,
            "extension": file.suffix.lower(),
            "modifiedDate": get_modified_date(file),
            "path": asset_path(file),
        })

    plan_files.sort(
        key=lambda x: x["fileName"].lower()
    )

    return plan_files


# =========================================================
# JSON 저장
# =========================================================

def save_json(data, output_file):
    with open(output_file, "w", encoding="utf-8") as f:
        json.dump(
            data,
            f,
            ensure_ascii=False,
            indent=2
        )


# =========================================================
# pubspec.yaml SITE ASSETS 블록 갱신
#
# Flutter는 하위 폴더를 자동으로 포함하지 않으므로
# 현장 폴더와 iso / pkg / plan_dwg 폴더를 각각 등록한다.
# =========================================================

def update_pubspec(asset_dirs):
    if not PUBSPEC.exists():
        print("pubspec.yaml을 찾지 못했습니다. (isonow 폴더에서 실행하세요)")
        return False

    raw = PUBSPEC.read_bytes().decode("utf-8")
    newline = "\r\n" if "\r\n" in raw else "\n"
    lines = raw.split(newline)

    start = next(
        (i for i, line in enumerate(lines) if ASSETS_START in line),
        -1,
    )
    end = next(
        (i for i, line in enumerate(lines) if ASSETS_END in line),
        -1,
    )

    if start < 0 or end < 0 or end < start:
        print("pubspec.yaml에서 SITE ASSETS 블록을 찾지 못했습니다.")
        return False

    indent = lines[start][: len(lines[start]) - len(lines[start].lstrip())]

    block = [
        lines[start],
        f"{indent}# 현장별 도면 폴더. tools/generate_pdf_metadata.py가 자동으로 갱신합니다.",
    ]

    for d in asset_dirs:
        block.append(f"{indent}- {d}")

    block.append(lines[end])

    new_lines = lines[:start] + block + lines[end + 1:]

    PUBSPEC.write_bytes(newline.join(new_lines).encode("utf-8"))

    return True


# =========================================================
# 실행
# =========================================================

def main():
    if not SITES_DIR.exists():
        print(f"{SITES_DIR} 폴더가 없습니다.")
        print("assets/sites/{현장이름}/iso, pkg, plan_dwg 구조로 도면을 넣어주세요.")
        return

    site_dirs = sorted(
        [d for d in SITES_DIR.iterdir() if d.is_dir()],
        key=lambda d: d.name.lower(),
    )

    if not site_dirs:
        print(f"{SITES_DIR} 안에 현장 폴더가 없습니다.")
        return

    asset_dirs = []

    print()
    print("========================================")
    print("       ISONow Metadata 생성 (현장별)")
    print("========================================")

    for site_dir in site_dirs:
        iso_dir = site_dir / "iso"
        pkg_dir = site_dir / "pkg"
        plan_dir = site_dir / "plan_dwg"

        iso_files = build_iso(iso_dir)
        pkg_files = build_pkg(pkg_dir)
        plan_files = build_plan(plan_dir)

        save_json(iso_files, site_dir / "iso_metadata.json")
        save_json(pkg_files, site_dir / "pkg_metadata.json")
        save_json(plan_files, site_dir / "plan_metadata.json")

        asset_dirs.append(f"{asset_path(site_dir)}/")

        for sub in (iso_dir, pkg_dir, plan_dir):
            if sub.exists():
                asset_dirs.append(f"{asset_path(sub)}/")

        print()
        print(f"[{site_dir.name}]")
        print(f"  ISO     : {len(iso_files)}개")
        print(f"  PKG     : {len(pkg_files)}개")
        print(f"  플랜도  : {len(plan_files)}개")

    print()

    if update_pubspec(asset_dirs):
        print("pubspec.yaml assets 갱신 완료")

    print("========================================")


if __name__ == "__main__":
    main()
