const path = require('path');

// 절대경로: NPM 전역 설치 경로를 환경 변수로부터 계산
// const globalNodeModules = process.env.NODE_PATH;
// 상대경로: 현재 설정 파일 위치(.config/prettier/)를 기준으로 두 단계 위로 올라가 글로벌 패키지 디렉토리를 지정
const globalNodeModules =
  process.platform === 'win32'
    ? path.join(__dirname, '../../data/.npm-packages/node_modules')
    : path.join(__dirname, '../../data/.npm-packages/lib/node_modules');

/** Prettier 설정 */
module.exports = {
  plugins: [
    // globalNodeModules 경로를 탐색 경로에 포함하여 플러그인 절대 경로 변환
    require.resolve('prettier-plugin-sql', { paths: [globalNodeModules] }),
    require.resolve('@prettier/plugin-xml', { paths: [globalNodeModules] }),
    require.resolve('prettier-plugin-jinja-template', { paths: [globalNodeModules] })
  ],
  useEditorConfig: true, // Prettier 에서 .editorconfig 사용 → true: 활성화(.prettierrc / prettier.config.js > .editorconfig > settings.json 순으로 적용)
  printWidth: 100, // Prettier가 줄 바꿈을 할 코드의 최대 길이 → 80: 80자(기본값)
  tabWidth: 2, // 탭 간격 → 2: 기본값
  useTabs: false, // 탭 사용 → true: 탭 문자(\t) 사용, false: 스페이스 문자( ) 사용
  semi: true, // 세미콜론 사용 → true: 사용(기본값)
  singleQuote: true, // 작은 따옴표 사용 → true: 작은 따옴표 사용, false: 큰 따옴표 사용(기본값)
  quoteProps: 'as-needed', // 객체 리터럴의 속성 이름에 따옴표 사용 여부 → 'as-needed': 필요한 경우만
  trailingComma: 'none', // 후행 콤마 사용 방식 → 'none': 사용 안 함, 'es5': ES5 호환 구문에서만 사용(기본값), 'all': 모든 구문에서 사용
  bracketSpacing: true, // 객체 리터럴에서 중괄호 내부에 공백 삽입 여부 → true: 공백 삽입 { a: 1 }, false: 공백 삽입 안 함 {a: 1}
  arrowParens: 'always', // 화살표 함수의 매개변수가 하나일 때 괄호 사용 여부 → 'always': 항상 사용, 'avoid': 괄호 생략
  endOfLine: 'lf', // 줄 바꿈 방식 → 'lf': LF(\n) 사용 (Unix / Linux / macOS,  가장 일반적인 개발 환경 표준), 'crlf': CRLF(\r\n) 사용 (Windows, 전통적인 표준)
  jsxSingleQuote: false, // JSX에 작은 따옴표 사용 여부 → false: 사용 안 함
  proseWrap: 'preserve', // Markdown 텍스트의 줄 바꿈 방식 → 'preserve': 원본 유지
  htmlWhitespaceSensitivity: 'css', // HTML 공백 감도 설정 → 'css': CSS 규칙에 따름

  /* Prettier-SQL 설정 */
  'Prettier-SQL.tabSizeOverride': 2,
  'Prettier-SQL.ignoreTabSettings': false,
  'Prettier-SQL.insertSpacesOverride': true,
  // 'Prettier-SQL.language': 'postgresql', // SQL 포맷팅에 사용할 데이터베이스 방언(Dialect)을 지정 → postgresql, mysql, sqlite 중 선택
  'Prettier-SQL.uppercase': true, // SELECT, FROM 대문자
  'Prettier-SQL.linesBetweenQueries': 2, // 쿼리 사이 빈 줄
  'Prettier-SQL.indent': '  ', // 들여쓰기 2

  overrides: [
    {
      files: ['*.js', '*.mjs', '*.cjs', '*.jsx', '*.ts', '*.tsx']
      // options: {
      //   tabWidth: 4
      // }
    },
    {
      files: ['*.html', '*.htm'],
      options: {
        parser: 'html', // ← 디폴트 일반 HTML 파서 강제 고정하여 타임리프/표준 HTML 프로젝트 보호
        singleAttributePerLine: false, // ← 속성 하나당 한 줄 (force-aligned 느낌 가장 비슷)
        bracketSameLine: true, // > 괄호를 다음 줄로 내리지 않고 끝에 붙임
        htmlWhitespaceSensitivity: 'ignore' // ← HTML 공백을 더 적극적으로 정리
      }
    },
    {
      files: ['*.xml', '*.xsl', '*.xsd', '*.mybatis'],
      options: {
        parser: 'xml',
        xmlWhitespaceSensitivity: 'preserve' // XML 내 공백 감도 설정 → 'strict': 엄격하게 인식, 'preserve': 의미 있는 공백은 보존, 'ignore': 공백 무시
      }
    },
    {
      files: ['*.sql'],
      options: {
        // language: 'postgresql', // SQL 포맷팅에 사용할 데이터베이스 방언(Dialect)을 지정 → postgresql, mysql, sqlite 중 선택
        uppercase: true,
        linesBetweenQueries: 2 // 쿼리 사이 빈 줄
      }
    }
  ]
};
