return {
  {
    'CopilotC-Nvim/CopilotChat.nvim',
    opts = {
      -- 기본 프롬프트에 한국어 응답 지시 추가
      question_header = '## devers2 ',
      answer_header = '## Copilot ',
      error_header = '## 에러 ',
      system_prompt = '반드시 한국어(Korean)로 답변해줘. 질문의 의도를 파악해서 간결하고 명확하게 설명해줘.',
    },
  },
}
