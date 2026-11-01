# 에이전트 스킬 (Claude · Codex · Antigravity 공용)

스킬 원본은 `skills/<스킬 이름>/SKILL.md` 한 곳에만 두고, 설치된 AI 에이전트의 스킬 폴더에는 스킬마다 링크만 겁니다.
다른 PC 에서는 `git pull` 후 새 셸을 열면 링크가 자동으로 맞춰집니다.

| 에이전트 | 연결되는 위치 |
|---|---|
| Claude | `~/.claude/skills/<스킬>` |
| Codex | `~/.agents/skills/<스킬>` |
| Antigravity | `~/.gemini/config/skills/<스킬>` |

## 스킬 추가

- **직접 작성**: `skills/<이름>/SKILL.md` 를 만들고 커밋합니다.
  여러 에이전트에서 쓰려면 앞부분(frontmatter)에는 `name` 과 `description` 만 씁니다.

  ```markdown
  ---
  name: gradle-release
  description: Maven Central 배포 절차. 배포·릴리스 요청 시 사용
  ---
  (절차, 주의사항. 필요하면 같은 폴더에 스크립트)
  ```

- **가져오기**: Orca 공유 링크 등으로 에이전트 폴더에 설치된 스킬은 `Alt+C ▸ 🤖 AI 에이전트 ▸ 스킬 가져오기`
  (또는 `agent-skills.sh import`)로 저장소에 옮깁니다. 원본은 `~/.devtools2/skill-backups/` 에 백업됩니다.

## 특정 에이전트에서 빼기

`skills/targets.conf` 에 `스킬 = claude, codex` 처럼 적습니다. 적지 않은 스킬은 모든 에이전트에 연결됩니다.

## 주의

- 이 저장소는 공개 저장소입니다. 다른 사람이 만든 스킬은 허락·라이선스를 확인하고 올리세요.
- 스킬 안의 스크립트·명령은 에이전트가 실행할 수 있으니 내용을 확인한 뒤 넣으세요.
- 같은 이름의 다른 스킬이 에이전트 폴더에 이미 있으면 덮어쓰지 않고 알려 줍니다.
- 명령: `agent-skills.sh sync` (링크 맞추기) · `status` (상태) · `import` (가져오기)
