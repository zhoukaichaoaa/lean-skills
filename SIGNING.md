# 签名、验证与发布资产

## 标签签名公钥

自 v0.13.0 起每个 tag 都用 SSH 密钥签名。公钥：

```
ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIKNd64ry22PkWE8tRnKU2dkZLbLBIajmjXApqFZOgcUq
```

指纹：`SHA256:0bkNGhHTaSlkX4v/BKjWihqa+0xKa5+GV0Cx4+vqyUk`

## 验证一个标签

把公钥写成 `allowed_signers`，然后验：

```bash
cat > allowed_signers <<'EOF'
109027172+zhoukaichaoaa@users.noreply.github.com ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIKNd64ry22PkWE8tRnKU2dkZLbLBIajmjXApqFZOgcUq
EOF

git -c gpg.ssh.allowedSignersFile=allowed_signers tag -v v0.17.0
```

应输出：

```
Good "git" signature for 109027172+zhoukaichaoaa@users.noreply.github.com with ED25519 key SHA256:0bkNGhHTaSlkX4v/BKjWihqa+0xKa5+GV0Cx4+vqyUk
```

这行走的是 **stderr**，标签对象本身走 stdout —— 如果你把输出重定向到文件却没看到它，多半是只接了 stdout。退出码 0 才是通过。

## 这个签名能证明什么、不能证明什么

**能**：所有 tag 出自同一把私钥，且打上之后没被改过。任何人拿上面的公钥都能独立核验。

**不能**：把这把密钥绑定到某个 GitHub 账号身份。它目前只登记为**仓库级 deploy key**，没有登记为账号级 signing key。后果是具体的：

- GitHub 网页上 tag **不会**显示 Verified 徽章；
- `GET /users/zhoukaichaoaa/ssh_signing_keys` 返回空数组，第三方无法通过 API 把公钥和账号对上；
- 因此"这把密钥属于谁"目前**只有本文件这一个声明来源**，而本文件和密钥在同一个仓库里 —— 拿到写权限的人可以同时改两者。这不是可信的身份绑定，只是可信的**一致性**证明。

要取得可被第三方独立核验的身份绑定，仓库所有者需要在 GitHub 账号的
Settings → SSH and GPG keys 里，把同一把公钥**额外**登记为 **Signing Key**（类型选 Signing，不是 Authentication）。登记之后上面那条 API 会返回它，Verified 徽章也会出现。在那之前，请按上一段的限度理解这些签名。

## 标签不可变

tag 一经推送不再移动，任何修复都走新版本号。v0.9.0 的标签曾被移动过一次，那是错误做法，已记在 CHANGELOG 里。

## 发布资产的哈希

**本项目不再公布 GitHub 自动生成的 codeload 压缩包（`.tar.gz` / `.zip`）的 SHA-256。**

那些包由 GitHub 在请求时实时打包，压缩实现、压缩级别与内部时间戳都不属于稳定接口，同一个 tag 在不同时间、不同边缘节点取到的字节可以不同。第三方用 `git archive` 也复现不出同样的字节。写一个这样的哈希进发布说明，读者要么核不出来，要么核不对时无法判断是被篡改还是 GitHub 换了打包参数 —— 它提供的是安全感，不是安全。

可复现、可独立核对的交付标识是 git 对象哈希，由对象模型本身保证：

```bash
git rev-parse v0.17.0            # tag 对象
git rev-parse v0.17.0^{commit}   # commit
git rev-parse v0.17.0^{tree}     # tree（内容的规范标识）
```

要固定一份逐字节可复现的归档，用 `git archive` 并把参数写全（各方必须用同一组参数才会得到同一份字节）：

```bash
git archive --format=tar --prefix=lean-skills-0.17.0/ v0.17.0 \
  | gzip -n -9 > lean-skills-0.17.0.tar.gz
sha256sum lean-skills-0.17.0.tar.gz
```

`-n` 让 gzip 不写入时间戳，是可复现的关键；漏掉它，同一棵树每次打出的哈希都不同。
