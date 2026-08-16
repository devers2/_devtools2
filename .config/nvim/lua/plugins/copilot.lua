return {
  {
    'CopilotC-Nvim/CopilotChat.nvim',
    -- [성능] cmd 없이는 lazy.lua의 기본값(lazy=false)이 적용되어 매 시작마다 무조건 로드됨.
    -- CopilotChat.nvim 공식 권장 설정도 cmd = "CopilotChat" 지연 로드라, :CopilotChat* 계열
    -- 명령을 처음 실행할 때만 로드되도록 맞춤(기존 키맵/사용법은 그대로 유지됨).
    cmd = {
      'CopilotChat',
      'CopilotChatOpen',
      'CopilotChatClose',
      'CopilotChatToggle',
      'CopilotChatStop',
      'CopilotChatReset',
    },
    opts = {
      -- 기본 프롬프트에 한국어 응답 지시 추가
      question_header = '## devers2 ',
      answer_header = '## Copilot ',
      error_header = '## 에러 ',
      system_prompt = '반드시 한국어(Korean)로 답변해줘. 질문의 의도를 파악해서 간결하고 명확하게 설명해줘.',
    },
  },
}
