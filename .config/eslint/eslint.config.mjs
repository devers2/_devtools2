import { createRequire } from 'node:module';

// ESM 환경(import)에서는 NODE_PATH 환경 변수를 통해 글로벌 패키지를 찾는 기능이 무시됩니다.
// 따라서 CommonJS의 require 함수를 직접 생성하여 우회 처리함으로써 글로벌 패키지를 정상 로드합니다.
const require = createRequire(import.meta.url);

const js = require('@eslint/js');
const prettierConfig = require('eslint-config-prettier');
const eslintPluginHtml = require('eslint-plugin-html');
const prettierPlugin = require('eslint-plugin-prettier');
const globals = require('globals');

// TypeScript 관련 모듈 불러오기
const tsParser = require('@typescript-eslint/parser');
const tsPlugin = require('@typescript-eslint/eslint-plugin');

// Vue 관련 모듈 불러오기
const vuePlugin = require('eslint-plugin-vue');
const vueParser = require('vue-eslint-parser');

// [Prettier 설정 동기화] <1> 공통 Prettier 설정 파일 불러오기
// 파일 위치가 .config/eslint 안이므로 ../prettier/ 로 이동하여 불러와야 합니다.
const userPrettierConfig = require('../prettier/.prettierrc.cjs');

/**
 * [Prettier 설정 동기화] <2> Prettier 설정 분리
 * overrides는 별도 로직으로 처리하기 위해 나머지 기본 설정에서 분리
 */
const { overrides = [], ...basePrettierOptions } = userPrettierConfig;

/**
 * [Prettier 설정 동기화] <3> Prettier Overrides 동적 매핑
 * - 'eslint-plugin-prettier'에 설정 객체를 직접 전달할 경우, 플러그인은 최상위 옵션(기본값)만 인식하고 'overrides' (파일별 예외 설정) 배열은 무시 됨
 * - 따라서 .prettierrc.cjs에 정의된 오버라이드 설정을 ESLint가 이해할 수 있는 형태의 Config 객체로 변환하여 수동으로 등록해 주어야 한다.
 */
const prettierOverrideConfigs = overrides.map((override) => {
  // 1) files 패턴을 배열로 통일 (문자열 하나만 있는 경우 배열로 변환)
  const rawPatterns = Array.isArray(override.files) ? override.files : [override.files];

  // 2) ESLint Glob 패턴으로 변환 (매우 중요!)
  // Prettier의 "*.html"은 "모든 위치의 HTML"을 의미하지만,
  // ESLint Flat Config에서 "*.html"은 "현재 루트 폴더의 HTML"만 의미한다.
  // 따라서 하위 폴더까지 적용되도록 "**/*.html" 형태로 변환이 필요하다.
  const eslintPatterns = rawPatterns.map((pattern) => {
    // 별표(*)로 시작하지만 이중 별표(**)가 아니고, 슬래시(/)가 없는 단순 패턴인 경우
    if (pattern.startsWith('*') && !pattern.startsWith('**') && !pattern.includes('/')) {
      return `**/${pattern}`;
    }
    return pattern;
  });

  // 3) HTML 전용 Prettier 옵션 필터링
  // eslint-plugin-html이 <script>에서 추출한 JS를 린팅할 때, HTML 전용 옵션
  // (parser, singleAttributePerLine 등)이 그대로 전달되면 JS 줄바꿈을 뭉개는 오작동 발생.
  // HTML 패턴 오버라이드일 때만 해당 옵션들을 제외하고 전달한다.
  const HTML_ONLY_OPTIONS = new Set([
    'parser',
    'singleAttributePerLine',
    'htmlWhitespaceSensitivity',
    'vueIndentScriptAndStyle',
    'attributeSeparator', // HTML 속성 구분자 관련
    'htmlFormat' // HTML 포맷팅 관련
    // 'bracketSameLine' → JSX/React에서도 사용되므로 HTML 전용으로 분류하지 않음
  ]);

  const isHtmlPattern = eslintPatterns.some((p) => /\.(html?|vue|svelte)$/.test(p));

  const filteredOptions = Object.fromEntries(
    Object.entries(override.options ?? {}).filter(([key]) => !(isHtmlPattern && HTML_ONLY_OPTIONS.has(key)))
  );

  return {
    // 변환된 패턴 사용 (예: ['**/*.html'])
    files: eslintPatterns,
    plugins: {
      prettier: prettierPlugin
    },
    rules: {
      // HTML 파일은 prettier/prettier 비활성화:
      // Prettier HTML 파서가 <script> 블록 포맷팅 결과와 ESLint prettier/prettier 결과가
      // 구조적으로 달라서 저장 시마다 충돌이 발생한다. HTML은 Prettier 직접 실행이 담당한다.
      'prettier/prettier': isHtmlPattern ? 'off' : ['warn', { ...basePrettierOptions, ...filteredOptions }]
    }
  };
});

