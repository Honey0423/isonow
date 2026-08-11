import json
import re
from pathlib import Path
from datetime import datetime


# =========================================================
# 폴더 설정
# =========================================================

ISO_DIR = Path("assets/iso")
PKG_DIR = Path("assets/pkg")
PLAN_DIR = Path("assets/plan_dwg")

ISO_OUTPUT = Path("assets/iso_metadata.json")
PKG_OUTPUT = Path("assets/pkg_metadata.json")
PLAN_OUTPUT = Path("assets/plan_metadata.json")


# =========================================================
# 공통 - 파일 최종 수정 날짜
# =========================================================

def get_modified_date(file):
    modified_time = datetime.fromtimestamp(
        file.stat().st_mtime
    )

    return modified_time.strftime("%Y-%m-%d")


# =========================================================
# ISO
#
# 기존에 잘 되던 로직 그대로
# =========================================================

iso_files = []

if ISO_DIR.exists():

    for file in ISO_DIR.iterdir():

        if not file.is_file():
            continue

        if file.suffix.lower() != ".pdf":
            continue

        # ■삭제가 들어간 파일은 제외
        if "■삭제" in file.name:
            continue

        file_name = file.name

        # .pdf 제거
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

            revision_number = int(
                revision_match.group(1)
            )

            # _Rev00 제거
            iso_name = re.sub(
                r"_Rev\d+$",
                "",
                base_name,
                flags=re.IGNORECASE
            )

            revision = f"Rev.{revision_number:02d}"

        else:

            iso_name = base_name
            revision = "Rev.?"

        # -----------------------------------------
        # 실제 파일 최종 수정 날짜
        # -----------------------------------------

        modified_date = get_modified_date(file)

        iso_files.append({
            "fileName": file_name,
            "isoName": iso_name,
            "revision": revision,
            "revisionNumber": (
                revision_number
                if revision_match
                else -1
            ),
            "modifiedDate": modified_date,
            "path": f"assets/iso/{file_name}",
        })


# ISO 이름 → Revision 순서
iso_files.sort(
    key=lambda x: (
        x["isoName"],
        x["revisionNumber"]
    )
)


# =========================================================
# PKG
#
# assets/pkg/ 안의 PDF를 전부 읽음
# =========================================================

pkg_files = []

if PKG_DIR.exists():

    for file in PKG_DIR.iterdir():

        if not file.is_file():
            continue

        if file.suffix.lower() != ".pdf":
            continue

        # ■삭제 파일 제외
        if "■삭제" in file.name:
            continue

        file_name = file.name

        # .pdf 제거
        base_name = file.stem

        modified_date = get_modified_date(file)

        pkg_files.append({
            "fileName": file_name,
            "pkgName": base_name,
            "modifiedDate": modified_date,
            "path": f"assets/pkg/{file_name}",
        })


# 파일명 기준 정렬
pkg_files.sort(
    key=lambda x: x["fileName"].lower()
)


# =========================================================
# PLAN
#
# assets/plan_dwg/
#
# DWG / DXF 모두 읽음
# =========================================================

plan_files = []

if PLAN_DIR.exists():

    for file in PLAN_DIR.iterdir():

        if not file.is_file():
            continue

        if file.suffix.lower() not in [
            ".dwg",
            ".dxf",
        ]:
            continue

        # ■삭제 파일 제외
        if "■삭제" in file.name:
            continue

        file_name = file.name

        base_name = file.stem

        modified_date = get_modified_date(file)

        plan_files.append({
            "fileName": file_name,
            "planName": base_name,
            "extension": file.suffix.lower(),
            "modifiedDate": modified_date,
            "path": f"assets/plan_dwg/{file_name}",
        })


# 파일명 기준 정렬
plan_files.sort(
    key=lambda x: x["fileName"].lower()
)


# =========================================================
# JSON 저장 함수
# =========================================================

def save_json(data, output_file):

    with open(
        output_file,
        "w",
        encoding="utf-8"
    ) as f:

        json.dump(
            data,
            f,
            ensure_ascii=False,
            indent=2
        )


# =========================================================
# 저장
# =========================================================

save_json(
    iso_files,
    ISO_OUTPUT
)

save_json(
    pkg_files,
    PKG_OUTPUT
)

save_json(
    plan_files,
    PLAN_OUTPUT
)


# =========================================================
# 결과 출력
# =========================================================

print()
print("========================================")
print("       ISONow Metadata 생성 완료")
print("========================================")

print()
print(
    f"ISO     : {len(iso_files)}개"
)

print(
    f"PKG     : {len(pkg_files)}개"
)

print(
    f"플랜도  : {len(plan_files)}개"
)

print()
print(f"ISO 저장     : {ISO_OUTPUT}")
print(f"PKG 저장     : {PKG_OUTPUT}")
print(f"플랜도 저장  : {PLAN_OUTPUT}")

print()
print("========================================")