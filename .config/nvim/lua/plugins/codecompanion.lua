--[[
===========================================================================================
[CodeCompanion.nvim: Neovim 안의 AI 채팅/인라인 어시스턴트]
===========================================================================================
avante.nvim 대신 CodeCompanion 선택 — Neovim 버퍼/LSP에 더 자연스럽게 녹아드는 방식.

[어댑터 두 종류]
  1. HTTP 어댑터(anthropic/openai/gemini/copilot 등): API를 직접 호출. 가볍고 빠름.
  2. ACP 어댑터(claude_code/codex/gemini_cli/opencode/goose): 실제 CLI 에이전트를
     서브프로세스로 띄워서 그 안의 도구 사용/컨텍스트 관리 능력까지 가져옴.
  아래는 요청하신 대로 ACP 어댑터 5종으로 구성했습니다.

[성능 — 다섯 개 다 미리 등록해놔도 괜찮은 이유]
  전부 "팩토리 함수"로만 등록됩니다(즉시 실행 안 됨, Lua 클로저 하나 만드는 정도의 비용).
  실제로 CLI 서브프로세스가 뜨는 건 :CodeCompanionChat 등에서 그 어댑터를 골라 대화를
  시작하는 순간뿐입니다. 등록만 해두고 안 쓰면 메모리/CPU 비용이 사실상 0입니다.
  구독/키 상태에 따라 지금 당장 다 못 써도 상관없습니다 — env 값은 그 어댑터가 실제로 로드되는
  시점에 읽히므로, 나중에 키가 생기면 env만 채우면 되고 구조를 다시 짤 필요가 없습니다.
  다만 여러 어댑터로 채팅 버퍼를 "동시에" 여러 개 열어두면 그만큼 서브프로세스가 늘어나니,
  안 쓰는 채팅 버퍼는 닫아두는 게 좋습니다(등록 개수가 아니라 "동시에 연 채팅 개수"가 비용).

[API 키 자동 탐색] 아래 env 블록을 통째로 비워도 됩니다 — CodeCompanion 기본 동작이 셸
환경변수에서 "<어댑터이름>_API_KEY" 패턴을 자동으로 찾습니다(ANTHROPIC_API_KEY 등). 이미 셸에
export 해뒀다면 아무것도 안 적어도 되고, 굳이 명시하고 싶을 때만 env 블록을 채우면 됩니다.

[사전 준비물 — 각 CLI 바이너리가 PATH에 있어야 함]
  - Claude Code : npm i -g @anthropic-ai/claude-code
  - Codex       : codex-acp 바이너리 필요 (OpenAI Codex CLI의 ACP 브릿지, 별도 설치)
  - Gemini CLI  : npm i -g @google/gemini-cli
  - OpenCode    : opencode.ai 설치 스크립트 — 인증은 CodeCompanion의 env가 아니라
                  OpenCode 자체 CLI(`opencode auth login`)로 하고, 모델 지정은
                  ~/.config/opencode/config.json 에서 함(공식 문서에 env 방식 없음).
  - Goose       : Block의 Goose CLI 설치 — 인증도 Goose 자체 설정(`goose configure`)으로 함.
  설치 후 :checkhealth codecompanion 으로 각 바이너리 인식 여부 확인 가능.

[의존성] plenary.nvim, nvim-treesitter 둘 다 이미 이 config에 설치되어 있어 추가 설치 없음.

[여러 ACP를 동시에 쓸 수 있냐는 질문 — Orca처럼]
  가능한 부분과 안 되는 부분이 나뉩니다.
  - 가능: 채팅 버퍼를 여러 개 열어서 각각 다른 에이전트를 붙일 수 있습니다
    (:CodeCompanionChat adapter=claude_code, :CodeCompanionChat adapter=goose 등을
    따로따로 실행 — 아래 <leader>ag 하위 키맵으로 바로 가능).
  - 안 됨: Orca는 각 에이전트를 별도 Git worktree에 격리해서 동시에 같은 작업을 시키고,
    파일 충돌을 자동으로 감지/조정하고, 에이전트끼리 컨텍스트를 주고받게 하는 "여러 에이전트
    함대(fleet) 오케스트레이션 도구"입니다(Neovim 플러그인이 아니라 별도 터미널 앱). CodeCompanion은
    "한 Neovim 세션 안에서 여러 채팅 버퍼를 각자 따로 관리"하는 수준이지, worktree 격리나
    충돌 자동 조정, 에이전트 간 핸드오프 같은 오케스트레이션 계층은 없습니다.
  진짜 Orca 같은 병렬 오케스트레이션이 필요하시면 그건 CodeCompanion과 별개로 Orca 자체를
  터미널 앱으로 설치하는 쪽이 맞습니다(원하시면 별도로 도와드릴 수 있음 — 지금은 안 건드렸습니다).
===========================================================================================
--]]
return {
  {
    'olimorris/codecompanion.nvim',
    -- [성능] 이 config의 다른 커스텀 플러그인과 동일한 원칙: 명령을 실제로 쓸 때만 로드.
    cmd = {
      'CodeCompanion',
      'CodeCompanionChat',
      'CodeCompanionCLI',
      'CodeCompanionCmd',
      'CodeCompanionActions',
      'CodeCompanionCodeReview',
    },
    dependencies = {
      'nvim-lua/plenary.nvim',
      'nvim-treesitter/nvim-treesitter',
    },
    opts = {
      adapters = {
        acp = {
          -- [Claude Code] 말씀하신 대로 구독 OAuth가 아니라 API 키 방식.
          -- 셸에 ANTHROPIC_API_KEY가 이미 있다면 아래 claude_code 블록 전체를 지워도
          -- 'claude_code' 라는 이름 자체는 CodeCompanion에 내장돼 있어 그대로 동작합니다.
          claude_code = function()
            return require('codecompanion.adapters').extend('claude_code', {
              env = {
                ANTHROPIC_API_KEY = os.getenv('ANTHROPIC_API_KEY'),
                -- Bitwarden 등 별도 저장소에서 읽고 싶다면 예:
                -- ANTHROPIC_API_KEY = 'cmd:bw get password Anthropic_API_Key',
              },
            })
          end,

          -- [Codex] OpenAI Codex CLI 브릿지. codex-acp 바이너리가 PATH에 있어야 함.
          codex = function()
            return require('codecompanion.adapters').extend('codex', {
              defaults = { auth_method = 'api-key' }, -- 'chat-gpt' 로 바꾸면 ChatGPT 로그인 방식
              env = {
                OPENAI_API_KEY = os.getenv('OPENAI_API_KEY'),
              },
            })
          end,

          -- [Gemini] Google Gemini CLI.
          gemini_cli = function()
            return require('codecompanion.adapters').extend('gemini_cli', {
              defaults = { auth_method = 'gemini-api-key' }, -- 'oauth-personal'/'vertex-ai' 도 가능
              env = {
                GEMINI_API_KEY = os.getenv('GEMINI_API_KEY'),
              },
            })
          end,

          -- [OpenCode] 인증/모델 설정은 CodeCompanion이 아니라 OpenCode 자체 CLI/설정 파일 몫이라
          -- env 블록이 없습니다(공식 문서에도 opencode용 env 예시가 없음).
          opencode = function()
            return require('codecompanion.adapters').extend('opencode', {})
          end,

          -- [Goose] 마찬가지로 인증은 `goose configure`로 별도 처리.
          goose = function()
            return require('codecompanion.adapters').extend('goose', {})
          end,
        },
      },
      -- ⚠️ CodeCompanion의 인라인 편집(interactions.inline)은 ACP 어댑터를 지원하지 않고
      -- HTTP 어댑터만 지원합니다(공식 문서 확인) — claude_code/codex 등은 ACP라서 inline에
      -- 쓰면 동작하지 않습니다. 그래서 inline만 내장 HTTP 어댑터 'anthropic'을 씁니다
      -- (별도 등록 없이 기본으로 ANTHROPIC_API_KEY를 자동 인식하므로 위 claude_code와
      -- 같은 키를 그대로 재사용). chat은 ACP를 그대로 씁니다.
      -- 채팅 어댑터만 바꾸고 싶으면 chat.adapter 문자열만 교체하면 됨(예: 'codex'/'gemini_cli').
      interactions = {
        chat = { adapter = 'claude_code' },
        inline = { adapter = 'anthropic' },
      },
    },
    -- keys 자체가 지연 로드 트리거를 겸함(위 cmd 목록과 중복 등록돼도 무해함).
    keys = {
      -- ── 기본 동작 ──
      { '<leader>aa', '<cmd>CodeCompanionActions<cr>', mode = { 'n', 'v' }, desc = '액션 팔레트 (Action Palette)' },
      { '<leader>ac', '<cmd>CodeCompanionChat Toggle<cr>', desc = '채팅 토글 (Toggle Chat)' },
      { '<leader>an', '<cmd>CodeCompanionChat<cr>', desc = '새 채팅 (New Chat)' },
      { '<leader>ai', '<cmd>CodeCompanion<cr>', mode = { 'n', 'v' }, desc = '인라인 편집 (Inline Edit)' },
      { '<leader>av', '<cmd>CodeCompanionChat Add<cr>', mode = 'v', desc = '선택 영역 채팅에 추가 (Add Selection to Chat)' },
      { '<leader>al', '<cmd>CodeCompanionCLI<cr>', desc = 'CLI 상호작용 (CLI Interaction)' },
      { '<leader>am', '<cmd>CodeCompanionCmd<cr>', desc = '커맨드라인 명령 생성 (Generate Command)' },
      { '<leader>ar', '<cmd>CodeCompanionCodeReview<cr>', desc = '코드 리뷰 (Code Review)' },
      -- ── 에이전트 지정 새 채팅 (여러 ACP를 각각 다른 버퍼로 동시에 띄우고 싶을 때) ──
      { '<leader>agc', '<cmd>CodeCompanionChat adapter=claude_code<cr>', desc = 'Claude Code로 채팅' },
      { '<leader>agx', '<cmd>CodeCompanionChat adapter=codex<cr>', desc = 'Codex로 채팅' },
      { '<leader>agg', '<cmd>CodeCompanionChat adapter=gemini_cli<cr>', desc = 'Gemini CLI로 채팅' },
      { '<leader>ago', '<cmd>CodeCompanionChat adapter=opencode<cr>', desc = 'OpenCode로 채팅' },
      { '<leader>ags', '<cmd>CodeCompanionChat adapter=goose<cr>', desc = 'Goose로 채팅' },
    },
  },
}
