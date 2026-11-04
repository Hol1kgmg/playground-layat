# layat agent skills 検証レポート

- 検証日: 2026-11-04
- 環境: Nix 2.34.9 / layat 0.1.0 / direnv / macOS / Claude Code
- 参考: <https://github.com/yasunori0418/layat>
- 比較対象: [playground-pnpm-skills](https://github.com/Hol1kgmg/playground-pnpm-skills)（pnpm agent skills）

## 結論

**layat を使うと、mise.toml の代わりに flake.nix だけで、GitHub リポジトリ上の agent skill を rev 単位で固定して受け取り、devShell 進入時に自動配置できる。**

- スキルは flake input（`flake = false`）として取得し、`flake.lock` で rev を固定する
- `direnv allow`（または `nix develop`）だけで、ロックされた rev のスキルがエージェント用ディレクトリに symlink される
- 依存の一つとして扱われるため、Dependabot（`nix` ecosystem）などで `flake.lock` の更新を PR 化できる見込み

pnpm skills と違い、**配布側に npm publish や `files` 指定などの要件はない**。`skills/<name>/SKILL.md` を持つ任意の Git リポジトリをそのまま取得できる。

## 仕組み

```
[配布側]                          [利用側]
github:Hol1kgmg/SKILL             flake.nix   ← input 宣言 + mkManifest で配置先を定義
└── skills/<name>/SKILL.md  ──▶   flake.lock  ← rev を固定
        (git push のみ)                │ direnv / nix develop
                                       ▼ shellHook: layat apply skills
                                 .agents/skills/layat-<name>  (symlink → /nix/store/...)
                                       ▲
                                 Dependabot が flake.lock 更新を PR 化
```

| pnpm skills | layat |
|---|---|
| `package.json` で依存宣言 | `flake.nix` の `inputs.skills`（`flake = false`） |
| `pnpm-lock.yaml` でバージョン固定 | `flake.lock` で rev 固定 |
| `pnpm install` でリンク | `layat apply skills`（devShell の `shellHook`） |
| `permissions.<pkg>.skills` で承認 | なし（`flake.nix` に書いた entry だけが配置される） |
| `.gitignore`（`pnpm-*`）を自動生成 | 手動で作成（`layat-*`）。`layat gitignore skills` で対象を一覧できる |
| リンク先は `node_modules/.pnpm/...` | リンク先は `/nix/store/...`（read-only） |
| mise でツール管理 | 同じ devShell で `gitleaks` / `lefthook` / `jq` も提供 |

## 検証結果

| 項目 | 内容 | 検証 |
|---|---|---|
| rev 単位での導入 | `flake.nix` に input を追加 → `nix flake lock` | ✅ |
| 全スキルの自動列挙 | `builtins.readDir "${skills}/skills"` からエントリを生成 | ✅ |
| shell 進入時の自動配置 | `shellHook` の `layat apply skills --no-wait` | ✅ |
| direnv 連携 | `.envrc` に `use flake` | ✅ |
| エージェントからの認識 | Claude Code が `layat-dependabot-review` / `layat-speckit-explain` を認識 | ✅ |
| リンクの Git 除外 | `.agents/skills/.gitignore`（`layat-*`）を手動作成 | ✅ |
| 配置状態の確認 | `layat status skills` で target / method / store パスを表示 | ✅ |
| rev 固定 | `flake.lock` の `nodes.skills.locked.rev` | ✅ |
| mise の置き換え | `mise.toml` を削除し、lefthook / gitleaks を devShell から提供 | ✅ |
| Dependabot による自動更新 PR | `package-ecosystem: nix` で `flake.lock` を更新 | ⚠️ 未検証 |

### 導入手順（実施内容）

```nix
# flake.nix（抜粋）
inputs.skills = { url = "github:Hol1kgmg/SKILL"; flake = false; };

layat = forAllSystems (system: {
  skills = layat.lib.mkManifest {
    pkgs = nixpkgs.legacyPackages.${system};
    root = layat.lib.projectRoot;
    entries = nixpkgs.lib.genAttrs' skillNames (name:
      nixpkgs.lib.nameValuePair ".agents/skills/layat-${name}" { src = skills; subpath = "skills/${name}"; });
  };
});

devShells = forAllSystems (system: { default = pkgs.mkShell {
  packages = [ pkgs.gitleaks pkgs.lefthook pkgs.jq layat.packages.${system}.layat ];
  shellHook = ''
    layat apply skills --no-wait
    lefthook install >/dev/null
  '';
}; });
```

```bash
nix flake lock
direnv allow   # または: nix develop
# => layat: no last-applied record; starting from an empty baseline
```

結果:

```
.agents/skills/
├── .gitignore                 # layat-*（手動作成）
├── layat-dependabot-review -> /nix/store/...-source/skills/dependabot-review
└── layat-speckit-explain   -> /nix/store/...-source/skills/speckit-explain
```

`layat status skills`:

```
# project:skills@/path/to/playground-layat (applied 2026-11-04T23:12:55+09:00)
.agents/skills/layat-dependabot-review  symlink  /nix/store/...-source/skills/dependabot-review
.agents/skills/layat-speckit-explain    symlink  /nix/store/...-source/skills/speckit-explain
```

### 更新

```bash
nix flake update skills   # flake.lock の rev を最新へ
# 次に shell へ入ると（direnv なら flake.lock 変更を検知して）再配置される
```

`use flake` は `flake.nix` / `flake.lock` を監視するため、pnpm 版で必要だった `watch_file` の追記は不要。

```
Dependabot PR マージ → git pull → (direnv が flake.lock 変更を検知) → layat apply → スキル更新
```

### 自動更新の構成例（Dependabot）

```yaml
# .github/dependabot.yml
version: 2
updates:
  - package-ecosystem: "nix"
    directory: "/"
    schedule:
      interval: "weekly"
```

`flake = false` の input にはバージョン番号がないため、更新 PR では SKILL.md やスクリプトの内容差分が実質的なレビューポイントになる（配布側の `dependabot-review` スキルがこの手順を持つ）。

## 制約

| 項目 | 内容 |
|---|---|
| 前提ツール | Nix（`nix-command flakes` の有効化）が必須 |
| ステータス | layat は MVP。API が変わりうる |
| Git 管理 | flake は Git 管理下のファイルしか見ないため、`flake.nix` は最低でも `git add -N` が必要 |
| `.gitignore` | pnpm と違い自動生成されない。`layat gitignore skills` は個別パス（`/.agents/...`）を出力する |
| 承認 | pnpm の `permissions` に相当する仕組みはない。`flake.nix` への記述そのものが承認になる |
| `nix flake check` | `unknown flake output 'layat'` の warning が出る（exit 0、想定どおり） |

## 運用上の注意

- **全件列挙**: `readDir` で配布元の `skills/*` をすべて配置するため、配布元にスキルが追加されると更新時に自動で増える。絞り込みたい場合は名前のリストに置き換える。
- **自動更新しない**: shell 進入時に行うのは「ロックされた rev の再配置」であり、配布元の最新を取りに行くわけではない。更新は `nix flake update skills` か Dependabot で明示的に行う。
- **read-only**: 配置物は Nix store への symlink のため、その場で編集できない。編集したい場合は `method = "copy"` か `mkOutOfStoreSymlink` を使う。
- **シンボリックリンク構成**: 本リポジトリでは `.claude/skills -> ../.agents/skills` のため、リンクは 1 箇所にのみ作成される。

## スキル配布側の要件

```
my-skills/
└── skills/
    └── <name>/
        └── SKILL.md
```

Git リポジトリに push するだけでよい（npm publish、`package.json` は不要）。リンク名は利用側の `flake.nix` で自由に決められる（本リポジトリでは `layat-<skill>`）。

## 未検証事項

- Dependabot（`nix` ecosystem）による `flake = false` input の更新 PR 作成
- home-manager モジュール / home mode（`~/.claude/skills` へのグローバル配置）
- 複数の配布元リポジトリの併用
- `mkApplyCommand` による shell 進入時の eval 省略
- 別環境（CI、Linux）での再現