/**
 * 프로젝트 전반에 걸쳐 사용될 공통 전역 변수 설정
 */
const COMMON_GLOBALS = {
  // 브라우저 전역 변수 (window, document, console, fetch 등)
  ...globals.browser,
  // Node 환경 전역 변수 (process, require, __dirname 등)
  ...globals.node,
  // 전역으로 사용되는 다른 변수가 있다면 아래에 추가:
  jQuery: 'readonly',
  $: 'readonly'
};

export default [
  /**
   * 1. 제외 설정 (Ignores)
   * ESLint의 검사(린팅) 대상에서 제외할 파일 및 디렉토리 설정
   */
  {
    ignores: [
      // 핵심 빌드 및 의존성
      'node_modules/',
      'build/',
      'dist/',
      'bin/',
      'target/',
      'out/',
      'classes/',
      'generated/',
      'generated-sources/',

      // 캐시 및 아티팩트
      '.gradle/',
      '.mvn/',
      '.m2/repository/',
      '.cache/',
      '.npm/',
      '.yarn/',
      '.pnp.*',
      '.turbo/',
      '.parcel-cache/',
      'bower_components/',
      'build-cache/',
      'dependency-cache/',
      '.venv/',
      'venv/',
      '__pycache__/',
      '**/*.pyc',
      '**/*.egg-info/',
      '**/pkg/',
      '.serverless/',
      '.git/',
      '.svn/',

      // 로그 및 임시/테스트 출력
      '**/*.log',
      '**/*.tmp',
      '**/logs/',
      '**/temp/',
      '**/tmp/',
      'coverage/',
      'jacoco/',
      'test-output/',
      'test-reports/',
      '.nyc_output/',

      // Minified 및 번들 파일
      '**/*.min.js',
      '**/*.umd.js',
      '**/*.bundle.js',
      '**/*.map.js',
      '**/*.min.css',
      'static/vendor/'
    ]
  },

  /**
   * 2. HTML 파일 전용 Processor 및 추가 규칙
   */
  {
    files: ['**/*.html'],
    plugins: {
      html: eslintPluginHtml // HTML 플러그인
    },
    languageOptions: {
      sourceType: 'module',
      globals: COMMON_GLOBALS
    },
    rules: {
      // JS 추천 룰 활성화 (HTML 내부 script에도 동일 적용)
      ...js.configs.recommended.rules,
      'no-unused-vars': 'error',
      'no-console': 'warn',
      'no-var': 'error',
      // const로 선언한 변수에 재할당을 금지
      'no-const-assign': 'error',
      // 재할당이 없는 변수는 반드시 const로 선언 (let 대신 const 권장)
      'prefer-const': 'error',
      // HTML 내장 JS에서 prettier/prettier 룰 비활성화
      // Prettier HTML 파서는 <script> 블록을 HTML 들여쓰기 컨텍스트(+2칸)로 처리하지만
      // ESLint prettier/prettier 룰은 추출된 JS를 독립 파일로 보고 다른 기준을 적용하여
      // 저장할 때마다 포맷팅 충돌이 발생한다. HTML 포맷팅은 Prettier 직접 실행에 맡긴다.
      'prettier/prettier': 'off'
    }
  },

  /**
   * 3. 모든 JS 파일에 대한 공통 기본 설정 (.js, .mjs, .cjs, .jsx)
   */
  {
    files: ['**/*.{js,mjs,cjs,jsx}'],
    // Flat Config 로 추천 설정을 펼쳐서 사용
    ...js.configs.recommended,
    languageOptions: {
      // 추천 설정의 languageOptions를 가져와서 기존 설정을 유지
      ...js.configs.recommended.languageOptions,
      // module: export/import 문법을 기본값으로 명시적으로 허용 (ESM 기본)
      sourceType: 'module',
      globals: COMMON_GLOBALS,
      parserOptions: {
        ecmaFeatures: {
          jsx: true
        }
      }
    },
    rules: {
      // 추천 규칙 유지
      ...js.configs.recommended.rules,
      // var 사용을 금지하고 let이나 const로 자동 치환
      'no-var': 'error',
      // 값이 재할당되지 않는 경우 자동으로 const로 치환
      'prefer-const': 'error'
    }
  },

  /**
   * 3-1. CommonJS 파일(.cjs) 재정의
   * 위 섹션 3의 모든 규칙 및 globals는 상속받고 sourceType: 'commonjs' 부분만 재정의
   */
  {
    files: ['**/*.{cjs}'],
    languageOptions: {
      // .cjs 파일은 CommonJS이므로 sourceType을 commonjs로 명확히 지정하여 재정의
      sourceType: 'commonjs'
    }
  },

  /**
   * 3-2. TypeScript 파일 (.ts, .tsx) 규칙 추가
   * 타 언어에 parser 오염 방지를 위해 모든 config 객체에 files 패턴 강제 지정
   */
  ...tsPlugin.configs['flat/recommended'].map((cfg) => {
    return {
      ...cfg,
      files: cfg.files || ['**/*.{ts,tsx}']
    };
  }),
  {
    files: ['**/*.{ts,tsx}'],
    languageOptions: {
      parser: tsParser,
      parserOptions: {
        sourceType: 'module'
      },
      globals: COMMON_GLOBALS
    },
    rules: {
      'no-var': 'error',
      'prefer-const': 'error'
    }
  },

  /**
   * 3-3. Vue 파일 (.vue) 규칙 추가
   * vue-eslint-parser로 템플릿과 스크립트를 올바르게 해독
   */
  ...vuePlugin.configs['flat/essential'].map((cfg) => {
    return {
      ...cfg,
      files: cfg.files || ['**/*.vue']
    };
  }),
  {
    files: ['**/*.vue'],
    languageOptions: {
      parser: vueParser,
      parserOptions: {
        parser: tsParser,
        sourceType: 'module',
        ecmaFeatures: {
          jsx: true
        }
      },
      globals: COMMON_GLOBALS
    },
    rules: {
      ...js.configs.recommended.rules,
      'no-var': 'error',
      'prefer-const': 'error'
    }
  },

  /**
   * 4. Prettier 플러그인(eslint-plugin-prettier) 설정
   * ESLint 검사 시 포맷팅 규칙을 강제 한다.
   * ※ JS, TS, Vue, HTML 모든 파일에 대해 적용
   */
  {
    files: ['**/*.{js,mjs,cjs,jsx,ts,tsx,vue,html}'],
    plugins: {
      prettier: prettierPlugin
    },
    rules: {
      /*
       * [Prettier 설정 동기화] <4> Prettier 실행 규칙 등록
       * - ESLint 포맷팅 규칙 심각도 설정 → "off": 보고 안함, "warn": 경고로 보고, "error": 에러로 보고
       * - basePrettierOptions: .prettierrc.cjs의 최상위 기본 설정 적용 (오버라이드 설정은 `...prettierOverrideConfigs`에서 처리)
       */
      'prettier/prettier': ['warn', basePrettierOptions]
    }
  },

  /**
   * [Prettier 설정 동기화] <5> Prettier Overrides 동적 설정 적용
   * 위에서 생성한 '오버라이드 설정 객체들'을 여기에 펼쳐 놓는다.
   */
  ...prettierOverrideConfigs,

  /**
   * 5. Prettier Config (eslint-config-prettier 적용: 충돌 규칙 끄기)
   * 반드시 다른 모든 extends/rules 설정보다 뒤에 위치해야 한다.
   */
  prettierConfig
];
