# embed+extract+exec パターンの実現可能性調査 (2026-03-16)

kuu-cli バイナリを各言語パッケージに embed し、サブプロセスで JSON プロトコルを介してパースする方式が実用的かを検証。

関連 DR: DR-044

## 検証環境

Ubuntu 24.04 (Docker), kernel 6.18.5, x86_64

## 検証 1: バイナリ embed+extract+exec

`/usr/bin/pwd` (35KB) を embed し、キャッシュディレクトリに展開して exec。

### Go (go:embed)

```go
//go:embed bin/*
var binFS embed.FS

data, _ := binFS.ReadFile("bin/embedded-cmd-linux-amd64")
// → ~/.cache/ に展開 → exec.Command(path).Output()
```

結果: **OK**。embed → extract → exec → cache hit 全て正常動作。

### Rust (include_bytes!)

```rust
const EMBEDDED_CMD: &[u8] = include_bytes!("../bin/embedded-cmd-linux-amd64");
// → ~/.cache/ に展開 → Command::new(path).output()
```

結果: **OK**。同上。

PoC: `examples/20260316-embed-go/`, `examples/20260316-embed-rust/`

## 検証 2: memfd_create (Linux)

ディスクに書かずにメモリ上で exec。

```python
fd = libc.memfd_create(b'test-exec', 0)
os.write(fd, open('/usr/bin/pwd', 'rb').read())
subprocess.run([f'/proc/self/fd/{fd}'], pass_fds=(fd,))
```

結果: **OK**。Docker コンテナ内でもディスク不要で実行可能。

### memfd_create の対応状況

| 環境 | 対応 | 備考 |
|------|------|------|
| Linux kernel 3.17+ (2014〜) | OK | ほぼ全現行ディストロ |
| Docker (デフォルト seccomp) | OK | 許可リストに含まれる |
| Kubernetes Pod | OK | Docker/containerd と同等 |
| AWS Lambda | OK | kernel 4.14+ ベース |
| read-only rootfs コンテナ | OK | ディスク不要なので最適 |
| gVisor (GKE sandbox) | OK | 実装済み |
| seccomp で明示ブロック | NG | 意図的強化のみ |
| macOS / Windows | なし | Linux 固有 syscall |

## 調査 3: OS ごとのセキュリティ制約

### 自プロセス書き出しと検疫マーク

| OS | DL ファイル | 自プロセスが書いたファイル |
|----|------------|------------------------|
| macOS | quarantine xattr → Gatekeeper 検査 | **付かない** |
| Windows | Zone.Identifier → SmartScreen 検査 | **付かない** |
| Linux | 制約なし | 制約なし |

embed+extract は自プロセスが書き出すため、ダウンロード検疫の対象にならない。

### macOS 固有

- Developer Program ($99/年) + コード署名 + notarization で Gatekeeper クリア
- 署名+公証済みバイナリを embed すれば、展開後そのまま実行可能
- CI で `codesign` + `xcrun notarytool submit --wait` + `xcrun stapler staple` を回すだけ

### Windows 固有

- Authenticode 証明書 ($200〜400/年) でコード署名
- 自プロセス書き出しなら署名なしでも SmartScreen は発動しない
- ウイルス対策のヒューリスティクスに引っかかる可能性はある（署名で回避）

### Linux 固有の制約

| 制約 | 影響 | 対策 |
|------|------|------|
| noexec マウント (/tmp 等) | extract 先が exec 不可 | ~/.cache/ や $XDG_RUNTIME_DIR にフォールバック |
| SELinux | ユーザー書き込みファイルの exec 制限 | memfd_create で回避 |
| AppArmor | プロファイルで実行パス制限 | 通常は ~/.cache は許可される |

## バイナリサイズ参考値

| バイナリ | サイズ |
|---------|--------|
| coreutils (pwd, cat 等) | 26〜138 KB |
| kuu WASM (wasm-gc) | 37 KB (core のみ), 96 KB (bridge 込み) |
| kuu-cli native (推定) | 数百 KB〜1 MB |

## 結論

- **embed+extract+exec は全主要 OS で実用的**
- Linux は memfd_create でディスク不要の完全隠蔽が可能
- macOS/Windows は署名で対応、自プロセス書き出しなら検疫マーク自体が付かない
- noexec やコンテナ制約も回避策がある
- バイナリサイズは coreutils と同オーダーで embed しても許容範囲
