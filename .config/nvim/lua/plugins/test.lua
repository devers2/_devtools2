--[[
===========================================================================================
[Neotest: 커서 아래 테스트 즉시 실행/디버그]
===========================================================================================
lazyvim.json 의 lazyvim.plugins.extras.test.core 익스트라가 neotest 코어와
<leader>t* 키맵을 이미 제공합니다. 이 파일은 실제 언어별 어댑터(Java/Python/JS·TS)만 연결합니다.

[의존성 정리 — 이미 다 갖춰져 있어서 추가로 설치할 것은 없습니다]
  1. nvim-nio        : neotest 코어의 필수 의존성. test.core 익스트라 자체가 선언하고 있어
                        다음 실행 시 lazy.nvim이 자동으로 새로 설치합니다(직접 추가 불필요).
  2. plenary.nvim     : 이미 이 config에 설치되어 있음(다른 플러그인이 이미 끌어옴).
  3. treesitter 파서  : java/python 파서 모두 treesitter.lua에 이미 등록되어 있음.
  4. nvim-jdtls, nvim-dap : 이미 java.lua/dap.lua에서 사용 중인 것을 그대로 재사용.

[의도적으로 넣지 않은 것]
  - antoinemadec/FixCursorHold.nvim : neotest 공식 README가 "권장"하는 선택 항목이지만
    (CursorHold 이벤트 폴링 부하 완화용, 구버전 neotest 대상 권장 사항), LazyVim 공식
    test.core 익스트라 자체도 이 플러그인을 넣지 않습니다. 최신 Neovim/neotest 조합에서는
    필수가 아니라고 판단해 이 config도 동일하게 생략합니다. 만약 상태 표시(가상 텍스트)
    갱신이 느리게 느껴지면 그때 추가를 검토하면 됩니다.
  - nvim-dap-ui, nvim-dap-virtual-text : neotest-java 예제에 자주 같이 나오지만 공식
    Requirements에는 없는 "흔한 동반 플러그인"일 뿐입니다. 이 config는 dap-ui 대신
    nvim-dap-view를 쓰고 있으므로(dap.lua 참고) 넣지 않았고, <leader>td(Debug Nearest)는
    기존 nvim-dap-view 화면 그대로 뜹니다.

[:checkhealth 경고 — 정상, 무시해도 됨]
  :checkhealth neotest-java 실행 시 아래 2개가 뜨는데 둘 다 실제 동작엔 문제없습니다.
  - "ERROR Plugin 'dapui' is missing": neotest-java의 health.lua가 rcarriga/nvim-dap-ui
    설치 여부를 하드코딩으로 검사합니다(다른 DAP UI를 쓸 가능성은 아예 고려 안 함).
    실제 디버그 실행 코드(init.lua)는 require("dapui")를 어디서도 호출하지 않고, DAP 설정
    테이블만 만들어서 nvim-dap에 넘길 뿐입니다 — 화면 표시는 dap.lua에 이미 등록된
    dap.listeners.after.event_initialized 리스너가 담당하며, 이 config는 dapui 대신
    nvim-dap-view를 쓰고 있으므로 <leader>td(Debug Nearest)도 기존 dap-view 화면 그대로
    정상 동작합니다. dapui를 설치할 필요 없습니다(설치해도 enabled=false라 로드조차 안 됨).
  - "WARNING Make sure Tree-sitter parser for 'java' is up-to-date": 일상적인 안내일 뿐이고
    신경 쓰이면 :TSUpdate java 한 번이면 사라집니다.

[사용 전 필수: 최초 1회 수동 설정]
  :NeotestJava setup
  → JUnit Platform Console Standalone jar를 Maven Central에서 SHA-256 체크섬 검증 후
    다운로드합니다(Mason이 아닌 neotest-java 자체 명령). 최초 1회만 실행하면 됩니다.
    (:MasonInstall 대상이 아니므로 Mason UI에는 나타나지 않습니다.)

[키맵 사용법] (whichkey.lua에 한글 설명 등록됨, <leader>t 로 시작)
  <leader>tt : 현재 파일의 테스트 전부 실행
  <leader>tr : 커서가 위치한 가장 가까운 테스트(메서드/함수) 하나만 실행
  <leader>tT : 프로젝트(cwd) 전체 테스트 파일 실행
  <leader>tl : 마지막에 실행한 테스트 재실행
  <leader>ts : 테스트 트리 요약 패널 토글 (전체 테스트 목록 + 통과/실패 상태)
  <leader>to : 커서 위치 테스트의 출력(콘솔 로그) 보기
  <leader>tO : 출력 패널 토글(계속 열어두고 보기)
  <leader>tS : 실행 중인 테스트 중지
  <leader>tw : 감시 모드 토글 — 파일 저장할 때마다 해당 테스트 자동 재실행
  <leader>ta : 이미 실행 중인 테스트 프로세스에 연결(attach)
  <leader>td : 커서가 위치한 가장 가까운 테스트를 DAP로 디버그 실행(브레이크포인트 정지)

[동작 방식]
  - Java: 클래스명이 test_classname_patterns(기본값 XxxTest/XxxTests/XxxIT/XxxSpec)에
    맞아야 인식됩니다. Gradle/Maven, 멀티모듈 프로젝트 자동 감지.
  - Python: pytest 러너 고정. 인터프리터는 neotest-python 기본 탐색을 그대로 사용
    (VIRTUAL_ENV → 프로젝트 .venv/venv → pipenv/poetry → uv → python3).
  - JS/TS: Vitest(neotest-vitest)와 Jest(neotest-jest)를 함께 등록합니다. 두 어댑터 모두 프로젝트의
    package.json 의존성(vitest / jest)을 보고 자기 프로젝트인지 판단하므로 한 프로젝트에 겹치지 않습니다.
    실행 명령은 프로젝트의 node_modules/.bin 을 자동으로 찾으므로(없으면 npx), 프로젝트에서 npm install 만
    되어 있으면 됩니다. 테스트 파일: *.test.ts / *.spec.ts (js·jsx·tsx 포함), __tests__/ 폴더.
===========================================================================================
--]]
return {
  -- [Java] neotest-java (자세한 설명은 상단 doc 참고)
  {
    'rcasia/neotest-java',
    ft = 'java',
    dependencies = {
      'mfussenegger/nvim-jdtls',
      'mfussenegger/nvim-dap',
    },
  },

  -- [Python] neotest-python (자세한 설명은 상단 doc 참고)
  { 'nvim-neotest/neotest-python', lazy = true },

  -- [JS/TS] Vitest · Jest (자세한 설명은 상단 doc 참고)
  { 'marilari88/neotest-vitest', lazy = true },
  { 'nvim-neotest/neotest-jest', lazy = true },

  {
    'nvim-neotest/neotest',
    opts = function(_, opts)
      opts.adapters = opts.adapters or {}
      -- [neotest-java 를 Java 프로젝트 파일로 한정]
      -- neotest-java 는 파일 이름이 테스트 클래스 패턴(…Test/…Tests/…IT/…Spec)에 맞으면 확장자와 무관하게
      -- 테스트 파일로 보고, node_modules 도 건너뛰지 않습니다. 그래서 JS/TS 프로젝트에서 node_modules 안의
      -- "LICENSE-MIT.txt"(…IT) 같은 파일까지 열어 보다 오류를 내고(neotest.log), 탐색 시간도 낭비했습니다(실측).
      -- 원래 어댑터를 복사해 .java 파일만, node_modules·.git 등은 건너뛰도록 감싸 숫자 키로 등록합니다
      -- (LazyVim test.core 는 숫자 키의 값을 어댑터 객체로 그대로 씁니다).
      local ok_java, java = pcall(require, 'neotest-java')
      if ok_java and type(java) == 'table' then
        local wrapped = {}
        for k, v in pairs(java) do
          wrapped[k] = v
        end
        local orig_filter, orig_is_test = java.filter_dir, java.is_test_file
        local skip_dirs = { node_modules = true, ['.git'] = true, dist = true, ['.venv'] = true, venv = true }
        wrapped.filter_dir = function(name, rel_path, root)
          if skip_dirs[name] then
            return false
          end
          return orig_filter == nil or orig_filter(name, rel_path, root)
        end
        wrapped.is_test_file = function(file_path)
          return type(file_path) == 'string' and file_path:match('%.java$') ~= nil and orig_is_test(file_path)
        end
        table.insert(opts.adapters, wrapped)
      else
        opts.adapters['neotest-java'] = {}
      end
      -- python 인터프리터는 지정하지 않습니다: neotest-python 기본 탐색이
      -- VIRTUAL_ENV → 프로젝트 .venv/venv → pipenv/poetry → uv → python3 순으로 찾아 줍니다.
      -- (VIRTUAL_ENV 만 보고 'python' 으로 폴백하면, venv 를 활성화하지 않고 nvim 을 연 경우
      --  프로젝트 .venv 의 pytest 를 못 찾고, python 명령이 없는 Ubuntu 에서는 실행 자체가 실패함)
      opts.adapters['neotest-python'] = {
        runner = 'pytest',
      }
      -- JS/TS: 기본값 그대로 (실행 명령·설정 파일·테스트 파일 판별을 각 어댑터가 프로젝트에서 자동 탐색)
      opts.adapters['neotest-vitest'] = {}
      opts.adapters['neotest-jest'] = {}
      return opts
    end,
  },
}
