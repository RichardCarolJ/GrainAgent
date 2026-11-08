// UI copy only. Original StockCatalog and engine profiles are unchanged.
// Source copy: reconstruction/ui-v9/film-guide.json; references: film-guide-sources.json.
struct FilmGuide {
    private let characterKey: String
    @MainActor var character: String { G(characterKey) }
    private let subjectsKey: String
    @MainActor var subjects: String { G(subjectsKey) }
    init(character: String, subjects: String) { characterKey = character; subjectsKey = subjects }
    static let entries: [String: FilmGuide] = [
        "cinestill_800t": FilmGuide(character: "灯光下的电影色彩", subjects: "夜景 · 霓虹 · 室内"),
        "fujifilm_c200": FilmGuide(character: "自然肤色，轻快日常", subjects: "生活 · 合影 · 旅行"),
        "fujifilm_neopan_acros_100_ii": FilmGuide(character: "细腻黑白，层次丰富", subjects: "建筑 · 静物 · 人像"),
        "fujifilm_pro_400h": FilmGuide(character: "肤色柔和，过渡细腻", subjects: "人像 · 婚礼 · 花草"),
        "fujifilm_provia_100f": FilmGuide(character: "色彩均衡，清晰通透", subjects: "旅行 · 风景 · 静物"),
        "fujifilm_velvia_100": FilmGuide(character: "浓郁鲜艳，突出色彩", subjects: "山川 · 花卉 · 日落"),
        "fujifilm_xtra_400": FilmGuide(character: "色彩明快，适合随拍", subjects: "街头 · 日常 · 旅行"),
        "ilford_hp5_plus_400": FilmGuide(character: "经典黑白，中等反差", subjects: "纪实 · 街头 · 人像"),
        "kodak_ektachrome_100": FilmGuide(character: "清透色彩，细节鲜明", subjects: "风景 · 建筑 · 静物"),
        "kodak_ektar_100": FilmGuide(character: "细腻鲜艳，色彩饱满", subjects: "自然 · 旅行 · 产品"),
        "kodak_gold_200": FilmGuide(character: "明亮彩色，日常快照", subjects: "阳光 · 家庭 · 旅行"),
        "kodak_kodachrome_64": FilmGuide(character: "经典彩色反转片", subjects: "旅行 · 街景 · 复古题材"),
        "kodak_portra_160": FilmGuide(character: "自然肤色，柔和细腻", subjects: "人像 · 婚礼 · 静物"),
        "kodak_portra_400": FilmGuide(character: "自然肤色，均衡色彩", subjects: "人像 · 日常 · 旅行"),
        "kodak_portra_800": FilmGuide(character: "自然肤色，高感光配方", subjects: "傍晚 · 室内 · 人像"),
        "kodak_portra_800_push1": FilmGuide(character: "Portra 800 迫冲一档", subjects: "试试更鲜明的夜景与人像"),
        "kodak_portra_800_push2": FilmGuide(character: "Portra 800 迫冲两档", subjects: "试试更强烈的夜景氛围"),
        "kodak_tmax_100": FilmGuide(character: "细腻黑白，细节清晰", subjects: "建筑 · 静物 · 风景"),
        "kodak_tri_x_400": FilmGuide(character: "经典黑白，纪实气质", subjects: "街头 · 纪实 · 人像"),
        "kodak_ultramax_400": FilmGuide(character: "鲜明彩色，日常随拍", subjects: "旅行 · 生活 · 活动"),
        "kodak_verita_200d": FilmGuide(character: "暖肤色，浓彩与深黑", subjects: "人像 · 街景 · 电影感"),
        "kodak_vision3_200t": FilmGuide(character: "钨丝灯型电影负片", subjects: "室内 · 灯光 · 人像"),
        "kodak_vision3_250d": FilmGuide(character: "日光型电影负片", subjects: "日常 · 外景 · 阴天"),
        "kodak_vision3_500t": FilmGuide(character: "高感光钨丝灯电影片", subjects: "夜景 · 灯光 · 街头"),
        "kodak_vision3_50d": FilmGuide(character: "低感光，细腻电影色彩", subjects: "晴天 · 风景 · 外景"),
    ]
}
