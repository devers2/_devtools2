-- ==============================================================================
-- DevTools2 Gittyup 테마 및 폰트 설정 (theme.lua)
-- Neovim 및 Windows Terminal 과 동일한 폰트/사이즈(D2Coding ligature, 11.5pt)와
-- 공식 올블랙 다크 테마(Dark.lua)를 적용합니다.
-- ==============================================================================

require("themes/Dark")

theme["font"] = {
  family = "D2Coding ligature",
  size = 11.5
}
