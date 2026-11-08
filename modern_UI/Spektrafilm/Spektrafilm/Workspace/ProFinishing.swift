import SwiftUI

struct ProFinishing: View {
    @Bindable var store: WorkspaceStore
    var body: some View {
        DateBackSection(session:store.session)
        ProSection(G("日期来源与位置微调")) {
            ProfessionalDateExtras(session:store.session)
        }
    }
}

@MainActor enum ProfessionalDateFormatting {
    static func date(_ settings: DateBackSettings) -> Date? {
        if settings.customText != nil, let iso = settings.customDateISO, let day = PhotoCalendarDay(iso) {
            return Calendar(identifier: .gregorian).date(from: DateComponents(year: day.year, month: day.month, day: day.day))
        }
        let pieces = settings.printedText.split(separator:" ").map(String.init)
        guard pieces.count == 3 else { return nil }
        let order = settings.order
        let y = order == .japan ? pieces[0] : pieces[2]
        let m = order == .us ? pieces[0] : pieces[1]
        let d = order == .japan ? pieces[2] : order == .us ? pieces[1] : pieces[0]
        guard let short = Int(y.replacingOccurrences(of:"'",with:"")),let month = Int(m),let day = Int(d) else { return nil }
        let year = short < 80 ? short+2000 : short < 100 ? short+1900 : short
        let components = DateComponents(year:year,month:month,day:day)
        guard let value = Calendar.current.date(from:components),Calendar.current.dateComponents([.year,.month,.day],from:value) == components else { return nil }
        return value
    }
    static func text(_ date:Date,order:DateBackOrder)->String {
        let c = Calendar.current.dateComponents([.year,.month,.day],from:date)
        return DateBackSettings.format(year:c.year!,month:c.month!,day:c.day!,order:order)
    }
    static func changeOrder(_ order:DateBackOrder,session:Session) {
        var p = session.params
        if p.dateBack.customText != nil,let date = date(p.dateBack) { p.dateBack.customText = text(date,order:order) }
        p.dateBack.order = order; session.params = p
    }
}

struct ProfessionalDateExtras: View {
    @Bindable var session:Session
    private var date:DateBackSettings { session.params.dateBack }
    private var positionAllowed:Bool {
        date.active && date.face != .data && date.placement == .frame && session.dateBackCamera?.printsInMargin != true && date.prints(date.face,filmEdge:session.params.filmEdge)
    }
    var body: some View {
        VStack(alignment:.leading,spacing:10) {
            Toggle(G("自定日期"),isOn:Binding(get:{ date.customText != nil },set:{ on in
                var p = session.params
                p.dateBack.customText = on ? ProfessionalDateFormatting.text(ProfessionalDateFormatting.date(date) ?? Date(),order:date.order) : nil
                p.dateBack.customDateISO = on ? Self.iso(ProfessionalDateFormatting.date(date) ?? Date()) : nil
                session.params = p
            })).disabled(date.face == .data)
            if date.customText != nil {
                DatePicker(G("日期"),selection:Binding(get:{ ProfessionalDateFormatting.date(date) ?? Date() },set:{ value in var p = session.params; p.dateBack.customText = ProfessionalDateFormatting.text(value,order:date.order); p.dateBack.customDateISO = Self.iso(value); session.params = p }),displayedComponents:.date).datePickerStyle(.field).disabled(date.face == .data)
            }
            Picker(G("顺序"),selection:Binding(get:{ date.order },set:{ ProfessionalDateFormatting.changeOrder($0,session:session) })) {
                Text(G("年 / 月 / 日")).tag(DateBackOrder.japan)
                Text(G("日 / 月 / 年")).tag(DateBackOrder.dayFirst)
                Text(G("月 / 日 / 年")).tag(DateBackOrder.us)
            }.disabled(date.face == .data)
            Text(date.printedText.isEmpty ? G("没有可用拍摄日期；开启自定日期填写。") : G("将印上：")+date.printedText).font(.system(size:11)).foregroundStyle(.secondary)
            ProfessionalValueSlider(title:G("水平内缩"),value:binding(\.insetXMM),range:DateBackSettings.insetRange,step:0.1,unit:"mm").disabled(!positionAllowed)
            ProfessionalValueSlider(title:G("垂直内缩"),value:binding(\.insetYMM),range:DateBackSettings.insetRange,step:0.1,unit:"mm").disabled(!positionAllowed)
            Text(G("位置按相机横持计算；竖拍随画面方向旋转。120 胶片的日期位置由所选片边决定。")).font(.system(size:10)).foregroundStyle(.secondary)
        }.font(.system(size:12)).disabled(!date.active)
    }
    private static func iso(_ date: Date) -> String {
        let c = Calendar(identifier: .gregorian).dateComponents([.year,.month,.day], from: date)
        return String(format: "%04d-%02d-%02d", c.year!, c.month!, c.day!)
    }
    private func binding(_ key:WritableKeyPath<DateBackSettings,Double>)->Binding<Double> {
        Binding(get:{ date[keyPath:key] },set:{ var p = session.params; p.dateBack[keyPath:key] = $0; session.params = p })
    }
}
