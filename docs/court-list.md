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

## 私隱
網頁話個人資料不可再用，所以 `CourtCase` 刻意唔載入訴訟各方。
