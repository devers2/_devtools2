-- =============================================================================
-- 🛡️ [Plugin Guard - 서드파티 플러그인 안전 격리 및 호환성 가드 모듈]
-- =============================================================================
-- 1. [목적]:
--    상위 라이브러리(Treesitter, LSP, DAP 등)의 대규모 메이저 업데이트로 내부 API가
--    Breaking Change 되더라도 Neovim 기동 중단이나 크래시를 100% 원천 차단합니다.
--
-- 2. [동작 방식]:
--    - pcall 기반 격리 실행 (Fault Isolation): 실패 시 해당 기능만 안전하게 비활성화
--    - 사용자 친화적 알림: 빨간색 에러 폭탄 대신 원인 및 해결 명령(:Lazy update <이름>) 안내
-- =============================================================================

local M = {}

---플러그인 안전 격리 초기화 함수
---@param plugin_name string 플러그인 표시/식별 이름 (예: "nvim-treesitter-textobjects")
---@param category string 플러그인 범주 (예: "Treesitter", "LSP", "DAP", "UI")
---@param setup_fn function 실제 플러그인 setup 로직을 담은 함수
---@return boolean success 초기화 성공 여부
function M.safe_setup(plugin_name, category, setup_fn)
  -- category 인자가 생략되고 함수만 전달된 경우 하위 호환 처리
  if type(category) == 'function' then
    setup_fn = category
    category = 'Plugin'
  end

  local ok, err = pcall(setup_fn)
  if not ok then
    vim.schedule(function()
      local full_err = tostring(err or 'Unknown error')
      -- 가독성을 위해 스택 트레이스 앞부분의 경로를 정돈
      local short_err = full_err:gsub('^.-:.-:%s*', ''):gsub('\n.*', '')
      if #short_err == 0 then
        short_err = full_err:sub(1, 150)
      end

      local msg = string.format(
        "⚠️ [%s] 플러그인이 최신 %s 환경과 호환되지 않아 안전하게 비활성화되었습니다.\n\n"
          .. "• 원인: %s\n"
          .. "• 해결 방법: 아래 명령어로 해당 플러그인을 최신 버전으로 업데이트해 주세요:\n"
          .. "  :Lazy update %s",
        plugin_name,
        category or 'Core',
        short_err,
        plugin_name
      )

      vim.notify(msg, vim.log.levels.WARN, {
        title = string.format('%s 호환성 가드', category or '플러그인'),
        timeout = 10000,
      })
    end)
    return false
  end

  return true
end

-- 어디서든 require 없이도 쓸 수 있도록 전역 헬퍼 등록
_G.safe_plugin_setup = M.safe_setup

return M
