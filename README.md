# playground-layat

[layat](https://github.com/yasunori0418/layat) で agent skill を管理する検証用リポジトリ。

## Prerequisites

- [Nix](https://nixos.org/)（`experimental-features = nix-command flakes`）
- [direnv](https://direnv.net/)（任意）

## Setup

```bash
direnv allow   # または: nix develop
```

devShell に入ると、次の2つが自動で実行される。
- `layat apply skills`: スキルを `.agents/skills/layat-<name>` に配置する（`.claude/skills` から参照される）
- `lefthook install`: pre-commit hook（gitleaks によるシークレットスキャン）を登録する

## Skills

- 配布元: `github:Hol1kgmg/SKILL` の `skills/*` を全件配置する（`flake.nix` の `skills` input）
- 配置物は Nix store への symlink で、`.agents/skills/.gitignore`（`layat-*`）により git の管理外になる
- 更新: `nix flake update skills`（次に shell へ入ったときに再配置される）
