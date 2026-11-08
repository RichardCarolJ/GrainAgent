# 本地构建资源

Tools/build-local.py 从本工程编译 Swift 和 C++。此目录包含本地构建所需的预编译资源。

- Precompiled/default.metallib：由原版未修改源码重编译、已核验的界面渲染着色器库。
- Precompiled/Assets.car：包含原版 AccentColor 数值的资源目录。GrainAgent 图标和相机材质另外从产品 Resources 打包。
- Precompiled/manifest.json：上述文件的 SHA-256，构建时先核验，不能静默替换。

素材和成像数据沿用 SpektraLab 1.3.5。两套 Metal 库由对应源码编译，支持 macOS 14。实际照片处理库、常量、胶片和相纸数据在 modern_UI/Spektrafilm/Spektrafilm/Resources/engine/，包含独立的 spektrafilm.metallib。许可证位于 Resources/Licenses。

当前没有改动 Metal 源码或胶片数据。以后若修改着色器，需要从对应源码重新构建并审核校验清单，不能继续表述为原版成像资源不变。

最低运行目标为 Apple Silicon / macOS 14.0，由 Product.json 统一控制。
两套 Metal 库的目标均为 macOS 14.0。macOS 26 及以上保留原生 Liquid Glass；
更早的受支持系统使用系统半透明材质，界面控件和处理逻辑共用。编译时仍需支持这些
新接口的 macOS 26 SDK / Swift 6 工具链；最低运行版本不等于最低构建 SDK。
正式发布的 GrainAgent 1.0.1 Build 29 已在 macOS 14 和 macOS 15 的 Mac 上通过验证。

ReleaseResources.json 是经审核的运行资源与界面图片清单。构建和打包都会核对文件名与 SHA-256；新增资源必须先确认用途再更新清单。未知图片、相机原片、照片参数、工作恢复记录和旧辅助可执行文件不得进入发行包或对应源码包。

IconSource/GrainAgent.png 是构建用的 1024 px 应用图标。
`swift Tools/generate-app-icon.swift` 生成 10 个 macOS 图标尺寸及 GrainAgent.icns。
构建和打包的 `--check` 核对透明边缘、可见尺寸、圆角及 ICNS 分辨率。

Metal 重编译来源、参数与哈希记录见 MetalBuild.json。
