# 法庭日誌（Court List）資料來源與解析

來自已暫停嘅 `iceninye/hk-court`，所有驗證過嘅技術搬返嚟 `xcode/Shared/CourtList.swift`。

## 來源
- `https://e-services.judiciary.hk/dcl/view.jsp?lang=tc&date=DDMMYYYY&court=CODE`
- 要 Safari User-Agent 加 `Referer: https://e-services.judiciary.hk/dcl/index.jsp?lang=tc`，否則 404。
- **只公布到下一個工作日**（約前一日 18:30）。之後日期回傳同一頁 4512 byte 空頁，所以做唔到「未來一星期」。
- `index.jsp?lang=tc&date=DDMMYYYY` 嘅下拉選單 ☑／☐ 顯示嗰日邊啲法院有案件表。
- 裁判法院用 `*MAG` 代碼（`KC` 會 404）；`ALLMAG` 係七個裁判法院嘅總和。

## 版面
- 標準 7 欄：法庭｜法官｜時間｜案件編號｜訴訟各方｜性質｜應訊代表（FMC 係「案件號碼」6 欄）。
- LT（申索编號）、SMT、MCL、各裁判法院：法庭同法官喺橫幅行，時間只喺每組第一行出現。
- CRC：案件格尾部夾備註，`trimCaseNo` 會去走。
- 合併儲存格（rowspan）令格數少咗：改按內容認時間、案號、法庭、法官，其餘沿用上一行。
- 冇案件編號嘅行（批量傳票、「見附頁」）唔算聆訊，但時間照樣沿用。
- 雙語儲存格只留中文（`chinesePart`）。

## 控罪／性質
已用 hk-court 驗證過嘅版面（`iceninye/hk-court` `scraper/fetch.py`）：
- **有表頭嘅標準案件表**（高院、區院、土地等）：「性質」或「控罪 / 性質」欄（按表頭對位）嘅中文內容存入 `CourtCase.nature`。多項控罪 `(1)甲 (1)A (2)乙 (2)B` → `(1)甲 (2)乙`。
  合併儲存格令格數唔齊時，除咗時間、案號、法庭、法官，剩低嘅格要同表頭「訴訟各方、控罪／性質、應訊代表」格數完全一樣先對位讀取，否則唔猜。
- **裁判法院**（冇表頭）：每行 `[時間] | 案號 | 被告 | 控罪 | 聆訊`（最少 4 格）。控罪存入 `CourtCase.offence`（控罪格唔可以同被告格一樣），聆訊存入 `nature`（`D1 - 判刑 D1 - Sentence` → `D1 - 判刑`）。
- 中文部分去走括號英文，超過 120 字截短加「…」。
- 顯示：階段字眼（答辯、審訊、聆訊…，`HearingStage`；或者有獨立控罪格時嘅聆訊格）喺「案件類型 · 階段」；控罪（`CourtCase.charge`）另起一行，widget 同 app 列表都有，app 詳情頁有獨立一欄。
- 「性質」格內容同「訴訟各方」格一模一樣就唔要（防止錯位時洩露訴訟各方）。

## 私隱
網頁話個人資料不可再用，所以 `CourtCase` 刻意唔載入訴訟各方。
