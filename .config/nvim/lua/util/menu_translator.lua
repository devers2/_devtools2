local M = {}

M._registered_interceptors = M._registered_interceptors or {}

---@class TranslationEntry
---@field ko string 한글 설명
---@field priority number? 정렬 우선순위 (낮을수록 상단 배치)

---@class InterceptorOptions
---@field name string 인터셉터 이름 (예: "dap_session", "dap_config")
---@field prompt_patterns string[] 매칭할 프로토콜/프롬프트 패턴
---@field translations table<string, TranslationEntry> 원본 라벨대비 한글 및 우선순위 맵
---@field default_priority number? 기본 우선순위 (기본값: 90)

--- 동적 메뉴 번역 및 정렬 인터셉터를 등록합니다.
---@param opts InterceptorOptions
function M.register_interceptor(opts)
  opts.default_priority = opts.default_priority or 90
  table.insert(M._registered_interceptors, opts)

  -- 1) dap.ui.pick_one 인터셉터 설치
  local dap_ok, dap_ui = pcall(require, 'dap.ui')
  if dap_ok and dap_ui and dap_ui.pick_one and not dap_ui._translator_wrapped then
    dap_ui._translator_wrapped = true
    local orig_pick_one = dap_ui.pick_one
    dap_ui.pick_one = function(items, prompt, label_fn, cb)
      if prompt and items then
        for _, interceptor in ipairs(M._registered_interceptors) do
          for _, pattern in ipairs(interceptor.prompt_patterns) do
            if prompt:find(pattern) then
              for _, item in ipairs(items) do
                local raw_label = label_fn(item)
                local trans = interceptor.translations[raw_label]
                if trans then
                  item._custom_display = trans.ko .. ' (' .. raw_label .. ')'
                  item._custom_priority = trans.priority or interceptor.default_priority
                else
                  item._custom_display = raw_label
                  item._custom_priority = interceptor.default_priority
                end
              end

              table.sort(items, function(a, b)
                return (a._custom_priority or 99) < (b._custom_priority or 99)
              end)

              return orig_pick_one(items, prompt, function(x)
                return x._custom_display or label_fn(x)
              end, cb)
            end
          end
        end
      end
      return orig_pick_one(items, prompt, label_fn, cb)
    end
  end

  -- 2) vim.ui.select 인터셉터 설치 (Snacks, Telescope, WhichKey 등 일반 피커 대응)
  -- ⚠️ Snacks.nvim도 자체적으로 vim.ui.select를 설정하는데, 둘 다 VeryLazy 시점에 동작해서
  --   먼저 실행되는 쪽이 나중 쪽에 덮어써지는 경쟁 상태가 있었음(실측: 로드 순서에 따라
  --   한글 번역 기능이 조용히 사라지는 경우 발생). vim.schedule로 한 틱 미뤄서 Snacks 설정이
  --   항상 먼저 끝난 뒤에 그 위를 감싸도록 순서를 고정함(:checkhealth의 "vim.ui.select is not
  --   set to Snacks.picker.select" 경고는 감싸는 구조상 계속 뜨지만, 안쪽에서 Snacks 피커를
  --   그대로 호출하므로 기능상 문제 아님).
  if not vim._ui_select_translator_wrapped then
    vim._ui_select_translator_wrapped = true
    vim.schedule(function()
    local orig_ui_select = vim.ui.select
    vim.ui.select = function(items, select_opts, on_choice)
      select_opts = select_opts or {}
      local prompt = select_opts.prompt or ''
      local format_item = select_opts.format_item or function(item)
        return tostring(item)
      end

      local matched_interceptor = nil
      if prompt and items then
        for _, interceptor in ipairs(M._registered_interceptors) do
          for _, pattern in ipairs(interceptor.prompt_patterns) do
            if prompt:find(pattern) then
              matched_interceptor = interceptor
              break
            end
          end
          if matched_interceptor then
            break
          end
        end
      end

      if matched_interceptor and type(items) == 'table' then
        local decorated = {}
        for idx, item in ipairs(items) do
          local raw_label = format_item(item)
          local trans = matched_interceptor.translations[raw_label]
          local display, priority
          if trans then
            display = trans.ko .. ' (' .. raw_label .. ')'
            priority = trans.priority or matched_interceptor.default_priority
          else
            display = raw_label
            priority = matched_interceptor.default_priority
          end
          table.insert(decorated, {
            original = item,
            display = display,
            priority = priority,
            idx = idx,
          })
        end

        table.sort(decorated, function(a, b)
          if a.priority ~= b.priority then
            return a.priority < b.priority
          end
          return a.idx < b.idx
        end)

        local new_items = {}
        local item_to_display = {}
        for _, d in ipairs(decorated) do
          table.insert(new_items, d.original)
          item_to_display[d.original] = d.display
        end

        local custom_opts = vim.tbl_extend('force', select_opts, {
          format_item = function(item)
            return item_to_display[item] or format_item(item)
          end,
        })

        return orig_ui_select(new_items, custom_opts, on_choice)
      end

      return orig_ui_select(items, select_opts, on_choice)
    end
    end)
  end
end

return M
