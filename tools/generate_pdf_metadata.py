import json
import re
from pathlib import Path
from datetime import datetime

PDF_DIR = Path("assets/pdf")
OUTPUT_FILE = Path("assets/pdf_metadata.json")

pdf_files = []

for file in PDF_DIR.iterdir():

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
        revision_number = int(revision_match.group(1))

        # _Rev00 제거
        iso_name = re.sub(
            r"_Rev\d+$",
            "",
            base_name,
            flags=re.IGNORECASE
        )

        revision = f"Rev.{revision_number:02d}"

    else:
        # Revision이 없으면 ?
        iso_name = base_name
        revision = "Rev.?"

    # -----------------------------------------
    # 파일 최종 수정 날짜
    # -----------------------------------------

    modified_time = datetime.fromtimestamp(
        file.stat().st_mtime
    )

    modified_date = modified_time.strftime("%Y-%m-%d")

    pdf_files.append({
        "fileName": file_name,
        "isoName": iso_name,
        "revision": revision,
        "revisionNumber": revision_number if revision_match else -1,
        "modifiedDate": modified_date,
        "path": f"assets/pdf/{file_name}",
    })


# ISO 이름 → Revision 순서로 정렬
pdf_files.sort(
    key=lambda x: (
        x["isoName"],
        x["revisionNumber"]
    )
)


with open(
    OUTPUT_FILE,
    "w",
    encoding="utf-8"
) as f:

    json.dump(
        pdf_files,
        f,
        ensure_ascii=False,
        indent=2
    )


print(f"완료: {len(pdf_files)}개의 PDF 정보를 생성했습니다.")
print(f"저장 위치: {OUTPUT_FILE}")