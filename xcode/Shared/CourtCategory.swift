import Foundation

/// 案件大類：法院 widget 同 app 用嚟分類同上色。
enum CourtCategory: String, CaseIterable, Codable, Hashable {
    case criminal, civil, family, appeal, tribunal, inquest, other

    var title: String {
        switch self {
        case .criminal: return "刑事"
        case .civil: return "民事"
        case .family: return "家事"
        case .appeal: return "上訴"
        case .tribunal: return "審裁處"
        case .inquest: return "死因"
        case .other: return "其他"
        }
    }
}

/// 由案件編號前綴推斷嘅案件類型（例如 `DCCJ` → 民事・民事訴訟）。
/// 只係按司法機構案號慣例推斷，唔係網頁原文；認唔到就歸「其他」。
struct CaseType: Equatable {
    let category: CourtCategory
    let label: String
}

enum CaseTypes {
    /// 案號開頭嘅英文字母：`DCCJ 1/2026` → `DCCJ`、`CCDI-269/2022(MC)` → `CCDI`。
    static func prefix(of caseNo: String) -> String {
        let trimmed = caseNo.trimmingCharacters(in: .whitespaces)
        return String(trimmed.prefix { $0.isASCII && $0.isLetter }).uppercased()
    }

    static func classify(_ caseNo: String) -> CaseType {
        let code = prefix(of: caseNo)
        if let known = table[code] { return known }
        for (head, match) in groups where code.hasPrefix(head) { return match }
        // 裁判法院：兩個字母嘅法院代號，加 CC（刑事案件）或者 S（傳票），例如 KCCC、WKS
        if code.count == 4, code.hasSuffix("CC") { return CaseType(category: .criminal, label: "刑事案件") }
        if code.count == 3, code.hasSuffix("S") { return CaseType(category: .criminal, label: "傳票案件") }
        for (head, match) in courts where code.hasPrefix(head) { return match }
        return CaseType(category: .other, label: "其他")
    }

    private static func make(_ category: CourtCategory, _ label: String) -> CaseType {
        CaseType(category: category, label: label)
    }

    /// 常見案號前綴。
    static let table: [String: CaseType] = [
        // 終審法院
        "FACC": make(.appeal, "終院刑事上訴"),
        "FACV": make(.appeal, "終院民事上訴"),
        "FAMC": make(.appeal, "終院刑事雜項"),
        "FAMV": make(.appeal, "終院民事雜項"),
        // 上訴法庭
        "CACC": make(.appeal, "刑事上訴"),
        "CACV": make(.appeal, "民事上訴"),
        "CAMP": make(.appeal, "上訴雜項"),
        "CAAR": make(.appeal, "刑期覆核"),
        // 原訟法庭
        "HCMA": make(.appeal, "裁判法院上訴"),
        "HCCC": make(.criminal, "刑事案件"),
        "HCA": make(.civil, "民事訴訟"),
        "HCAL": make(.civil, "憲法及行政法"),
        "HCMP": make(.civil, "雜項程序"),
        "HCPI": make(.civil, "人身傷亡"),
        "HCB": make(.civil, "破產"),
        "HCCW": make(.civil, "公司清盤"),
        "HCCL": make(.civil, "商業"),
        "HCCT": make(.civil, "建築及仲裁"),
        "HCAJ": make(.civil, "海事"),
        // 區域法院
        "DCCC": make(.criminal, "刑事案件"),
        "DCCJ": make(.civil, "民事訴訟"),
        "DCPI": make(.civil, "人身傷亡"),
        "DCEC": make(.civil, "僱員補償"),
        "DCMP": make(.civil, "雜項程序"),
        "DCTC": make(.civil, "稅務申索"),
        "DCEO": make(.civil, "平等機會"),
        // 家事法庭
        "FCMC": make(.family, "婚姻訴訟"),
        "FCMP": make(.family, "家事雜項"),
        "FCAD": make(.family, "領養"),
        // 審裁處、死因裁判法庭
        "LDBM": make(.tribunal, "大廈管理"),
        "LBTC": make(.tribunal, "勞資申索"),
        "SCTC": make(.tribunal, "小額錢債申索"),
        "CCDI": make(.inquest, "死因研訊"),
    ]

    /// 表入面冇、但開頭已經講明係邊個法院／審裁處嘅案號（先於裁判法院規則，免得誤認）。
    private static let groups: [(String, CaseType)] = [
        ("FA", make(.appeal, "終院案件")),
        ("CA", make(.appeal, "上訴庭案件")),
        ("FC", make(.family, "家事案件")),
        ("LD", make(.tribunal, "土地審裁處")),
        ("LB", make(.tribunal, "勞資審裁處")),
        ("SC", make(.tribunal, "小額錢債")),
        ("CC", make(.inquest, "死因研訊")),
    ]

    /// 最後先按法院大致歸類；唔肯定係民事定刑事就唔估。
    private static let courts: [(String, CaseType)] = [
        ("HC", make(.other, "高院案件")),
        ("DC", make(.other, "區院案件")),
    ]
}

/// 法院案件表嘅「聆訊性質」字眼（答辯、訊問、審訊…）。
/// 用固定字詞認，所以唔會將被告姓名或者控罪誤當成性質（網頁話明個人資料不可再用）。
enum HearingStage {
    static let words = [
        "審前覆核", "交付審判", "答辯", "訊問", "審訊", "提訊", "判刑", "聆訊", "裁決", "宣判",
        "求情", "覆核", "提堂", "續審", "判決", "預審", "研訊", "指示",
    ]

    /// 雙語格只睇中文部分；要以字詞開頭、而且夠短先算（避免備註句子）。
    static func match(_ text: String) -> String? {
        let zh = CourtList.chinesePart(text).trimmingCharacters(in: .whitespaces)
        guard !zh.isEmpty, zh.count <= 8, words.contains(where: { zh.hasPrefix($0) }) else { return nil }
        return zh
    }
}

extension CourtCase {
    var caseType: CaseType { CaseTypes.classify(caseNo) }

    /// 聆訊階段（答辯、審訊、D1 - 判刑…）：有獨立控罪格（`offence`）嗰陣 `nature` 就係聆訊格；否則只認固定階段字眼。
    var stage: String? {
        if offence != nil { return nature }
        return nature.flatMap(HearingStage.match)
    }

    /// 控罪／性質：有獨立控罪格就用佢；否則 `nature` 唔係階段字眼（例如「傷人」「販運危險藥物；管有…」）先當控罪。
    /// widget 同 app 另起一行顯示。
    var charge: String? {
        if let offence, !offence.isEmpty { return offence }
        guard let nature, !nature.isEmpty, HearingStage.match(nature) == nil else { return nil }
        return nature
    }

    /// 「民事訴訟 · 聆訊」：案件類型加網頁上嘅聆訊階段（兩者一樣就唔重複）。
    var detailText: String {
        let label = caseType.label
        guard let stage, stage != label else { return label }
        return "\(label) · \(stage)"
    }
}

/// 一個分類有幾多宗。
struct CategoryCount: Equatable {
    let category: CourtCategory
    let count: Int
}

extension CourtDay {
    /// 按 `CourtCategory.allCases` 次序，只列有案件嘅分類。
    var categoryCounts: [CategoryCount] {
        var counts: [CourtCategory: Int] = [:]
        for item in cases { counts[item.caseType.category, default: 0] += 1 }
        return CourtCategory.allCases.compactMap { category in
            guard let count = counts[category], count > 0 else { return nil }
            return CategoryCount(category: category, count: count)
        }
    }
}
