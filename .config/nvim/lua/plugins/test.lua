--[[
===========================================================================================
[Neotest: 커서 아래 테스트 즉시 실행/디버그]
===========================================================================================
lazyvim.json 의 lazyvim.plugins.extras.test.core 익스트라가 neotest 코어와
<leader>t* 키맵을 이미 제공합니다. 이 파일은 실제 언어별 어댑터(Java/Python)만 연결합니다.

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
  - Python: pytest 러너 고정. 인터프리터는 dap.lua/keymaps.lua의 FastAPI 디버깅 설정과
    동일하게 프로젝트 venv(VIRTUAL_ENV)를 우선 사용하고, 없으면 PATH의 기본 python으로 폴백.
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

  {
    'nvim-neotest/neotest',
    opts = function(_, opts)
      opts.adapters = opts.adapters or {}
      opts.adapters['neotest-java'] = {}
      opts.adapters['neotest-python'] = {
        runner = 'pytest',
        python = function()
          return os.getenv('VIRTUAL_ENV') and (os.getenv('VIRTUAL_ENV') .. '/bin/python') or 'python'
        end,
      }
      return opts
    end,
  },
}
