return {
  {
    -- 변수 표기법 변환 (camelCase, snake_case, PascalCase, kebab-case 등)
    'johmsalas/text-case.nvim',
    opts = {
      prefix = '<leader>\\',
    },
    keys = {
      -- Which-Key 그룹 레이블 등록
      { '<leader>\\', group = '[\\] 대소문자 변환 (Convert Case)' },
      { '<leader>\\o', group = '[o] 모션 지정 변환 (Motion Operator)', mode = { 'n' } },

      -- ── 노멀 모드: 커서 위치 단어 즉시 변환 (quick_replace) ──────────────
      {
        '<leader>\\c',
        function()
          require('textcase').current_word('to_camel_case')
        end,
        desc = 'camelCase로 변환 (toCamelCase)',
        mode = 'n',
      },
      {
        '<leader>\\s',
        function()
          require('textcase').current_word('to_snake_case')
        end,
        desc = 'snake_case로 변환 (to_snake_case)',
        mode = 'n',
      },
      {
        '<leader>\\n',
        function()
          require('textcase').current_word('to_constant_case')
        end,
        desc = 'CONSTANT_CASE로 변환 (TO_CONSTANT_CASE)',
        mode = 'n',
      },
      {
        '<leader>\\p',
        function()
          require('textcase').current_word('to_pascal_case')
        end,
        desc = 'PascalCase로 변환 (ToPascalCase)',
        mode = 'n',
      },
      {
        '<leader>\\d',
        function()
          require('textcase').current_word('to_dash_case')
        end,
        desc = 'dash-case로 변환 (to-dash-case)',
        mode = 'n',
      },
      {
        '<leader>\\u',
        function()
          require('textcase').current_word('to_upper_case')
        end,
        desc = '대문자로 변환 (TO UPPER CASE)',
        mode = 'n',
      },
      {
        '<leader>\\l',
        function()
          require('textcase').current_word('to_lower_case')
        end,
        desc = '소문자로 변환 (to lower case)',
        mode = 'n',
      },
      -- ⚠️ 원래 <leader>\a, <leader>\A였으나 config/keymaps.lua의 유니코드 인코드/디코드
      --   기능과 같은 키를 공유하고 있었음(실측: keymaps.lua가 VeryLazy 시점에 나중에
      --   vim.keymap.set으로 등록되어 이 매핑을 덮어써서 무력화됨). <leader>\w, <leader>\t로 이동.
      {
        '<leader>\\w',
        function()
          require('textcase').current_word('to_phrase_case')
        end,
        desc = 'phrase case로 변환 (to phrase case)',
        mode = 'n',
      },
      {
        '<leader>\\t',
        function()
          require('textcase').current_word('to_title_case')
        end,
        desc = 'Title Case로 변환 (To Title Case)',
        mode = 'n',
      },

      -- ── 비주얼 모드: 선택 영역 즉시 변환 ────────────────────────────────
      {
        '<leader>\\c',
        function()
          require('textcase').visual('to_camel_case')
        end,
        desc = 'camelCase로 변환 (toCamelCase)',
        mode = 'x',
      },
      {
        '<leader>\\s',
        function()
          require('textcase').visual('to_snake_case')
        end,
        desc = 'snake_case로 변환 (to_snake_case)',
        mode = 'x',
      },
      {
        '<leader>\\n',
        function()
          require('textcase').visual('to_constant_case')
        end,
        desc = 'CONSTANT_CASE로 변환 (TO_CONSTANT_CASE)',
        mode = 'x',
      },
      {
        '<leader>\\p',
        function()
          require('textcase').visual('to_pascal_case')
        end,
        desc = 'PascalCase로 변환 (ToPascalCase)',
        mode = 'x',
      },
      {
        '<leader>\\d',
        function()
          require('textcase').visual('to_dash_case')
        end,
        desc = 'dash-case로 변환 (to-dash-case)',
        mode = 'x',
      },
      {
        '<leader>\\u',
        function()
          require('textcase').visual('to_upper_case')
        end,
        desc = '대문자로 변환 (TO UPPER CASE)',
        mode = 'x',
      },
      {
        '<leader>\\l',
        function()
          require('textcase').visual('to_lower_case')
        end,
        desc = '소문자로 변환 (to lower case)',
        mode = 'x',
      },

      -- ── 노멀 모드: Pending 모션 지정 후 변환 (gul / guw 처럼 범위 지정) ──
      {
        '<leader>\\oc',
        function()
          require('textcase').operator('to_camel_case')
        end,
        desc = 'camelCase 모션 변환 (toCamelCase motion)',
        mode = 'n',
      },
      {
        '<leader>\\os',
        function()
          require('textcase').operator('to_snake_case')
        end,
        desc = 'snake_case 모션 변환 (to_snake_case motion)',
        mode = 'n',
      },
      {
        '<leader>\\on',
        function()
          require('textcase').operator('to_constant_case')
        end,
        desc = 'CONSTANT_CASE 모션 변환 (TO_CONSTANT_CASE motion)',
        mode = 'n',
      },
      {
        '<leader>\\op',
        function()
          require('textcase').operator('to_pascal_case')
        end,
        desc = 'PascalCase 모션 변환 (ToPascalCase motion)',
        mode = 'n',
      },
      {
        '<leader>\\od',
        function()
          require('textcase').operator('to_dash_case')
        end,
        desc = 'dash-case 모션 변환 (to-dash-case motion)',
        mode = 'n',
      },
      {
        '<leader>\\ou',
        function()
          require('textcase').operator('to_upper_case')
        end,
        desc = '대문자 모션 변환 (TO UPPER CASE motion)',
        mode = 'n',
      },
      {
        '<leader>\\ol',
        function()
          require('textcase').operator('to_lower_case')
        end,
        desc = '소문자 모션 변환 (to lower case motion)',
        mode = 'n',
      },

      -- ── LSP Rename 변환 ───────────────────────────────────────────────────
      {
        '<leader>\\C',
        function()
          require('textcase').lsp_rename('to_camel_case')
        end,
        desc = 'LSP 이름 변경: camelCase (LSP rename toCamelCase)',
        mode = 'n',
      },
      {
        '<leader>\\S',
        function()
          require('textcase').lsp_rename('to_snake_case')
        end,
        desc = 'LSP 이름 변경: snake_case (LSP rename to_snake_case)',
        mode = 'n',
      },
      {
        '<leader>\\N',
        function()
          require('textcase').lsp_rename('to_constant_case')
        end,
        desc = 'LSP 이름 변경: CONSTANT_CASE (LSP rename TO_CONSTANT_CASE)',
        mode = 'n',
      },
      {
        '<leader>\\P',
        function()
          require('textcase').lsp_rename('to_pascal_case')
        end,
        desc = 'LSP 이름 변경: PascalCase (LSP rename ToPascalCase)',
        mode = 'n',
      },
      {
        '<leader>\\D',
        function()
          require('textcase').lsp_rename('to_dash_case')
        end,
        desc = 'LSP 이름 변경: dash-case (LSP rename to-dash-case)',
        mode = 'n',
      },
      {
        '<leader>\\U',
        function()
          require('textcase').lsp_rename('to_upper_case')
        end,
        desc = 'LSP 이름 변경: 대문자 (LSP rename TO UPPER CASE)',
        mode = 'n',
      },
      {
        '<leader>\\L',
        function()
          require('textcase').lsp_rename('to_lower_case')
        end,
        desc = 'LSP 이름 변경: 소문자 (LSP rename to lower case)',
        mode = 'n',
      },
    },
  },
}
