-- ===========================================================================================
-- 🛡️ [Orphan Guard - 고아 프로세스 방지 및 터미널 닫힘 즉시 회수 모듈]
-- ===========================================================================================
-- 1. [목적]:
--    WSL/Linux 환경에서 사용자가 Windows Terminal 창(X) 또는 탭을 강제로 닫을 때,
--    터미널에 연결된 부모 TUI(nvim)만 죽고 백엔드 코어(nvim --embed)와 JDTLS/Java 프로세스는
--    systemd(PID 1)로 입양되어 백그라운드에 고아 프로세스로 영구 생존하는 것을 원천 차단합니다.
--
-- 2. [3중 방어 메커니즘]:
--    1) Linux 커널 PR_SET_PDEATHSIG: 부모 프로세스 사망 즉시 커널이 자식에게 SIGTERM 발사
--    2) SIGHUP / SIGTERM 신호 감지: 신호 수신 즉시 모든 LSP 클라이언트를 강제 종료하고 os.exit(0)
--    3) 고아 워치독(Watchdog): 부모 PID == 1 감지 시 vim.schedule 대기 없이 1초 내 직통 os.exit(0)
-- ===========================================================================================

local M = {}

---고아 프로세스 방지 가드 가동
function M.setup()
  local function terminate_immediately()
    -- 1. 모든 LSP 클라이언트(JDTLS 등) 강제 종료 시도
    pcall(function()
      for _, client in ipairs(vim.lsp.get_clients()) do
        pcall(function()
          client:stop(true)
        end)
      end
    end)
    -- 2. 프로세스 즉시 종료 (vim.schedule 대기 없이 OS 레벨 즉사)
    os.exit(0)
  end

  -- A. Linux 커널 PR_SET_PDEATHSIG (부모 프로세스 사망 즉시 커널이 SIGTERM 발사)
  pcall(function()
    if vim.fn.has('linux') == 1 then
      local ffi = require('ffi')
      ffi.cdef[[
        int prctl(int option, unsigned long arg2, unsigned long arg3, unsigned long arg4, unsigned long arg5);
      ]]
      local PR_SET_PDEATHSIG = 1
      local SIGTERM = 15
      ffi.C.prctl(PR_SET_PDEATHSIG, SIGTERM, 0, 0, 0)
    end
  end)

  -- B. SIGHUP 및 SIGTERM 신호 수신 즉시 직통 종료
  pcall(function()
    local sig_hup = vim.uv.new_signal()
    sig_hup:start('sighup', terminate_immediately)

    local sig_term = vim.uv.new_signal()
    sig_term:start('sigterm', terminate_immediately)
  end)

  -- C. 고아 프로세스 감시 워치독 (부모 PID == 1 감지 시 1초 내 직통 종료)
  pcall(function()
    local initial_ppid = vim.uv.os_getppid()
    if initial_ppid and initial_ppid > 1 then
      local watchdog = vim.uv.new_timer()
      watchdog:start(1000, 1000, function()
        if vim.uv.os_getppid() == 1 then
          watchdog:stop()
          watchdog:close()
          terminate_immediately()
        end
      end)
    end
  end)
end

return M
