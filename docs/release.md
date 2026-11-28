# 发布流程

本项目使用 Fastlane 统一读取 Xcode Release Build Settings 中的版本、构建号、Bundle ID 和 Team 配置，并按用途生成三类 Release。所有产物写入 `.build/releases/<版本>-<构建号>/`，该目录不会进入 Git。

## 环境准备

```bash
bundle install
```

Xcode 当前配置：

- Team：`Q554G4S79A`
- Bundle ID：`com.larryisthere.tagivy`
- 版本：由 Xcode 的 `MARKETING_VERSION` 和 `CURRENT_PROJECT_VERSION` 统一提供
- App Sandbox、用户所选文件只读权限、App-scoped Bookmark 和 Hardened Runtime 保持启用

## 准备正式版本

每个正式发布周期先在干净工作区执行一次：

```bash
bundle exec fastlane mac prepare_release version:1.0.2
```

该 lane 会将 `MARKETING_VERSION` 更新为指定版本，并将 `CURRENT_PROJECT_VERSION` 递增一次，同时同步 Xcode 工程和工程生成脚本。随后更新 `CHANGELOG.md`、完成验收并提交版本改动。GitHub 与 App Store 发布同一版本时共用这个 Build 号；`local_release` 不消耗 Build 号。

账号、API Key、GitHub Token 和公证凭证只保存在本机钥匙串或环境变量中，禁止写入仓库。

## 本地 Release

```bash
bundle exec fastlane mac local_release
```

该 lane 使用 Xcode Automatic Signing 和已配置的 Team，构建 `arm64 + x86_64` Universal App，随后校验版本、构建号、架构、Team、Sandbox、Hardened Runtime 与代码签名，并生成 ZIP 和 SHA-256 文件。

本地 lane 允许 Apple Development 签名，适合当前已配置开发证书的 Mac 使用。Gatekeeper 公开分发、公证和其他用户安装需要下方的 GitHub Release 流程。

## GitHub Release

### 一次性准备

1. 在 Apple Developer 后台创建并安装 `Developer ID Application` 证书。
2. 将 App ID 和所需能力配置完整，让 Xcode 可以取得 Developer ID provisioning profile。
3. 创建 App Store Connect API Key，并保存到本机。
4. 将公证凭证存入钥匙串（本机已存在的配置名为 `FileFacet-Notary`）：

```bash
xcrun notarytool store-credentials "FileFacet-Notary" \
  --key-id "$APP_STORE_CONNECT_KEY_ID" \
  --issuer "$APP_STORE_CONNECT_ISSUER_ID" \
  --key "$APP_STORE_CONNECT_KEY_PATH"
```

5. 使用 `gh auth login` 登录 GitHub，并为仓库配置 remote 或明确提供仓库名。
6. App 内更新用 Sparkle 的 EdDSA 私钥签名。私钥只在发布 Mac 的登录钥匙串里（Sparkle `generate_keys` 生成，对应 `Config/Info.plist` 的 `SUPublicEDKey`），需另行安全备份；丢失后已安装的版本无法再验证新更新。

### 发布

GitHub Release 只通过这个 lane 发布，不再使用手工签名或手工公证脚本。在 main 上、合并版本改动后执行：

```bash
bundle exec fastlane mac github_release
```

默认值：

- 签名身份：自动选取当前 Team 的 `Developer ID Application` 证书，可用 `DEVELOPER_ID_APPLICATION` 覆盖。
- 公证凭证：`FileFacet-Notary`，可用 `NOTARYTOOL_KEYCHAIN_PROFILE` 覆盖。
- 仓库：`larryisthere/Tagivy`，可用 `GITHUB_REPOSITORY` 覆盖。

该 lane 只允许从无未提交改动且当前提交已存在于目标 GitHub 仓库的工作区发布。流程依次为：

1. 检查 `CHANGELOG.md` 已包含目标版本区块。
2. 运行项目不变量检查和全部测试，任何失败都会中止发布。
3. 使用 Manual signing 指定 Developer ID Application 身份，关闭开发调试 entitlement 注入并加入可信时间戳，执行 Release 构建和签名检查。
4. 公证、stapling、生成 ZIP 与 SHA-256。
5. 创建指向当前提交的 `v<版本>` 草稿 Release，上传产物（失败自动重试），全部上传成功后再正式发布。
6. 用 Sparkle 私钥签名安装包，把这一版加入 `appcast` 分支的 `appcast.xml`（App 检查更新读的就是它）。Beta 版进 beta 频道，只有在设置里打开“接收测试版”的用户会收到。

Release 已发布但 appcast 更新失败时，用 `bundle exec fastlane mac appcast_publish`（Beta 加 `beta:<序号>`）重试。

需要覆盖 tag 时可设置 `RELEASE_TAG`。

### Beta 版

给测试者的 Beta 版走同一条签名、公证流程，只是加上 `beta:<序号>`：

```bash
bundle exec fastlane mac github_release beta:1
```

- tag 为 `v<版本>-beta.<序号>`，标题为 `Tagivy <版本> Beta <序号>`，安装包名为 `Tagivy-<版本>-beta.<序号>-<构建号>-macOS-universal.zip`。
- Release 标记为 GitHub Pre-release，不会成为 `releases/latest`，README 的下载链接仍指向正式版。
- App 内的版本号保持纯数字（`MARKETING_VERSION`），`CHANGELOG.md` 同样需要 `## [<版本>]` 区块；可以从功能分支发布，只要提交已推到 GitHub。
- 产物保存在 `.build/releases/<版本>-<构建号>/github-beta.<序号>/`，上传失败后用 `bundle exec fastlane mac github_publish beta:<序号>` 重试。

### 上传失败后重试

公证后的产物保存在 `.build/releases/<版本>-<构建号>/github/`。若第 5 步因网络失败，无需重新构建和公证，直接执行：

```bash
bundle exec fastlane mac github_publish
```

该 lane 会校验产物 SHA-256，复用已有草稿或新建草稿，重新上传并发布；目标版本已正式发布时会拒绝执行。

### 单独运行测试

```bash
bundle exec fastlane mac test
```

如果当前机器尚未配置 `Developer ID Application` 与公证凭证，可以先在 GitHub 创建仅包含发布说明和源码归档的 Release。开发签名的本地 App 不应作为公开安装包上传。

## Mac App Store

### 一次性准备

1. 在 App Store Connect 创建与 Bundle ID 对应的 macOS App。
2. 确认 Apple Distribution 证书和 Mac App Store provisioning profile 可用。
3. 创建具备上传权限的 App Store Connect API Key。

### 上传构建

```bash
export APP_STORE_CONNECT_KEY_ID="..."
export APP_STORE_CONNECT_ISSUER_ID="..."
export APP_STORE_CONNECT_KEY_PATH="/absolute/path/AuthKey_XXXX.p8"
bundle exec fastlane mac app_store_release
```

该 lane 只允许从无未提交改动的工作区发布，生成 App Store Connect `.pkg` 并上传构建，不会自动提交审核，也不会修改商店文案或截图。

## 发布前检查

- `CHANGELOG.md` 已包含目标版本的用户可感知变化。
- Xcode 中的版本与构建号已递增，App Store 构建号未被使用过。
- 全部测试通过（`github_release` 会自动执行并在失败时中止）。
- 本地 Release 已生成并保存 SHA-256。
- GitHub 包通过 `codesign`、`notarytool` 和 `stapler` 校验。
- App Store Connect 构建处理完成后，再在后台选择版本并提交审核。
- 正式发布前在目标 Mac 上完成设备与交互验收。
