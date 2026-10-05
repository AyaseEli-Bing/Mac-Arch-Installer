## 关联 issue

<!-- 例：Closes #12 / Refs #12。行为类改动若无对应 issue，请先开一条。 -->

## 改了什么

<!-- 具体文件与函数，不要写"优化了脚本"。 -->

## 为什么

<!-- 根因；试过但放弃的方案也写一句。 -->

## 验证

```bash
# 贴你实际跑过的命令与结果；无法跑的部分明确说明（见 CONTRIBUTING「没有 Parallels 时怎么自证」）
for f in arch-install/*.sh; do bash -n "$f" || exit 1; done
shellcheck -S warning arch-install/*.sh
npx markdownlint-cli2 "*.md"
```

- [ ] 语法与 shellcheck 通过
- [ ] 改了 Markdown → markdownlint 通过
- [ ] 宿主机侧兼容 bash 3.2（未用 4.x 语法）
- [ ] 文档同步：中英 README 结构对应，涉及的参数/组数/条目数已更新
- [ ] 未把破坏性命令的 stderr 丢进 `/dev/null`
- [ ] 实机验证情况已如实说明（跑了什么 / 因条件所限没跑什么）

## AI 辅助说明

<!-- 若改动由 AI 生成或改写，请一句话说明，并写清你如何核对。如实披露即可，不会因此被拒。 -->
