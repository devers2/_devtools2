return {
  {
    -- 변수 표기법 변환 (camelCase, snake_case, PascalCase, kebab-case 등)
    'johmsalas/text-case.nvim',
    config = function()
      require('textcase').setup({
        -- <leader>cc 를 prefix로 사용 (Convert Code / Convert Case)
        -- g+a 는 LazyVim 기본 동작(Code Action)으로 반환
        prefix = '<leader>\\',
      })
    end,
    keys = {
      -- Which-Key 그룹 레이블 등록
      { '<leader>\\', desc = '+Convert Case' },
      { '<leader>\\o', desc = '+Pending Mode Operator', mode = { 'n' } },

      -- ── 노멀 모드: 커서 위치 단어 즉시 변환 (quick_replace) ──────────────
      {
        '<leader>\\c',
        function()
          require('textcase').current_word('to_camel_case')
        end,

        desc = 'toCamelCase',
        mode = 'n',
      },
      {
        '<leader>\\s',
        function()
          require('textcase').current_word('to_snake_case')
        end,
        desc = 'to_snake_case',
        mode = 'n',
      },
      {
        '<leader>\\n',
        function()
          require('textcase').current_word('to_constant_case')
        end,
        desc = 'TO_CONSTANT_CASE',
        mode = 'n',
      },
      {
        '<leader>\\p',
        function()
          require('textcase').current_word('to_pascal_case')
        end,
        desc = 'ToPascalCase',
        mode = 'n',
      },
      {
        '<leader>\\d',
        function()
          require('textcase').current_word('to_dash_case')
        end,
        desc = 'to-dash-case',
        mode = 'n',
      },
      {
        '<leader>\\u',
        function()
          require('textcase').current_word('to_upper_case')
        end,
        desc = 'TO UPPER CASE',
        mode = 'n',
      },
      {
        '<leader>\\l',
        function()
          require('textcase').current_word('to_lower_case')
        end,
        desc = 'to lower case',
        mode = 'n',
      },

      -- ── 비주얼 모드: 선택 영역 즉시 변환 ────────────────────────────────
      {
        '<leader>\\c',
        function()
          require('textcase').visual('to_camel_case')
        end,
        desc = 'toCamelCase',
        mode = 'x',
      },
      {
        '<leader>\\s',
        function()
          require('textcase').visual('to_snake_case')
        end,
        desc = 'to_snake_case',
        mode = 'x',
      },
      {
        '<leader>\\n',
        function()
          require('textcase').visual('to_constant_case')
        end,
        desc = 'TO_CONSTANT_CASE',
        mode = 'x',
      },
      {
        '<leader>\\p',
        function()
          require('textcase').visual('to_pascal_case')
        end,
        desc = 'ToPascalCase',
        mode = 'x',
      },
      {
        '<leader>\\d',
        function()
          require('textcase').visual('to_dash_case')
        end,
        desc = 'to-dash-case',
        mode = 'x',
      },
      {
        '<leader>\\u',
        function()
          require('textcase').visual('to_upper_case')
        end,
        desc = 'TO UPPER CASE',
        mode = 'x',
      },
      {
        '<leader>\\l',
        function()
          require('textcase').visual('to_lower_case')
        end,
        desc = 'to lower case',
        mode = 'x',
      },

      -- ── 노멀 모드: Pending 모션 지정 후 변환 (gul / guw 처럼 범위 지정) ──
      {
        '<leader>\\oc',
        function()
          require('textcase').operator('to_camel_case')
        end,
        desc = 'toCamelCase (motion)',
        mode = 'n',
      },
      {
        '<leader>\\os',
        function()
          require('textcase').operator('to_snake_case')
        end,
        desc = 'to_snake_case (motion)',
        mode = 'n',
      },
      {
        '<leader>\\on',
        function()
          require('textcase').operator('to_constant_case')
        end,
        desc = 'TO_CONSTANT_CASE (motion)',
        mode = 'n',
      },
      {
        '<leader>\\op',
        function()
          require('textcase').operator('to_pascal_case')
        end,
        desc = 'ToPascalCase (motion)',
        mode = 'n',
      },
      {
        '<leader>\\od',
        function()
          require('textcase').operator('to_dash_case')
        end,
        desc = 'to-dash-case (motion)',
        mode = 'n',
      },
      {
        '<leader>\\ou',
        function()
          require('textcase').operator('to_upper_case')
        end,
        desc = 'TO UPPER CASE (motion)',
        mode = 'n',
      },
      {
        '<leader>\\ol',
        function()
          require('textcase').operator('to_lower_case')
        end,
        desc = 'to lower case (motion)',
        mode = 'n',
      },

      -- ── LSP Rename 변환 ───────────────────────────────────────────────────
      {
        '<leader>\\C',
        function()
          require('textcase').lsp_rename('to_camel_case')
        end,
        desc = 'LSP rename toCamelCase',
        mode = 'n',
      },
      {
        '<leader>\\S',
        function()
          require('textcase').lsp_rename('to_snake_case')
        end,
        desc = 'LSP rename to_snake_case',
        mode = 'n',
      },
      {
        '<leader>\\N',
        function()
          require('textcase').lsp_rename('to_constant_case')
        end,
        desc = 'LSP rename TO_CONSTANT_CASE',
        mode = 'n',
      },
      {
        '<leader>\\P',
        function()
          require('textcase').lsp_rename('to_pascal_case')
        end,
        desc = 'LSP rename ToPascalCase',
        mode = 'n',
      },
      {
        '<leader>\\D',
        function()
          require('textcase').lsp_rename('to_dash_case')
        end,
        desc = 'LSP rename to-dash-case',
        mode = 'n',
      },
      {
        '<leader>\\U',
        function()
          require('textcase').lsp_rename('to_upper_case')
        end,
        desc = 'LSP rename TO UPPER CASE',
        mode = 'n',
      },
      {
        '<leader>\\L',
        function()
          require('textcase').lsp_rename('to_lower_case')
        end,
        desc = 'LSP rename to lower case',
        mode = 'n',
      },
    },
  },
}
