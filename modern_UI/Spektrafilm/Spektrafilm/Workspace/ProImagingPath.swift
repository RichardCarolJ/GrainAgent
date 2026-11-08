import SwiftUI
struct ProImagingPath: View {
    @Bindable var store: WorkspaceStore
    var body: some View {
        HStack(spacing:5) {
            Text(G("照片")); Image(systemName:"chevron.right").font(.system(size:8))
            Text(store.session.noFilm ? G("原图") : store.session.filmIsPositive ? G("反转片") : G("负片"))
            if !store.session.noFilm {
                Image(systemName:"chevron.right").font(.system(size:8))
                Text(store.route == "di" ? "DI" : store.route == "print" ? G("相纸 → 成片") : G("扫描"))
            }
        }.font(.system(size:10,weight:.medium)).foregroundStyle(.secondary)
    }
}
